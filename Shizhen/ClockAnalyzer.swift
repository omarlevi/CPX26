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
        let modelOK = m.mlImpairedProb < 0 ? true : m.mlImpairedProb < 0.6   // Youden-optimal threshold on held-out test set (0.59)
        let numbersOK = m.numbersFound >= 10 && m.meanAngleErrorDeg < 20
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
        let outlineIndex = d.strokes.indices.max(by: { d.strokes[$0].length < d.strokes[$1].length })
        // hands: straight-ish strokes with one end near the centre
        var handAngles: [Double] = []
        var handIdx = Set<Int>()
        for (i, st) in d.strokes.enumerated() where i != outlineIndex && st.points.count >= 2 {
            guard let a = st.points.first, let b = st.points.last else { continue }
            let chord = hypot(b.x - a.x, b.y - a.y)
            guard chord > f.r * 0.25, st.length > 0, chord / st.length > 0.75 else { continue }
            let da = hypot(a.x - f.cx, a.y - f.cy), db = hypot(b.x - f.cx, b.y - f.cy)
            guard min(da, db) < f.r * 0.35 else { continue }
            let far = da < db ? b : a
            handAngles.append(clockAngle(far.x, far.y, f))
            handIdx.insert(i)
        }
        m.handCount = handAngles.count
        let minuteOK = handAngles.contains { angDiff($0, 60) < 25 }       // pointing at 2
        let hourOK = handAngles.contains { angDiff($0, 335) < 30 }        // just before 11
        m.handsCorrect = minuteOK && hourOK

        // numbers: cluster the remaining strokes (one cluster per written number), then read each cluster
        var candidates: [Stroke] = []
        for (i, st) in d.strokes.enumerated() where i != outlineIndex && !handIdx.contains(i) {
            let cx = st.points.map { $0.x }.reduce(0, +) / Double(max(1, st.points.count))
            let cy = st.points.map { $0.y }.reduce(0, +) / Double(max(1, st.points.count))
            if hypot(cx - f.cx, cy - f.cy) > f.r * 0.3 { candidates.append(st) }   // ignore centre dot / arrowheads
        }
        let marks = cluster(candidates, gap: f.r * 0.09)
        var errors: [Double] = []
        var labelled: [(angle: Double, n: Int)] = []
        var left = 0, right = 0
        for mk in marks.prefix(16) {
            let a = clockAngle(mk.cx, mk.cy, f)
            if mk.cx < f.cx - f.r * 0.05 { left += 1 } else if mk.cx > f.cx + f.r * 0.05 { right += 1 }
            if let n = readNumber(mk.strokes) {
                labelled.append((a, n))
                errors.append(angDiff(a, Double(n % 12) * 30))
            } else {
                // unread mark: how far is it from the nearest hour position?
                errors.append(angDiff(a, (a / 30).rounded() * 30))
            }
        }
        m.numbersFound = min(12, marks.count)
        m.numbersRead = labelled.count
        m.meanAngleErrorDeg = errors.isEmpty ? 0 : errors.reduce(0, +) / Double(errors.count)
        // sequence: read numbers should increase clockwise from 12
        let ordered = labelled.sorted { $0.angle < $1.angle }.map { $0.n % 12 }
        let inOrder = zip(ordered, ordered.dropFirst()).filter { $0.0 < $0.1 }.count
        let orderOK = ordered.count < 3 || Double(inOrder) / Double(ordered.count - 1) >= 0.8
        m.sequenceCorrect = m.numbersFound >= 10 && m.meanAngleErrorDeg < 20 && orderOK
        let total = max(1, left + right)
        m.leftRightBalance = Double(left) / Double(total)
        m.neglectFlag = marks.count >= 6 && (m.leftRightBalance < 0.2 || m.leftRightBalance > 0.8)
    }

    struct Mark { var strokes: [Stroke]; var minX, minY, maxX, maxY: Double
        var cx: Double { (minX + maxX) / 2 }; var cy: Double { (minY + maxY) / 2 } }

    /// Groups strokes whose bounding boxes are within `gap` of each other (e.g. the "1" and "2" of 12).
    static func cluster(_ strokes: [Stroke], gap: Double) -> [Mark] {
        var marks: [Mark] = []
        for st in strokes {
            let xs = st.points.map { $0.x }, ys = st.points.map { $0.y }
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { continue }
            var m = Mark(strokes: [st], minX: x0, minY: y0, maxX: x1, maxY: y1)
            var merged = true
            while merged {
                merged = false
                if let j = marks.firstIndex(where: { o in
                    !(m.maxX + gap < o.minX || o.maxX + gap < m.minX || m.maxY + gap < o.minY || o.maxY + gap < m.minY) }) {
                    let o = marks.remove(at: j)
                    m = Mark(strokes: o.strokes + m.strokes, minX: min(o.minX, m.minX), minY: min(o.minY, m.minY),
                             maxX: max(o.maxX, m.maxX), maxY: max(o.maxY, m.maxY))
                    merged = true
                }
            }
            marks.append(m)
        }
        return marks
    }

    /// Renders one cluster on its own and reads it with Vision (handles 1/l/I, 0/O look-alikes).
    static func readNumber(_ strokes: [Stroke]) -> Int? {
        let xs = strokes.flatMap { $0.points.map { $0.x } }, ys = strokes.flatMap { $0.points.map { $0.y } }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        let side = max(x1 - x0, y1 - y0, 10) * 1.8
        let ox = (x0 + x1) / 2 - side / 2, oy = (y0 + y1) / 2 - side / 2
        let local = Drawing(strokes: strokes.map { Stroke(points: $0.points.map { StrokePoint(x: $0.x - ox, y: $0.y - oy, t: $0.t) }) },
                            width: side, height: side)
        // wide canvas so two-digit numbers read left-to-right
        guard let img = render(local, size: CGSize(width: 160, height: 160), lineWidth: 6).cgImage else { return nil }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        req.minimumTextHeight = 0.1
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
        let fix: [Character: Character] = ["l": "1", "I": "1", "|": "1", "i": "1", "!": "1", "O": "0", "o": "0", "D": "0",
                                           "S": "5", "s": "5", "Z": "2", "z": "2", "B": "8", "g": "9", "q": "9", "G": "6", "b": "6", "T": "7"]
        for obs in req.results ?? [] {
            for cand in obs.topCandidates(3) {
                let cleaned = String(cand.string.compactMap { c -> Character? in
                    if c.isNumber { return c }
                    return fix[c]
                })
                if let n = Int(cleaned), (1...12).contains(n) { return n }
            }
        }
        return nil
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
