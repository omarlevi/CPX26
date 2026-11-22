import SwiftUI

// MARK: - Carer settings: profile, schedule, research consent, export, pairing

struct CarerSettings: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var link: FamilyLink
    @Environment(\.dismiss) private var dismiss
    @State private var reminder = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section(T("配对", "Pairing")) {
                    LabeledContent(T("配对码", "Pairing code"), value: store.data.pairingCode).font(.title3.monospacedDigit())
                    Text(T("在长辈的手机上选择“我来做检查”→“连接家人”，输入此号码。",
                           "On their phone choose \"I'm taking the check\" → \"Link family\" and enter this code.")).font(.caption)
                    LabeledContent(T("已连接", "Linked devices"), value: link.connectedPeers.isEmpty ? "—" : link.connectedPeers.joined(separator: ", "))
                }
                ProfileFields(profile: $store.data.profile)
                Section(T("提醒", "Reminders")) {
                    DatePicker(T("提醒时间", "Reminder time"), selection: $reminder, displayedComponents: .hourAndMinute)
                    Picker(T("频率", "How often"), selection: $store.data.settings.cadenceDays) {
                        Text(T("每周", "Weekly")).tag(7); Text(T("每两周（推荐）", "Every 2 weeks (recommended)")).tag(14); Text(T("每月", "Monthly")).tag(30)
                    }
                    Text(T("前一周做 3 次（第 1、3、7 天）建立个人基线。之后间隔进行，避免因练习而“学会”测试。",
                           "The first week has 3 checks (days 1, 3, 7) to build a personal baseline. After that, spacing them out stops people from simply learning the test."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(T("科研数据（可选）", "Research data (optional)")) {
                    Toggle(T("同意匿名分享数据用于痴呆研究", "Share de-identified data for dementia research"), isOn: $store.data.settings.researchConsent)
                    Text(T("默认关闭。开启后，仅分享去除姓名的绘图和分数（年龄按 5 岁分段），用于改进模型和医学研究。可随时关闭。符合《个人信息保护法》对敏感个人信息“单独同意”的要求。",
                           "Off by default. When on, only drawings and scores without names (age in 5-year bands) are shared to improve the model and support research. You can turn it off any time. Health data is sensitive personal information and needs this separate consent."))
                        .font(.caption).foregroundStyle(.secondary)
                    if store.data.settings.researchConsent, let url = store.researchExportURL() {
                        ShareLink(item: url) { Label(T("导出匿名数据", "Export de-identified data"), systemImage: "square.and.arrow.up") }
                    }
                }
                Section(T("语言与身份", "Language & role")) {
                    LanguageToggle()
                    Button(T("切换为“做检查”身份（单设备演示）", "Switch to the check-taker role (single-device demo)")) { store.data.role = .taker; dismiss() }
                    Button(T("重新查看使用介绍", "Show the intro again")) { store.data.carerTourDone = false; dismiss() }
                    Button(T("清除所有数据", "Erase all data"), role: .destructive) { store.resetAll(); dismiss() }
                }
                Section {
                    Text(T("Shizhen 是筛查与监测辅助工具，不是医疗器械，也不能诊断疾病。所有分析在本机完成。",
                           "Shizhen is a screening and monitoring aid, not a medical device, and cannot diagnose. All analysis runs on this device."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(T("设置", "Settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("完成", "Done")) { save(); dismiss() } } }
            .onAppear {
                var c = DateComponents(); c.hour = store.data.settings.reminderHour; c.minute = store.data.settings.reminderMinute
                reminder = Calendar.current.date(from: c) ?? Date()
            }
        }
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminder)
        store.data.settings.reminderHour = c.hour ?? 10; store.data.settings.reminderMinute = c.minute ?? 0
        Notifier.scheduleReminder(at: store.nextDueDate)
        link.send(.init(kind: .profile, profile: store.data.profile))
    }
}

// MARK: - Demo controls (triple-tap the logo). Everything created here is labelled "Demo data".

struct DemoControls: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var link: FamilyLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(T("载入 3 个月：稳定", "Load 3 months: stable")) { load(decline: false) }
                    Button(T("载入 3 个月：逐渐下降", "Load 3 months: gradual decline")) { load(decline: true) }
                    Button(T("模拟突然变化（紧急）", "Simulate sudden change (urgent)")) { sudden() }
                    Button(T("载入：错过检查", "Load: missed checks")) { load(decline: false, offsets: [75, 73, 69, 55, 27]) }
                    Button(T("清除演示数据", "Clear demo data"), role: .destructive) {
                        store.data.sessions.removeAll { $0.isDemo }; store.latestAlert = nil; dismiss()
                    }
                } footer: {
                    Text(T("演示数据会明确标注，仅用于展示。", "Demo data is clearly labelled and only for presentations."))
                }
            }
            .navigationTitle(T("演示控制", "Demo controls"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("完成", "Done")) { dismiss() } } }
        }
    }

    private func load(decline: Bool, offsets custom: [Double]? = nil) {
        store.data.sessions.removeAll { $0.isDemo }
        store.latestAlert = nil
        // baseline days 1,3,7 then every 14 days (about 3 months)
        let offsets: [Double] = custom ?? [92, 90, 86, 72, 58, 44, 30, 16, 2]
        var history: [SessionResult] = []
        for (i, d) in offsets.enumerated() {
            let severity = decline ? max(0, Double(i - 3)) / 5.0 : 0     // 0 ... 1.2
            var s = DemoFactory.session(daysAgo: d, severity: min(severity, 1), seed: i)
            let (st, r, n) = RiskEngine.evaluate(history: history, new: s, profile: store.data.profile)
            s.status = st; s.reasons = r; s.confidenceNotes = n
            history.append(s)
        }
        store.data.sessions.append(contentsOf: history)
        for s in history { link.send(.init(kind: .session, session: s)) }
        if let last = history.last, last.status == .doctor || last.status == .urgent {
            store.latestAlert = last
            Notifier.post(title: T("\(store.data.profile.name)：\(last.status.title)", "\(store.data.profile.name): \(last.status.title)"),
                          body: RiskEngine.message(for: last.status), critical: true)
        }
        dismiss()
    }

    private func sudden() {
        if store.realSessions.count < 3 { load(decline: false) }
        var s = DemoFactory.session(daysAgo: 0, severity: 1, seed: 99)
        s.orientationScore = 0; s.recallScore = 0
        s.metrics.neglectFlag = true; s.metrics.leftRightBalance = 0.9
        let (st, r, n) = RiskEngine.evaluate(history: store.realSessions, new: s, profile: store.data.profile)
        s.status = st; s.reasons = r; s.confidenceNotes = n
        store.add(s)
        link.send(.init(kind: .session, session: s))
        store.latestAlert = s
        Notifier.post(title: T("\(store.data.profile.name)：紧急", "\(store.data.profile.name): Urgent"),
                      body: RiskEngine.message(for: s.status), critical: true)
        dismiss()
    }
}

