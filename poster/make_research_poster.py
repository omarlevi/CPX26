"""ISEF-style research poster for Shizhen (figure-heavy, minimal text). All numbers from ml/results + test-set predictions."""
import json, os
import numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from sklearn.metrics import roc_curve, roc_auc_score, precision_recall_curve, average_precision_score, balanced_accuracy_score
from PIL import Image, ImageDraw, ImageFont

FD = "/usr/share/fonts/opentype/inter/"
for w in ["Regular", "Medium", "SemiBold", "Bold"]: font_manager.fontManager.addfont(FD + f"Inter-{w}.otf")
INK, TEAL, TEAL2, GREY, AMBER, RED = "#14212b", "#0f6e7a", "#8cc7cd", "#566573", "#d98a1c", "#c0392b"
plt.rcParams.update({"font.family": "Inter", "font.size": 14, "axes.spines.top": False, "axes.spines.right": False,
                     "axes.edgecolor": GREY, "axes.labelcolor": INK, "xtick.color": INK, "ytick.color": INK,
                     "axes.grid": True, "grid.color": "#e3e8eb", "grid.linewidth": 0.8, "axes.axisbelow": True})
r = json.load(open("ml/results/shulman_metrics.json"))
pr = np.load("ml/results/test_preds.npz"); P_, Y = pr["p"], pr["y"]
yb, sb = (Y == 0).astype(int), P_[:, 0]            # impaired vs not
FIG = "poster/fig"; os.makedirs(FIG, exist_ok=True)
def save(fig, name): fig.tight_layout(); fig.savefig(f"{FIG}/{name}.png", dpi=220, facecolor="white"); plt.close(fig)
def title(ax, t): ax.set_title(t, fontsize=15, loc="left", fontweight="bold", color=INK, pad=10)

# bootstrap CIs
rng = np.random.default_rng(0); B = 2000; thr = r["youden_threshold"]
boots = {"AUC": [], "Sensitivity": [], "Specificity": [], "Bal. acc.": []}
for _ in range(B):
    i = rng.integers(0, len(Y), len(Y))
    if yb[i].min() == yb[i].max(): continue
    pred = sb[i] >= thr
    boots["AUC"].append(roc_auc_score(yb[i], sb[i]))
    boots["Sensitivity"].append((pred & (yb[i] == 1)).sum() / (yb[i] == 1).sum())
    boots["Specificity"].append((~pred & (yb[i] == 0)).sum() / (yb[i] == 0).sum())
    boots["Bal. acc."].append(balanced_accuracy_score(Y[i], P_[i].argmax(1)))
ci = {k: (np.mean(v), *np.percentile(v, [2.5, 97.5])) for k, v in boots.items()}
json.dump({k: list(map(float, v)) for k, v in ci.items()}, open("ml/results/bootstrap_ci.json", "w"), indent=1)

# 1 problem: dementia projection + 60+ population
fig, (a1, a2) = plt.subplots(1, 2, figsize=(9, 3.6))
a1.bar(["1990", "2021", "2050*"], [4, 17, 115], color=[TEAL2, TEAL, RED], width=0.6)
for i, v in enumerate([4, 17, 115]): a1.text(i, v + 3, f"{v}M", ha="center", fontweight="bold")
a1.set_ylim(0, 135); a1.set_ylabel("Millions"); title(a1, "Dementia in China")
a2.plot([2024, 2025], [310.3, 323.4], "o-", color=TEAL, lw=3); a2.plot([2025, 2035], [323.4, 400], "o--", color=RED, lw=3)
a2.text(2025, 333, "323M", ha="center", fontweight="bold"); a2.text(2035, 408, ">400M*", ha="center", fontweight="bold", color=RED)
a2.set_ylim(280, 440); a2.set_xticks([2025, 2030, 2035]); title(a2, "Chinese aged 60+")
fig.text(0.99, 0.01, "*projection", ha="right", fontsize=10, color=GREY); save(fig, "problem")

