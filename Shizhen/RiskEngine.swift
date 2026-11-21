import Foundation

/// Compares a new check with the person's own baseline and recent history.
/// Rule-based and fully explainable: every status comes with plain-language reasons.
enum RiskEngine {

    struct Baseline {
        var miniCog: Double; var think: (Double, Double); var pauses: (Double, Double)
        var impaired: (Double, Double); var speed: (Double, Double)
    }

    static func meanSD(_ v: [Double]) -> (Double, Double) {
        guard !v.isEmpty else { return (0, 1) }
        let m = v.reduce(0, +) / Double(v.count)
        let sd = sqrt(v.map { pow($0 - m, 2) }.reduce(0, +) / Double(max(1, v.count - 1)))
        return (m, max(sd, 0.15 * max(abs(m), 0.1)))   // floor so tiny baselines don't explode z-scores
    }

    static func baseline(_ s: [SessionResult]) -> Baseline? {
        let b = Array(s.prefix(3))
        guard b.count == 3 else { return nil }
        return Baseline(miniCog: b.map { Double($0.miniCog) }.reduce(0, +) / 3,
                        think: meanSD(b.map { $0.metrics.thinkTime }),
                        pauses: meanSD(b.map { Double($0.metrics.pauses.count) }),
                        impaired: meanSD(b.map { max(0, $0.metrics.mlImpairedProb) }),
                        speed: meanSD(b.map { $0.metrics.meanSpeed }))
    }

    /// - Parameters: history = earlier sessions (oldest first), new = the session being scored.
    static func evaluate(history: [SessionResult], new s: SessionResult, profile: Profile) -> (RiskStatus, [String], [String]) {
        var reasons: [String] = []
        let notes = confidenceNotes(s, profile: profile)
        let prev = history.last

        // 1. Sudden change -> urgent (possible delirium / stroke), checked even during baseline
        if let p = prev, s.date.timeIntervalSince(p.date) <= 15 * 86_400 {
            if p.miniCog - s.miniCog >= 3 {
                reasons.append(T("与上次相比突然明显下降（Mini-Cog \(p.miniCog)→\(s.miniCog)）",
                                 "Sudden drop since last check (Mini-Cog \(p.miniCog) → \(s.miniCog))"))
            }
            if p.orientationScore == 2 && s.orientationScore == 0 {
                reasons.append(T("上次能正确说出日期，这次不能", "Knew the day and year last time, not this time"))
            }
            if s.metrics.neglectFlag && !p.metrics.neglectFlag {
                reasons.append(T("数字集中在表盘一侧（可能是单侧忽略）", "Numbers crowded on one side (possible one-sided neglect)"))
            }
            if !reasons.isEmpty { return (.urgent, reasons, notes) }
        }

        let all = history + [s]
        guard let b = baseline(all) else {
            return (.building, [T("基线 \(min(all.count, 3))/3", "Baseline \(min(all.count, 3)) of 3")], notes)
        }
        guard all.count > 3 else {
            return (.stable, [T("基线已完成", "Baseline complete")], notes)
        }

        // 2. Sustained problems -> see a doctor
        var doctor = false
        if s.miniCog < 3, let p = prev, p.miniCog < 3 {
            doctor = true
            reasons.append(T("连续两次 Mini-Cog 低于 3 分", "Mini-Cog below 3 on two checks in a row"))
        }
        if s.metrics.mlImpairedProb > 0.6, let p = prev, p.metrics.mlImpairedProb > 0.6 {
            doctor = true
            reasons.append(T("AI 连续两次判断钟面有明显错误", "Clock model flagged clear errors twice in a row"))
        }
        let recent = all.suffix(3).map { Double($0.miniCog) }
        if recent.count == 3, recent[0] > recent[1], recent[1] > recent[2], recent[2] < b.miniCog - 1 {
            doctor = true
            reasons.append(T("连续三次逐渐下降", "Steady decline over the last three checks"))
        }
        if doctor { return (.doctor, reasons, notes) }

        // 3. Drift from personal baseline -> watch
        let zThink = (s.metrics.thinkTime - b.think.0) / b.think.1
        let zPause = (Double(s.metrics.pauses.count) - b.pauses.0) / b.pauses.1
        let zImp = (max(0, s.metrics.mlImpairedProb) - b.impaired.0) / b.impaired.1
        if s.miniCog < 3 { reasons.append(T("本次 Mini-Cog 低于 3 分", "Mini-Cog below 3 this time")) }
        if zThink > 1.5 { reasons.append(T("思考停顿时间比平时长", "Thinking pauses longer than usual")) }
        if zPause > 1.5 { reasons.append(T("停顿次数比平时多", "More hesitations than usual")) }
        if zImp > 1.5 { reasons.append(T("钟面比基线差", "Clock quality worse than baseline")) }
        if !reasons.isEmpty { return (.watch, reasons, notes) }
        return (.stable, [T("与基线相比稳定", "Stable compared with baseline")], notes)
    }

    static func confidenceNotes(_ s: SessionResult, profile: Profile) -> [String] {
        var n: [String] = []
        if profile.tremor || s.calibrationTremor > 3 || s.metrics.tremorIndex > 4 {
            n.append(T("检测到手抖，绘图结果准确度可能降低", "Tremor detected: drawing accuracy may be lower"))
        }
        if profile.vision == "impaired" || s.calibrationDeviation > 0.12 {
            n.append(T("视力问题可能影响结果", "Eyesight may affect this result"))
        }
        if !profile.readsNumbers || profile.educationYears < 6 {
            n.append(T("受教育年限较少，钟面评分可能偏低", "Limited schooling can lower clock scores"))
        }
        if let c = s.copyMetrics {
            if c.clockPoints == 2 && s.metrics.clockPoints == 0 {
                n.append(T("能临摹但不能凭记忆画：更像记忆/理解问题，而非视力或手部问题",
                           "Copies well but struggles from memory: points to memory, not eyesight or hands"))
            } else if c.clockPoints == 0 && s.metrics.clockPoints == 0 {
                n.append(T("临摹也有困难：可能与视觉空间、手部或视力有关",
                           "Copy is also hard: may involve vision, hands or visuospatial skills"))
            }
        }
        if s.metrics.wasInterrupted { n.append(T("画钟时离开了应用", "App was left during drawing")) }
        if s.metrics.restartCount > 0 { n.append(T("画出界重来 \(s.metrics.restartCount) 次", "Restarted \(s.metrics.restartCount)× after drawing off-canvas")) }
        return n
    }

    static func message(for status: RiskStatus) -> String {
        switch status {
        case .building: return T("正在建立个人基线，请继续完成检查。", "Building a personal baseline. Keep going.")
        case .stable: return T("与个人基线相比保持稳定。", "Stable compared with the personal baseline.")
        case .watch: return T("有一些变化。建议 3 天后再做一次检查。", "Some changes. We suggest an extra check in 3 days.")
        case .doctor: return T("这不是医学诊断。结果显示的变化常与记忆或思维问题相关。请尽快预约记忆门诊或神经内科。",
                               "This is not a medical diagnosis. These results show changes often linked to memory or thinking problems. Please see a licensed doctor (memory clinic or neurology) soon.")
        case .urgent: return T("突然的变化可能由谵妄、感染、药物或中风引起，这些往往可以治疗。请今天联系医生。如有口角歪斜、手臂无力或说话含糊，请立即拨打 120。",
                               "A sudden change like this can be caused by delirium, infection, medication effects or a stroke, which are often treatable. Contact a doctor today. If there is face drooping, arm weakness or slurred speech, call 120 now.")
        }
    }
}
