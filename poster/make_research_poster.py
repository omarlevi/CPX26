"""ISEF-style research poster for Shizhen. Core visual = AMD Creative Factory illustration (unaltered, placed in layout)."""
import json, math
import numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from PIL import Image, ImageDraw, ImageFont

FD = "/usr/share/fonts/opentype/inter/"
for w in ["Regular", "Medium", "SemiBold", "Bold"]:
    font_manager.fontManager.addfont(FD + f"Inter-{w}.otf")
plt.rcParams.update({"font.family": "Inter", "font.size": 15, "axes.spines.top": False, "axes.spines.right": False,
                     "axes.edgecolor": "#56657a", "axes.labelcolor": "#14212b", "xtick.color": "#14212b", "ytick.color": "#14212b"})
INK, TEAL, TEAL2, GREY, AMBER, RED = "#14212b", "#0f6e7a", "#8cc7cd", "#566573", "#d98a1c", "#c0392b"
r = json.load(open("ml/results/shulman_metrics.json"))
FIG = "poster/fig"; import os; os.makedirs(FIG, exist_ok=True)
def save(fig, name): fig.tight_layout(); fig.savefig(f"{FIG}/{name}.png", dpi=220, transparent=False, facecolor="white"); plt.close(fig)

# 1. Background: dementia cases in China (millions)
fig, ax = plt.subplots(figsize=(6.2, 3.4))
yrs, vals = [1990, 2021, 2050], [4, 17, 115]
ax.bar([str(y) for y in yrs], vals, color=[TEAL2, TEAL, RED], width=0.55)
for i, v in enumerate(vals): ax.text(i, v + 3, f"{v}M", ha="center", fontweight="bold", color=INK)
ax.set_ylabel("People with dementia (millions)"); ax.set_ylim(0, 132)
ax.set_title("Dementia in China (2050 = projection)", fontsize=15, color=INK, loc="left"); save(fig, "bg_dementia")

# 2. Dataset class distribution
fig, ax = plt.subplots(figsize=(6.2, 3.0))
labels, n = ["Impaired\n(Shulman 0-3)", "Minor errors\n(4)", "Normal\n(5)"], [438, 1047, 1623]
ax.barh(labels, n, color=[RED, AMBER, TEAL])
for i, v in enumerate(n): ax.text(v + 25, i, f"{v}", va="center", fontweight="bold")
ax.set_xlabel("Clock drawings (n = 3,108)"); ax.set_xlim(0, 1900); ax.invert_yaxis(); save(fig, "dataset")

# 3. ROC
fig, ax = plt.subplots(figsize=(4.8, 4.6))
ax.plot(r["roc"]["fpr"], r["roc"]["tpr"], color=TEAL, lw=3, label=f"ClockScorer (AUC {r['test_auc_impaired']:.2f})")
ax.plot([0, 1], [0, 1], ls="--", color="#9aa7b1", label="Chance (AUC 0.50)")
ax.scatter([1 - r["specificity"]], [r["sensitivity"]], s=90, color=RED, zorder=5, label="Operating point (p = 0.59)")
ax.set_xlabel("False positive rate (1 − specificity)"); ax.set_ylabel("True positive rate (sensitivity)")
ax.set_title("ROC: impaired vs. not impaired", fontsize=15, loc="left"); ax.legend(frameon=False, fontsize=12, loc="lower right"); save(fig, "roc")

# 4. Confusion matrix (row %)
cm = np.array(r["confusion_matrix"]); pct = cm / cm.sum(1, keepdims=True) * 100
fig, ax = plt.subplots(figsize=(4.8, 4.6)); ax.imshow(pct, cmap="BuGn", vmin=0, vmax=100)
names = ["Impaired", "Minor", "Normal"]
for (i, j), v in np.ndenumerate(pct):
    ax.text(j, i, f"{v:.0f}%\n(n={cm[i,j]})", ha="center", va="center", fontsize=13, color="white" if v > 55 else INK, fontweight="bold")
ax.set_xticks(range(3), names); ax.set_yticks(range(3), names)
ax.set_xlabel("Predicted by ClockScorer"); ax.set_ylabel("Clinician label")
ax.set_title("Confusion matrix (row %)", fontsize=15, loc="left")
for s in ax.spines.values(): s.set_visible(False)
save(fig, "confusion")

