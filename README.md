# Shizhen 时针

**A 3-minute, on-device brain check that families can run at home, and follow remotely.**

Shizhen ("hour hand") turns the clinically used Clock Drawing Test (CDT) and Mini-Cog-style word recall into a short check-in on iPhone or iPad. Core ML scores the drawing on the device. PencilKit captures *how* it was drawn: pauses, pen lifts, restarts and number planning. Each result is compared with that person's own baseline, and a linked relative's phone gets a status, a trend and an alert when something changes.

> Shizhen is a screening and monitoring aid, **not a medical device and not a diagnosis.** It tells families when to see a doctor.

Built for **CrossPointX 2026, Track 1: Apple Human-Centered Care**.

## The problem

- China has **323 million people aged 60+** (end of 2025), and about **60% live alone or with only a spouse** ("empty nesters"). [Caixin 2026](https://www.caixinglobal.com/2026-08-01/chinas-elderly-population-tops-323-million-as-aging-pressures-mount-102470288.html), [SCMP](https://www.scmp.com/news/china/politics/article/3283392/more-60-chinese-over-60-are-empty-nesters-survey-finds)
- About **15–17 million people** in China live with dementia, and a landmark study found **93% of cases went undetected**. [China CDC Weekly 2025](https://weekly.chinacdc.cn/fileCCDCW/journal/article/ccdcw/2025/38/PDF/CCDCW250379.pdf), [Quartz / KCL study](https://qz.com/108800/in-china-93-of-dementia-cases-go-undetected)
- Cases are projected to reach **115 million by 2050**, the fastest rise in the world. [PLOS One via The Star](https://www.thestar.com.my/aseanplus/aseanplus-news/2025/05/15/china-has-worlds-fastest-rise-in-dementia-with-up-to-115-million-cases-forecast-by-2050)
- The CDT is already used at national scale (Japan screened **1.5M+ drivers aged 75+** with it in FY2017). Scoring it, though, needs trained raters and takes time, so it stays inside clinics. [Sato et al., Front. Neurol. 2022](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9110693/)
- Deep learning can score the CDT automatically: 90.1% balanced accuracy for executive-function decline and 77.2% for probable dementia on 40k+ NHATS drawings (Sato et al. 2022). A 2025 Vision Transformer matched expert human coders. [Sci. Reports 2025](https://www.nature.com/articles/s41598-025-34064-6)

## What it does

| For the older adult (Taker) | For the family (Carer) |
|---|---|
| One big button, voice guidance in Mandarin, a 3-minute check | Status at a glance: Stable / Watch / See a doctor / Urgent |
| Warm-up trace (tremor and vision calibration) | Trend vs. personal baseline (Swift Charts) |
| Orientation, 3-word memory, clock drawing (command), recall, clock copy when needed | **Stroke replay**: watch the drawing again with pauses highlighted |
| Out-of-bounds guard (red glow, haptic, retry) | Adherence calendar, reminder schedule |
| Gentle, dignified results | Instant alert on sudden change (possible delirium or stroke) |

## Built with

- **Swift, SwiftUI**, Swift Charts, SwiftData
- **Core ML + Create ML**: clock-drawing image classifier; tabular risk model
- **Vision**: `VNRecognizeTextRequest` for digit placement, `VNCoreMLRequest`
- **PencilKit**: stroke points with timestamps (finger or Apple Pencil)
- **Speech + AVFoundation**: on-device recognition, zh-CN text-to-speech
- **MultipeerConnectivity**: Taker ↔ Carer sync for the offline demo (production target: CloudKit end-to-end encrypted sharing)
- **UserNotifications**: local reminders and alerts
- All inference runs **on the device**. No Apple Intelligence or Foundation Models are needed, so it works on mainland-China devices.

### Data, instruments and references
- **NHATS** (National Health and Aging Trends Study) clock drawings and scores, if access is granted. See `docs/SPEC.md` for how they're used. NHATS is sponsored by the U.S. National Institute on Aging.
- **Mini-Cog** (© S. Borson) inspires the word-recall + clock scoring. This hackathon prototype is non-commercial; commercial use requires a license.
- **4AT** delirium screening concepts (acute change, attention) inform the "sudden change" alert.
- Clinical/ML references are listed in `docs/SPEC.md`.

### AI-assisted development disclosure
This project was built during the hackathon (Nov 21–22, 2026) with help from **Claude Code (Anthropic)** for research, planning and code generation. Poster artwork is generated with **AMD Creative Factory → Image**, as the rules require.

## Run it

1. Open `Shizhen.xcodeproj` in Xcode 16+ (iOS 17+ target).
2. Pick an iPhone or iPad simulator and press **Run**.
3. To run on your own device: plug it in, select it, and under *Signing & Capabilities* choose your **Personal Team** (a free Apple ID works). Enable **Developer Mode** on the device when asked.

## License

[Apache License 2.0](LICENSE)
