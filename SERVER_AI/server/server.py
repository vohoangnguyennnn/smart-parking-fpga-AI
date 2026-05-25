"""
Parking System Backend
Flask server with OCR + gate control for entry/exit ESP32-CAM setup.
Firebase Realtime Database integration.
"""

import os
import sys
import time
import threading
from concurrent.futures import ThreadPoolExecutor, TimeoutError as CFTimeoutError
from pathlib import Path
from flask import Flask, jsonify, request
import requests

import firebase_admin
from firebase_admin import credentials, db as firebase_db

SERVER_AI_ROOT = Path(__file__).resolve().parents[1]
if str(SERVER_AI_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVER_AI_ROOT))

from ai.plate_recognition import detect_plate

# ── Config ──────────────────────────────────────────────────────────────────────

TOTAL_SLOTS   = 4
CAPTURE_DIR   = SERVER_AI_ROOT / "captures"
CAPTURE_PATH  = CAPTURE_DIR / "capture_exit.jpg"
CAM_TIMEOUT   = 10        # seconds
IMG_MAX_SIZE  = 1_000_000 # bytes
OCR_TIMEOUT   = 5        # seconds

ESP_CAM = {
    "entry": os.getenv("ENTRY_CAM_URL", "http://YOUR_ENTRY_ESP32_CAM_IP/capture"),
    "exit":  os.getenv("EXIT_CAM_URL", "http://YOUR_EXIT_ESP32_CAM_IP/capture"),
}

# ── Firebase Init ────────────────────────────────────────────────────────────────

_fb_initialized = False
try:
    cred = credentials.Certificate(str(SERVER_AI_ROOT / "config/firebase_key.json"))
    firebase_admin.initialize_app(cred, {
        "databaseURL": os.getenv(
            "FIREBASE_DATABASE_URL",
            "https://YOUR_FIREBASE_PROJECT_ID-default-rtdb.firebaseio.com/",
        ),
    })
    _fb_initialized = True
    print("[FIREBASE] Initialized successfully")
except Exception as e:
    print(f"[FIREBASE] Init failed — {e}  (Firebase sync disabled)")


# ── In-memory DB ─────────────────────────────────────────────────────────────────

class PlateDB:
    """Thread-safe in-memory plate registry."""

    def __init__(self):
        self._lock = threading.Lock()
        self._plates: dict[str, str] = {}  # plate_number → status ("IN" | "OUT")

    def save(self, plate: str) -> str:
        with self._lock:
            self._plates[plate] = "IN"
            return self._plates[plate]

    def is_in(self, plate: str) -> bool:
        with self._lock:
            return self._plates.get(plate) == "IN"

    def mark_out(self, plate: str) -> None:
        with self._lock:
            self._plates[plate] = "OUT"


# ── Firebase Helpers ─────────────────────────────────────────────────────────────

def push_firebase_event(action: str, plate: str, gate: str, slot_mask: int) -> None:
    """Push event to /logs, /vehicles/{plate}, and /realtime."""
    if not _fb_initialized:
        return

    now = int(time.time())
    occupied = _count_occupied(slot_mask)
    free = TOTAL_SLOTS - occupied

    try:
        # A. /logs
        log_action = "IN" if action == "open_entry" else "OUT"
        firebase_db.reference("/logs").push({
            "plate":   plate,
            "gate":    gate,
            "action":  log_action,
            "time":    now,
        })

        # B. /vehicles/{plate}
        if action == "open_entry":
            status = "IN"
        elif action == "open_exit":
            status = "OUT"
        else:
            return
        firebase_db.reference(f"/vehicles/{plate}").set({
            "status":    status,
            "last_seen": now,
        })

        # C. /realtime
        firebase_db.reference("/realtime").update({
            "slots": {
                "occupied":   occupied,
                "free":       free,
                "total":      TOTAL_SLOTS,
                "last_update": now,
            },
            "last_event": {
                "plate":  plate,
                "gate":   gate,
                "action": log_action,
                "time":   now,
            },
        })
    except Exception as e:
        print(f"[FIREBASE] push_firebase_event failed — {e}")