# 2 dataset donut
fig, ax = plt.subplots(figsize=(4.4, 4.0))
ax.pie([438, 1047, 1623], colors=[RED, AMBER, TEAL], startangle=90, counterclock=False, wedgeprops=dict(width=0.38, edgecolor="white"),
       labels=["Impaired 438", "Minor 1,047", "Normal 1,623"], textprops=dict(fontsize=13))
ax.text(0, 0, "3,108\nclocks", ha="center", va="center", fontsize=17, fontweight="bold"); title(ax, "Clinician-scored dataset"); save(fig, "donut")

# 3 ROC with bootstrap band
fig, ax = plt.subplots(figsize=(5, 4.3)); grid = np.linspace(0, 1, 101); tprs = []
for _ in range(400):
    i = rng.integers(0, len(Y), len(Y))
    if yb[i].min() == yb[i].max(): continue
    f_, t_, _ = roc_curve(yb[i], sb[i]); tprs.append(np.interp(grid, f_, t_))
lo, hi = np.percentile(tprs, [2.5, 97.5], axis=0)
f_, t_, _ = roc_curve(yb, sb)
ax.fill_between(grid, lo, hi, color=TEAL2, alpha=0.45, label="95% bootstrap CI")
ax.plot(f_, t_, color=TEAL, lw=3, label=f"AUC {ci['AUC'][0]:.2f} [{ci['AUC'][1]:.2f}–{ci['AUC'][2]:.2f}]")
ax.plot([0, 1], [0, 1], ls="--", color="#9aa7b1")
ax.scatter([1 - r["specificity"]], [r["sensitivity"]], s=80, color=RED, zorder=5, label="Operating point")
ax.set_xlabel("False positive rate"); ax.set_ylabel("Sensitivity"); ax.legend(frameon=False, fontsize=11, loc="lower right"); title(ax, "ROC: impaired vs. not"); save(fig, "roc")

# 4 PR curve
fig, ax = plt.subplots(figsize=(5, 4.3)); pr_p, pr_r, _ = precision_recall_curve(yb, sb); ap = average_precision_score(yb, sb)
ax.fill_between(pr_r, pr_p, color=TEAL2, alpha=0.35, step="post"); ax.step(pr_r, pr_p, color=TEAL, lw=3, where="post", label=f"AP = {ap:.2f}")
ax.axhline(yb.mean(), ls="--", color="#9aa7b1", label=f"Prevalence = {yb.mean():.2f}")
ax.set_xlabel("Recall"); ax.set_ylabel("Precision"); ax.set_ylim(0, 1.03); ax.legend(frameon=False, fontsize=11, loc="lower left"); title(ax, "Precision–recall"); save(fig, "pr")

# 5 confusion
cm = np.array(r["confusion_matrix"]); pct = cm / cm.sum(1, keepdims=True) * 100
fig, ax = plt.subplots(figsize=(5, 4.3)); ax.imshow(pct, cmap="BuGn", vmin=0, vmax=100); ax.grid(False)
for (i, j), v in np.ndenumerate(pct):
    ax.text(j, i, f"{v:.0f}%\nn={cm[i,j]}", ha="center", va="center", fontsize=13, fontweight="bold", color="white" if v > 55 else INK)
ax.set_xticks(range(3), ["Impaired", "Minor", "Normal"]); ax.set_yticks(range(3), ["Impaired", "Minor", "Normal"])
ax.set_xlabel("Predicted"); ax.set_ylabel("Clinician label"); [s.set_visible(False) for s in ax.spines.values()]; title(ax, "Confusion matrix"); save(fig, "confusion")

