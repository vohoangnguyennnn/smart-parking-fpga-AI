# ═══════════════════════════════════════════════════════════════
#  CRNN Training on Kaggle — Vietnamese License Plate OCR
#  Dataset: topkek69/vietnamese-license-plate-ocr
#  GPU: RTX Pro 6000 Blackwell
# ═══════════════════════════════════════════════════════════════

import os, json, random
import numpy as np
import pandas as pd
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader, ConcatDataset, random_split
import torchvision.transforms as T
import re

DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
print(f"Device : {DEVICE}")
print(f"GPU    : {torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'}")

# ── 1. Khám phá cấu trúc dataset ────────────────────────────────────────────
for dirname, dirs, files in os.walk('/kaggle/input'):
    for f in files[:5]:
        print(os.path.join(dirname, f))
    if files:
        print(f"  ... ({len(files)} files total in {dirname})\n")

# ── 2. Đọc dataset — tự detect CSV hay folder structure ─────────────────────
INPUT_DIR = Path('/kaggle/input/vietnamese-license-plate-ocr')

csv_files = list(INPUT_DIR.rglob('*.csv'))
print("CSV files found:", csv_files)

if csv_files:
    df = pd.read_csv(csv_files[0])
    print(f"\nShape: {df.shape}")
    print(df.head(10))
    print(f"\nColumns: {df.columns.tolist()}")

# ── 3. Parse label ───────────────────────────────────────────────────────────
def load_real_data(input_dir: Path):
    samples = []

    csv_files = list(input_dir.rglob('*.csv'))
    if csv_files:
        df = pd.read_csv(csv_files[0])

        fname_col = None
        for c in df.columns:
            if c.lower() in ['filename', 'file', 'image', 'name', 'path']:
                fname_col = c
                break

        label_col = None
        for c in df.columns:
            if c.lower() in ['label', 'text', 'plate', 'plate_text',
                             'license', 'number', 'annotation']:
                label_col = c
                break

        if fname_col and label_col:
            print(f"Format A detected: '{fname_col}' + '{label_col}'")
            img_dirs = [d for d in input_dir.rglob('*')
                       if d.is_dir() and any(d.glob('*.jpg')) or
                       d.is_dir() and any(d.glob('*.png'))]

            for _, row in df.iterrows():
                label = str(row[label_col]).strip().upper()
                if not label or label == 'NAN':
                    continue
                fname = str(row[fname_col]).strip()
                found = False
                for img_dir in img_dirs:
                    p = img_dir / fname
                    if p.exists():
                        samples.append((p, label))
                        found = True
                        break
                if not found:
                    p = input_dir / fname
                    if p.exists():
                        samples.append((p, label))

            if samples:
                print(f"Loaded {len(samples)} samples from CSV")
                return samples

    # Format B: tên file = label
    img_files = list(input_dir.rglob('*.jpg')) + list(input_dir.rglob('*.png'))
    for p in img_files:
        stem = p.stem.upper().strip()
        cleaned = re.sub(r'[^A-Z0-9]', '', stem)
        if 5 <= len(cleaned) <= 10:
            samples.append((p, stem))

    if samples:
        print(f"Format B detected: filename = label")
        print(f"Loaded {len(samples)} samples from filenames")

    return samples

real_samples = load_real_data(INPUT_DIR)
print(f"\nTotal real samples: {len(real_samples)}")
if real_samples:
    print("Sample examples:")
    for p, label in real_samples[:5]:
        print(f"  {p.name} → '{label}'")

# ── 4. CTC Utils ─────────────────────────────────────────────────────────────
CHARS = '-0123456789ABCDEFGHKLMNPSTUVXYZ'
char2idx = {c: i+1 for i, c in enumerate(CHARS)}
idx2char = {i+1: c for i, c in enumerate(CHARS)}
NUM_CLASSES = len(CHARS) + 1

def encode(text: str) -> list:
    return [char2idx[c] for c in text.upper() if c in char2idx]

def decode(indices: list) -> str:
    result, prev = [], 0
    for idx in indices:
        if idx != prev and idx != 0:
            result.append(idx2char.get(idx, ''))
        prev = idx
    return ''.join(result)

