"""
YOLOv8 + CRNN License Plate Recognition
Run debug mode from SERVER_AI/: python -m ai.plate_recognition
"""

import cv2
import numpy as np
import torch
import torch.nn as nn
import re
from pathlib import Path
from PIL import Image
from ultralytics import YOLO

# ── Config ────────────────────────────────────────────────────────────────────
SERVER_AI_ROOT = Path(__file__).resolve().parents[1]
MODEL_PATH  = SERVER_AI_ROOT / "models/yolo/license_plate_best.pt"
CRNN_PATH   = SERVER_AI_ROOT / "models/crnn/best_crnn.pth"
INPUT_IMAGE = SERVER_AI_ROOT / "sample_images"
OUTPUT_DIR  = SERVER_AI_ROOT / "outputs"
CONFIDENCE  = 0.25
TARGET_H    = 32
MAX_W       = 160
DEVICE      = 'cuda' if torch.cuda.is_available() else 'cpu'
# ────────────────────────────────────────────────────────────────────────────────

# ── CTC charset (must match training) ─────────────────────────────────────────
CHARS       = '-0123456789ABCDEFGHKLMNPSTUVXYZ'
idx2char    = {i + 1: c for i, c in enumerate(CHARS)}
NUM_CLASSES = len(CHARS) + 1

# ── Preprocess ─────────────────────────────────────────────────────────────────
def preprocess_plate(img_pil: Image.Image) -> torch.Tensor:
    img = img_pil.convert('L')
    w, h = img.size
    ratio = TARGET_H / h
    new_w = min(int(w * ratio), MAX_W)
    img   = img.resize((new_w, TARGET_H), Image.LANCZOS)
    if new_w < MAX_W:
        pad  = Image.new('L', (MAX_W, TARGET_H), 255)
        pad.paste(img, (0, 0))
        img  = pad
    arr    = np.array(img, dtype=np.float32) / 255.0
    arr    = (arr - 0.5) / 0.5
    tensor = torch.from_numpy(arr).unsqueeze(0)
    return tensor

# ── Post-processing ────────────────────────────────────────────────────────────
def normalize_plate(text: str) -> str:
    if not text:
        return ""
    cleaned = re.sub(r'[^A-Za-z0-9]', '', text).upper()
    chars = list(cleaned)
    map_ld = {'O':'0','Q':'0','I':'1','L':'4','Z':'2','S':'5','B':'8','G':'6'}
    for i in [0, 1]:
        if i < len(chars) and not chars[i].isdigit():
            chars[i] = map_ld.get(chars[i], chars[i])
    if len(chars) >= 3 and not chars[2].isalpha():
        map_dl = {'0':'O','1':'I','4':'A','5':'S','6':'G','8':'B','2':'Z'}
        chars[2] = map_dl.get(chars[2], chars[2])
    for i in range(3, len(chars)):
        if not chars[i].isdigit():
            chars[i] = map_ld.get(chars[i], chars[i])
    return "".join(chars)

def fix_plate_length(text: str) -> str:
    if not text:
        return ""
    cleaned = re.sub(r'[^A-Z0-9]', '', text)
    prefix  = cleaned[:3]
    digits  = cleaned[3:8]
    if len(digits) == 5:
        return f"{prefix}-{digits[:3]}.{digits[3:]}"
    else:
        return f"{prefix}-{digits}"

# ── CRNN model (matches train_crnn.py) ────────────────────────────────────────
class CRNN(nn.Module):
    def __init__(self, num_classes, hidden=384):
        super().__init__()
        def conv_block(in_c, out_c):
            return nn.Sequential(
                nn.Conv2d(in_c, out_c, 3, padding=1),
                nn.BatchNorm2d(out_c),
                nn.ReLU(inplace=True),
            )
        self.cnn = nn.Sequential(
            conv_block(1, 32),     nn.MaxPool2d((2, 2)),
            conv_block(32, 64),    nn.MaxPool2d((2, 2)),
            conv_block(64, 128),   nn.MaxPool2d((2, 1)),
            nn.Dropout2d(0.15),
            conv_block(128, 256),  nn.MaxPool2d((2, 1)),
            conv_block(256, 256),
            nn.Conv2d(256, 256, 3, padding=1),
            nn.BatchNorm2d(256),
            nn.ReLU(inplace=True),
            nn.MaxPool2d((2, 1)),
        )
        self.rnn = nn.LSTM(256, hidden, num_layers=2,
                           bidirectional=True, batch_first=True, dropout=0.3)
        self.fc  = nn.Linear(hidden * 2, num_classes)

    def forward(self, x):
        feat = self.cnn(x).squeeze(2).permute(0, 2, 1)
        out, _ = self.rnn(feat)
        out    = self.fc(out)
        return out.permute(1, 0, 2)

