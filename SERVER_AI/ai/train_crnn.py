# ═══════════════════════════════════════════════════════════════
#  CRNN — Nhận dạng biển số xe Việt Nam (OCR)
#  Dataset: topkek69/vietnamese-license-plate-ocr (Kaggle)
#  Kiến trúc: CNN trích đặc trưng → BiLSTM → CTC loss
# ═══════════════════════════════════════════════════════════════

import json, random, difflib, re
from pathlib import Path
import pandas as pd
from PIL import Image
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader, ConcatDataset
import torchvision.transforms as T

DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
print(f"Device : {DEVICE}")
print(f"GPU    : {torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'}")

# Tăng tốc GPU: kích thước ảnh cố định → cudnn tự chọn kernel nhanh nhất; TF32 cho matmul.
if DEVICE == 'cuda':
    torch.backends.cudnn.benchmark        = True
    torch.backends.cuda.matmul.allow_tf32 = True
    torch.backends.cudnn.allow_tf32       = True

# ── 1. Tự dò thư mục dataset dưới /kaggle/input ──────────────────────────────
# Chọn thư mục chứa NHIỀU ẢNH nhất (tránh dính nhầm dataset rỗng cùng được mount).
def find_dataset_dir() -> Path:
    base = Path('/kaggle/input')
    counts = {}
    for p in base.rglob('*'):
        if p.is_file() and p.suffix.lower() in ('.jpg', '.jpeg', '.png'):
            counts[p.parent] = counts.get(p.parent, 0) + 1
    if not counts:
        print("⚠️  Không thấy ảnh nào — dùng /kaggle/input")
        return base
    top_img_dir = max(counts, key=counts.get)
    root = top_img_dir.parent
    print(f"Dataset dir: {root}  ({counts[top_img_dir]} ảnh ở {top_img_dir.name}/)")
    return root

INPUT_DIR = find_dataset_dir()

# ── 2. Đọc nhãn từ CSV ───────────────────────────────────────────────────────
# Cấu trúc: cropped/ (ảnh thật) + generated/ (ảnh sinh sẵn), nhãn ở labels/*.csv
# (cột Name, Label). Đọc cả hai CSV, tách thật/generated theo thư mục cha của ảnh.
def load_data(input_dir: Path):
    img_by_name = {}
    for p in input_dir.rglob('*'):
        if p.is_file() and p.suffix.lower() in ('.jpg', '.jpeg', '.png'):
            img_by_name[p.name] = p

    cropped, generated = [], []
    for csv in sorted(input_dir.rglob('*.csv')):
        df = pd.read_csv(csv)
        name_col = next((c for c in df.columns if c.lower() in
                         ('name', 'filename', 'file', 'image', 'img', 'path')), df.columns[0])
        label_col = next((c for c in df.columns if c.lower() in
                          ('label', 'text', 'plate', 'license', 'number')), None)
        if label_col is None:
            continue
        for _, row in df.iterrows():
            fname = Path(str(row[name_col]).strip()).name
            label = str(row[label_col]).strip().upper()
            p = img_by_name.get(fname)
            if not label or label == 'NAN' or p is None:
                continue
            (generated if 'generated' in p.parent.name.lower() else cropped).append((p, label))
    return cropped, generated

real_samples, gen_samples = load_data(INPUT_DIR)
print(f"Ảnh thật (cropped): {len(real_samples)} | Generated: {len(gen_samples)}")

# ── 3. Bảng ký tự + CTC encode/decode ────────────────────────────────────────
CHARS = '0123456789ABCDEFGHKLMNPSTUVXYZ'      # tập ký tự xuất hiện trên biển số VN
char2idx = {c: i + 1 for i, c in enumerate(CHARS)}   # index 0 dành cho 'blank' của CTC
idx2char = {i + 1: c for i, c in enumerate(CHARS)}
NUM_CLASSES = len(CHARS) + 1

def encode(text: str) -> list:
    return [char2idx[c] for c in text.upper() if c in char2idx]

def decode(indices: list) -> str:
    # Giải mã CTC: bỏ ký tự lặp liên tiếp và bỏ blank (0)
    result, prev = [], 0
    for idx in indices:
        if idx != prev and idx != 0:
            result.append(idx2char.get(idx, ''))
        prev = idx
    return ''.join(result)

print(f"NUM_CLASSES: {NUM_CLASSES}")

