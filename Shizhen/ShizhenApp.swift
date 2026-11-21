import SwiftUI
import UserNotifications

@main
struct ShizhenApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var link = FamilyLink()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(link)
                .onAppear { link.store = store }
                .tint(Color(red: 0.06, green: 0.43, blue: 0.48))
        }
    }
}
