import Foundation
import UIKit
import Vision
import CoreML

/// Turns a captured drawing into ClockMetrics, entirely on-device.
enum ClockAnalyzer {

    // MARK: - Public entry

    static func analyze(_ d: Drawing, restarts: Int, interrupted: Bool) -> ClockMetrics {
        var m = ClockMetrics()
        m.restartCount = restarts
        m.wasInterrupted = interrupted
        guard !d.isEmpty else { return m }
        kinematics(d, into: &m)
        geometry(d, into: &m)
        let ml = runModels(d)
        m.mlClass = ml.cls; m.mlImpairedProb = ml.impaired; m.mlNormalProb = ml.normal
        m.cognitiveImpairedProb = ml.cognitive
        m.clockPoints = miniCogClockPoints(m)
        return m
    }

    /// Mini-Cog clock component (2 normal / 0 abnormal) combining rules and the Core ML scorer.
    static func miniCogClockPoints(_ m: ClockMetrics) -> Int {
        let modelOK = m.mlImpairedProb < 0 ? true : m.mlImpairedProb < 0.5
        let numbersOK = m.numbersFound >= 9 && m.meanAngleErrorDeg < 30
        let modelSaysNormal = m.mlNormalProb >= 0.6 || m.mlClass == "minor_errors"
        if m.handsCorrect && modelOK && (numbersOK || modelSaysNormal) && !m.neglectFlag { return 2 }
        return 0
    }

    // MARK: - Process (kinematic) features

    static func kinematics(_ d: Drawing, into m: inout ClockMetrics) {
        let s = d.strokes.sorted { $0.start < $1.start }
        m.strokeCount = s.count
        m.latency = s.first?.start ?? 0
        m.totalTime = s.map { $0.end }.max() ?? 0
        m.inkTime = s.reduce(0) { $0 + max(0, $1.end - $1.start) }
        m.thinkTime = max(0, m.totalTime - m.inkTime)
        m.thinkRatio = m.totalTime > 0 ? m.thinkTime / m.totalTime : 0
        var pauses: [Pause] = []
        if m.latency > 2, let p = s.first?.points.first {
            pauses.append(Pause(x: p.x, y: p.y, t: 0, duration: m.latency))
        }
        for i in 1..<max(1, s.count) where s.count > 1 {
            let gap = s[i].start - s[i-1].end
            if gap > 2, let p = s[i].points.first {
                pauses.append(Pause(x: p.x, y: p.y, t: s[i-1].end, duration: gap))
            }
        }
        m.pauses = pauses
        let len = s.reduce(0) { $0 + $1.length }
        m.meanSpeed = m.inkTime > 0 ? len / m.inkTime : 0
        m.tremorIndex = tremor(s, scale: max(d.width, d.height))
    }

    /// High-frequency jitter: RMS distance between raw points and a moving-average smoothed path,
    /// normalised by canvas size (x1000). Healthy finger drawing is typically < 2.
    static func tremor(_ strokes: [Stroke], scale: Double) -> Double {
        var sum = 0.0, n = 0.0
        for st in strokes where st.points.count >= 7 {
            let p = st.points
            for i in 3..<(p.count - 3) {
                var mx = 0.0, my = 0.0
                for k in -3...3 { mx += p[i+k].x; my += p[i+k].y }
                mx /= 7; my /= 7
                sum += pow(p[i].x - mx, 2) + pow(p[i].y - my, 2); n += 1
            }
        }
        guard n > 0, scale > 0 else { return 0 }
        return sqrt(sum / n) / scale * 1000
    }

    // MARK: - Geometry (face, hands, numbers)

    struct Face { var cx: Double; var cy: Double; var r: Double }

    static func face(_ d: Drawing) -> Face {
        // the longest stroke is almost always the outline
        if let outline = d.strokes.max(by: { $0.length < $1.length }), outline.points.count > 10 {
            let cx = outline.points.map { $0.x }.reduce(0, +) / Double(outline.points.count)
            let cy = outline.points.map { $0.y }.reduce(0, +) / Double(outline.points.count)
            let r = outline.points.map { hypot($0.x - cx, $0.y - cy) }.reduce(0, +) / Double(outline.points.count)
            if r > 20 { return Face(cx: cx, cy: cy, r: r) }
        }
        let xs = d.strokes.flatMap { $0.points.map { $0.x } }, ys = d.strokes.flatMap { $0.points.map { $0.y } }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        return Face(cx: (minX + maxX) / 2, cy: (minY + maxY) / 2, r: max(maxX - minX, maxY - minY) / 2)
    }

    /// Clock angle in degrees, clockwise from 12 o'clock (screen coordinates, y down).
    static func clockAngle(_ x: Double, _ y: Double, _ f: Face) -> Double {
        var a = atan2(x - f.cx, -(y - f.cy)) * 180 / .pi
        if a < 0 { a += 360 }
        return a
    }