print(f"NUM_CLASSES: {NUM_CLASSES}")
print(f"Test encode '51A-12345': {encode('51A-12345')}")
print(f"Test decode: {decode(encode('51A-12345'))}")

# ── 5. Aspect-ratio preserving resize with padding ───────────────────────────
TARGET_H   = 32
MAX_W      = 160   # increased from 128

def resize_keep_ratio_with_padding(img: Image.Image,
                                   target_h: int = TARGET_H,
                                   max_w: int   = MAX_W) -> Image.Image:
    """Resize image preserving aspect ratio, pad right side with white."""
    w, h = img.size
    ratio = target_h / h
    new_w = int(w * ratio)
    new_w = min(new_w, max_w)

    img = img.resize((new_w, target_h), Image.LANCZOS)

    if new_w < max_w:
        pad = Image.new('RGB', (max_w, target_h), (255, 255, 255))
        pad.paste(img, (0, 0))
        return pad
    return img

# ── 6. Post-processing: Vietnamese plate format fixer ───────────────────────
LETTERS = set('ABCDEFGHKLMNPSTUVXYZ')
DIGITS  = set('0123456789')

def fix_plate(text: str) -> str:
    """
    Enforce Vietnamese 1-line plate format:
      - Strip non-alphanumeric
      - Index 2 (0-based) MUST be a letter
      - Remaining chars forced to digits
      - Length clamped to 6–9
    """
    # Strip everything non-alphanumeric
    raw = re.sub(r'[^A-Z0-9]', '', text.upper())
    if len(raw) < 6:
        return raw

    # Clamp to max 9 chars
    raw = raw[:9]

    # Enforce letter at index 2
    chars = list(raw)
    if len(chars) > 2:
        if chars[2] not in LETTERS:
            # Try to find a letter nearby, else use 'A'
            chars[2] = 'A'

    # Force remaining (index 3+) to digits — replace, never remove (CTC needs fixed len)
    result = chars[:3]
    for c in chars[3:]:
        result.append(c if c in DIGITS else '0')
    result = result[:9]

    out = ''.join(result)
    # Ensure length >= 6
    if len(out) < 6:
        return raw[:9]
    return out

# Sanity check
for t in ['51A12345', '62B-9876', '43-12345', '75AB1234', '11AA12345']:
    print(f"fix_plate('{t}') = '{fix_plate(t)}'")

# ── 7. Synthetic data generator — more realistic ─────────────────────────────
FONT_CANDIDATES = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf',
    '/kaggle/working/font.ttf',
]

def _get_font(size=18):
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except:
            continue
    return ImageFont.load_default()

def gen_plate_text() -> str:
    tinh = f"{random.randint(11, 99)}"
    if random.random() < 0.3:
        chu = random.choice('ABCDEFGHKLMNPSTUVXYZ') + \
              random.choice('ABCDEFGHKLMNPSTUVXYZ')
        so  = f"{random.randint(1000, 9999)}"
    else:
        chu = random.choice('ABCDEFGHKLMNPSTUVXYZ')
        so  = f"{random.randint(10000, 99999)}"
    return f"{tinh}{chu}-{so}"