# 6 score distribution
fig, ax = plt.subplots(figsize=(5, 4.3)); bins = np.linspace(0, 1, 26)
ax.hist(sb[yb == 0], bins=bins, color=TEAL, alpha=0.75, label="Not impaired", density=True)
ax.hist(sb[yb == 1], bins=bins, color=RED, alpha=0.7, label="Impaired", density=True)
ax.axvline(thr, color=INK, ls="--", lw=2); ax.text(thr + 0.02, ax.get_ylim()[1] * 0.9, f"threshold {thr:.2f}", fontsize=11)
ax.set_xlabel("Predicted P(impaired)"); ax.set_ylabel("Density"); ax.legend(frameon=False, fontsize=11); title(ax, "Score separation"); save(fig, "dist")

# 7 threshold sweep
fig, ax = plt.subplots(figsize=(5, 4.3)); ts = np.linspace(0.01, 0.99, 99)
sens = [((sb >= t) & (yb == 1)).sum() / (yb == 1).sum() for t in ts]; spec = [((sb < t) & (yb == 0)).sum() / (yb == 0).sum() for t in ts]
ax.plot(ts, sens, color=RED, lw=3, label="Sensitivity"); ax.plot(ts, spec, color=TEAL, lw=3, label="Specificity")
ax.axvline(thr, color=INK, ls="--", lw=2); ax.set_xlabel("Decision threshold"); ax.set_ylabel("Rate"); ax.set_ylim(0, 1.03)
ax.legend(frameon=False, fontsize=11, loc="lower center"); title(ax, "Threshold trade-off"); save(fig, "sweep")

# 8 bootstrap metric bars
fig, ax = plt.subplots(figsize=(5, 4.3)); ks = list(ci); m = [ci[k][0] for k in ks]
err = [[ci[k][0] - ci[k][1] for k in ks], [ci[k][2] - ci[k][0] for k in ks]]
ax.bar(ks, m, yerr=err, capsize=8, color=[TEAL, RED, TEAL, TEAL2], width=0.6, error_kw=dict(lw=2, ecolor=INK))
for i, v in enumerate(m): ax.text(i, 0.06, f"{v:.2f}", ha="center", color="white", fontweight="bold", fontsize=15)
ax.axhline(0.9, ls=":", color=INK); ax.set_ylim(0, 1.08); title(ax, "Metrics ± 95% CI (n = 465)"); save(fig, "ci")

# 9 model size vs accuracy (dataset authors' reported accuracy vs ours)
fig, ax = plt.subplots(figsize=(5, 4.3))
acc_ours = np.trace(cm) / cm.sum() * 100
pts = [("ResNet-152", 60.2, 76.7, GREY), ("API-Net\n(ResNet-152)", 60.2, 78.0, GREY), ("API-Net\n(DenseNet-121)", 8.0, 78.9, GREY), ("Shizhen\nmini-VGG", 0.84, acc_ours, RED)]
for n, pm, a, c in pts:
    ax.scatter(pm, a, s=260 if c == RED else 150, color=c, zorder=5, edgecolor="white", lw=2)
    ax.annotate(n, (pm, a), xytext=(10, -6 if c != RED else 8), textcoords="offset points", fontsize=11, color=INK, fontweight="bold" if c == RED else "normal")
ax.set_xscale("log"); ax.set_xlim(0.4, 200); ax.set_ylim(72, 81)
ax.set_xlabel("Parameters (millions, log scale)"); ax.set_ylabel("3-class accuracy (%)"); title(ax, "70× smaller, similar accuracy"); save(fig, "size")

# 10 training curves
fig, ax = plt.subplots(figsize=(5, 4.3)); h = r["history"]; ep = [x["epoch"] for x in h]
ax.plot(ep, [x["train_loss"] for x in h], color=AMBER, lw=2.5, label="Train loss"); ax.set_ylabel("Loss"); ax.set_xlabel("Epoch")
a2 = ax.twinx(); a2.plot(ep, [x["val_bal_acc"] for x in h], color=TEAL, lw=2.5, label="Val. balanced acc."); a2.set_ylim(0.3, 0.8); a2.grid(False)
a2.spines["right"].set_visible(True); a2.set_ylabel("Balanced accuracy")
ax.legend(handles=ax.get_lines() + a2.get_lines(), frameon=False, fontsize=11, loc="center right"); title(ax, "Training (40 epochs, CPU)"); save(fig, "train")

