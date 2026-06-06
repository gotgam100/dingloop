import SwiftUI
import UIKit
import UserNotifications

final class DingLoopAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let alarmNotificationIdentifier = "ding-things-repeating-alarm"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == alarmNotificationIdentifier {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}

@main
struct DingLoopApp: App {
    @UIApplicationDelegateAdaptor(DingLoopAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