def push_slot_detail(slot_mask: int) -> None:
    """Convert bitmask to slot_N labels and push to /slot_detail."""
    if not _fb_initialized:
        return

    slot_detail = {}
    for i in range(1, TOTAL_SLOTS + 1):
        key = f"slot_{i}"
        slot_detail[key] = "occupied" if (slot_mask >> (i - 1)) & 1 else "free"

    try:
        ref = firebase_db.reference("/slot_detail")
        ref.set(slot_detail)

        # Also sync slot counts and last_event back to /realtime
        occupied = _count_occupied(slot_mask)
        firebase_db.reference("/realtime").update({
            "slots": {
                "occupied":    occupied,
                "free":        TOTAL_SLOTS - occupied,
                "total":       TOTAL_SLOTS,
                "last_update": int(time.time()),
            },
            "last_event": {
                "plate":  "",
                "gate":   "system",
                "action": "slot_update",
                "time":   int(time.time()),
            },
        })
    except Exception as e:
        print(f"[FIREBASE] push_slot_detail failed — {e}")


# ── Helpers ──────────────────────────────────────────────────────────────────────

def _capture_image(cam_url: str) -> bytes:
    """Fetch a JPEG from ESP32-CAM and validate it."""
    res = requests.get(cam_url, timeout=CAM_TIMEOUT)

    if res.status_code != 200:
        raise RuntimeError(f"camera_http_{res.status_code}")

    content_type = res.headers.get("Content-Type", "")
    if "image" not in content_type.lower():
        raise RuntimeError("invalid_content_type")

    raw = res.content
    if not raw:
        raise RuntimeError("empty_response")

    if len(raw) > IMG_MAX_SIZE:
        raise RuntimeError("image_too_large")

    return raw