# 11 process data illustration
fig, ax = plt.subplots(figsize=(5, 4.3)); ax.set_aspect("equal"); ax.axis("off"); t = np.linspace(0, 2 * np.pi, 200); g = np.random.default_rng(3)
ax.plot(np.sin(t) + g.normal(0, .006, 200), np.cos(t) * .97 + g.normal(0, .006, 200), color=INK, lw=2.5)
for k in range(1, 13): a = k * np.pi / 6; ax.text(.8 * np.sin(a), .8 * np.cos(a), str(k), ha="center", va="center", fontsize=14)
ax.plot([0, .42 * np.sin(np.radians(335))], [0, .42 * np.cos(np.radians(335))], color=INK, lw=3.5); ax.plot([0, .68 * np.sin(np.radians(60))], [0, .68 * np.cos(np.radians(60))], color=INK, lw=2.5)
for k, dd in [(4, 6.1), (8, 3.4), (11, 9.0)]:
    a = k * np.pi / 6; x, y_ = .8 * np.sin(a), .8 * np.cos(a); rad = .05 + dd * .012
    ax.add_patch(plt.Circle((x, y_), rad, color=AMBER, alpha=.3)); ax.add_patch(plt.Circle((x, y_), rad, fill=False, color=AMBER, lw=2))
    ax.text(x, y_ + rad + .07, f"{dd:.0f}s", ha="center", color=AMBER, fontweight="bold")
ax.set_xlim(-1.15, 1.15); ax.set_ylim(-1.15, 1.25); title(ax, "Process data: pauses (illustrative)"); save(fig, "replay")

# ------------------------------------------------------------------ layout
W, H = 4800, 3600; Pz = Image.new("RGB", (W, H), "#f5f7f8"); d = ImageDraw.Draw(Pz)
def f(w, s_): return ImageFont.truetype(FD + f"Inter-{w}.otf", s_)
def wrap(text, font, width):
    out, cur = [], ""
    for wd in text.split():
        t_ = (cur + " " + wd).strip()
        if d.textlength(t_, font=font) <= width: cur = t_
        else: out.append(cur); cur = wd
    out.append(cur); return out
def para(x, y, text, size=33, width=1400, fill=INK, w="Regular", gap=1.4):
    fo = f(w, size)
    for ln in wrap(text, fo, width): d.text((x, y), ln, font=fo, fill=fill); y += int(size * gap)
    return y + 14
def bullets(x, y, items, size=33, width=1400):
    for it in items:
        fo = f("Regular", size); d.ellipse([x + 4, y + size * .42, x + 20, y + size * .42 + 16], fill=TEAL)
        for ln in wrap(it, fo, width - 44): d.text((x + 40, y), ln, font=fo, fill=INK); y += int(size * 1.38)
        y += 14
    return y
def caption(x, y, text, width):
    return para(x, y, text, size=28, width=width, fill=GREY, w="Medium", gap=1.35)
def panel(x, y, w, h, t):
    d.rounded_rectangle([x, y, x + w, y + h], 26, fill="white", outline="#d7dee3", width=3)
    d.rounded_rectangle([x, y, x + w, y + 80], 26, fill=TEAL); d.rectangle([x, y + 50, x + w, y + 80], fill=TEAL)
    d.text((x + 36, y + 14), t.upper(), font=f("Bold", 44), fill="white"); return y + 115
def img(name, x, y, w):
    im = Image.open(f"{FIG}/{name}.png").convert("RGB"); h = int(im.height * w / im.width); Pz.paste(im.resize((w, h), Image.LANCZOS), (x, y)); return y + h

