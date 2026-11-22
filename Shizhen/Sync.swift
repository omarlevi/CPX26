import Foundation
import MultipeerConnectivity
import UserNotifications
import UIKit

/// Family link. Demo transport: MultipeerConnectivity (encrypted, no internet or paid account needed).
/// Production target: CloudKit shared zone + APNs.
final class FamilyLink: NSObject, ObservableObject {
    static let service = "shizhen-sync"

    struct Envelope: Codable {
        enum Kind: String, Codable { case session, profile, remind, extraCheck, hello }
        var kind: Kind
        var session: SessionResult?
        var profile: Profile?
        var name: String?
    }

    @Published var connectedPeers: [String] = []
    @Published var isSearching = false

    weak var store: AppStore?
    private let me = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session: MCSession = {
        let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var wantedCode = ""

    /// Carer: advertise with the pairing code.
    func startHosting(code: String) {
        advertiser?.stopAdvertisingPeer()
        let a = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: ["code": code], serviceType: Self.service)
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
    }

    /// Taker: look for the carer advertising this code.
    func join(code: String) {
        wantedCode = code
        store?.data.linkedCode = code
        browser?.stopBrowsingForPeers()
        let b = MCNearbyServiceBrowser(peer: me, serviceType: Self.service)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
        isSearching = true
    }

    func send(_ e: Envelope) {
        guard !session.connectedPeers.isEmpty, let d = try? JSONEncoder().encode(e) else { return }
        try? session.send(d, toPeers: session.connectedPeers, with: .reliable)
    }

    private func handle(_ e: Envelope) {
        guard let store else { return }
        switch e.kind {
        case .session:
            guard let s = e.session else { return }
            guard store.data.role == .carer else { store.add(s); return }
            store.receive(s, fromCode: e.name)
            let who = store.name(forCode: e.name)
            do {
                Notifier.post(title: T("\(who) 完成了检查", "\(who) finished a check"),
                              body: "\(s.status.title) · Mini-Cog \(s.miniCog)/5", critical: s.status == .urgent || s.status == .doctor)
                if (s.status == .urgent || s.status == .doctor) && store.name(forCode: e.name) == store.displayName(store.data.profile) { store.latestAlert = s }
            }
        case .profile:
            if let p = e.profile { store.data.profile = p }
        case .remind:
            Notifier.post(title: T("该做脑力小检查了", "Time for your brain check"),
                          body: T("家人提醒您做今天的 3 分钟检查", "Your family asked you to do today's 3-minute check"), critical: false)
        case .extraCheck:
            store.data.pendingExtraCheck = true
            Notifier.post(title: T("家人请您加做一次检查", "Your family asked for an extra check"),
                          body: T("只需 3 分钟", "It only takes 3 minutes"), critical: false)
        case .hello:
            break
        }
    }
}

extension FamilyLink: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers.map { $0.displayName }
            if state == .connected {
                self.isSearching = false
                self.browser?.stopBrowsingForPeers()
                if let store = self.store, store.data.role == .carer {
                    self.send(Envelope(kind: .profile, profile: store.data.profile))
                    // share full history so both devices match
                    for s in store.realSessions { self.send(Envelope(kind: .session, session: s)) }
                }
            }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let e = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        DispatchQueue.main.async { self.handle(e) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension FamilyLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension FamilyLink: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["code"] == wantedCode else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

// MARK: - Local notifications

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(title: String, body: String, critical: Bool) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        c.sound = .default
        c.interruptionLevel = .active; _ = critical
        let r = UNNotificationRequest(identifier: UUID().uuidString, content: c,
                                      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(r)
    }

    static func scheduleReminder(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["shizhen.reminder"])
        let c = UNMutableNotificationContent()
        c.title = T("该做脑力小检查了", "Time for your brain check")
        c.body = T("3 分钟，点一下就开始", "3 minutes. Tap to start.")
        c.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let r = UNNotificationRequest(identifier: "shizhen.reminder", content: c,
                                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        center.add(r)
    }
}

/// Shows notifications as banners even while the app is open (needed for the live demo).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
