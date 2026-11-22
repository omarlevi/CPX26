import SwiftUI
import Charts

// MARK: - Dashboard

struct CarerDashboard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var link: FamilyLink
    @State private var showDemo = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let alert = store.latestAlert { AlertBanner(session: alert) }
                    if store.overdueDays > 1 || store.missedChecks > 0 { MissedCheckBanner() }
                    StatusCard()
                    actions
                    if store.realSessions.count >= 2 { TrendCard() }
                    AdherenceCard()
                    history
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(store.data.profile.name.isEmpty ? Relation.label(store.data.profile.relation) : store.data.profile.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "clock.badge.checkmark").font(.title2).foregroundStyle(Color.accentColor)
                        .onTapGesture(count: 3) { showDemo = true }
                        .accessibilityLabel("Shizhen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(T("设置", "Settings"))
                }
            }
            .sheet(isPresented: $showDemo) { DemoControls().environmentObject(store).environmentObject(link) }
            .sheet(isPresented: $showSettings) { CarerSettings().environmentObject(store).environmentObject(link) }
            .fullScreenCover(isPresented: Binding(get: { !store.data.carerSetupDone || !store.data.carerTourDone }, set: { _ in })) {
                CarerOnboarding().environmentObject(store).environmentObject(link)
            }
            .navigationDestination(for: SessionResult.self) { SessionDetail(session: $0) }
        }
        .onAppear { link.startHosting(code: store.data.pairingCode) }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                link.send(.init(kind: .remind))
            } label: { Label(T("提醒检查", "Remind now"), systemImage: "bell.badge").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
            Button {
                link.send(.init(kind: .extraCheck))
            } label: { Label(T("加做一次", "Extra check"), systemImage: "plus.circle").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
        }
        .disabled(link.connectedPeers.isEmpty)
        .overlay(alignment: .bottom) {
            if link.connectedPeers.isEmpty {
                Text(T("配对码 \(store.data.pairingCode)：在长辈的设备上输入", "Pairing code \(store.data.pairingCode): enter it on their device"))
                    .font(.caption).foregroundStyle(.secondary).offset(y: 22)
            }
        }
        .padding(.bottom, link.connectedPeers.isEmpty ? 22 : 0)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("历次检查", "All checks")).font(.headline)
            ForEach(store.realSessions.reversed()) { s in
                NavigationLink(value: s) {
                    HStack {
                        StatusPill(status: s.status)
                        VStack(alignment: .leading) {
                            Text(s.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                            Text("Mini-Cog \(s.miniCog)/5 · \(s.metrics.pauses.count) " + T("次停顿", "pauses"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if s.isDemo { Text(T("演示数据", "Demo data")).font(.caption2).padding(4).background(.yellow.opacity(0.3), in: Capsule()) }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            if store.realSessions.isEmpty {
                Text(T("还没有检查记录。在长辈的设备上开始第一次检查，或三击左上角图标加载演示数据。",
                       "No checks yet. Start the first check on their device, or triple-tap the logo to load demo data."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusPill: View {
    var status: RiskStatus
    var color: Color {
        switch status {
        case .building: return .gray
        case .stable: return .green
        case .watch: return .yellow
        case .doctor: return .orange
        case .urgent: return .red
        }
    }
    var body: some View {
        Text(status.title).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.2), in: Capsule()).foregroundStyle(color == .yellow ? Color.brown : color)
    }
}

struct AlertBanner: View {
    @EnvironmentObject var store: AppStore
    var session: SessionResult
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(session.status.title, systemImage: "exclamationmark.triangle.fill").font(.title3.bold())
            Text(RiskEngine.message(for: session.status)).font(.callout)
            ForEach(session.reasons, id: \.self) { Text("• " + $0).font(.callout) }
            HStack {
                NavigationLink(value: session) { Text(T("查看详情", "View details")).bold() }
                Spacer()
                Button(T("知道了", "Dismiss")) { store.latestAlert = nil }
            }
        }
        .padding()
        .foregroundStyle(.white)
        .background(session.status == .urgent ? Color.red : Color.orange, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Red warning when checks are being skipped (a gap is itself a warning sign).
struct MissedCheckBanner: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var link: FamilyLink
    var body: some View {
        let who = store.data.profile.name.isEmpty ? Relation.label(store.data.profile.relation) : store.data.profile.name
        VStack(alignment: .leading, spacing: 8) {
            Label(T("检查已中断", "Checks are being missed"), systemImage: "calendar.badge.exclamationmark").font(.title3.bold())
            if store.overdueDays > 1 {
                Text(T("\(who) 的检查已逾期 \(store.overdueDays) 天。上次检查是 \(store.daysSinceLast) 天前。",
                       "\(who)'s check is \(store.overdueDays) days overdue. Last check was \(store.daysSinceLast) days ago."))
            }
            if store.missedChecks > 0 {
                Text(T("近期共错过约 \(store.missedChecks) 次检查。间隔太长会让变化更难被及时发现。",
                       "About \(store.missedChecks) checks missed recently. Long gaps make changes harder to catch in time."))
            }
            Button {
                link.send(.init(kind: .remind))
            } label: { Label(T("现在提醒", "Remind now"), systemImage: "bell.fill").bold() }
                .buttonStyle(.bordered).tint(.white).disabled(link.connectedPeers.isEmpty)
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StatusCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var link: FamilyLink
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(status: store.currentStatus)
                Spacer()
                Label(link.connectedPeers.isEmpty ? T("未连接", "Not linked") : T("已连接", "Linked"),
                      systemImage: link.connectedPeers.isEmpty ? "link.badge.plus" : "link")
                    .font(.caption).foregroundStyle(link.connectedPeers.isEmpty ? Color.secondary : Color.green)
            }
            Text(RiskEngine.message(for: store.currentStatus)).font(.body)
            if let l = store.latest {
                ForEach(l.reasons, id: \.self) { Text("• " + $0).font(.callout).foregroundStyle(.secondary) }
                Divider()
                HStack {
                    Metric(T("上次检查", "Last check"), l.date.formatted(.relative(presentation: .named)))
                    Metric(T("下次", "Next"), store.nextDueDate.formatted(date: .abbreviated, time: .omitted))
                    Metric("Mini-Cog", "\(l.miniCog)/5")
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct Metric: View {
    var label: String; var value: String
    init(_ l: String, _ v: String) { label = l; value = v }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Trends

struct TrendCard: View {
    @EnvironmentObject var store: AppStore
    @State private var metric = 0
    var body: some View {
        let s = store.realSessions
        let base = Array(s.prefix(3))
        VStack(alignment: .leading, spacing: 10) {
            Text(T("趋势（与个人基线对比）", "Trend vs. personal baseline")).font(.headline)
            Picker("", selection: $metric) {
                Text("Mini-Cog").tag(0); Text(T("思考时间", "Think time")).tag(1); Text(T("钟面 AI", "Clock AI")).tag(2)
            }
            .pickerStyle(.segmented)
            Chart {
                if base.count == 3 {
                    let vals = base.map { value($0) }
                    let m = vals.reduce(0, +) / 3
                    RuleMark(y: .value("Baseline", m)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading) { Text(T("基线", "Baseline")).font(.caption2).foregroundStyle(.secondary) }
                }
                ForEach(s) { x in
                    LineMark(x: .value("Date", x.date), y: .value("Value", value(x))).interpolationMethod(.monotone)
                    PointMark(x: .value("Date", x.date), y: .value("Value", value(x)))
                        .foregroundStyle(color(x.status)).symbolSize(70)
                }
            }
            .frame(height: 200)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func value(_ s: SessionResult) -> Double {
        switch metric {
        case 0: return Double(s.miniCog)
        case 1: return s.metrics.thinkTime
        default: return max(0, s.metrics.mlImpairedProb) * 100
        }
    }
    private var caption: String {
        switch metric {
        case 0: return T("满分 5 分，低于 3 分为筛查阳性", "Out of 5; below 3 is a positive screen")
        case 1: return T("画钟时不落笔的秒数，越高说明计划越困难", "Seconds spent not drawing; higher = harder to plan")
        default: return T("Core ML 判断钟面受损的概率（%）", "Core ML probability the clock is impaired (%)")
        }
    }
    private func color(_ s: RiskStatus) -> Color {
        switch s { case .stable, .building: return .green; case .watch: return .yellow; case .doctor: return .orange; case .urgent: return .red }
    }
}

struct AdherenceCard: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        let days = (0..<56).reversed().map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
        let done = Set(store.realSessions.map { Calendar.current.startOfDay(for: $0.date) })
        VStack(alignment: .leading, spacing: 8) {
            Text(T("坚持情况（近 8 周）", "Consistency (last 8 weeks)")).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 14), spacing: 4) {
                ForEach(days, id: \.self) { d in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(done.contains(Calendar.current.startOfDay(for: d)) ? Color.accentColor : Color.secondary.opacity(0.15))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            Text(T("下次检查：", "Next check due: ") + store.nextDueDate.formatted(date: .complete, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Session detail

struct SessionDetail: View {
    let session: SessionResult
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { StatusPill(status: session.status); Spacer(); Text(session.date.formatted()).foregroundStyle(.secondary) }
                Text(RiskEngine.message(for: session.status))
                ForEach(session.reasons, id: \.self) { Text("• " + $0).font(.callout) }
                if !session.confidenceNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(T("准确度提示", "Accuracy notes"), systemImage: "info.circle").font(.subheadline.bold())
                        ForEach(session.confidenceNotes, id: \.self) { Text("• " + $0).font(.callout) }
                    }
                    .padding().background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                Text(T("画钟回放", "Stroke replay")).font(.headline)
                StrokeReplay(drawing: session.command, pauses: session.metrics.pauses).frame(maxHeight: 460)
                metricsGrid
                if let copy = session.copy {
                    Text(T("临摹", "Copy condition")).font(.headline)
                    StrokeReplay(drawing: copy, pauses: session.copyMetrics?.pauses ?? []).frame(maxHeight: 300)
                }
                Text(T("记忆：", "Memory: ") + "\(session.recallScore)/3 · " + T("定向：", "Orientation: ") + "\(session.orientationScore)/2")
                Text(T("这不是医学诊断。", "This is not a medical diagnosis.")).font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(T("检查详情", "Check details"))
    }

    private var metricsGrid: some View {
        let m = session.metrics
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 10) {
            Tile(T("钟面 AI", "Clock AI"), m.mlImpairedProb < 0 ? "—" : (m.mlClass == "impaired" ? T("受损", "Impaired") : m.mlClass == "normal" ? T("正常", "Normal") : T("轻微错误", "Minor errors")),
                 m.mlImpairedProb < 0 ? "" : String(format: T("受损概率 %.0f%%", "%.0f%% impaired"), m.mlImpairedProb * 100))
            Tile(T("数字", "Numbers"), "\(m.numbersFound)/12",
                 m.numbersFound == 0 ? T("未找到数字", "no numbers found")
                 : String(format: T("识别 %d 个 · 平均偏差 %.0f°", "%d read · avg. offset %.0f°"), m.numbersRead, m.meanAngleErrorDeg))
            Tile(T("指针", "Hands"), m.handsCorrect ? "✓ 11:10" : "✗", "\(m.handCount) " + T("条", "found"))
            Tile(T("总时间", "Total time"), String(format: "%.0fs", m.totalTime), String(format: T("开始前 %.1fs", "%.1fs before first stroke"), m.latency))
            Tile(T("思考时间", "Think time"), String(format: "%.0fs", m.thinkTime), String(format: "%.0f%%", m.thinkRatio * 100))
            Tile(T("停顿 >2秒", "Pauses >2s"), "\(m.pauses.count)", "\(m.strokeCount) " + T("笔", "strokes"))
            Tile(T("手抖指数", "Tremor index"), String(format: "%.1f", m.tremorIndex), m.tremorIndex > 4 ? T("偏高", "elevated") : T("正常", "typical"))
            Tile(T("空间分布", "Left/right balance"), String(format: "%.0f%% / %.0f%%", m.leftRightBalance * 100, (1 - m.leftRightBalance) * 100),
                 m.neglectFlag ? T("⚠️ 偏向一侧", "⚠️ one-sided") : "")
        }
    }
}

struct Tile: View {
    var title: String; var value: String; var sub: String
    init(_ t: String, _ v: String, _ s: String) { title = t; value = v; sub = s }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
            if !sub.isEmpty { Text(sub).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