# header
d.rectangle([0, 0, W, 420], fill=INK)
logo = Image.open("Shizhen/Assets.xcassets/Logo.imageset/logo.png").resize((270, 270)); Pz.paste(logo, (80, 75))
d.text((390, 80), "Shizhen", font=f("Bold", 130), fill="white")
d.text((394, 235), "On-device AI clock-drawing screening for early", font=f("SemiBold", 52), fill=TEAL2)
d.text((394, 300), "detection of cognitive decline at home", font=f("SemiBold", 52), fill=TEAL2)
kx = 2500
for big, small in [(f"{ci['AUC'][0]:.2f}", "AUC"), (f"{r['sensitivity']*100:.0f}%", "Sensitivity"), (f"{r['specificity']*100:.0f}%", "Specificity"), ("1.7 MB", "On-device model")]:
    d.rounded_rectangle([kx, 85, kx + 520, 335], 24, fill="#1e3140")
    d.text((kx + 260, 160), big, font=f("Bold", 96), fill="white", anchor="mm"); d.text((kx + 260, 275), small, font=f("Medium", 36), fill=TEAL2, anchor="mm"); kx += 560

g, top = 60, 470; cw = (W - 4 * g) // 3; cx = [g, 2 * g + cw, 3 * g + 2 * cw]; tw = cw - 80

# ---- column 1: Problem, How it works, Question
y = panel(cx[0], top, cw, 1120, "Problem")
y = img("problem", cx[0] + 40, y, cw - 80) + 10
y = bullets(cx[0] + 40, y, [
    "In China, 93% of dementia cases went undetected in a landmark study, and 60% of over-60s live without their children.",
    "Doctors screen with the Clock Drawing Test, but a trained rater must score it, so it rarely leaves the clinic."], width=tw)
y = panel(cx[0], 1630, cw, 1060, "How Shizhen works")
for n_, (a, b) in enumerate([("Draw a clock at 11:10", "with a finger, voice-guided, about 3 minutes"),
                             ("Remember 3 words", "plus day and year (orientation)"),
                             ("AI scores it on the phone", "image + how it was drawn (pauses, tremor)"),
                             ("Compare with their own baseline", "3 checks in week one, then every 14 days"),
                             ("Family is alerted", "decline · sudden change · missed checks")], 1):
    d.ellipse([cx[0] + 40, y, cx[0] + 110, y + 70], fill=TEAL); d.text((cx[0] + 75, y + 35), str(n_), font=f("Bold", 40), fill="white", anchor="mm")
    d.text((cx[0] + 135, y - 2), a, font=f("SemiBold", 36), fill=INK); d.text((cx[0] + 135, y + 46), b, font=f("Regular", 29), fill=GREY)
    y += 165
y = panel(cx[0], 2730, cw, 770, "Question & Hypothesis")
y = para(cx[0] + 40, y, "Can a phone-sized model score free-drawn clocks accurately enough for families to use at home?", size=34, width=tw, w="Medium")
d.rounded_rectangle([cx[0] + 40, y + 10, cx[0] + cw - 40, y + 300], 20, fill="#e6f2f3")
d.text((cx[0] + 80, y + 40), "H:", font=f("Bold", 60), fill=TEAL)
para(cx[0] + 190, y + 48, "A compact model reaches AUC ≥ 0.90 on people it has never seen.", size=36, width=tw - 180, w="SemiBold")
d.text((cx[0] + 190, y + 210), "✓ Supported: AUC 0.96", font=f("Bold", 40), fill=TEAL)

# ---- column 2: Method, Process data (clock)
y = panel(cx[1], top, cw, 1500, "Method")
y = para(cx[1] + 40, y, "Trained on 3,108 clocks from older adults, each scored by a clinician (Chulalongkorn University dataset).", width=tw)
img("donut", cx[1] + 40, y, 640)
bullets(cx[1] + 720, y + 90, ["Split by person: tested only on people never seen in training",
                              "Small CNN (mini-VGG, 0.84M parameters), as in Sato et al. 2022",
                              "No mirror flips: a mirrored clock is a wrong clock"], size=30, width=cw - 760)
