"""Shizhen clock-drawing model training (CPU-friendly, mirrors Sato et al. 2022 mini-VGG).

Tasks
  shulman : 3-class clock quality (impaired = Shulman 0-3 / minor = 4 / normal = 5)
  mci     : binary cognitive screen from a single clock drawing (MoCA <= 24 = impaired),
            initialised from the shulman model (transfer learning)

Datasets are read from --data-root (not redistributed in this repo):
  <root>/clock_shulman/<score>_<name>/<subject>_<k>.png   (Chulalongkorn CDT, Raksasat et al. 2023)
  <root>/mci/images/<id>/clock.png + <root>/mci/label.csv   (Chulalongkorn MCI drawings)
  <root>/nhats/...  -> see load_nhats(); identical pipeline once NHATS access is granted.

Outputs to --out: <task>.pt, <task>.mlpackage, metrics.json, figures/*.png
"""
import argparse, json, os, random, time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from PIL import Image, ImageOps
from sklearn.metrics import (balanced_accuracy_score, confusion_matrix, f1_score,
                             roc_auc_score, roc_curve)

SIZE = 128
torch.set_num_threads(os.cpu_count() or 4)


# ---------------------------------------------------------------- preprocessing
def preprocess(path: Path) -> np.ndarray:
    """Grayscale -> crop to ink bounding box -> pad to square -> 128x128, ink=1 bg=0.
    The iOS app applies exactly the same steps to the PencilKit rendering."""
    im = ImageOps.grayscale(Image.open(path).convert("RGB"))
    a = np.asarray(im, dtype=np.float32) / 255.0
    ink = a < 0.6
    if ink.any():
        ys, xs = np.where(ink)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        a = a[y0:y1 + 1, x0:x1 + 1]
    h, w = a.shape
    s = int(max(h, w) * 1.1) + 2
    canvas = np.ones((s, s), np.float32)
    canvas[(s - h) // 2:(s - h) // 2 + h, (s - w) // 2:(s - w) // 2 + w] = a
    im = Image.fromarray((canvas * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.BILINEAR)
    return 1.0 - np.asarray(im, dtype=np.float32) / 255.0


def load_shulman(root: Path):
    X, y, g = [], [], []
    base = root / "clock_shulman"
    for d in sorted(base.iterdir()):
        if not d.is_dir() or not d.name[0].isdigit():
            continue
        score = int(d.name[0])
        label = 0 if score <= 3 else (1 if score == 4 else 2)
        for f in sorted(d.glob("*.png")):
            X.append(preprocess(f)); y.append(label); g.append(f.stem.split("_")[0])
    return np.stack(X), np.array(y), np.array(g), ["impaired", "minor_errors", "normal"]


def load_mci(root: Path):
    import pandas as pd
    lab = pd.read_csv(root / "mci" / "label.csv", dtype={"patient_id": str})
    X, y, g = [], [], []
    for pid, moca in zip(lab.patient_id, lab.MoCA_score):
        f = root / "mci" / "images" / pid / "clock.png"
        if f.exists():
            X.append(preprocess(f)); y.append(1 if moca <= 24 else 0); g.append(pid)
    return np.stack(X), np.array(y), np.array(g), ["normal", "impaired"]


def load_nhats(root: Path):
    """NHATS public-use clock images + SP file (cg#dclkdraw 0-5, demographics).
    Drop-in once access is approved: same preprocessing and model."""
    raise NotImplementedError("NHATS access pending; see docs/DATA.md")


# ---------------------------------------------------------------- model (mini-VGG)
class MiniVGG(nn.Module):
    def __init__(self, n_classes: int):
        super().__init__()
        def block(cin, cout):
            return nn.Sequential(nn.Conv2d(cin, cout, 3, padding=1), nn.BatchNorm2d(cout), nn.ReLU(True),
                                 nn.Conv2d(cout, cout, 3, padding=1), nn.BatchNorm2d(cout), nn.ReLU(True),
                                 nn.MaxPool2d(2))
        self.features = nn.Sequential(block(1, 32), block(32, 64), block(64, 128), block(128, 192))
        self.head = nn.Sequential(nn.AdaptiveAvgPool2d(1), nn.Flatten(), nn.Dropout(0.4), nn.Linear(192, n_classes))

    def forward(self, x):
        return self.head(self.features(x))


class CoreMLWrapper(nn.Module):
    """Takes a raw grayscale image (white paper = 255) and outputs probabilities."""
    def __init__(self, net):
        super().__init__(); self.net = net

    def forward(self, img):
        x = 1.0 - img / 255.0
        return F.softmax(self.net(x), dim=1)


# ---------------------------------------------------------------- training utils
def augment(x: torch.Tensor) -> torch.Tensor:
    # small rotation / scale / shift; NO mirror flips (a mirrored clock is a wrong clock)
    n = x.shape[0]
    ang = (torch.rand(n) - 0.5) * 2 * np.deg2rad(12)
    sc = 1 + (torch.rand(n) - 0.5) * 0.2
    tx, ty = (torch.rand(n) - 0.5) * 0.12, (torch.rand(n) - 0.5) * 0.12
    cos, sin = torch.cos(ang) / sc, torch.sin(ang) / sc
    theta = torch.stack([torch.stack([cos, -sin, tx], 1), torch.stack([sin, cos, ty], 1)], 1)
    grid = F.affine_grid(theta, x.shape, align_corners=False)
    x = F.grid_sample(x, grid, align_corners=False)
    # stroke-thickness jitter (finger vs pen): random dilation
    if random.random() < 0.5:
        x = F.max_pool2d(x, 3, 1, 1)
    return x


def group_split(y, g, seed, frac=(0.7, 0.15, 0.15)):
    rng = np.random.default_rng(seed)
    groups = np.unique(g)
    # stratify groups by their (max) label
    glab = {gg: y[g == gg].max() for gg in groups}
    tr, va, te = [], [], []
    for lab in np.unique(y):
        gs = np.array([gg for gg in groups if glab[gg] == lab]); rng.shuffle(gs)
        n1, n2 = int(len(gs) * frac[0]), int(len(gs) * (frac[0] + frac[1]))
        tr += list(gs[:n1]); va += list(gs[n1:n2]); te += list(gs[n2:])
    m = lambda s: np.isin(g, s)
    return m(tr), m(va), m(te)


def evaluate(net, X, y):
    net.eval(); out = []
    with torch.no_grad():
        for i in range(0, len(X), 256):
            out.append(F.softmax(net(torch.from_numpy(X[i:i + 256]).unsqueeze(1)), 1).numpy())
    p = np.concatenate(out)
    return p, balanced_accuracy_score(y, p.argmax(1))


def train(task, X, y, g, classes, out: Path, epochs, seed, init=None):
    torch.manual_seed(seed); random.seed(seed); np.random.seed(seed)
    tr, va, te = group_split(y, g, seed)
    net = MiniVGG(len(classes))
    if init:
        sd = torch.load(init, map_location="cpu", weights_only=True)
        sd = {k: v for k, v in sd.items() if not k.startswith("head")}
        net.load_state_dict(sd, strict=False)
    counts = np.bincount(y[tr], minlength=len(classes))
    w = torch.tensor(len(y[tr]) / (len(classes) * np.maximum(counts, 1)), dtype=torch.float32)
    opt = torch.optim.AdamW(net.parameters(), lr=2e-3 if not init else 7e-4, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=opt.param_groups[0]["lr"],
                                                total_steps=epochs * int(np.ceil(tr.sum() / 64)))
    Xtr, ytr = torch.from_numpy(X[tr]).unsqueeze(1), torch.from_numpy(y[tr]).long()
    best, best_sd, hist = -1, None, []
    for ep in range(epochs):
        net.train(); perm = torch.randperm(len(Xtr)); t0 = time.time(); tl = 0
        for i in range(0, len(perm), 64):
            idx = perm[i:i + 64]
            loss = F.cross_entropy(net(augment(Xtr[idx])), ytr[idx], weight=w, label_smoothing=0.05)
            opt.zero_grad(); loss.backward(); opt.step(); sched.step(); tl += loss.item() * len(idx)
        _, vb = evaluate(net, X[va], y[va])
        hist.append({"epoch": ep + 1, "train_loss": tl / len(perm), "val_bal_acc": vb})
        print(f"[{task}] epoch {ep+1}/{epochs} loss {tl/len(perm):.3f} val_bal_acc {vb:.3f} ({time.time()-t0:.0f}s)", flush=True)
        if vb > best:
            best, best_sd = vb, {k: v.clone() for k, v in net.state_dict().items()}
    net.load_state_dict(best_sd)
    p, tb = evaluate(net, X[te], y[te])
    yt = y[te]
    res = {"task": task, "classes": classes, "seed": seed, "n_train": int(tr.sum()), "n_val": int(va.sum()),
           "n_test": int(te.sum()), "test_balanced_accuracy": float(tb),
           "test_macro_f1": float(f1_score(yt, p.argmax(1), average="macro")),
           "confusion_matrix": confusion_matrix(yt, p.argmax(1)).tolist(), "history": hist}
    # binary view: impaired vs not
    imp = classes.index("impaired")
    yb, sb = (yt == imp).astype(int), p[:, imp]
    res["test_auc_impaired"] = float(roc_auc_score(yb, sb))
    fpr, tpr, thr = roc_curve(yb, sb)
    j = np.argmax(tpr - fpr)
    res["youden_threshold"] = float(thr[j]); res["sensitivity"] = float(tpr[j]); res["specificity"] = float(1 - fpr[j])
    res["roc"] = {"fpr": fpr.tolist(), "tpr": tpr.tolist()}
    torch.save(net.state_dict(), out / f"{task}.pt")
    return net, res


def export_coreml(net, classes, path: Path, desc: str):
    import coremltools as ct
    net.eval(); wrapped = CoreMLWrapper(net).eval()
    ex = torch.rand(1, 1, SIZE, SIZE) * 255
    traced = torch.jit.trace(wrapped, ex)
    mlm = ct.convert(traced, convert_to="mlprogram",
                     inputs=[ct.ImageType(name="clock", shape=(1, 1, SIZE, SIZE),
                                          color_layout=ct.colorlayout.GRAYSCALE)],
                     classifier_config=ct.ClassifierConfig(classes),
                     minimum_deployment_target=ct.target.iOS17)
    mlm.short_description = desc
    mlm.author = "Shizhen team (CrossPointX 2026)"
    mlm.license = "Apache-2.0 (model weights); training data credited in docs/DATA.md"
    mlm.save(str(path))


def figures(res, out: Path):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fd = out / "figures"; fd.mkdir(exist_ok=True)
    t = res["task"]
    fig, ax = plt.subplots(figsize=(4, 4))
    ax.plot(res["roc"]["fpr"], res["roc"]["tpr"], lw=2, color="#0f6e7a")
    ax.plot([0, 1], [0, 1], ls="--", color="#999")
    ax.set_xlabel("False positive rate"); ax.set_ylabel("True positive rate")
    ax.set_title(f"{t}: ROC (AUC {res['test_auc_impaired']:.2f})"); fig.tight_layout(); fig.savefig(fd / f"{t}_roc.png", dpi=200)
    cm = np.array(res["confusion_matrix"])
    fig, ax = plt.subplots(figsize=(4, 4)); ax.imshow(cm, cmap="Blues")
    for (i, j), v in np.ndenumerate(cm):
        ax.text(j, i, v, ha="center", va="center", color="black")
    ax.set_xticks(range(len(res["classes"]))); ax.set_xticklabels(res["classes"], rotation=30)
    ax.set_yticks(range(len(res["classes"]))); ax.set_yticklabels(res["classes"])
    ax.set_xlabel("Predicted"); ax.set_ylabel("Expert label"); ax.set_title(f"{t}: confusion matrix")
    fig.tight_layout(); fig.savefig(fd / f"{t}_confusion.png", dpi=200)
    fig, ax = plt.subplots(figsize=(5, 3))
    ax.plot([h["epoch"] for h in res["history"]], [h["val_bal_acc"] for h in res["history"]], color="#0f6e7a")
    ax.set_xlabel("Epoch"); ax.set_ylabel("Validation balanced accuracy"); ax.set_title(f"{t}: training")
    fig.tight_layout(); fig.savefig(fd / f"{t}_training.png", dpi=200)
    plt.close("all")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", choices=["shulman", "mci"], required=True)
    ap.add_argument("--data-root", type=Path, required=True)
    ap.add_argument("--out", type=Path, default=Path("ml/out"))
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--init", type=Path, default=None)
    a = ap.parse_args(); a.out.mkdir(parents=True, exist_ok=True)
    X, y, g, classes = (load_shulman if a.task == "shulman" else load_mci)(a.data_root)
    print(f"loaded {len(X)} drawings, label counts {np.bincount(y).tolist()}", flush=True)
    net, res = train(a.task, X, y, g, classes, a.out, a.epochs, a.seed, a.init)
    print(json.dumps({k: v for k, v in res.items() if k not in ("history", "roc")}, indent=1), flush=True)
    figures(res, a.out)
    name = {"shulman": "ClockScorer", "mci": "CognitiveScreen"}[a.task]
    export_coreml(net, classes, a.out / f"{name}.mlpackage",
                  {"shulman": "Clock-drawing quality (Shulman-based: impaired 0-3 / minor 4 / normal 5)",
                   "mci": "Cognitive screen from one clock drawing (MoCA<=24 = impaired). Not a diagnosis."}[a.task])
    json.dump(res, open(a.out / f"{a.task}_metrics.json", "w"), indent=1)
    print("done", flush=True)