# 5. Key metrics bar
fig, ax = plt.subplots(figsize=(6.2, 3.2))
m = {"AUC": r["test_auc_impaired"], "Sensitivity": r["sensitivity"], "Specificity": r["specificity"], "Balanced acc.\n(3-class)": r["test_balanced_accuracy"]}
ax.bar(list(m), list(m.values()), color=[TEAL, TEAL, TEAL, TEAL2], width=0.6)
for i, v in enumerate(m.values()): ax.text(i, v + 0.02, f"{v*100:.0f}%" if i else f"{v:.2f}", ha="center", fontweight="bold")
ax.axhline(0.9, ls=":", color=GREY)
ax.set_ylim(0, 1.12); ax.set_yticks([0, .25, .5, .75, 1]); ax.set_title("Held-out test set (n = 465 unseen)  ·  dotted line = AUC 0.90 target", fontsize=13, loc="left"); save(fig, "metrics")

# 6. Training curve
fig, ax = plt.subplots(figsize=(6.2, 2.8))
h = r["history"]; ax.plot([x["epoch"] for x in h], [x["val_bal_acc"] for x in h], color=TEAL, lw=2.5)
ax.set_xlabel("Epoch"); ax.set_ylabel("Val. balanced acc."); ax.set_ylim(0.3, 0.8)
ax.set_title("Training (mini-VGG from scratch, CPU)", fontsize=15, loc="left"); save(fig, "training")

# 7. Process data illustration: replayed strokes with pauses
fig, ax = plt.subplots(figsize=(4.6, 4.6)); ax.set_aspect("equal"); ax.axis("off")
t = np.linspace(0, 2 * np.pi, 200); rng = np.random.default_rng(3)
ax.plot(np.sin(t) + rng.normal(0, .006, 200), np.cos(t) * 0.97 + rng.normal(0, .006, 200), color=INK, lw=2.5)
for k in range(1, 13):
    a = k * np.pi / 6; ax.text(0.8 * np.sin(a), 0.8 * np.cos(a), str(k), ha="center", va="center", fontsize=15, color=INK)
ax.plot([0, 0.42 * np.sin(np.radians(335))], [0, 0.42 * np.cos(np.radians(335))], color=INK, lw=3.5)
ax.plot([0, 0.68 * np.sin(np.radians(60))], [0, 0.68 * np.cos(np.radians(60))], color=INK, lw=2.5)
for (k, d) in [(4, 6.1), (8, 3.4), (11, 9.0)]:
    a = k * np.pi / 6; x, y = 0.8 * np.sin(a), 0.8 * np.cos(a); rad = 0.05 + d * 0.012
    ax.add_patch(plt.Circle((x, y), rad, color=AMBER, alpha=0.3)); ax.add_patch(plt.Circle((x, y), rad, fill=False, color=AMBER, lw=2))
    ax.text(x, y + rad + 0.06, f"{d:.0f}s", ha="center", color=AMBER, fontweight="bold", fontsize=13)
ax.set_xlim(-1.15, 1.15); ax.set_ylim(-1.15, 1.2)
ax.set_title("Stroke replay: pauses > 2 s (illustrative)", fontsize=15, loc="left", color=INK); save(fig, "replay")

# ------------------------------------------------------------------ layout
W, H = 4800, 3600
P = Image.new("RGB", (W, H), "#f5f7f8"); d = ImageDraw.Draw(P)
def f(w, s): return ImageFont.truetype(FD + f"Inter-{w}.otf", s)
def wrap(text, font, width):
    out, cur = [], ""
    for wd in text.split():
        t = (cur + " " + wd).strip()
        if d.textlength(t, font=font) <= width: cur = t
        else: out.append(cur); cur = wd
    out.append(cur); return out
def para(x, y, text, size=30, width=1420, fill=INK, w="Regular", gap=1.42):
    fo = f(w, size)
    for ln in wrap(text, fo, width): d.text((x, y), ln, font=fo, fill=fill); y += int(size * gap)
    return y + 12
def bullets(x, y, items, size=29, width=1420):
    for it in items:
        fo = f("Regular", size); lines = wrap(it, fo, width - 40)
        d.ellipse([x + 4, y + size * 0.45, x + 18, y + size * 0.45 + 14], fill=TEAL)
        for ln in lines: d.text((x + 36, y), ln, font=fo, fill=INK); y += int(size * 1.42)
        y += 10
    return y + 6