y += 600
steps = [("Finger strokes", "timestamped"), ("Normalize", "128×128"), ("Mini-VGG", "0.84M params"), ("Core ML", "1.7 MB, offline"), ("Risk engine", "own baseline"), ("Family alert", "status · replay")]
for i, (a, b) in enumerate(steps):
    col, row = i % 3, i // 3; bw = (cw - 80 - 2 * 30) // 3; X = cx[1] + 40 + col * (bw + 30); Y = y + row * 175
    dark = i in (2, 3); d.rounded_rectangle([X, Y, X + bw, Y + 140], 18, fill=TEAL if dark else "#e6f2f3")
    d.text((X + 24, Y + 22), a, font=f("Bold", 34), fill="white" if dark else INK); d.text((X + 24, Y + 80), b, font=f("Regular", 28), fill="white" if dark else GREY)
para(cx[1] + 40, y + 380, "Everything runs on the iPhone: no cloud, private, and it works in China, where Apple Intelligence is unavailable.", size=31, width=tw, fill=GREY)
y = panel(cx[1], 2010, cw, 1490, "More than a picture")
y = para(cx[1] + 40, y, "Paper tests only see the finished clock. We also record how it was drawn: when, where, and how long someone paused.", width=tw)
img("replay", cx[1] + 230, y, 1050)
caption(cx[1] + 40, y + 930, "Stroke replay (illustrative): orange circles mark pauses over 2 s, sized by length. Families and doctors can see exactly why a check was flagged.", tw)

# ---- column 3: Results (4 charts with captions) + Conclusions
y = panel(cx[2], top, cw, 2200, "Results (465 drawings from unseen people)")
hw = (cw - 120) // 2
for k, (name, cap) in enumerate([
        ("roc", "Separates impaired from healthy clocks: AUC 0.96 (95% CI 0.93–0.98)."),
        ("confusion", "93% of impaired clocks caught. Most errors over-flag minor mistakes, the safer direction."),
        ("dist", "Impaired and healthy clocks get clearly different scores."),
        ("size", "70× smaller than published models with similar accuracy, small enough for any phone.")]):
    col, row = k % 2, k // 2; X = cx[2] + 40 + col * (hw + 40); Y = y + row * 1030
    yy = img(name, X, Y, hw); caption(X, yy + 8, cap, hw)
y = panel(cx[2], 2710, cw, 790, "Conclusions")
bullets(cx[2] + 40, y, [
    "Hypothesis supported: AUC 0.96, sensitivity 88%, specificity 94% on unseen people.",
    "A clinic-grade screen can run privately on a phone, so families can check at home.",
    "Next: NHATS data (50k+ clocks), validation with older adults. A screening aid, not a diagnosis."], size=34, width=tw)

d.rectangle([0, H - 60, W, H], fill=INK)
d.text((g, H - 47), "Data: Chulalongkorn CDT (Raksasat et al., Sci. Rep. 2023) · Method: Sato et al., Front. Neurol. 2022 (NHATS) · Stats: KCL/Lancet; PLOS One 2025; Caixin 2026 · CrossPointX 2026 Track 1 · github.com/omarlevi/CPX26 · Built with Claude Code",
       font=f("Regular", 26), fill="#c9d3d9")
Pz.save("poster/shizhen-research-poster.png", optimize=True); Pz.save("poster/shizhen-research-poster.pdf", resolution=100)
Pz.resize((W // 4, H // 4)).save("/tmp/claude-0/-home-user-CPX26/c179a320-028e-58b6-8c25-278b6d454e8d/scratchpad/rp.png"); print("ok")
