import UIKit
import OneSignal

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        OneSignal.initialize("app-id", withLaunchOptions: launchOptions)
        application.registerForRemoteNotifications()
        return true
    }
}