# ── 4. Tiền xử lý ảnh ─────────────────────────────────────────────────────────
TARGET_H = 32
MAX_W    = 256        # đủ rộng cho biển 2 dòng sau khi ghép ngang (rộng gấp ~2)

# Biển số xe máy VN gồm 2 DÒNG (trên: '2 số + 1 chữ', dưới: '4-5 số'). CRNN đọc
# ngang trái→phải nên không đọc được bố cục chồng dọc → tách nửa trên/dưới và ghép
# cạnh nhau thành một dòng. Chỉ tách biển gần vuông (2 dòng); biển rộng (1 dòng) giữ nguyên.
def maybe_split_two_line(img: Image.Image, ratio_thresh: float = 2.0) -> Image.Image:
    w, h = img.size
    if w / h >= ratio_thresh:
        return img
    half = h // 2
    out = Image.new('RGB', (w * 2, half), (255, 255, 255))
    out.paste(img.crop((0, 0, w, half)), (0, 0))
    out.paste(img.crop((0, half, w, h)), (w, 0))
    return out

# Resize giữ tỉ lệ, đệm trắng bên phải cho đủ chiều rộng MAX_W.
def resize_keep_ratio(img: Image.Image) -> Image.Image:
    w, h = img.size
    new_w = min(int(w * TARGET_H / h), MAX_W)
    img = img.resize((new_w, TARGET_H), Image.LANCZOS)
    if new_w < MAX_W:
        pad = Image.new('RGB', (MAX_W, TARGET_H), (255, 255, 255))
        pad.paste(img, (0, 0))
        return pad
    return img

# ── 5. Trực quan hoá bước tách dòng (tạo hình minh hoạ cho báo cáo) ───────────
def visualize_split(samples, n=6, save_path='/kaggle/working/split_preview.png'):
    import matplotlib.pyplot as plt
    samples = samples[:n]
    if not samples:
        return
    fig, axes = plt.subplots(len(samples), 3, figsize=(13, 2.2 * len(samples)))
    if len(samples) == 1:
        axes = axes.reshape(1, -1)
    for r, (p, label) in enumerate(samples):
        orig  = Image.open(p).convert('RGB')
        split = maybe_split_two_line(orig)
        for c, (im, title) in enumerate([
            (orig,  f"Gốc: {label} {orig.size}"),
            (split, f"Sau tách {split.size}"),
            (resize_keep_ratio(split), f"Model nhìn ({MAX_W}x{TARGET_H})"),
        ]):
            axes[r, c].imshow(im); axes[r, c].set_title(title, fontsize=8); axes[r, c].axis('off')
    plt.tight_layout(); plt.savefig(save_path, dpi=120); plt.show()
    print(f"Đã lưu: {save_path}")

visualize_split(real_samples)

# ── 6. Dataset ────────────────────────────────────────────────────────────────
transform = T.Compose([
    T.Grayscale(),
    T.ToTensor(),
    T.Normalize((0.5,), (0.5,)),
])

# Augmentation cho ảnh train: mô phỏng nghiêng/méo/sáng-tối/mờ của crop thực tế,
# giúp lặp lại một ảnh nhiều lần trở thành nhiều biến thể khác nhau (không học thuộc).
real_aug = T.Compose([
    T.RandomApply([T.RandomRotation(4, fill=255)], p=0.6),
    T.RandomApply([T.RandomPerspective(distortion_scale=0.12, p=1.0, fill=255)], p=0.4),
    T.ColorJitter(brightness=0.3, contrast=0.3),
    T.RandomApply([T.GaussianBlur(3, sigma=(0.1, 1.2))], p=0.3),
])
# Che ngẫu nhiên một mảng nhỏ trên tensor → buộc model đọc theo ngữ cảnh, chống overfit.
random_erase = T.RandomErasing(p=0.25, scale=(0.02, 0.08), value=1.0)

class PlateDataset(Dataset):
    def __init__(self, samples, augment=False):
        # Bỏ mẫu chứa ký tự ngoài bảng CHARS
        self.samples = [(p, lb) for p, lb in samples
                        if all(c in char2idx for c in lb.upper() if c not in ' .-')]
        self.augment = augment
        print(f"Dataset ({'train+aug' if augment else 'val'}): {len(self.samples)} mẫu")

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, text = self.samples[idx]
        try:
            img = Image.open(path).convert('RGB')
        except Exception:
            img = Image.new('RGB', (MAX_W, TARGET_H), (255, 255, 255))
        text = re.sub(r'[^A-Z0-9]', '', text.upper())
        img  = maybe_split_two_line(img)
        if self.augment:
            img = real_aug(img)
        tensor = transform(resize_keep_ratio(img))
        if self.augment:
            tensor = random_erase(tensor)
        return tensor, torch.tensor(encode(text), dtype=torch.long), text