def panel(x, y, w, h, title):
    d.rounded_rectangle([x, y, x + w, y + h], 26, fill="white", outline="#d7dee3", width=3)
    d.rounded_rectangle([x, y, x + w, y + 78], 26, fill=TEAL); d.rectangle([x, y + 50, x + w, y + 78], fill=TEAL)
    d.text((x + 36, y + 14), title.upper(), font=f("Bold", 42), fill="white"); return y + 110
def img(path, x, y, w):
    im = Image.open(path).convert("RGB"); h = int(im.height * w / im.width); P.paste(im.resize((w, h), Image.LANCZOS), (x, y)); return y + h

# header
d.rectangle([0, 0, W, 430], fill=INK)
logo = Image.open("Shizhen/Assets.xcassets/Logo.imageset/logo.png").resize((300, 300)); P.paste(logo, (90, 65))
d.text((440, 70), "Shizhen: On-Device AI Clock-Drawing Screening", font=f("Bold", 104), fill="white")
d.text((440, 195), "for Early Detection of Cognitive Decline at Home", font=f("Bold", 104), fill=TEAL2)
d.text((444, 335), "CrossPointX 2026 · Track 1: Apple Human-Centered Care · github.com/omarlevi/CPX26", font=f("Medium", 40), fill="#c9d3d9")

colw, gut, top = 1500, 75, 490
cx = [gut, gut * 2 + colw, gut * 3 + colw * 2]
# ---------- column 1
y = panel(cx[0], top, colw, 700, "Abstract")
y = para(cx[0] + 40, y, "Dementia is rising fastest in China, yet most cases have historically gone undetected. The Clock Drawing Test (CDT) is a validated screen, but it needs trained raters to score, so it stays in clinics. We built Shizhen, an iPhone app that delivers a 3-minute, voice-guided CDT + word-recall check at home, scores the drawing with a Core ML model on the device, records drawing-process data (pauses, timing, tremor), and alerts a linked family member. A compact CNN trained from scratch on 3,108 clinician-scored clocks reached AUC 0.96 (sensitivity 88%, specificity 94%) on participants it never saw, supporting phone-based, family-led monitoring.", size=30)
y = panel(cx[0], 1230, colw, 1230, "Background & Problem")
y = img(f"{FIG}/bg_dementia.png", cx[0] + 230, y, 1040)
y = bullets(cx[0] + 40, y + 10, [
    "323M Chinese are aged 60+ (end 2025), and about 60% live without their children.",
    "93% of dementia cases went undetected in a landmark China study (KCL).",
    "The CDT is used at national scale: Japan screened 1.5M+ drivers aged 75+ in FY2017. But manual scoring is \"time-consuming, and makes CDT essentially unsuitable to apply in a very large number of people\" (Sato et al., 2022)."], size=28)
y = panel(cx[0], 2500, colw, 1000, "Objective & Hypothesis")
y = para(cx[0] + 40, y, "Research question", size=32, w="Bold", fill=TEAL)
y = para(cx[0] + 40, y, "Can a phone-sized model, running fully on-device, score free-drawn clocks accurately enough to support family-led monitoring at home?", size=30)
y = para(cx[0] + 40, y, "Hypothesis", size=32, w="Bold", fill=TEAL)
y = para(cx[0] + 40, y, "A compact CNN trained from scratch will reach AUC ≥ 0.90 for impaired clocks on unseen participants, comparable to larger pretrained models.", size=30)
y = para(cx[0] + 40, y, "Target users", size=32, w="Bold", fill=TEAL)
y = bullets(cx[0] + 40, y, ["Older adults living alone (\"empty nesters\").", "Adult children in another city who can't see day-to-day changes."], size=29)

# ---------- column 2
y = panel(cx[1], top, colw, 1590, "Solution")
art = Image.open("poster/amd-raw.jpg").convert("RGB"); aw = 760; ah = int(art.height * aw / art.width)
P.paste(art.resize((aw, ah), Image.LANCZOS), (cx[1] + 40, y))
d.text((cx[1] + 40, y + ah + 8), "Illustration: AMD Creative Factory", font=f("Regular", 22), fill=GREY)
sy = y
for step, txt in [("1", "Warm-up trace\n(tremor calibration)"), ("2", "Day + year,\n3 words to remember"), ("3", "Draw a clock at\n11:10 with a finger"),
                  ("4", "Type the 3 words\nback"), ("5", "Family phone:\nstatus, trend, replay")]:
    bx = cx[1] + 840
    d.ellipse([bx, sy, bx + 74, sy + 74], fill=TEAL); d.text((bx + 26, sy + 10), step, font=f("Bold", 44), fill="white")
    d.multiline_text((bx + 100, sy + 2), txt, font=f("Medium", 30), fill=INK, spacing=6); sy += 210
