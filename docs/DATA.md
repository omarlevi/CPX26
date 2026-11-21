# Data & Models

## Research foundation
Shizhen's scoring follows the approach validated on the **U.S. National Health and Aging Trends Study (NHATS)**:
- Sato et al. (2022), 40k+ NHATS clocks, mini-VGG CNN: 90.1% / 77.2% balanced accuracy for executive-function decline and probable dementia.
- NHATS itself has scored its clocks automatically with deep learning since 2022.

We use the same task framing (free-drawn clock at 11:10, 0–5 quality scale, an image CNN), the same mini-VGG architecture family, and augmentation **without mirror flips**.

## Training data in v1 (this build)
| Dataset | What it is | Use in Shizhen |
|---|---|---|
| **Chulalongkorn CDT dataset**: Raksasat et al., *Sci. Reports* 2023 ([paper](https://www.nature.com/articles/s41598-023-44723-1), [data](https://github.com/cccnlab/CDT-API-Network)) | 3,108 clock drawings from older adults in Thailand, scored by clinicians on the **Shulman 0–5** scale | `ClockScorer.mlmodel`: impaired (0–3) / minor errors (4) / normal (5) |
| **Chulalongkorn multi-drawing MCI dataset** ([paper](https://www.biorxiv.org/content/10.1101/2021.12.15.472738v1), [data](https://github.com/cccnlab/MCI-multiple-drawings)) | 918 older adults with **digitally drawn** clocks + their MoCA score | `CognitiveScreen.mlmodel`: MoCA ≤ 24 (impaired) vs. ≥ 25. Fine-tuned from ClockScorer |

Both datasets are public research releases from Chulalongkorn University (Bangkok). They are **not redistributed** in this repository. `ml/train.py` reads them from a local folder. Credit: the cccnlab group (C. Chunharas, I. Chatnuntawech et al.).

**Why these fit Shizhen:** both cohorts are **Asian older adults**, closer to our first users in China than a U.S. cohort. The MCI set was drawn **on a tablet**, the same setting as our app.

## NHATS (next dataset; application submitted Nov 21, 2026)
NHATS public-use clock images (rounds 1–14) plus the Sample Person file (clock score `cg#dclkdraw`, age, sex, education, dementia classification) will be added as soon as registration is approved. `ml/train.py` has a `load_nhats()` entry point. The preprocessing, model and Core ML export are unchanged, so the swap is: download → implement the loader → `python ml/train.py --task shulman --data-root …` → replace the two `.mlpackage` files.

NHATS adds:
- 50k+ U.S. clocks (scale, and a second population for cross-cultural validation),
- demographics for the tabular **RiskModel** (clock + recall + age/sex/education → dementia class), testing Sato et al.'s suggestion that adding participant features improves accuracy.

## Process (kinematic) features
No public dataset contains labeled, timestamped digital clock strokes. In v1, these features (think time, pauses, pen lifts, speed, tremor) are therefore compared with **each person's own baseline**, using the direction of effect published in the digital CDT literature. Consented user data (opt-in) will train a kinematic model in v2.

## Reproduce
```bash
python -m venv mlenv && source mlenv/bin/activate
pip install "torch==2.7.0" "torchvision==0.22.0" coremltools scikit-learn matplotlib pandas pillow
git clone https://github.com/cccnlab/CDT-API-Network && unzip CDT-API-Network/clock_shulman.zip -d data/
git clone https://github.com/cccnlab/MCI-multiple-drawings && unzip MCI-multiple-drawings/images.zip -d data/mci/
cp MCI-multiple-drawings/label.csv data/mci/
python ml/train.py --task shulman --data-root data --out ml/out
python ml/train.py --task mci --data-root data --out ml/out --init ml/out/shulman.pt
```
The `.mlpackage` outputs go in `Shizhen/ML/`. Metrics and figures are written to `ml/out/`.