    static func angDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    static func geometry(_ d: Drawing, into m: inout ClockMetrics) {
        let f = face(d)
        // hands: straight-ish strokes with one end near the centre
        var handAngles: [Double] = []
        let outline = d.strokes.max(by: { $0.length < $1.length })
        for st in d.strokes where st != outline && st.points.count >= 2 {
            guard let a = st.points.first, let b = st.points.last else { continue }
            let chord = hypot(b.x - a.x, b.y - a.y)
            guard chord > f.r * 0.25, st.length > 0, chord / st.length > 0.75 else { continue }
            let da = hypot(a.x - f.cx, a.y - f.cy), db = hypot(b.x - f.cx, b.y - f.cy)
            let (near, far) = da < db ? (a, b) : (b, a)
            guard min(da, db) < f.r * 0.35 else { continue }
            _ = near
            handAngles.append(clockAngle(far.x, far.y, f))
        }
        m.handCount = handAngles.count
        let minuteOK = handAngles.contains { angDiff($0, 60) < 25 }       // pointing at 2
        let hourOK = handAngles.contains { angDiff($0, 335) < 30 }        // just before 11
        m.handsCorrect = minuteOK && hourOK

        // numbers via Vision text recognition on the rendered drawing
        let found = recognizeNumbers(d)
        var errors: [Double] = []
        var left = 0, right = 0
        var seen = Set<Int>()
        for (n, pt) in found where !seen.contains(n) {
            seen.insert(n)
            errors.append(angDiff(clockAngle(pt.x, pt.y, f), Double(n % 12) * 30))
            if pt.x < f.cx { left += 1 } else { right += 1 }
        }
        m.numbersFound = seen.count
        m.meanAngleErrorDeg = errors.isEmpty ? 180 : errors.reduce(0, +) / Double(errors.count)
        m.sequenceCorrect = m.numbersFound >= 9 && m.meanAngleErrorDeg < 30
        let total = max(1, left + right)
        m.leftRightBalance = Double(left) / Double(total)
        m.neglectFlag = seen.count >= 6 && (m.leftRightBalance < 0.2 || m.leftRightBalance > 0.8)
    }

    /// Returns recognised clock numbers (1-12) with their centre in drawing coordinates.
    static func recognizeNumbers(_ d: Drawing) -> [(Int, CGPoint)] {
        guard let img = render(d, size: CGSize(width: d.width, height: d.height), lineWidth: 5).cgImage else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.minimumTextHeight = 0.02
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        try? handler.perform([req])
        var out: [(Int, CGPoint)] = []
        for obs in req.results ?? [] {
            guard let cand = obs.topCandidates(1).first else { continue }
            let digits = cand.string.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            let bb = obs.boundingBox
            let center = CGPoint(x: bb.midX * d.width, y: (1 - bb.midY) * d.height)
            for n in digits where (1...12).contains(n) { out.append((n, center)) }
        }
        return out
    }

    // MARK: - Rendering

    static func render(_ d: Drawing, size: CGSize, lineWidth: CGFloat = 4, upTo time: Double = .infinity) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let sx = size.width / d.width, sy = size.height / d.height
            let c = ctx.cgContext
            c.setStrokeColor(UIColor.black.cgColor); c.setLineWidth(lineWidth)
            c.setLineCap(.round); c.setLineJoin(.round)
            for st in d.strokes {
                let pts = st.points.filter { $0.t <= time }
                guard let first = pts.first else { continue }
                c.move(to: CGPoint(x: first.x * sx, y: first.y * sy))
                if pts.count == 1 { c.addLine(to: CGPoint(x: first.x * sx + 0.5, y: first.y * sy)) }
                for p in pts.dropFirst() { c.addLine(to: CGPoint(x: p.x * sx, y: p.y * sy)) }
                c.strokePath()
            }
        }
    }

    /// Same preprocessing as ml/train.py: crop to ink, pad square (x1.1), 128x128 grayscale.
    static func modelInput(_ d: Drawing) -> CGImage? {
        let xs = d.strokes.flatMap { $0.points.map { $0.x } }, ys = d.strokes.flatMap { $0.points.map { $0.y } }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let side = max(w, h) * 1.1 + 2
        let ox = minX - (side - w) / 2, oy = minY - (side - h) / 2
        var shifted = d
        shifted.strokes = d.strokes.map { Stroke(points: $0.points.map { StrokePoint(x: $0.x - ox, y: $0.y - oy, t: $0.t) }) }
        shifted.width = side; shifted.height = side
        // line width matched to dataset appearance (~3px at 128)
        let big = render(shifted, size: CGSize(width: 512, height: 512), lineWidth: 10)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 128,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let src = big.cgImage else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        return ctx.makeImage()
    }

    // MARK: - Core ML

    private static let clockModel: MLModel? = loadModel("ClockScorer")
    private static let cognitiveModel: MLModel? = loadModel("CognitiveScreen")

    private static func loadModel(_ name: String) -> MLModel? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        return try? MLModel(contentsOf: url, configuration: cfg)
    }

    static var modelsAvailable: Bool { clockModel != nil }

    static func runModels(_ d: Drawing) -> (cls: String, impaired: Double, normal: Double, cognitive: Double) {
        guard let img = modelInput(d) else { return ("unavailable", -1, -1, -1) }
        var cls = "unavailable", imp = -1.0, norm = -1.0, cog = -1.0
        if let m = clockModel, let probs = predict(m, img) {
            imp = probs["impaired"] ?? -1; norm = probs["normal"] ?? -1
            cls = probs.max(by: { $0.value < $1.value })?.key ?? "unavailable"
        }
        if let m = cognitiveModel, let probs = predict(m, img) { cog = probs["impaired"] ?? -1 }
        return (cls, imp, norm, cog)
    }

    private static func predict(_ model: MLModel, _ img: CGImage) -> [String: Double]? {
        guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first,
              let constraint = model.modelDescription.inputDescriptionsByName[inputName]?.imageConstraint,
              let fv = try? MLFeatureValue(cgImage: img, constraint: constraint, options: nil),
              let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: fv]),
              let out = try? model.prediction(from: provider) else { return nil }
        for name in out.featureNames {
            if let dict = out.featureValue(for: name)?.dictionaryValue as? [String: NSNumber] {
                return dict.mapValues { $0.doubleValue }
            }
        }
        return nil
    }
}
