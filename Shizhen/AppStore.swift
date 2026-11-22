import Foundation
import SwiftUI

/// Single source of truth. Persisted as JSON in Documents (all data stays on device).
final class AppStore: ObservableObject {
    static var currentLanguage: AppLanguage = .zh

    struct Persisted: Codable {
        var role: Role?
        var profile = Profile()
        var settings = Settings()
        var sessions: [SessionResult] = []
        var pairingCode: String = AppStore.newCode()
        var pendingExtraCheck = false
        var hasSeenTutorial = false
        var carerSetupDone = false
        var carerTourDone = false
        /// Carer can follow several family members; the active one lives in profile/sessions/pairingCode.
        var people: [PersonRecord] = []
        var activePerson = 0
        /// Taker: the carer's pairing code this device linked with.
        var linkedCode: String = ""

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = try c.decodeIfPresent(Role.self, forKey: .role)
            profile = (try? c.decodeIfPresent(Profile.self, forKey: .profile)) ?? Profile()
            settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
            sessions = (try? c.decodeIfPresent([SessionResult].self, forKey: .sessions)) ?? []
            pairingCode = (try? c.decodeIfPresent(String.self, forKey: .pairingCode)) ?? AppStore.newCode()
            pendingExtraCheck = (try? c.decodeIfPresent(Bool.self, forKey: .pendingExtraCheck)) ?? false
            hasSeenTutorial = (try? c.decodeIfPresent(Bool.self, forKey: .hasSeenTutorial)) ?? false
            carerSetupDone = (try? c.decodeIfPresent(Bool.self, forKey: .carerSetupDone)) ?? false
            carerTourDone = (try? c.decodeIfPresent(Bool.self, forKey: .carerTourDone)) ?? false
            people = (try? c.decodeIfPresent([PersonRecord].self, forKey: .people)) ?? []
            activePerson = (try? c.decodeIfPresent(Int.self, forKey: .activePerson)) ?? 0
            linkedCode = (try? c.decodeIfPresent(String.self, forKey: .linkedCode)) ?? ""
        }
    }

    struct PersonRecord: Codable, Identifiable {
        var id = UUID()
        var profile = Profile()
        var sessions: [SessionResult] = []
        var pairingCode = AppStore.newCode()
    }

    static let maxPeople = 5

    @Published var data: Persisted { didSet { save() } }
    @Published var latestAlert: SessionResult?

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("shizhen.json")
    }()

    init() {
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(Persisted.self, from: d) {
            data = p
        } else {
            data = Persisted()
        }
        AppStore.currentLanguage = data.settings.language
    }

    static func newCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }

    private func save() {
        AppStore.currentLanguage = data.settings.language
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url, options: .atomic) }
    }

    // MARK: derived

    var realSessions: [SessionResult] { data.sessions.sorted { $0.date < $1.date } }
    var latest: SessionResult? { realSessions.last }
    var currentStatus: RiskStatus { latest?.status ?? .building }

    var nextDueDate: Date {
        let cadence = Double(data.settings.cadenceDays)
        let count = realSessions.filter { !$0.isDemo }.count
        guard let last = realSessions.last?.date else { return Date() }
        // baseline week: days 1, 3, 7
        let gap: Double = count == 1 ? 2 : (count == 2 ? 4 : cadence)
        let due = last.addingTimeInterval(gap * 86_400)
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: due)
        comps.hour = data.settings.reminderHour; comps.minute = data.settings.reminderMinute
        return Calendar.current.date(from: comps) ?? due
    }

    /// Days past the due date (0 if not overdue).
    var overdueDays: Int {
        guard !realSessions.isEmpty else { return 0 }
        return max(0, Int(Date().timeIntervalSince(nextDueDate) / 86_400))
    }

    var daysSinceLast: Int {
        guard let d = realSessions.last?.date else { return 0 }
        return Int(Date().timeIntervalSince(d) / 86_400)
    }

    /// Checks skipped between past sessions (after the baseline week), plus any skipped since the last one.
    var missedChecks: Int {
        let s = realSessions
        guard s.count > 3 else { return overdueDays / data.settings.cadenceDays }
        let cadence = Double(data.settings.cadenceDays)
        var missed = 0
        for i in 3..<s.count {
            let gap = s[i].date.timeIntervalSince(s[i-1].date) / 86_400
            if gap > cadence * 1.5 { missed += Int((gap / cadence).rounded()) - 1 }
        }
        return missed + overdueDays / data.settings.cadenceDays
    }

    var wordListIndex: Int { realSessions.count % WordList.lists.count }

    // MARK: multiple family members (carer)

    func displayName(_ p: Profile) -> String { p.name.isEmpty ? Relation.label(p.relation) : p.name }

    /// Copies the active person's live fields back into the people list.
    private func syncActive() {
        if data.people.isEmpty {
            data.people = [PersonRecord(profile: data.profile, sessions: data.sessions, pairingCode: data.pairingCode)]
            data.activePerson = 0
            return
        }
        let i = min(data.activePerson, data.people.count - 1)
        data.people[i].profile = data.profile
        data.people[i].sessions = data.sessions
        data.people[i].pairingCode = data.pairingCode
    }

    var peopleList: [PersonRecord] { syncedPeople() }

    private func syncedPeople() -> [PersonRecord] {
        var list = data.people
        if list.isEmpty { return [PersonRecord(profile: data.profile, sessions: data.sessions, pairingCode: data.pairingCode)] }
        let i = min(data.activePerson, list.count - 1)
        list[i].profile = data.profile; list[i].sessions = data.sessions; list[i].pairingCode = data.pairingCode
        return list
    }

    func switchTo(_ index: Int) {
        syncActive()
        guard data.people.indices.contains(index), index != data.activePerson else { return }
        var d = data
        d.activePerson = index
        d.profile = d.people[index].profile
        d.sessions = d.people[index].sessions
        d.pairingCode = d.people[index].pairingCode
        data = d
        latestAlert = nil
    }

    func addPerson() {
        syncActive()
        guard data.people.count < AppStore.maxPeople else { return }
        var p = Profile(); p.relation = "dad"; p.name = Relation.label("dad")
        data.people.append(PersonRecord(profile: p))
        switchTo(data.people.count - 1)
        data.carerSetupDone = false      // show the profile form for the new person
    }

    func removeActivePerson() {
        syncActive()
        guard data.people.count > 1 else { return }
        data.people.remove(at: data.activePerson)
        let next = max(0, data.activePerson - 1)
        var d = data
        d.activePerson = next; d.profile = d.people[next].profile; d.sessions = d.people[next].sessions; d.pairingCode = d.people[next].pairingCode
        data = d; latestAlert = nil
    }

    /// Routes a check that arrived from a linked phone to the right family member.
    func receive(_ s: SessionResult, fromCode code: String?) {
        if let code, code != data.pairingCode, let i = data.people.firstIndex(where: { $0.pairingCode == code }), i != data.activePerson {
            if let j = data.people[i].sessions.firstIndex(where: { $0.id == s.id }) { data.people[i].sessions[j] = s } else { data.people[i].sessions.append(s) }
        } else {
            add(s)
        }
    }

    func name(forCode code: String?) -> String {
        if let code, let p = syncedPeople().first(where: { $0.pairingCode == code }) { return displayName(p.profile) }
        return displayName(data.profile)
    }

    // MARK: mutations

    func add(_ s: SessionResult) {
        if let i = data.sessions.firstIndex(where: { $0.id == s.id }) { data.sessions[i] = s } else { data.sessions.append(s) }
    }

    func setLanguage(_ l: AppLanguage) { data.settings.language = l; AppStore.currentLanguage = l; objectWillChange.send() }

    func resetAll() {
        let lang = data.settings.language
        data = Persisted(); data.settings.language = lang
    }

    /// De-identified research export (only when consent is on).
    func researchExportURL() -> URL? {
        guard data.settings.researchConsent else { return nil }
        struct Row: Codable {
            var ageBand: String; var sex: String; var educationYears: Int
            var daysSinceFirst: Int; var miniCog: Int; var orientation: Int
            var metrics: ClockMetrics; var strokes: [Stroke]
        }
        let first = realSessions.first?.date ?? Date()
        let band = "\((data.profile.age / 5) * 5)-\((data.profile.age / 5) * 5 + 4)"
        let rows = realSessions.filter { !$0.isDemo }.map {
            Row(ageBand: band, sex: data.profile.sex, educationYears: data.profile.educationYears,
                daysSinceFirst: Int($0.date.timeIntervalSince(first) / 86_400), miniCog: $0.miniCog,
                orientation: $0.orientationScore, metrics: $0.metrics, strokes: $0.command.strokes)
        }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("shizhen-deidentified.json")
        let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted
        guard let d = try? enc.encode(rows) else { return nil }
        try? d.write(to: u)
        return u
    }
}
