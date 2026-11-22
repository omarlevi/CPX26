"""Lays out the Shizhen poster: AMD Creative Factory illustration (unaltered core visual) + text overlay and info panel."""
from PIL import Image, ImageDraw, ImageFont
F = "/usr/share/fonts/opentype/inter/"
def f(w, s): return ImageFont.truetype(F + f"Inter-{w}.otf", s)
ink, teal, grey, cream = (20, 33, 43), (15, 110, 122), (86, 101, 115), (250, 246, 238)
art = Image.open("poster/amd-raw.jpg").convert("RGB").resize((2048, 3072), Image.LANCZOS)
W, H = 2048, 3072 + 1500
P = Image.new("RGB", (W, H), cream); P.paste(art, (0, 0)); d = ImageDraw.Draw(P)
def wrap(text, font, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=font) <= width: cur = t
        else: lines.append(cur); cur = w
    lines.append(cur); return lines
def para(x, y, text, font, width, fill=ink, gap=1.35):
    for ln in wrap(text, font, width):
        d.text((x, y), ln, font=font, fill=fill); y += int(font.size * gap)
    return y
d.text((120, 130), "SHIZHEN", font=f("Bold", 150), fill=ink)
d.text((126, 310), "A 3-minute brain check your family can follow.", font=f("Medium", 62), fill=teal)
y = para(126, 430, "An iPhone app that turns the clinically used Clock Drawing Test into an on-device AI check-in for older adults, with a linked view for the family member who lives far away.", f("Regular", 46), 1750, grey)
x = 126; y += 40
for big, small in [("323M", "Chinese aged 60+"), ("~60%", "live without children"), ("93%", "of dementia went undetected")]:
    d.text((x, y), big, font=f("Bold", 96), fill=ink); d.text((x, y + 112), small, font=f("Regular", 36), fill=grey); x += 620
y0 = 3072; d.rectangle([0, y0, W, H], fill=(245, 247, 248))
col, cw = [120, 1090], 860
def section(x, y, title, items):
    d.text((x, y), title.upper(), font=f("Bold", 40), fill=teal); y += 70
    for it in items: y = para(x, y, it, f("Regular", 38), cw) + 18
    return y
section(col[0], y0 + 90, "Who & what", [
    "Users: empty-nest elders (60%+ of China's 60+) and adult children in another city.",
    "Problem: decline is noticed late. Testing means a clinic visit, and the word for dementia carries stigma."])
section(col[0], y0 + 560, "How it works", [
    "1. Warm-up trace measures tremor.", "2. Day + year, then 3 words to remember.",
    "3. Draw a clock at 11:10 with a finger.", "4. Type the 3 words back.",
    "5. Family phone gets the status, the trend vs. a personal baseline, and the stroke replay."])
section(col[1], y0 + 90, "On-device AI", [
    "Core ML ClockScorer, tested on 465 drawings from unseen people: AUC 0.96, sensitivity 88%, specificity 94%.",
    "Process data: when, where and how long every pause happened, not just the final picture.",
    "Alerts: steady decline, sudden change (possible delirium or stroke), numbers crowded on one side, tremor, missed checks."])
section(col[1], y0 + 760, "Design takeaways", [
    "One big button, voice guidance, no account for the elder.",
    "Compare each person with themselves, not with others.",
    "Private by design: no cloud, works in China. Not a diagnosis: it tells families when to see a doctor."])
d.text((120, H - 110), "Swift · SwiftUI · Core ML · Vision · PencilKit · Swift Charts · MultipeerConnectivity        github.com/omarlevi/CPX26", font=f("Medium", 32), fill=grey)
d.text((120, H - 60), "Track 1: Apple Human-Centered Care · CrossPointX 2026 · Illustration generated with AMD Creative Factory", font=f("Regular", 28), fill=grey)
P.save("poster/shizhen-poster.png", optimize=True)
P.save("poster/shizhen-poster.pdf", resolution=200)
