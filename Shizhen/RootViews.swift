import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Group {
            switch store.data.role {
            case .none: RolePicker()
            case .some(.taker): TakerHome()
            case .some(.carer): CarerDashboard()
            }
        }
        .id(store.data.settings.language)   // re-render all strings when language changes
    }
}

struct LanguageToggle: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Picker("", selection: Binding(get: { store.data.settings.language }, set: { store.setLanguage($0) })) {
            Text("中文").tag(AppLanguage.zh); Text("EN").tag(AppLanguage.en)
        }
        .pickerStyle(.segmented).frame(width: 130)
        .accessibilityLabel("Language")
    }
}

// MARK: - Role picker (first launch)

struct RolePicker: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 28) {
            HStack { Spacer(); LanguageToggle() }
            Spacer()
            ReferenceClock().frame(width: 140)
            Text("时针 Shizhen").font(.system(size: 44, weight: .bold))
            Text(T("3 分钟脑力小检查，家人随时了解", "A 3-minute brain check your family can follow"))
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 14) {
                RoleButton(icon: "figure.and.child.holdinghands", title: T("我来照顾家人", "I'm looking after someone"),
                           subtitle: T("设置、查看结果、接收提醒", "Set up, see results, get alerts")) {
                    store.data.role = .carer; Notifier.requestPermission()
                }
                RoleButton(icon: "hand.draw", title: T("我来做检查", "I'm doing the check"),
                           subtitle: T("大字体，有语音引导", "Large text, spoken guidance")) {
                    store.data.role = .taker; Notifier.requestPermission()
                }
            }
            Spacer()
            Text(T("所有分析都在本机完成。这不是医学诊断。", "All analysis happens on this device. Not a medical diagnosis."))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: 640)
    }
}

struct RoleButton: View {
    var icon: String; var title: String; var subtitle: String; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 34)).frame(width: 50)
                VStack(alignment: .leading) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Taker home: one giant button

struct TakerHome: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var link: FamilyLink
    @State private var running = false
    @State private var code = ""
    @State private var showPair = false
    @State private var showSwitch = false

    var body: some View {
        VStack(spacing: 26) {
            HStack {
                Button { showPair = true } label: {
                    Label(link.connectedPeers.isEmpty ? T("连接家人", "Link family") : T("已连接家人", "Family linked"),
                          systemImage: link.connectedPeers.isEmpty ? "link.badge.plus" : "person.2.fill")
                }
                .font(.title3)
                Spacer()
                LanguageToggle()
            }
            Spacer()
            Text(greeting).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center)
            if store.data.pendingExtraCheck {
                Label(T("家人请您做一次检查", "Your family asked for a check"), systemImage: "heart.fill")
                    .font(.title3.bold()).padding().background(Color.pink.opacity(0.15), in: Capsule())
            }
            Button { running = true } label: {
                VStack(spacing: 10) {
                    Image(systemName: "hand.draw.fill").font(.system(size: 64))
                    Text(T("开始今天的检查", "Start today's check")).font(.system(size: 34, weight: .bold))
                    Text(T("大约 3 分钟", "About 3 minutes")).font(.title3)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 560).padding(.vertical, 46)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 32))
            }
            .accessibilityLabel(T("开始今天的检查，大约三分钟", "Start today's check, about three minutes"))
            Text(T("下次检查：", "Next check: ") + store.nextDueDate.formatted(date: .abbreviated, time: .shortened))
                .font(.title3).foregroundStyle(.secondary)
            Spacer()
            Button(T("切换身份", "Switch role")) { showSwitch = true }.font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(28)
        .fullScreenCover(isPresented: $running) { SessionFlow() }
        .sheet(isPresented: $showPair) { pairSheet }
        .confirmationDialog(T("切换身份？", "Switch role?"), isPresented: $showSwitch) {
            Button(T("切换为家属", "Switch to carer")) { store.data.role = .carer }
            Button(T("重新选择", "Choose again")) { store.data.role = nil }
        }
        .onAppear { if !store.data.hasSeenTutorial { Voice.shared.say("您好！点一下蓝色大按钮开始。", "Hello! Tap the big button to start.") } }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let zh = h < 12 ? "早上好" : (h < 18 ? "下午好" : "晚上好")
        let en = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        return T("\(zh)！", "\(en)!")
    }

    private var pairSheet: some View {
        VStack(spacing: 20) {
            BigTitle(T("连接家人", "Link with family"), T("输入家人手机上显示的 6 位数字", "Enter the 6-digit code shown on your family member's phone"))
            TextField("000000", text: $code)
                .keyboardType(.numberPad).font(.system(size: 44, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            if link.isSearching { ProgressView(T("正在连接…", "Connecting…")) }
            if !link.connectedPeers.isEmpty {
                Label(T("已连接：", "Linked: ") + link.connectedPeers.joined(separator: ", "), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            }
            BigButton(T("连接", "Link"), enabled: code.count == 6) { link.join(code: code) }
            Button(T("关闭", "Close")) { showPair = false }
        }
        .padding(28)
        .presentationDetents([.medium, .large])
    }
}
