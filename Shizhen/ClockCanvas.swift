import SwiftUI
import PencilKit
import UIKit

/// Finger- or Pencil-friendly canvas that records every point with its timestamp.
/// If a stroke touches the edge, it reports `onOutOfBounds` and clears itself.
struct ClockCanvas: UIViewRepresentable {
    @Binding var drawing: Drawing
    var startTime: Date
    var lineWidth: CGFloat = 5
    var onOutOfBounds: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawingPolicy = .anyInput
        v.tool = PKInkingTool(.pen, color: .black, width: lineWidth)
        v.backgroundColor = .white
        v.isOpaque = true
        v.overrideUserInterfaceStyle = .light
        v.isScrollEnabled = false
        v.bouncesZoom = false
        v.delegate = context.coordinator
        v.accessibilityLabel = T("画布：请在这里画钟", "Canvas: draw the clock here")
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if drawing.isEmpty && !v.drawing.strokes.isEmpty {
            context.coordinator.ignoreNext = true
            v.drawing = PKDrawing()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ClockCanvas
        var ignoreNext = false
        init(_ p: ClockCanvas) { parent = p }

        func canvasViewDrawingDidChange(_ v: PKCanvasView) {
            if ignoreNext { ignoreNext = false; return }
            let size = v.bounds.size
            guard size.width > 0 else { return }
            let margin: CGFloat = 6
            var strokes: [Stroke] = []
            var outOfBounds = false
            for s in v.drawing.strokes {
                let base = s.path.creationDate.timeIntervalSince(parent.startTime)
                var pts: [StrokePoint] = []
                for p in s.path {
                    let loc = p.location.applying(s.transform)
                    if loc.x < margin || loc.y < margin || loc.x > size.width - margin || loc.y > size.height - margin {
                        outOfBounds = true
                    }
                    pts.append(StrokePoint(x: Double(loc.x), y: Double(loc.y), t: max(0, base + p.timeOffset)))
                }
                strokes.append(Stroke(points: pts))
            }
            if outOfBounds {
                ignoreNext = true
                v.drawing = PKDrawing()
                parent.drawing = Drawing(strokes: [], width: Double(size.width), height: Double(size.height))
                parent.onOutOfBounds()
                return
            }
            parent.drawing = Drawing(strokes: strokes, width: Double(size.width), height: Double(size.height))
        }
    }
}

/// Wraps the canvas with the red-glow + shake + haptic out-of-bounds feedback.
struct GuardedCanvas: View {
    @Binding var drawing: Drawing
    var startTime: Date
    @Binding var restarts: Int
    @State private var glow = false
    @State private var shake: CGFloat = 0

    var body: some View {
        ClockCanvas(drawing: $drawing, startTime: startTime) {
            restarts += 1
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Voice.shared.say("出界了，我们再试一次。请在框里画。", "Let's try again. Please stay inside the box.")
            withAnimation(.easeInOut(duration: 0.08).repeatCount(5, autoreverses: true)) { shake = 12 }
            withAnimation(.easeOut(duration: 0.2)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { shake = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { glow = false } }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(glow ? Color.red : Color.secondary.opacity(0.35), lineWidth: glow ? 6 : 2)
                .shadow(color: glow ? .red.opacity(0.7) : .clear, radius: glow ? 14 : 0)
        )
        .overlay(alignment: .top) {
            if glow {
                Text(T("请在框内画，再试一次", "Stay inside the box. Try again."))
                    .font(.title3.bold()).padding(10)
                    .background(.red, in: Capsule()).foregroundStyle(.white).padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .offset(x: shake)
    }
}

/// A reference clock (used only in the copy condition) and as the app motif.
struct ReferenceClock: View {
    var hour: Double = 11
    var minute: Double = 10
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 6
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.black), lineWidth: 3)
            for n in 1...12 {
                let a = Double(n) * .pi / 6
                let p = CGPoint(x: c.x + sin(a) * r * 0.8, y: c.y - cos(a) * r * 0.8)
                ctx.draw(Text("\(n)").font(.system(size: r * 0.18, weight: .medium)).foregroundColor(.black), at: p)
            }
            func hand(_ angle: Double, _ len: Double, _ w: CGFloat) {
                var p = Path(); p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + sin(angle) * r * len, y: c.y - cos(angle) * r * len))
                ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            hand((hour + minute / 60) * .pi / 6, 0.5, 5)
            hand(minute * .pi / 30, 0.75, 3)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(T("参考钟：十一点十分", "Reference clock showing ten past eleven"))
    }
}
