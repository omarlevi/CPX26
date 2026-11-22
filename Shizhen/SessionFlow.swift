import SwiftUI

/// The 3-minute check for the older adult. One instruction per screen, everything spoken aloud.
struct SessionFlow: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var link: FamilyLink
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    enum Step: Int { case tutorial, warmup, day, year, words, clock, recall, copy, analyzing, done }

    @State private var step: Step = .warmup
    @State private var result = SessionResult()
    @State private var words: [(zh: String, en: String)] = []
    @State private var warm = Drawing()
    @State private var clock = Drawing()
    @State private var copyDrawing = Drawing()
    @State private var stepStart = Date()
    @State private var restarts = 0
    @State private var interrupted = false
    @State private var chosen: Set<String> = []
    @StateObject private var listener = Listener()

    private var needsCopy: Bool {
        store.realSessions.filter { !$0.isDemo }.count < 3 || result.metrics.clockPoints == 0
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            Group {
                switch step {
                case .tutorial: tutorial
                case .warmup: warmup
                case .day: dayQuestion
                case .year: yearQuestion
                case .words: wordsStep
                case .clock: clockStep
                case .recall: recallStep
                case .copy: copyStep
                case .analyzing: ProgressView(T("正在分析…", "Analysing…")).controlSize(.large).frame(maxHeight: .infinity)
                case .done: doneStep
                }
            }
            .frame(maxWidth: 720)
            .transition(.opacity)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .onAppear(perform: begin)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && (step == .clock || step == .copy) { interrupted = true }
        }
    }

    // MARK: header

    private var header: some View {
        HStack {
            Button { Voice.shared.stop(); dismiss() } label: {
                Label(T("退出", "Exit"), systemImage: "xmark").font(.title3)
            }
            Spacer()
            if step != .done {
                ProgressView(value: Double(min(step.rawValue, 7)), total: 7).frame(width: 160)
            }
            Spacer()
            Button { speakCurrent() } label: {
                Label(T("再听一遍", "Repeat"), systemImage: "speaker.wave.2.fill").font(.title3)
            }
        }
    }

    // MARK: steps

    private var tutorial: some View {
        VStack(spacing: 16) {
            BigTitle(T("先练习一下", "Let's practise first"), T("用手指沿着虚线画", "Trace the dotted shape with your finger"))
            TutorialDemo().frame(height: 160)
            ZStack {
                ClockCanvas(drawing: $warm, startTime: stepStart)
                TutorialShape().stroke(style: StrokeStyle(lineWidth: 3, dash: [8, 8])).foregroundStyle(.gray.opacity(0.6))
                    .padding(60).allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.35), lineWidth: 2))
            BigButton(T("我会了", "Got it")) { store.data.hasSeenTutorial = true; warm = Drawing(); go(.warmup) }
        }
    }

    private var warmup: some View {
        VStack(spacing: 16) {
            BigTitle(T("热身：沿着圆圈画一圈", "Warm-up: trace the circle"), T("慢慢来，不用着急", "Take your time"))
            GeometryReader { g in
                ZStack {
                    ClockCanvas(drawing: $warm, startTime: stepStart)
                    Circle().stroke(style: StrokeStyle(lineWidth: 3, dash: [8, 8])).foregroundStyle(.gray.opacity(0.6))
                        .frame(width: min(g.size.width, g.size.height) * 0.6).allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.35), lineWidth: 2))
            BigButton(T("画好了", "Done"), enabled: !warm.isEmpty) {
                scoreWarmup(); go(.day)
            }
        }
    }

    private var dayQuestion: some View {
        let days = Calendar.current.weekdaySymbols
        let zhDays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let today = Calendar.current.component(.weekday, from: Date()) - 1
        return VStack(spacing: 16) {
            BigTitle(T("今天是星期几？", "What day of the week is it today?"), "")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(0..<7, id: \.self) { i in
                    ChoiceButton(AppStore.currentLanguage == .zh ? zhDays[i] : days[i]) {
                        if i == today { result.orientationScore += 1 }
                        go(.year)
                    }
                }
            }
            Spacer()
        }
    }

    private var yearQuestion: some View {
        let y = Calendar.current.component(.year, from: Date())
        let options = [y - 2, y - 1, y, y + 1]
        return VStack(spacing: 16) {
            BigTitle(T("今年是哪一年？", "What year is it?"), "")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(options, id: \.self) { o in
                    ChoiceButton(String(o)) {
                        if o == y { result.orientationScore += 1 }
                        go(.words)
                    }
                }
            }
            Spacer()
        }
    }

    private var wordsStep: some View {
        VStack(spacing: 24) {
            BigTitle(T("请记住这三个词", "Please remember these three words"), T("稍后我会请您说出来", "I'll ask you for them later"))
            HStack(spacing: 16) {
                ForEach(words.indices, id: \.self) { i in
                    Text(AppStore.currentLanguage == .zh ? words[i].zh : words[i].en)
                        .font(.system(size: 40, weight: .bold)).padding(.vertical, 28).frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            Spacer()
            BigButton(T("我记住了", "I've got them")) { go(.clock) }
        }
    }

    private var clockStep: some View {
        VStack(spacing: 12) {
            BigTitle(T("请画一个钟", "Draw a clock"),
                     T("写上所有数字，把指针指向十一点十分", "Put in all the numbers and set the hands to ten past eleven"))
            GuardedCanvas(drawing: $clock, startTime: stepStart, restarts: $restarts)
            HStack {
                Button(T("清除重画", "Clear")) { clock = Drawing() }.font(.title3).buttonStyle(.bordered)
                BigButton(T("画好了", "Done"), enabled: !clock.isEmpty) {
                    result.command = clock
                    result.metrics = ClockAnalyzer.analyze(clock, restarts: restarts, interrupted: interrupted)
                    listener.prepare()
                    go(.recall)
                }
            }
        }
    }

    private var recallStep: some View {
        let targets = words.map { AppStore.currentLanguage == .zh ? $0.zh : $0.en }
        let distractors = WordList.lists.enumerated().filter { $0.offset != store.wordListIndex }
            .flatMap { $0.element }.prefix(6).map { AppStore.currentLanguage == .zh ? $0.zh : $0.en }
        let tiles = (targets + distractors).sorted()
        return VStack(spacing: 16) {
            BigTitle(T("刚才的三个词是什么？", "What were the three words?"), T("可以说出来，也可以点选", "Say them, or tap them"))
            if listener.available {
                Button {
                    listener.isListening ? listener.stop() : listener.start()
                } label: {
                    Label(listener.isListening ? T("停止", "Stop") : T("按下说话", "Tap to speak"),
                          systemImage: listener.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2.bold()).frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent).tint(listener.isListening ? .red : .accentColor)
                if !listener.transcript.isEmpty { Text("“\(listener.transcript)”").font(.title3) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(tiles, id: \.self) { w in
                    let on = chosen.contains(w) || heard(w)
                    Button { if chosen.contains(w) { chosen.remove(w) } else if chosen.count < 3 { chosen.insert(w) } } label: {
                        Text(w).font(.title2.bold()).frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(on ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Spacer()
            BigButton(T("完成", "Done")) {
                listener.stop()
                let got = targets.filter { chosen.contains($0) || heard($0) }
                result.recalled = got; result.recallScore = got.count
                if needsCopy { go(.copy) } else { finish() }
            }
        }
    }

    private var copyStep: some View {
        VStack(spacing: 12) {
            BigTitle(T("照着这个钟画一个", "Copy this clock"), T("最后一步", "Last step"))
            // phone-first: small reference on top, full-width canvas below
            VStack(spacing: 10) {
                ReferenceClock().frame(width: 130, height: 130)
                GuardedCanvas(drawing: $copyDrawing, startTime: stepStart, restarts: .constant(0))
            }
            BigButton(T("画好了", "Done"), enabled: !copyDrawing.isEmpty) {
                result.copy = copyDrawing
                result.copyMetrics = ClockAnalyzer.analyze(copyDrawing, restarts: 0, interrupted: interrupted)
                finish()
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 24) {
            Image(systemName: result.status == .urgent || result.status == .doctor ? "heart.text.square.fill" : "checkmark.seal.fill")
                .font(.system(size: 90)).foregroundStyle(result.status == .urgent ? Color.red : Color.green)
            BigTitle(T("谢谢您！", "Thank you!"), T("您的家人已收到结果", "Your family has been updated"))
            if result.status == .urgent || result.status == .doctor {
                Text(RiskEngine.message(for: result.status)).font(.title3).multilineTextAlignment(.center)
                    .padding().background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
            } else {
                Text(T("下次检查：", "Next check: ") + store.nextDueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            BigButton(T("回到首页", "Back to home")) { dismiss() }
        }
    }

    // MARK: logic

    private func begin() {
        words = WordList.lists[store.wordListIndex]
        result.words = words.map { $0.zh + "/" + $0.en }
        go(store.data.hasSeenTutorial ? .warmup : .tutorial)
    }

    private func go(_ s: Step) {
        withAnimation { step = s }
        stepStart = Date()
        speak(s)
    }

    private func speakCurrent() { speak(step) }

    private func speak(_ s: Step) {
        let v = Voice.shared
        switch s {
        case .tutorial: v.say("我们先练习一下。用手指沿着虚线画。", "Let's practise first. Trace the dotted shape with your finger.")
        case .warmup: v.say("热身一下，请沿着圆圈画一圈。", "Warm-up. Please trace around the circle.")
        case .day: v.say("今天是星期几？", "What day of the week is it today?")
        case .year: v.say("今年是哪一年？", "What year is it?")
        case .words:
            let zh = words.map { $0.zh }.joined(separator: "，"), en = words.map { $0.en }.joined(separator: ", ")
            v.say("请记住这三个词：\(zh)。", "Please remember these three words: \(en).")
        case .clock: v.say("请画一个钟，写上所有数字，把指针指向十一点十分。", "Please draw a clock. Put in all the numbers, and set the hands to ten past eleven.")
        case .recall: v.say("刚才的三个词是什么？", "What were the three words I asked you to remember?")
        case .copy: v.say("最后一步，请照着这个钟画一个。", "Last step. Please copy this clock.")
        case .analyzing: break
        case .done: v.say("谢谢您，做得很好！", "Thank you, well done!")
        }
    }

    private func heard(_ w: String) -> Bool {
        !listener.transcript.isEmpty && listener.transcript.lowercased().contains(w.lowercased())
    }

    private func scoreWarmup() {
        let pts = warm.strokes.flatMap { $0.points }
        guard !pts.isEmpty else { return }
        let cx = warm.width / 2, cy = warm.height / 2, r = min(warm.width, warm.height) * 0.3
        let dev = pts.map { abs(hypot($0.x - cx, $0.y - cy) - r) / r }.reduce(0, +) / Double(pts.count)
        result.calibrationDeviation = dev
        result.calibrationTremor = ClockAnalyzer.tremor(warm.strokes, scale: max(warm.width, warm.height))
    }

    private func finish() {
        withAnimation { step = .analyzing }
        result.date = Date()
        let history = store.realSessions
        let (status, reasons, notes) = RiskEngine.evaluate(history: history, new: result, profile: store.data.profile)
        result.status = status; result.reasons = reasons; result.confidenceNotes = notes
        store.add(result)
        store.data.pendingExtraCheck = false
        link.send(.init(kind: .session, session: result))
        Notifier.scheduleReminder(at: store.nextDueDate)
        if status == .urgent { Notifier.post(title: RiskStatus.urgent.title, body: RiskEngine.message(for: .urgent), critical: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { go(.done) }
    }
}

// MARK: - Shared big-UI components

struct BigTitle: View {
    var title: String; var subtitle: String
    init(_ t: String, _ s: String) { title = t; subtitle = s }
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 34, weight: .bold)).multilineTextAlignment(.center)
            if !subtitle.isEmpty { Text(subtitle).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BigButton: View {
    var title: String; var enabled = true; var action: () -> Void
    init(_ t: String, enabled: Bool = true, action: @escaping () -> Void) { title = t; self.enabled = enabled; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 26, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 18)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!enabled)
    }
}

struct ChoiceButton: View {
    var title: String; var action: () -> Void
    init(_ t: String, action: @escaping () -> Void) { title = t; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 24, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 22)
        }
        .buttonStyle(.bordered)
    }
}

/// Spiral + star practice shape (never a clock, so the tutorial doesn't teach the test).
struct TutorialShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        for i in 0..<5 {
            let a = Double(i) * 4 * .pi / 5 - .pi / 2
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Animated stroke-order demo: a dot travels along the star, showing where to start and which way to go.
struct TutorialDemo: View {
    @State private var progress: CGFloat = 0
    var body: some View {
        ZStack {
            TutorialShape().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            TutorialShape().trim(from: 0, to: progress).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Image(systemName: "hand.point.up.left.fill").font(.largeTitle).foregroundStyle(.secondary)
                .offset(x: 50, y: 50)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) { progress = 1 } }
        .accessibilityLabel(T("示范：从顶部开始画星星", "Demo: start at the top and draw the star"))
    }
}