def collate_fn(batch):
    imgs, labels, texts = zip(*batch)
    imgs   = torch.stack(imgs)
    lengths = torch.tensor([len(l) for l in labels], dtype=torch.long)
    return imgs, torch.cat(labels), lengths, texts

# ── 7. Mô hình CRNN ──────────────────────────────────────────────────────────
class CRNN(nn.Module):
    def __init__(self, num_classes, hidden=384):
        super().__init__()
        def conv_block(in_c, out_c):
            return nn.Sequential(
                nn.Conv2d(in_c, out_c, 3, padding=1),
                nn.BatchNorm2d(out_c),
                nn.ReLU(inplace=True),
            )
        # CNN: chiều cao giảm dần về 1, chiều rộng giữ lại làm chuỗi thời gian T cho LSTM.
        self.cnn = nn.Sequential(
            conv_block(1, 32),     nn.MaxPool2d((2, 2)),   # 16 x 128
            conv_block(32, 64),    nn.MaxPool2d((2, 2)),   # 8  x 64
            conv_block(64, 128),   nn.MaxPool2d((2, 1)),   # 4  x 64
            nn.Dropout2d(0.15),
            conv_block(128, 256),  nn.MaxPool2d((2, 1)),   # 2  x 64
            conv_block(256, 256),
            nn.Conv2d(256, 256, 3, padding=1),
            nn.BatchNorm2d(256), nn.ReLU(inplace=True),
            nn.MaxPool2d((2, 1)),                          # 1  x 64
        )
        self.rnn = nn.LSTM(256, hidden, num_layers=2,
                           bidirectional=True, batch_first=True, dropout=0.3)
        self.fc  = nn.Linear(hidden * 2, num_classes)

    def forward(self, x):
        feat   = self.cnn(x).squeeze(2).permute(0, 2, 1)   # (B, T, C)
        out, _ = self.rnn(feat)
        out    = self.fc(out)
        return out.permute(1, 0, 2)                         # (T, B, C) cho CTC

# ── 8. Huấn luyện ─────────────────────────────────────────────────────────────
EPOCHS      = 40
BATCH       = 256
LR          = 3e-4
REAL_REPEAT = 4          # lặp ảnh thật để tăng tỉ trọng (mỗi lần khác nhau nhờ augmentation)
VAL_FRAC    = 0.1
PATIENCE    = 8          # dừng sớm nếu độ chính xác không cải thiện sau PATIENCE epoch
SAVE_PATH   = '/kaggle/working/best_crnn.pth'

assert len(real_samples) > 0, "Không load được ảnh thật — kiểm tra đường dẫn dataset."

# Chia val từ ảnh THẬT trước khi nhân bản → val không rò rỉ, đo được độ chính xác thực.
random.seed(0)
shuffled = real_samples[:]
random.shuffle(shuffled)
n_val      = max(1, int(len(shuffled) * VAL_FRAC))
val_real   = shuffled[:n_val]
train_real = shuffled[n_val:]

train_real_ds = PlateDataset(train_real, augment=True)
val_ds        = PlateDataset(val_real,   augment=False)
gen_ds        = PlateDataset(gen_samples, augment=True)   # generated chỉ dùng để train

# Train = generated + ảnh thật (đã augment, lặp REAL_REPEAT lần). Val = chỉ ảnh thật.
train_ds = ConcatDataset([gen_ds] + [train_real_ds] * REAL_REPEAT)
print(f"Train: {len(train_ds):,} | Val (ảnh thật): {len(val_ds):,}")

train_loader = DataLoader(train_ds, BATCH, shuffle=True, collate_fn=collate_fn,
                          num_workers=8, pin_memory=True, persistent_workers=True)
val_loader   = DataLoader(val_ds, BATCH, shuffle=False, collate_fn=collate_fn,
                          num_workers=8, pin_memory=True, persistent_workers=True)