def load_crnn(path: str):
    model = CRNN(NUM_CLASSES).to(DEVICE)
    state = torch.load(path, map_location=DEVICE)
    model.load_state_dict(state)
    model.eval()
    return model

def decode(indices: list) -> str:
    result, prev = [], 0
    for idx in indices:
        if idx != prev and idx != 0:
            result.append(idx2char.get(idx, ''))
        prev = idx
    return ''.join(result)

def read_plate(tensor: torch.Tensor, model: CRNN) -> str:
    with torch.no_grad():
        out   = model(tensor.unsqueeze(0).to(DEVICE))
        preds = out.argmax(2).squeeze(1).cpu().tolist()
        return decode(preds)

# ── Global model singletons (loaded once at import) ───────────────────────────
print("🔄 Loading models...")
yolo  = YOLO(str(MODEL_PATH))
crnn  = load_crnn(CRNN_PATH)
print("✅ Models loaded")

# ── Public API ─────────────────────────────────────────────────────────────────
def detect_plate(image_path: str) -> str:
    """
    Run YOLO detection then CRNN OCR on the first detected plate.
    Returns formatted plate string or 'UNKNOWN' on failure.
    """
    img = cv2.imread(str(image_path))
    if img is None:
        return "UNKNOWN"

    ih, iw = img.shape[:2]
    results = yolo(img, conf=CONFIDENCE, verbose=False)[0]

    if results.boxes is None:
        return "UNKNOWN"

    x1, y1, x2, y2 = map(int, results.boxes[0].xyxy[0].tolist())

    pad_x = int((x2 - x1) * 0.08)
    pad_y = int((y2 - y1) * 0.12)
    x1_p  = max(0, x1 - pad_x)
    y1_p  = max(0, y1 - pad_y)
    x2_p  = min(iw, x2 + pad_x)
    y2_p  = min(ih, y2 + pad_y)

    crop = img[y1_p:y2_p, x1_p:x2_p]
    if crop.size == 0:
        return "UNKNOWN"

    crop_pil = Image.fromarray(crop[:, :, ::-1])
    tensor   = preprocess_plate(crop_pil)
    raw_text = read_plate(tensor, crnn)

    plate = normalize_plate(raw_text)
    plate = fix_plate_length(plate)
    return plate if plate else "UNKNOWN"

# ── Main (debug only) ──────────────────────────────────────────────────────────
def main():
    gpu = torch.cuda.is_available()
    print(f"{'✅' if gpu else '⚠️'} Device: {torch.cuda.get_device_name(0) if gpu else 'CPU'}\n")

    out_dir = Path(OUTPUT_DIR)
    out_dir.mkdir(parents=True, exist_ok=True)

    input_path = Path(INPUT_IMAGE)
    if input_path.is_file():
        image_files = [input_path]
    elif input_path.is_dir():
        image_files = sorted(input_path.glob("*.[jp][pn][g]"))
    else:
        raise FileNotFoundError(f"Input not found: {INPUT_IMAGE}")

    print(f"🖼️  Processing {len(image_files)} image(s)...\n")

    for img_path in image_files:
        img = cv2.imread(str(img_path))
        if img is None:
            print(f"⚠️  Skip: {img_path.name}")
            continue

        ih, iw = img.shape[:2]
        results   = yolo(img, conf=CONFIDENCE, verbose=False)[0]
        annotated = img.copy()

        if results.boxes is None:
            print(f"  {img_path.name}: khong detect duoc bien so")
            continue

        for i, box in enumerate(results.boxes):
            x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
            conf = float(box.conf[0])

            pad_x = int((x2 - x1) * 0.08)
            pad_y = int((y2 - y1) * 0.12)
            x1_p  = max(0, x1 - pad_x)
            y1_p  = max(0, y1 - pad_y)
            x2_p  = min(iw, x2 + pad_x)
            y2_p  = min(ih, y2 + pad_y)

            crop = img[y1_p:y2_p, x1_p:x2_p]
            if crop.size == 0:
                continue

            crop_pil = Image.fromarray(crop[:, :, ::-1])
            tensor   = preprocess_plate(crop_pil)
            raw_text = read_plate(tensor, crnn)

            plate_text = normalize_plate(raw_text)
            plate_text = fix_plate_length(plate_text)

            print(f"  [{i+1}] {img_path.name} | conf={conf:.2f} | plate='{plate_text}'")

            cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(annotated, plate_text, (x1, max(y1 - 8, 15)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)

        out_path = out_dir / f"result_{img_path.name}"
        cv2.imwrite(str(out_path), annotated)
        print(f"  -> Saved: {out_path.name}\n")

if __name__ == "__main__":
    main()
