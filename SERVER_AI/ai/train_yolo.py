"""
YOLOv8 License Plate Detection — Training Script
Optimized for: RTX 3050 4GB VRAM + i5-12500H
Run from SERVER_AI/: python -m ai.train_yolo
"""

from pathlib import Path
from ultralytics import YOLO
import torch

# ── Config ──────────────────────────────────────────────────────────────────
# RTX 3050 4GB safe ceiling: yolov8n + batch=8 + imgsz=640
SERVER_AI_ROOT = Path(__file__).resolve().parents[1]
DATA_YAML   = str(SERVER_AI_ROOT / "dataset/data.yaml")
MODEL_NAME   = "yolov8n.pt"  # ultralytics auto-downloads on first run
EPOCHS       = 30
IMG_SIZE     = 640                 # dataset pre-resized to 640x640 → no extra memory cost
BATCH        = 8                   # RTX 3050 4GB safe ceiling (batch=16 WILL OOM)
DEVICE       = 0                # GPU 0; use "cpu" if no GPU
PROJECT      = str(SERVER_AI_ROOT / "training_outputs/yolo")
NAME         = "license_plate"
PATIENCE     = 25                  # early stopping
SAVE_PERIOD  = 10                  # checkpoint every N epochs
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # Load pretrained YOLOv8 nano model
    model = YOLO(MODEL_NAME)

    # Train
    results = model.train(
        data        = DATA_YAML,
        epochs      = EPOCHS,
        imgsz       = IMG_SIZE,
        batch       = BATCH,
        device      = DEVICE,
        project     = PROJECT,
        name        = NAME,
        patience    = PATIENCE,
        save_period = SAVE_PERIOD,
        workers     = 4,            # i5-12500H = 12 cores, 4 workers = safe
        amp         = True,         # mixed precision (faster, ~40% less VRAM)
        verbose     = True,
    )

    # Print final mAP
    map50    = results.results_dict.get("metrics/mAP50(B)", 0)
    map50_95 = results.results_dict.get("metrics/mAP50-95(B)", 0)
    print(f"\n✅ Training done!")
    print(f"   mAP@0.5      : {map50:.4f}")
    print(f"   mAP@0.5:0.95 : {map50_95:.4f}")
    print(f"   Best model   : {model.trainer.best}")
    print("CUDA:", torch.cuda.is_available())
    print("GPU:", torch.cuda.get_device_name(0))
