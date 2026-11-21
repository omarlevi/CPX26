import SwiftUI

/// Re-plays a drawing in real time. Pauses (> 2 s) appear as pulsing amber dots sized by duration,
/// so a family member or clinician can see exactly where the person hesitated.
struct StrokeReplay: View {
    let drawing: Drawing
    let pauses: [Pause]
    @State private var t: Double = 0
    @State private var playing = false
    @State private var speed: Double = 2
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            Canvas { ctx, size in
                let sx = size.width / drawing.width, sy = size.height / drawing.height
                let s = min(sx, sy)
                let ox = (size.width - drawing.width * s) / 2, oy = (size.height - drawing.height * s) / 2
                func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
                for st in drawing.strokes {
                    let pts = st.points.filter { $0.t <= t }
                    guard let f = pts.first else { continue }
                    var path = Path(); path.move(to: pt(f.x, f.y))
                    for p in pts.dropFirst() { path.addLine(to: pt(p.x, p.y)) }
                    ctx.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                for p in pauses where p.t + p.duration <= t {
                    let r = min(28, 6 + p.duration * 3)
                    let c = pt(p.x, p.y)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.orange.opacity(0.35)))
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.orange), lineWidth: 2)
                    ctx.draw(Text(String(format: "%.0fs", p.duration)).font(.caption2.bold()).foregroundColor(.orange),
                             at: CGPoint(x: c.x, y: c.y - r - 8))
                }
                // live "thinking" indicator while the pen is up
                if let active = pauses.first(where: { t >= $0.t && t < $0.t + $0.duration }) {
                    let c = pt(active.x, active.y)
                    let r = 6 + (t - active.t) * 3
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.orange), lineWidth: 3)
                }
            }
            .aspectRatio(drawing.width / max(drawing.height, 1), contentMode: .fit)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.3)))
            .accessibilityLabel(T("绘画回放，共 \(pauses.count) 次停顿", "Drawing replay with \(pauses.count) pauses"))

            HStack {
                Button { if t >= drawing.duration { t = 0 }; playing.toggle() } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle)
                }
                .accessibilityLabel(playing ? T("暂停", "Pause") : T("播放", "Play"))
                Slider(value: $t, in: 0...max(drawing.duration, 0.1))
                Text(String(format: "%.0f / %.0fs", t, drawing.duration)).font(.caption.monospacedDigit()).frame(width: 70)
                Picker("", selection: $speed) {
                    Text("1×").tag(1.0); Text("2×").tag(2.0); Text("4×").tag(4.0)
                }
                .pickerStyle(.segmented).frame(width: 120)
            }
        }
        .onReceive(timer) { _ in
            guard playing else { return }
            t = min(drawing.duration, t + speed / 30)
            if t >= drawing.duration { playing = false }
        }
    }
}
