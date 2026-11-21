# Shizhen: Product & Build Spec

This is the source of truth for what we build. Priorities: **P0** = must work in the demo, **P1** = should have, **P2** = roadmap (poster and pitch only).

## 1. Users and roles

The app has two interfaces, chosen at first launch: **"I'm doing the check" (Taker)** and **"I'm looking after someone" (Carer)**.

- **Taker** (older adult): large type (Dynamic Type XL+), high contrast, one primary action per screen, every instruction spoken aloud (AVSpeechSynthesizer zh-CN, with an English toggle), full VoiceOver labels. Assume no reading of small text and no settings.
- **Carer** (adult child or relative): sets everything up, sees results, gets alerts.

### Lowering the barrier (adoption is the real problem)
1. **The Carer sets up everything** on their own phone: profile, schedule, reminder time.
2. **Invite → link**: the Carer shows a QR code or 6-digit code. The Taker's device scans or enters it once and is paired. No account or password for the Taker. (P0 in the demo: Multipeer pairing by code. P2: iCloud / Sign in with Apple / WeChat login and invite deep link. Those need a paid developer account and WeChat Open Platform approval.)
3. **Notification → straight into the check.** Tapping "Time for your brain check" opens step 1 directly.
4. **Home-screen widget** with one big button (P1). **Siri Shortcut** "脑力检查" (P2).
5. **Social nudge.** The Carer sees adherence and can tap "Remind Mom," which sends a local notification on the Taker's device (P0 via Multipeer).
6. The check is framed as a routine health check (like blood pressure), never as a "dementia test." We use the term 认知 (cognition), never 痴呆 ("idiocy").
7. P2 vision: built into iOS Health like the PHQ-9/GAD-7 mental-health assessments (iOS 17) and the AirPods hearing test. Then there's nothing to install.

## 2. Schedule (prevents practice effects and fatigue)
- **Baseline week**: 3 sessions on days 1, 3 and 7. Together they define the personal baseline (mean ± SD per metric). Until the baseline is complete, results show "Building baseline (2 of 3)" and no risk verdict.
- **Then every 14 days**, at a reminder time the Carer chooses. The Carer can also trigger an **extra check** ("I noticed something").
- **Word lists rotate** (6 lists of 3 words) so recall can't be memorized. The clock is always set to **11:10**, which keeps it comparable with NHATS and the literature (the "10" pulls attention toward the wrong number, which is a known sign of executive dysfunction).
- **Adherence calendar** for the Carer: completed, missed and upcoming sessions, like Medications in Apple Health.

## 3. Taker session flow (about 3 minutes)
0. **Tutorial** (first time, then optional): an animated finger traces a **spiral and a star** with stroke-order animation, and the user practices on a canvas. **We never show a clock in the tutorial**, because that would teach the test.
1. **Warm-up / calibration** (10 s, every session): trace a dotted circle, then tap 3 dots. This measures tremor jitter (RMS deviation from the guide path), speed and tap accuracy. It's used to adjust confidence for motor or vision problems.
2. **Orientation** (P0): "What day of the week is it?" (7 big buttons), then "What year is it?" (4 choices). Both are checked automatically against the system date.
3. **Three words**: spoken and shown for 5 s. The user taps "I remember them."
4. **Clock, command condition** (the core): "Draw a clock. Put in all the numbers. Set the hands to ten past eleven." The canvas is blank, with no reference image.
   - **Out-of-bounds guard**: if a stroke touches within 8 pt of the canvas edge, the border glows red, the canvas does a shake animation with a haptic, a spoken prompt says "Let's try again. Please stay inside the box," and the canvas clears. `restartCount` += 1 (restarts are recorded as a feature, a planning signal).
   - **Integrity**: if the app goes to the background mid-drawing, the session is flagged `wasInterrupted`. Time to first stroke and total time are recorded. A drawing that is implausibly fast and perfect after a previous impaired result gets flagged for review.
   - A "Done" button appears after the first stroke.
5. **Recall**: "Which 3 words did I say?" Speech (SFSpeechRecognizer zh-CN, `requiresOnDeviceRecognition` when supported) **or** tap 3 of 9 word tiles (fallback, always available).
6. **Clock, copy condition** (only at baseline sessions and when the command clock scores abnormal): a reference clock showing 11:10 is displayed for the user to copy. Poor command + good copy suggests a memory/semantic cause. Poor command + poor copy suggests visuospatial, motor or vision causes (or executive/vascular). This is how we help separate cognitive decline from eyesight or tremor.
7. **Finish**: "Thank you! Your family has been updated." The Taker sees a gentle summary. They never get a scary probability.

## 4. Scoring
### 4.1 Mini-Cog-style score (P0, rule-based, fully explainable)
- Recall: 0–3 (1 per word).
- Clock: 2 = normal (all 12 numbers in the correct order and position, hands pointing at 11 and 2), 0 = abnormal.
- Total 0–5. **< 3 = screen positive.**