def _atomic_write(path: str, data: bytes) -> None:
    """Write data to a temp file then atomically replace target."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def _run_ocr(path: str) -> str:
    """Run plate detection with timeout. Returns plate string or 'UNKNOWN' on failure."""
    try:
        future = _ocr_executor.submit(detect_plate, path)
        result = future.result(timeout=OCR_TIMEOUT)
        return result.strip() if result else "UNKNOWN"
    except CFTimeoutError:
        print(f"[OCR] Timeout after {OCR_TIMEOUT}s")
        return "UNKNOWN"
    except Exception as e:
        print(f"[OCR] Error: {e}")
        return "UNKNOWN"


def _count_occupied(slot_mask: int) -> int:
    """Count bits set to 1 in slot_mask."""
    return bin(slot_mask).count("1")


def _log_slot_state(slot_mask: int) -> None:
    occupied = _count_occupied(slot_mask)
    free     = TOTAL_SLOTS - occupied
    print(f"[SLOTS] mask=0b{slot_mask:0{TOTAL_SLOTS}b}  "
          f"occupied={occupied}  free={free}")


# ── App ──────────────────────────────────────────────────────────────────────────

app = Flask(__name__)
db  = PlateDB()
_locks: dict[str, threading.Lock] = {
    "entry": threading.Lock(),
    "exit":  threading.Lock(),
}
_ocr_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="ocr-")


@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "status": "server running",
        "total_slots": TOTAL_SLOTS,
        "cameras": list(ESP_CAM.keys()),
    })


@app.route("/trigger", methods=["POST"])
def trigger():
    """
    POST /trigger
    Body JSON: { "gate": "entry"|"exit", "slot_mask": int }
    """
    t0 = time.time()

    try:
        body = request.get_json(force=True)
    except Exception:
        return _respond_err("invalid_json", t0)

    gate = body.get("gate")

    if gate not in _locks:
        return _respond_err(f"unknown_gate_{gate}", t0)

    slot_mask = body.get("slot_mask")
    if not isinstance(slot_mask, int) or slot_mask < 0 or slot_mask > (1 << TOTAL_SLOTS) - 1:
        return _respond_err("invalid_slot_mask", t0)

    occupied = _count_occupied(slot_mask)
    free     = TOTAL_SLOTS - occupied

    print(f"[{gate.upper()}] → request  slot_mask={slot_mask}  "
          f"occupied={occupied}  free={free}")

    with _locks[gate]:
        def elapsed() -> str:
            return f"{(time.time()-t0)*1000:.0f}ms"

        try:
            print(f"[{gate.upper()}] processing…  [{elapsed()}]")

            # ── ENTRY ──────────────────────────────────────────────────────────────
            if gate == "entry":
                if free == 0:
                    print(f"[{gate.upper()}] ← REJECT  reason=no_free_slots  "
                          f"action=reject  [{elapsed()}]")
                    return _respond_ok("reject", "FULL", t0)

                try:
                    raw = _capture_image(ESP_CAM[gate])
                except requests.exceptions.Timeout:
                    return _respond_err("camera_timeout", t0)
                except requests.exceptions.ConnectionError:
                    return _respond_err("camera_connection_error", t0)
                except RuntimeError as e:
                    return _respond_err(str(e), t0)

                path = CAPTURE_DIR / f"capture_{gate}.jpg"
                _atomic_write(path, raw)
                plate = _run_ocr(path)

                if plate in ("UNKNOWN", ""):
                    print(f"[{gate.upper()}] ← REJECT  plate={plate!r}  "
                          f"action=reject  [{elapsed()}]")
                    return _respond_ok("reject", plate, t0)

                if db.is_in(plate):
                    print(f"[{gate.upper()}] ← REJECT duplicate plate={plate} "
                        f"action=reject [{elapsed()}]")
                    return _respond_ok("reject", plate, t0)

                db.save(plate)
                push_firebase_event("open_entry", plate, "entry", slot_mask)
                print(f"[{gate.upper()}] ← OPEN  plate={plate}  "
                      f"action=open_entry  [{elapsed()}]")
                return _respond_ok("open_entry", plate, t0)

            # ── EXIT ───────────────────────────────────────────────────────────────
            if gate == "exit":
                try:
                    raw = _capture_image(ESP_CAM[gate])
                except requests.exceptions.Timeout:
                    return _respond_err("camera_timeout", t0)
                except requests.exceptions.ConnectionError:
                    return _respond_err("camera_connection_error", t0)
                except RuntimeError as e:
                    return _respond_err(str(e), t0)

                _atomic_write(CAPTURE_PATH, raw)
                plate = _run_ocr(CAPTURE_PATH)

                if plate in ("UNKNOWN", "") or not db.is_in(plate):
                    reason = "unknown_plate" if plate not in ("UNKNOWN", "") else "ocr_failed"
                    print(f"[{gate.upper()}] ← REJECT  plate={plate!r}  "
                          f"reason={reason}  action=reject  [{elapsed()}]")
                    return _respond_ok("reject", plate, t0)

                db.mark_out(plate)
                push_firebase_event("open_exit", plate, "exit", slot_mask)
                print(f"[{gate.upper()}] ← OPEN  plate={plate}  "
                      f"action=open_exit  [{elapsed()}]")
                return _respond_ok("open_exit", plate, t0)

        except Exception as e:
            print(f"[{gate.upper()}] ← ERROR  {e}  [{elapsed()}]")
            return _respond_err("internal_error", t0)

    # unreachable
    return _respond_err("internal_error", t0)


@app.route("/update_slots", methods=["POST"])
def update_slots():
    """
    POST /update_slots
    Body JSON: { "slot_mask": int }
    Logs slot state — no gate action.
    """
    try:
        body      = request.get_json(force=True)
        slot_mask = body.get("slot_mask")
        if not isinstance(slot_mask, int) or slot_mask < 0 or slot_mask > (1 << TOTAL_SLOTS) - 1:
            return jsonify({"status": "error", "reason": "invalid_slot_mask"}), 400
    except Exception:
        return jsonify({"status": "error", "reason": "invalid_json"}), 400

    _log_slot_state(slot_mask)
    push_slot_detail(slot_mask)
    return jsonify({"status": "ok"})


# ── Response helpers ─────────────────────────────────────────────────────────────

def _respond_ok(action: str, plate: str = "", t0: float = 0) -> tuple:
    elapsed = f"{(time.time()-t0)*1000:.0f}ms" if t0 else ""
    return jsonify({
        "status": "ok",
        "plate":  plate,
        "action": action,
        "elapsed": elapsed,
    }), 200


def _respond_err(reason: str, t0: float = 0) -> tuple:
    elapsed = f"{(time.time()-t0)*1000:.0f}ms" if t0 else ""
    return jsonify({
        "status": "error",
        "plate":  "",
        "action": "reject",
        "reason": reason,
        "elapsed": elapsed,
    }), 200


# ── Entry point ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print(f"[SERVER] Parking system — {TOTAL_SLOTS} slots")
    print(f"[SERVER] Entry camera : {ESP_CAM['entry']}")
    print(f"[SERVER] Exit  camera : {ESP_CAM['exit']}")
    print(f"[SERVER] Capture path : {CAPTURE_PATH}")
    app.run(host="0.0.0.0", port=5000, debug=False, use_reloader=False)