def gen_image(text: str) -> Image.Image:
    # Wider synthetic plate range for better width variation
    width  = random.randint(100, 180)
    height = 32

    # Realistic plate colors: yellow (most common), white, blue (military)
    bg_color = random.choice([
        (230, 195,  10),   # yellow plate
        (245, 240, 220),   # white plate
        (180, 200, 230),   # blue-ish (military)
        (255, 220,   0),   # yellow variant
    ])
    img = Image.new('RGB', (width, height), bg_color)
    arr = np.array(img)

    # Light noise only
    noise = np.random.randint(-15, 15, arr.shape, dtype=np.int16)
    arr = np.clip(arr.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr)

    # Subtle blur (only 20% of the time)
    if random.random() < 0.2:
        img = img.filter(ImageFilter.GaussianBlur(radius=random.uniform(0.3, 0.6)))

    # Black border
    draw = ImageDraw.Draw(img)
    border_w = 1
    draw.rectangle([0, 0, width-1, height-1], outline=(0, 0, 0), width=border_w)

    # Text rendering — bold, well-centered
    font_size = random.randint(16, 22)
    font      = _get_font(size=font_size)
    bbox      = draw.textbbox((0, 0), text, font=font)
    tw        = bbox[2] - bbox[0]
    th        = bbox[3] - bbox[1]
    x         = max((width  - tw) // 2, 2)
    y         = max((height - th) // 2 - 1, 1)
    draw.text((x, y), text, fill=(0, 0, 0), font=font)

    # Small horizontal random tilt
    angle = random.uniform(-1.5, 1.5)
    img   = img.rotate(angle, fillcolor=bg_color, expand=False)

    return img

# ── 8. Dataset classes ───────────────────────────────────────────────────────
transform = T.Compose([
    T.Grayscale(),
    T.ToTensor(),
    T.Normalize((0.5,), (0.5,))
])

class SyntheticDataset(Dataset):
    def __init__(self, size=50000):
        self.texts = [gen_plate_text() for _ in range(size)]

    def __len__(self):
        return len(self.texts)

    def __getitem__(self, idx):
        text = self.texts[idx]
        img  = gen_image(text)
        img  = resize_keep_ratio_with_padding(img)
        return transform(img), torch.tensor(encode(text), dtype=torch.long), text

class RealDataset(Dataset):
    def __init__(self, samples):
        self.samples = [
            (p, label) for p, label in samples
            if all(c in char2idx for c in label.upper() if c not in ' .-')
        ]
        print(f"Real dataset after filter: {len(self.samples)}")

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, text = self.samples[idx]
        try:
            img = Image.open(path).convert('RGB')
        except:
            img = Image.new('RGB', (MAX_W, TARGET_H), (255, 255, 0))
        text = re.sub(r'[^A-Z0-9]', '', text.upper())
        img  = resize_keep_ratio_with_padding(img)
        return transform(img), torch.tensor(encode(text), dtype=torch.long), text

def collate_fn(batch):
    imgs, labels, texts = zip(*batch)
    imgs          = torch.stack(imgs)
    label_lengths = torch.tensor([len(l) for l in labels], dtype=torch.long)
    labels_concat = torch.cat(labels)
    return imgs, labels_concat, label_lengths, texts

# ── 9. CRNN Model — deeper CNN, wider input ─────────────────────────────────
class CRNN(nn.Module):
    def __init__(self, num_classes, hidden=384):
        super().__init__()
        # Input: 1 x 32 x 160
        def conv_block(in_c, out_c):
            return nn.Sequential(
                nn.Conv2d(in_c, out_c, 3, padding=1),
                nn.BatchNorm2d(out_c),
                nn.ReLU(inplace=True),
            )

        self.cnn = nn.Sequential(
            conv_block(1, 32),    nn.MaxPool2d((2,2)),     # 16 x 80
            conv_block(32, 64),    nn.MaxPool2d((2,2)),     # 8  x 40
            conv_block(64, 128),   nn.MaxPool2d((2,1)),     # 4  x 40
            nn.Dropout2d(0.15),                            # FIX: light dropout in CNN
            conv_block(128, 256),  nn.MaxPool2d((2,1)),     # 2  x 40
            conv_block(256, 256),                             # 2  x 40
            nn.Conv2d(256, 256, 3, padding=1),
            nn.BatchNorm2d(256),
            nn.ReLU(inplace=True),
            nn.MaxPool2d((2,1)),                             # 1  x 40
        )
        # Feature map at this point: (B, 256, 1, 40)
        self.rnn = nn.LSTM(256, hidden, num_layers=2,
                           bidirectional=True, batch_first=True, dropout=0.3)
        self.fc  = nn.Linear(hidden*2, num_classes)

    def forward(self, x):
        feat = self.cnn(x).squeeze(2).permute(0, 2, 1)   # (B, T, C)
        out, _ = self.rnn(feat)
        out    = self.fc(out)                              # FIX: apply classification FC
        return out.permute(1, 0, 2)                       # (T, B, C)

# ── 10. Train ────────────────────────────────────────────────────────────────
EPOCHS     = 50
BATCH      = 256       # RTX 6000 VRAM — bump to 256
LR         = 3e-4
SYNTH_SIZE = 50000
SAVE_PATH  = '/kaggle/working/best_crnn.pth'

print("Building datasets...")
synth_ds = SyntheticDataset(size=SYNTH_SIZE)
real_ds  = RealDataset(real_samples)

# FIX: oversample real 10x (was 20) for better synthetic/real balance
real_oversampled = ConcatDataset([real_ds] * 10)
combined         = ConcatDataset([synth_ds, real_oversampled])
print(f"Synthetic: {len(synth_ds):,} | Real×10: {len(real_oversampled):,} | Total: {len(combined):,}")

n_val    = int(len(combined) * 0.1)
train_ds, val_ds = random_split(combined, [len(combined)-n_val, n_val])

train_loader = DataLoader(train_ds, BATCH, shuffle=True,
                          collate_fn=collate_fn, num_workers=4, pin_memory=True)
val_loader   = DataLoader(val_ds,   BATCH, shuffle=False,
                          collate_fn=collate_fn, num_workers=4, pin_memory=True)

# Model
model     = CRNN(NUM_CLASSES).to(DEVICE)
optimizer = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=1e-4)
scheduler = torch.optim.lr_scheduler.OneCycleLR(
    optimizer, max_lr=LR, epochs=EPOCHS, steps_per_epoch=len(train_loader))
ctc_loss  = nn.CTCLoss(blank=0, zero_infinity=True)

best_val_loss = float('inf')

for epoch in range(EPOCHS):
    # Train
    model.train()
    train_loss = 0
    for imgs, labels, label_lens, _ in train_loader:
        imgs   = imgs.to(DEVICE)
        labels = labels.to(DEVICE)
        out    = model(imgs)
        T_, B_ = out.shape[0], out.shape[1]
        input_lens = torch.full((B_,), T_, dtype=torch.long)
        loss = ctc_loss(out.log_softmax(2), labels, input_lens, label_lens)
        optimizer.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
        optimizer.step()
        scheduler.step()
        train_loss += loss.item()
    train_loss /= len(train_loader)

    # Validation — two metrics: raw CTC decode vs format-fixed
    model.eval()
    val_loss   = 0
    correct    = 0      # raw accuracy
    correct_fx = 0      # fixed-plate accuracy
    total      = 0
    with torch.no_grad():
        for imgs, labels, label_lens, texts in val_loader:
            imgs   = imgs.to(DEVICE)
            labels = labels.to(DEVICE)
            out    = model(imgs)
            T_, B_ = out.shape[0], out.shape[1]
            input_lens = torch.full((B_,), T_, dtype=torch.long)
            val_loss  += ctc_loss(out.log_softmax(2),
                                   labels, input_lens, label_lens).item()
            preds = out.argmax(2).permute(1, 0).cpu().tolist()
            for i, gt in enumerate(texts):
                raw_pred = decode(preds[i])
                pred_fx  = fix_plate(raw_pred)
                gt_fx    = fix_plate(gt)
                if raw_pred.replace('-', '') == gt.replace('-', ''):
                    correct += 1
                if pred_fx.replace('-', '') == gt_fx.replace('-', ''):
                    correct_fx += 1
                total += 1

    val_loss /= len(val_loader)
    acc    = correct/total*100    if total > 0 else 0
    acc_fx = correct_fx/total*100  if total > 0 else 0

    print(f"Epoch {epoch+1:02d}/{EPOCHS} | "
          f"Train: {train_loss:.4f} | Val: {val_loss:.4f} | "
          f"Acc(raw): {acc:.1f}% | Acc(fix): {acc_fx:.1f}%")

    if val_loss < best_val_loss:
        best_val_loss = val_loss
        torch.save(model.state_dict(), SAVE_PATH)
        print(f"  → Saved ✓")

print(f"\nDone! Download: {SAVE_PATH}")