### 4.2 Automatic clock analysis (P0)
- Render the strokes to a 512×512 grayscale image (black on white, uniform stroke width, cropped to the bounding box + margin). This matches the NHATS paper scans and removes scanning and cropping noise.
- **Vision OCR** (`VNRecognizeTextRequest`, digits) → for each detected number: its angle around the fitted circle center vs. the expected angle. Metrics: `numbersFound` (0–12), `meanAngleErrorDeg`, `sequenceCorrect`, `numbersOutsideFace`.
- **Circle fit** (least squares on the outermost long stroke): closure gap, roundness.
- **Hands**: the 2 longest straight-ish strokes near the center → angles. Target is hour ≈ 335° (just before 11), minute = 60° (the 2).
- **Hemispatial balance**: ratio of numbers on the left vs. right half. A heavy imbalance raises a **neglect / possible stroke** flag.
- **Core ML ClockScorer** (see §6): predicted NHATS 0–5 clock score + confidence.

### 4.3 Process (kinematic) features (P0, our differentiator)
These come from PencilKit `PKStrokePoint.timeOffset` and point locations:
- `totalTime`, `latencyToFirstStroke`, `inkTime`, `thinkTime` (= total − ink), `thinkRatio`
- `pauseCount` (gaps > 2 s between strokes) and the location of each pause → shown in the **stroke replay**
- `strokeCount`, `penLifts`, `restartCount`
- `meanSpeed`, `speedVariability`, `tremorIndex` (high-frequency jitter after smoothing; compared with the warm-up calibration)
- `numberOrderPlan`: the order the numbers were written in (anchoring 12-3-6-9 first is a sign of good planning).

The literature (MIT/Lahey dCDT, Linus Health) shows process features detect impairment that the final image hides. We have no labeled digital dataset yet, so in v1 these are judged **against the person's own baseline** (z-scores) plus published direction-of-effect (longer think time and more pauses = worse). v2 trains on consented user data.

### 4.4 Risk status (shown to the Carer)
| Status | Rule (v1) | Message |
|---|---|---|
| Building baseline | fewer than 3 sessions | "Baseline 2 of 3. Keep going." |
| Stable | within baseline ± 1.5 SD, Mini-Cog ≥ 3 | "Stable compared with Mom's baseline." |
| Watch | one metric group worse than baseline by > 1.5 SD, or a single Mini-Cog < 3 | "Some changes. We've scheduled an extra check in 3 days." |
| See a doctor | Mini-Cog < 3 on 2 consecutive sessions, OR a sustained decline over ≥ 3 sessions, OR risk model ≥ threshold | "We recommend booking a memory clinic (记忆门诊) or neurology appointment in the next few weeks." |
| **Urgent** | a sudden drop vs. the previous session within ≤ 14 days (e.g., Mini-Cog falls by ≥ 3, or orientation fails when it was correct before), OR a new neglect pattern | "A sudden change like this can be caused by delirium, infection, medication effects or a stroke, which are often treatable. Contact a doctor **today**. If there is face drooping, arm weakness or slurred speech, call **120** now." Both devices get notified. |

**Wording rule (decided):** we never say "probability of dementia." The fixed text for See a doctor is: *"This is not a medical diagnosis. These results show changes that are often linked to memory or thinking problems. Please see a licensed doctor soon."* We don't make calibrated probability claims, and false alarms carry real harm and liability.

**Confidence note:** when `tremorIndex`, the profile's vision/literacy flags or a poor copy condition suggest non-cognitive causes, show "Accuracy may be lower because of tremor / eyesight / limited literacy. The copy test suggests motor rather than memory difficulty."

## 5. Carer interface
- **Dashboard**: status pill, last check, next check, adherence calendar, "Remind now," "Extra check."
- **Trends** (Swift Charts): Mini-Cog total, ClockScorer score, think time, pauses vs. the baseline band.
- **Session detail**: final drawing; **stroke replay** (animated, scrubbable, with pause markers as pulsing dots sized by duration); digit-placement overlay (expected vs. actual angle); metric cards with plain-language explanations. This is the explainability answer to the paper's "it remains unclear which aspects the DNN used."
- **Profile** (feeds the risk model and the confidence notes): age, sex, years of education, handedness, vision (normal / glasses / impaired), tremor (Y/N), reads numbers comfortably (Y/N), family history of dementia (Y/N), known diagnoses.
- **Settings**: reminder time, cadence, language, **research data sharing (OFF by default)**, export de-identified data (CSV/JSON), pairing.

### Research data program (decided: opt-in only, no "selling" without consent)
Health data is *sensitive personal information* under China's PIPL. It needs separate, explicit consent and has cross-border restrictions. We build:
- a separate consent screen (plain language, revocable),
- de-identification (no name, birth year rounded to 5-year bands, no free text),
- an export file a research partner could receive.

Business line: "consented, de-identified longitudinal drawing data for research partners (hospitals, pharma trials, universities)." Consented data also trains the next model version.