model     = CRNN(NUM_CLASSES).to(DEVICE)
optimizer = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=3e-4)
scheduler = torch.optim.lr_scheduler.OneCycleLR(
    optimizer, max_lr=LR, epochs=EPOCHS, steps_per_epoch=len(train_loader))
ctc_loss  = nn.CTCLoss(blank=0, zero_infinity=True)

best_acc, no_improve, history = -1.0, 0, []

for epoch in range(EPOCHS):
    # --- Train ---
    model.train()
    train_loss = 0
    for imgs, labels, label_lens, _ in train_loader:
        imgs, labels = imgs.to(DEVICE, non_blocking=True), labels.to(DEVICE, non_blocking=True)
        # Mixed precision bf16: train nhanh hơn, ổn định với CTC nên không cần GradScaler.
        with torch.autocast(device_type='cuda', enabled=DEVICE == 'cuda', dtype=torch.bfloat16):
            out = model(imgs)
            input_lens = torch.full((out.shape[1],), out.shape[0], dtype=torch.long)
            loss = ctc_loss(out.log_softmax(2), labels, input_lens, label_lens)
        optimizer.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
        optimizer.step()
        scheduler.step()
        train_loss += loss.item()
    train_loss /= len(train_loader)

    # --- Validation ---
    model.eval()
    val_loss, correct, char_sim, total = 0, 0, 0.0, 0
    with torch.no_grad():
        for imgs, labels, label_lens, texts in val_loader:
            imgs, labels = imgs.to(DEVICE, non_blocking=True), labels.to(DEVICE, non_blocking=True)
            with torch.autocast(device_type='cuda', enabled=DEVICE == 'cuda', dtype=torch.bfloat16):
                out = model(imgs)
                input_lens = torch.full((out.shape[1],), out.shape[0], dtype=torch.long)
                val_loss += ctc_loss(out.log_softmax(2), labels, input_lens, label_lens).item()
            preds = out.argmax(2).permute(1, 0).cpu().tolist()
            for i, gt in enumerate(texts):
                pred = decode(preds[i])
                if pred == gt:
                    correct += 1
                char_sim += difflib.SequenceMatcher(None, pred, gt).ratio()
                total += 1
    val_loss /= len(val_loader)
    acc      = correct / total * 100 if total else 0
    char_acc = char_sim / total * 100 if total else 0

    history.append({'epoch': epoch + 1, 'train_loss': train_loss, 'val_loss': val_loss,
                    'acc': acc, 'char_acc': char_acc, 'lr': optimizer.param_groups[0]['lr']})
    print(f"Epoch {epoch+1:02d}/{EPOCHS} | Train: {train_loss:.4f} | Val: {val_loss:.4f} | "
          f"Acc: {acc:.1f}% | Char: {char_acc:.1f}%")

    # Lưu model theo độ chính xác toàn-biển (exact match) trên val thật.
    if acc > best_acc:
        best_acc, no_improve = acc, 0
        torch.save(model.state_dict(), SAVE_PATH)
        print(f"  → Lưu ✓ (best Acc: {best_acc:.1f}%)")
    else:
        no_improve += 1
        if no_improve >= PATIENCE:
            print(f"  → Dừng sớm: {PATIENCE} epoch không cải thiện (best Acc: {best_acc:.1f}%)")
            break

print(f"\nXong! Model: {SAVE_PATH}")

# ── 9. Bảng + biểu đồ tổng kết ───────────────────────────────────────────────
import matplotlib.pyplot as plt

hist_df = pd.DataFrame(history)
hist_df.to_csv('/kaggle/working/train_history.csv', index=False)
best = hist_df.loc[hist_df['acc'].idxmax()]

print("\n" + "=" * 60 + "\nBẢNG TỔNG KẾT (10 epoch cuối)\n" + "=" * 60)
print(hist_df.tail(10).to_string(index=False, formatters={
    'train_loss': '{:.4f}'.format, 'val_loss': '{:.4f}'.format,
    'acc': '{:.1f}'.format, 'char_acc': '{:.1f}'.format, 'lr': '{:.2e}'.format}))