/// Generates synthetic clocks with realistic timing for demos (severity 0 = healthy, 1 = impaired).
enum DemoFactory {
    static func session(daysAgo: Double, severity: Double, seed: Int) -> SessionResult {
        var rng = SeededRNG(seed: UInt64(seed + 1))
        var s = SessionResult()
        s.isDemo = true
        s.date = Date().addingTimeInterval(-daysAgo * 86_400)
        s.words = WordList.lists[seed % 6].map { $0.zh + "/" + $0.en }
        s.recallScore = severity < 0.3 ? 3 : (severity < 0.7 ? 2 : 1)
        s.orientationScore = severity < 0.8 ? 2 : 1
        s.command = clock(severity: severity, rng: &rng)
        var m = ClockAnalyzer.analyze(s.command, restarts: severity > 0.7 ? 1 : 0, interrupted: false)
        // demo strokes have no handwriting for OCR to read, so set the image features from severity
        m.numbersFound = severity < 0.4 ? 12 : (severity < 0.8 ? 9 : 6)
        m.meanAngleErrorDeg = 6 + severity * 40
        m.handsCorrect = severity < 0.5
        m.handCount = 2
        m.mlImpairedProb = min(0.95, 0.05 + severity * 0.85 + Double.random(in: 0...0.05, using: &rng))
        m.mlNormalProb = max(0.02, 0.85 - severity * 0.8)
        m.mlClass = m.mlImpairedProb > 0.5 ? "impaired" : (m.mlNormalProb > 0.5 ? "normal" : "minor_errors")
        m.clockPoints = ClockAnalyzer.miniCogClockPoints(m)
        s.metrics = m
        return s
    }

    /// Draws a clock as timed strokes: face, 12 tick marks (stand-ins for numbers), two hands.
    static func clock(severity: Double, rng: inout SeededRNG) -> Drawing {
        var d = Drawing(strokes: [], width: 600, height: 600)
        var t = 0.8 + severity * 4
        let c = (x: 300.0, y: 300.0), r = 230.0
        func jitter(_ a: Double) -> Double { Double.random(in: -a...a, using: &rng) }
        // face
        var pts: [StrokePoint] = []
        let squash = 1 - severity * 0.25
        for i in 0...90 {
            let a = Double(i) / 90 * 2 * .pi * (1 - severity * 0.08)
            pts.append(StrokePoint(x: c.x + sin(a) * r + jitter(1 + severity * 4), y: c.y - cos(a) * r * squash + jitter(1 + severity * 4), t: t))
            t += 0.02 + severity * 0.01
        }
        d.strokes.append(Stroke(points: pts))
        // numbers (ticks); impaired clocks crowd numbers on the right side and skip some
        let count = severity < 0.4 ? 12 : (severity < 0.8 ? 10 : 7)
        for n in 1...count {
            t += 0.35 + severity * (n % 3 == 0 ? 4.5 : 1.2) + jitter(0.1)
            let spread = 1 - severity * 0.45
            let a = Double(n) * .pi / 6 * spread
            let p0 = (x: c.x + sin(a) * r * 0.82, y: c.y - cos(a) * r * 0.82 * squash)
            let p1 = (x: c.x + sin(a) * r * 0.70, y: c.y - cos(a) * r * 0.70 * squash)
            var tp: [StrokePoint] = []
            for k in 0...6 {
                let f = Double(k) / 6
                tp.append(StrokePoint(x: p0.x + (p1.x - p0.x) * f + jitter(severity * 2), y: p0.y + (p1.y - p0.y) * f + jitter(severity * 2), t: t))
                t += 0.03
            }
            d.strokes.append(Stroke(points: tp))
        }
        // hands: correct 11:10 when healthy; "pulled to 10" error when impaired
        let hourA = severity < 0.5 ? 335.0 : 300.0, minA = severity < 0.5 ? 60.0 : 300.0
        for (ang, len) in [(hourA, 0.45), (minA, 0.7)] {
            t += 0.6 + severity * 3
            var hp: [StrokePoint] = []
            for k in 0...10 {
                let f = Double(k) / 10, a = ang * .pi / 180
                hp.append(StrokePoint(x: c.x + sin(a) * r * len * f + jitter(severity * 2), y: c.y - cos(a) * r * len * f + jitter(severity * 2), t: t))
                t += 0.03
            }
            d.strokes.append(Stroke(points: hp))
        }
        return d
    }
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
