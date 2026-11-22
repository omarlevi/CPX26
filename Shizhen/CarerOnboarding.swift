import SwiftUI

/// Profile fields shared by first-time setup and Settings.
struct ProfileFields: View {
    @Binding var profile: Profile

    var body: some View {
        Section(T("TA 是您的…", "They are your…")) {
            Picker(T("关系", "Relationship"), selection: $profile.relation) {
                ForEach(Relation.all, id: \.self) { Text(Relation.label($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .onChange(of: profile.relation) { _, r in
                // keep the name in sync unless the family typed their own
                if profile.name.isEmpty || Relation.all.map({ Relation.label($0) }).contains(profile.name) || ["Mom", "Dad", "Grandma", "Grandpa", "Spouse"].contains(profile.name) {
                    profile.name = r == "other" ? "" : Relation.label(r)
                }
            }
            TextField(T("称呼（如：王阿姨）", "What you call them (e.g. Grandma Li)"), text: $profile.name)
        }
        Section(T("基本信息（用于提高准确度）", "Basics (used to improve accuracy)")) {
            HStack {
                Text(T("年龄", "Age")).font(.headline)
                Picker(T("年龄", "Age"), selection: $profile.age) {
                    ForEach(40...110, id: \.self) { Text(T("\($0) 岁", "\($0) years old")).tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().frame(height: 110)
            }
            HStack {
                Text(T("受教育年限", "Years of schooling")).font(.headline)
                Picker(T("受教育年限", "Years of schooling"), selection: $profile.educationYears) {
                    ForEach(0...25, id: \.self) { Text(T("\($0) 年", "\($0) years")).tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().frame(height: 110)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(T("性别", "Sex")).font(.headline)
                Picker(T("性别", "Sex"), selection: $profile.sex) {
                    Text(T("女", "Female")).tag("F"); Text(T("男", "Male")).tag("M")
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(T("写字用哪只手", "Which hand do they write with?")).font(.headline)
                Picker(T("写字用哪只手", "Writing hand"), selection: $profile.handedness) {
                    Text(T("右手", "Right hand")).tag("R"); Text(T("左手", "Left hand")).tag("L")
                }
                .pickerStyle(.segmented).labelsHidden()
            }
        }
        Section(T("可能影响结果的情况", "Things that can affect results")) {
            Picker(T("视力", "Eyesight"), selection: $profile.vision) {
                Text(T("正常", "Normal")).tag("normal"); Text(T("戴眼镜", "Glasses")).tag("glasses"); Text(T("视力差", "Poor")).tag("impaired")
            }
            Toggle(T("手抖", "Hand tremor"), isOn: $profile.tremor)
            Toggle(T("能轻松认读数字", "Reads numbers easily"), isOn: $profile.readsNumbers)
            Toggle(T("家族中有人患痴呆", "Family history of dementia"), isOn: $profile.familyHistory)
        }
    }
}

/// First launch for the family member: 1) profile, 2) quick tour of the dashboard.
struct CarerOnboarding: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var link: FamilyLink
    @State private var page = 0

    var body: some View {
        if !store.data.carerSetupDone {
            NavigationStack {
                Form {
                    ProfileFields(profile: $store.data.profile)
                }
                .navigationTitle(T("设置资料", "Set up their profile"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(T("下一步", "Next")) { store.data.carerSetupDone = true }.bold()
                    }
                }
            }
        } else {
            tour
        }
    }

    private struct Card: Identifiable { let id: Int; let icon: String; let title: String; let body: String }

    private var cards: [Card] {
        let who = store.data.profile.name.isEmpty ? Relation.label(store.data.profile.relation) : store.data.profile.name
        return [
            Card(id: 0, icon: "link", title: T("1. 连接", "1. Link their phone"),
                 body: T("在 \(who) 的手机上选“我来做检查”，输入这 6 位配对码：\(store.data.pairingCode)",
                         "On \(who)'s phone choose \"I'm taking the check\" and enter this code: \(store.data.pairingCode)")),
            Card(id: 1, icon: "circle.fill", title: T("2. 状态", "2. Status at a glance"),
                 body: T("绿色＝稳定，黄色＝留意，橙色＝建议就医，红色＝紧急。每次检查后自动更新并通知您。",
                         "Green = stable, yellow = watch, orange = see a doctor, red = urgent. Updates after every check, and you get a notification.")),
            Card(id: 2, icon: "chart.xyaxis.line", title: T("3. 趋势", "3. Trend"),
                 body: T("前 3 次检查建立 \(who) 的个人基线。", "The first 3 checks build \(who)'s personal baseline.")),
            Card(id: 3, icon: "play.circle", title: T("4. 回放", "4. Replay"),
                 body: T("点开任意一次检查，可以回放画钟过程，橙色圆点表示停顿思考的位置。",
                         "Open any check to replay the drawing. Orange dots show where they paused to think.")),
            Card(id: 4, icon: "bell", title: T("5. 提醒", "5. Reminders"),
                 body: T("每两周提醒一次。您也可以随时点“提醒检查”或“加做一次”。",
                         "We remind them every 2 weeks. You can also tap \"Remind now\" or \"Extra check\" any time."))
        ]
    }

    private var tour: some View {
        VStack(spacing: 20) {
            TabView(selection: $page) {
                ForEach(cards) { c in
                    VStack(spacing: 18) {
                        Image(systemName: c.icon).font(.system(size: 54)).foregroundStyle(Color.accentColor)
                        Text(c.title).font(.title.bold())
                        Text(c.body).font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .tag(c.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            HStack {
                Button(T("跳过", "Skip")) { store.data.carerTourDone = true }
                Spacer()
                Button(page < cards.count - 1 ? T("下一步", "Next") : T("开始使用", "Get started")) {
                    if page < cards.count - 1 { withAnimation { page += 1 } } else { store.data.carerTourDone = true }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }
}