print(f"\nBest epoch {int(best['epoch'])}: Acc {best['acc']:.1f}% | "
      f"Char {best['char_acc']:.1f}% | Val loss {best['val_loss']:.4f}")

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
ax1.plot(hist_df['epoch'], hist_df['train_loss'], label='Train loss')
ax1.plot(hist_df['epoch'], hist_df['val_loss'], label='Val loss')
ax1.set_title('Loss'); ax1.set_xlabel('Epoch'); ax1.legend(); ax1.grid(alpha=0.3)
ax2.plot(hist_df['epoch'], hist_df['acc'], label='Accuracy (toàn biển)')
ax2.plot(hist_df['epoch'], hist_df['char_acc'], label='Char accuracy')
ax2.axvline(int(best['epoch']), color='gray', ls='--', alpha=0.6, label=f"best ep {int(best['epoch'])}")
ax2.set_title('Accuracy'); ax2.set_xlabel('Epoch'); ax2.set_ylabel('%'); ax2.legend(); ax2.grid(alpha=0.3)
plt.tight_layout(); plt.savefig('/kaggle/working/train_curves.png', dpi=120); plt.show()

# ── 10. Đánh giá chi tiết: F1 / recall / confusion matrix (mức ký tự) ─────────
# OCR là bài toán chuỗi → căn chỉnh dự đoán với nhãn từng ký tự ('∅' = thừa/thiếu)
# rồi tính các chỉ số phân loại trên từng ký tự.
from sklearn.metrics import (confusion_matrix, classification_report,
                             precision_recall_fscore_support,
                             accuracy_score, cohen_kappa_score)

NULL   = '∅'
LABELS = list(CHARS) + [NULL]

def levenshtein(a, b):
    dp = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        prev, dp[0] = dp[0], i
        for j, cb in enumerate(b, 1):
            prev, dp[j] = dp[j], (prev if ca == cb else 1 + min(prev, dp[j], dp[j - 1]))
    return dp[-1]

def align_chars(gt, pred):
    pairs = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, gt, pred).get_opcodes():
        if tag == 'equal':
            pairs += [(gt[i1 + k], pred[j1 + k]) for k in range(i2 - i1)]
        elif tag == 'replace':
            g, p = gt[i1:i2], pred[j1:j2]
            for k in range(max(len(g), len(p))):
                pairs.append((g[k] if k < len(g) else NULL, p[k] if k < len(p) else NULL))
        elif tag == 'delete':
            pairs += [(gt[k], NULL) for k in range(i1, i2)]
        elif tag == 'insert':
            pairs += [(NULL, pred[k]) for k in range(j1, j2)]
    return pairs

# Đánh giá lại bằng model tốt nhất đã lưu
model.load_state_dict(torch.load(SAVE_PATH, map_location=DEVICE))
model.eval()

all_gt, all_pred = [], []
with torch.no_grad(), torch.autocast(device_type='cuda', enabled=DEVICE == 'cuda', dtype=torch.bfloat16):
    for imgs, labels, label_lens, texts in val_loader:
        imgs  = imgs.to(DEVICE, non_blocking=True)
        preds = model(imgs).argmax(2).permute(1, 0).cpu().tolist()
        for i, gt in enumerate(texts):
            all_gt.append(gt); all_pred.append(decode(preds[i]))

# Lưu dự đoán từng mẫu (để soi lỗi)
pd.DataFrame({'gt': all_gt, 'pred': all_pred,
              'correct': [g == p for g, p in zip(all_gt, all_pred)]}
             ).to_csv('/kaggle/working/val_predictions.csv', index=False)

# Ghép cặp ký tự trên toàn val
y_true, y_pred = [], []
for g, p in zip(all_gt, all_pred):
    for gc, pc in align_chars(g, p):
        y_true.append(gc); y_pred.append(pc)

cm = confusion_matrix(y_true, y_pred, labels=LABELS)
pd.DataFrame(cm, index=LABELS, columns=LABELS).to_csv('/kaggle/working/confusion_matrix.csv')
pd.DataFrame(classification_report(y_true, y_pred, labels=LABELS, zero_division=0,
                                   output_dict=True)).transpose().to_csv(
    '/kaggle/working/classification_report.csv')

cer = sum(levenshtein(g, p) for g, p in zip(all_gt, all_pred)) / max(1, sum(len(g) for g in all_gt))
p_mac, r_mac, f1_mac, _ = precision_recall_fscore_support(
    y_true, y_pred, labels=list(CHARS), average='macro', zero_division=0)
p_wt, r_wt, f1_wt, _ = precision_recall_fscore_support(
    y_true, y_pred, labels=list(CHARS), average='weighted', zero_division=0)
