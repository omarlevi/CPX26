import Foundation
import CoreGraphics

enum Role: String, Codable { case taker, carer }
enum AppLanguage: String, Codable, CaseIterable { case zh, en }

// MARK: - Drawing capture

struct StrokePoint: Codable, Hashable {
    var x: Double
    var y: Double
    /// seconds since the drawing step started
    var t: Double
}

struct Stroke: Codable, Hashable {
    var points: [StrokePoint]
    var start: Double { points.first?.t ?? 0 }
    var end: Double { points.last?.t ?? 0 }
    var length: Double {
        guard points.count > 1 else { return 0 }
        var d = 0.0
        for i in 1..<points.count { d += hypot(points[i].x - points[i-1].x, points[i].y - points[i-1].y) }
        return d
    }
}

struct Drawing: Codable, Hashable {
    var strokes: [Stroke] = []
    var width: Double = 600
    var height: Double = 600
    var duration: Double { strokes.map { $0.end }.max() ?? 0 }
    var isEmpty: Bool { strokes.isEmpty }
}

// MARK: - Analysis output

struct Pause: Codable, Hashable {
    var x: Double
    var y: Double
    var t: Double
    var duration: Double
}

struct ClockMetrics: Codable, Hashable {
    // final-image features
    var numbersFound: Int = 0
    var meanAngleErrorDeg: Double = 0
    var sequenceCorrect: Bool = false
    var handsCorrect: Bool = false
    var handCount: Int = 0
    var neglectFlag: Bool = false
    var leftRightBalance: Double = 0.5
    // Core ML
    var mlClass: String = "unavailable"
    var mlImpairedProb: Double = -1
    var mlNormalProb: Double = -1
    var cognitiveImpairedProb: Double = -1
    // process (kinematic) features
    var totalTime: Double = 0
    var latency: Double = 0
    var inkTime: Double = 0
    var thinkTime: Double = 0
    var thinkRatio: Double = 0
    var pauses: [Pause] = []
    var strokeCount: Int = 0
    var restartCount: Int = 0
    var meanSpeed: Double = 0
    var tremorIndex: Double = 0
    var wasInterrupted: Bool = false
    /// Mini-Cog clock component: 2 = normal, 0 = abnormal
    var clockPoints: Int = 0
}

enum RiskStatus: String, Codable {
    case building, stable, watch, doctor, urgent

    var title: String {
        switch self {
        case .building: return T("建立基线中", "Building baseline")
        case .stable: return T("稳定", "Stable")
        case .watch: return T("需要留意", "Watch")
        case .doctor: return T("建议就医", "See a doctor")
        case .urgent: return T("紧急", "Urgent")
        }
    }
}

struct SessionResult: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var words: [String] = []
    var recalled: [String] = []
    var recallScore: Int = 0
    var orientationScore: Int = 0          // 0-2 (day of week, year)
    var calibrationTremor: Double = 0
    var calibrationDeviation: Double = 0
    var command = Drawing()
    var copy: Drawing? = nil
    var metrics = ClockMetrics()
    var copyMetrics: ClockMetrics? = nil
    var status: RiskStatus = .building
    var reasons: [String] = []
    var confidenceNotes: [String] = []
    var isDemo = false

    var miniCog: Int { recallScore + metrics.clockPoints }
}

struct Profile: Codable, Hashable {
    var name: String = "妈妈 Mom"
    var age: Int = 72
    var sex: String = "F"
    var educationYears: Int = 9
    var handedness: String = "R"
    var vision: String = "glasses"   // normal / glasses / impaired
    var tremor: Bool = false
    var readsNumbers: Bool = true
    var familyHistory: Bool = false
}

struct Settings: Codable, Hashable {
    var reminderHour = 10
    var reminderMinute = 0
    var cadenceDays = 14
    var researchConsent = false
    var language: AppLanguage = .zh
}

// MARK: - Word lists (Mini-Cog versions 1-6, © S. Borson; non-commercial prototype use)

struct WordList {
    static let lists: [[(zh: String, en: String)]] = [
        [("香蕉", "banana"), ("日出", "sunrise"), ("椅子", "chair")],
        [("领导", "leader"), ("季节", "season"), ("桌子", "table")],
        [("村庄", "village"), ("厨房", "kitchen"), ("婴儿", "baby")],
        [("河流", "river"), ("国家", "nation"), ("手指", "finger")],
        [("船长", "captain"), ("花园", "garden"), ("照片", "picture")],
        [("女儿", "daughter"), ("天堂", "heaven"), ("高山", "mountain")]
    ]
}

// MARK: - Localisation helper

/// Returns the Chinese or English string depending on the current app language.
func T(_ zh: String, _ en: String) -> String {
    AppStore.currentLanguage == .zh ? zh : en
}