## 6. Machine learning
### 6.1 ClockScorer (Core ML image model): P0 if data arrives, else the fallback
- **Data**: NHATS clock drawing images with interviewer scores 0–5 (rounds 1–9+, 40k+ images). Fallback if NHATS access is delayed: a public Roboflow "clock drawing" set + about 200 venue-collected finger drawings (normal + deliberately reproduced error types).
- **Labels**: 3 classes, **0–2 impaired / 3 borderline / 4–5 normal**, which is more robust than 6 classes for a 1-day training run. Also report 6-class accuracy if time allows.
- **Training**: Create ML Image Classifier on the Mac Studio (transfer learning, built-in augmentation: rotate, flip, noise). Split 70/15/15 **by participant** (so the same person never appears in both train and test). Optional: PyTorch/ViT on the RTX 4090, then coremltools.
- **Benchmarks we report**: balanced accuracy, confusion matrix, ROC-AUC on the held-out set; compared with Sato et al. 2022 (mini-VGG, 90.1% / 77.2% balanced accuracy for their tasks).

### 6.2 RiskModel (Core ML tabular): P1
- **Inputs**: clock score, recall, orientation, age, sex, education.
- **Label**: NHATS dementia classification (probable / possible / none), derived from NHATS variables with their documented algorithm.
- Create ML Boosted Tree classifier. **Headline stat**: AUC of clock-only vs. clock + demographics + recall. This directly tests the paper's suggestion that "adding participant features may improve accuracy."

### 6.3 Domain gap (paper → finger on phone)
Rendering normalization (§4.2) + augmentation + validation on venue finger drawings. Report finger-drawn accuracy separately and be upfront about it. The iPad (bigger canvas) is the primary demo device. The iPhone works too. Published mobile CDT scoring exists (U-Net/CNN with mobile sensor data, Sensors 2021).

## 7. Sync and notifications
- **Demo/offline**: MultipeerConnectivity (no internet or paid account needed). Sessions are encoded as JSON (drawing + metrics) and sent Taker → Carer. Commands go Carer → Taker (remind, extra check).
- **Local notifications** on both devices: reminders, "Mom finished her check ✓", Watch / See a doctor / Urgent alerts.
- **Production (P2)**: CloudKit shared zone (end-to-end encrypted), APNs push, iCloud backup so progress survives device changes.
- **All analysis runs on the device.** Only results are synced, between the family's own devices.

## 8. Demo mode (P0, essential for a 3-minute pitch)
Triple-tap the logo on the Carer dashboard to open **Demo Controls**. Everything it creates is labeled *Demo data*:
- "Load 3 months: stable" → baseline + 6 sessions
- "Load 3 months: gradual decline" → triggers See a doctor
- "Simulate sudden change" → the next session triggers **Urgent** on both devices
- "Reset"

Live flow at the table: the judge draws on the **iPad (Taker)** → the result appears on the **iPhone (Carer)** within seconds → tap Simulate sudden change → both devices alert.

## 9. Priority cut list
- **P0**: role picker, Taker flow (warm-up, orientation, words, clock with out-of-bounds guard, recall), rule-based scoring + kinematics, stroke replay, Carer dashboard + trends + session detail, Multipeer pairing + sync, local notifications, demo mode, accessibility basics.
- **P1**: Core ML ClockScorer, copy condition, RiskModel, profile-based confidence notes, consent + export, widget, tutorial animation.
- **P2 (pitch only)**: CloudKit/iCloud, WeChat login, deep-link invites, Siri, 4AT attention items, Parkinson's micrographia, depression screens, Apple Health integration.

## 10. References
- Sato K, Niimi Y, Mano T, Iwata A, Iwatsubo T. *Automated Evaluation of Conventional Clock-Drawing Test Using Deep Neural Network: Potential as a Mass Screening Tool to Detect Individuals With Cognitive Decline.* Front Neurol 2022;13:896403. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9110693/
- NHATS: Automated coding of the NHATS clock drawing test (2023). https://www.nhats.org/sites/default/files/public-documentation/Automated%20Coding%20of%20the%20NHATS%20Clock%20Drawing%20Test_07272023.pdf
- Using Deep Learning Neural Networks to Improve Dementia Detection: Automating Coding of the Clock-Drawing Test. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11527222/
- A novel vision transformer model produces clock drawing test scores as accurate as expert human coders. Sci Rep 2025. https://www.nature.com/articles/s41598-025-34064-6
- Automatic, Qualitative Scoring of the CDT Based on U-Net, CNN and Mobile Sensor Data. Sensors 2021. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8348723/
- Command vs. copy clock drawing in dementia subtypes. https://pmc.ncbi.nlm.nih.gov/articles/PMC3065510
- MIT dCDT / THink. https://clocksketch.csail.mit.edu/
- Reversible causes of cognitive impairment (review). https://touchneurology.com/alzheimers-disease-dementia/journal-articles/how-reversible-are-reversible-dementias/