p_mic, r_mic, f1_mic, _ = precision_recall_fscore_support(
    y_true, y_pred, labels=list(CHARS), average='micro', zero_division=0)

summary = {
    'val_samples'        : len(all_gt),
    # Mức biển số (cả chuỗi phải đúng)
    'exact_match_%'      : round(100 * sum(g == p for g, p in zip(all_gt, all_pred)) / len(all_gt), 2),
    'length_match_%'     : round(100 * sum(len(g) == len(p) for g, p in zip(all_gt, all_pred)) / len(all_gt), 2),
    'mean_edit_distance' : round(sum(levenshtein(g, p) for g, p in zip(all_gt, all_pred)) / len(all_gt), 3),
    # Mức ký tự
    'char_error_rate_%'  : round(100 * cer, 2),
    'char_accuracy_%'    : round(100 * (1 - cer), 2),
    'char_accuracy_aligned_%': round(100 * accuracy_score(y_true, y_pred), 2),
    'cohen_kappa'        : round(cohen_kappa_score(y_true, y_pred), 4),
    'precision_macro'    : round(p_mac, 4), 'recall_macro'   : round(r_mac, 4), 'f1_macro'   : round(f1_mac, 4),
    'precision_micro'    : round(p_mic, 4), 'recall_micro'   : round(r_mic, 4), 'f1_micro'   : round(f1_mic, 4),
    'precision_weighted' : round(p_wt, 4),  'recall_weighted': round(r_wt, 4),  'f1_weighted': round(f1_wt, 4),
}
with open('/kaggle/working/eval_metrics.json', 'w') as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)

# Top cặp ký tự bị nhầm nhiều nhất (off-diagonal của confusion matrix) → soi lỗi cho báo cáo
conf_pairs = [{'gt': LABELS[i], 'pred': LABELS[j], 'count': int(cm[i, j])}
              for i in range(len(LABELS)) for j in range(len(LABELS))
              if i != j and cm[i, j] > 0]
pd.DataFrame(sorted(conf_pairs, key=lambda d: -d['count'])).to_csv(
    '/kaggle/working/top_confusions.csv', index=False)

# Accuracy theo từng vị trí ký tự (vị trí 2 = chữ cái thường yếu nhất)
pos_correct, pos_total = {}, {}
for g, p in zip(all_gt, all_pred):
    for i, gc in enumerate(g):
        pos_total[i]   = pos_total.get(i, 0) + 1
        pos_correct[i] = pos_correct.get(i, 0) + (i < len(p) and p[i] == gc)
pd.DataFrame([{'position': i, 'accuracy_%': round(100 * pos_correct[i] / pos_total[i], 2),
               'support': pos_total[i]} for i in sorted(pos_total)]
             ).to_csv('/kaggle/working/per_position_accuracy.csv', index=False)

print("\n" + "=" * 60 + "\nĐÁNH GIÁ MODEL TỐT NHẤT (mức ký tự, trên val thật)\n" + "=" * 60)
for k, v in summary.items():
    print(f"  {k:20s}: {v}")

# Heatmap confusion matrix (chuẩn hoá theo hàng = recall mỗi ký tự)
cm_norm = cm / cm.sum(axis=1, keepdims=True).clip(min=1)
fig, ax = plt.subplots(figsize=(11, 9))
im = ax.imshow(cm_norm, cmap='Blues', vmin=0, vmax=1)
ax.set_xticks(range(len(LABELS))); ax.set_xticklabels(LABELS, fontsize=7)
ax.set_yticks(range(len(LABELS))); ax.set_yticklabels(LABELS, fontsize=7)
ax.set_xlabel('Predicted'); ax.set_ylabel('Ground truth')
ax.set_title('Confusion matrix (chuẩn hoá theo hàng = recall mỗi ký tự)')
fig.colorbar(im, ax=ax, fraction=0.046)
plt.tight_layout(); plt.savefig('/kaggle/working/confusion_matrix.png', dpi=120); plt.show()

print("\nFile xuất ra /kaggle/working/ (tải về cho báo cáo):")
for fn in ['best_crnn.pth', 'train_history.csv', 'train_curves.png', 'split_preview.png',
           'eval_metrics.json', 'classification_report.csv', 'confusion_matrix.csv',
           'confusion_matrix.png', 'top_confusions.csv', 'per_position_accuracy.csv',
           'val_predictions.csv']:
    print(f"  • {fn}")