y = y + ah + 50
y = bullets(cx[1] + 40, y, [
    "Alerts: steady decline · sudden change (possible delirium/stroke) · numbers crowded on one side (neglect) · tremor · missed checks.",
    "Each person is compared with their own 3-check baseline, then every 14 days."], size=29)
y = panel(cx[1], 2140, colw, 1360, "Methods")
y = para(cx[1] + 40, y, "Data. Chulalongkorn CDT dataset: 3,108 free-drawn clocks from older adults, scored by clinicians on the Shulman 0–5 scale; grouped into impaired (0–3), minor errors (4), normal (5).", size=28)
y = img(f"{FIG}/dataset.png", cx[1] + 90, y, 1300)
y = para(cx[1] + 40, y + 10, "Pipeline. Strokes → crop to ink, pad square, 128×128 grayscale → mini-VGG (4 conv blocks, ~0.84M parameters; architecture family of Sato et al. 2022) → softmax. Split 70/15/15 by participant; class-weighted loss; rotation/scale/shift/stroke-width augmentation (no mirror flips: a mirrored clock is a wrong clock). 40 epochs on CPU. Exported with coremltools to a 1.7 MB Core ML model (iOS 17).", size=28)
y = para(cx[1] + 40, y, "App. SwiftUI · PencilKit (timestamped points) · Vision (number placement) · Swift Charts · MultipeerConnectivity · on-device only.", size=28, fill=GREY)

# ---------- column 3
y = panel(cx[2], top, colw, 1720, "Results")
img(f"{FIG}/roc.png", cx[2] + 30, y, 720); img(f"{FIG}/confusion.png", cx[2] + 760, y, 720)
y += int(720 * 4.6 / 4.8) + 10
y = img(f"{FIG}/metrics.png", cx[2] + 60, y, 1380) + 10
y = para(cx[2] + 40, y, "Hypothesis supported: AUC 0.96 ≥ 0.90. Most errors move \"minor errors\" toward \"impaired\", which is the cautious direction for screening.", size=29, w="SemiBold")
y = panel(cx[2], 2270, colw, 640, "Discussion")
img(f"{FIG}/replay.png", cx[2] + 1000, y - 10, 470)
y = bullets(cx[2] + 40, y, [
    "Explainable: the stroke replay shows when and where someone hesitated, answering the \"black box\" concern raised by Sato et al.",
    "Native digital capture removes the scanning/cropping noise of paper studies.",
    "Limits: a single clock is a weak MCI signal (AUC 0.63, experimental); finger vs. paper domain gap."], size=27, width=960)
y = panel(cx[2], 2950, colw, 550, "Conclusion & Future work")
y = bullets(cx[2] + 40, y, [
    "A 1.7 MB on-device model can screen clocks at clinical-paper accuracy, enabling private, family-led monitoring that works in China.",
    "Next: NHATS (50k+ clocks, access pending) + demographics model; validation with healthy-aging cohorts; iCloud/WeChat sign-in. Not a diagnosis."], size=28)

# footer: references
d.rectangle([0, H - 75, W, H], fill=INK)
d.text((gut, H - 58), "References: Sato et al., Front. Neurol. 2022 · Raksasat et al., Sci. Rep. 2023 (Chulalongkorn CDT) · Borson, Mini-Cog · Prince/KCL, China dementia detection · Caixin 2026 (60+ population) · PLOS One 2025 projection · NHATS (NIA)   |   Built with Claude Code · Illustration: AMD Creative Factory",
       font=f("Regular", 26), fill="#c9d3d9")
P.save("poster/shizhen-research-poster.png", optimize=True)
P.save("poster/shizhen-research-poster.pdf", resolution=100)
P.resize((W // 4, H // 4)).save("/tmp/claude-0/-home-user-CPX26/c179a320-028e-58b6-8c25-278b6d454e8d/scratchpad/rp.png")
print("ok")
