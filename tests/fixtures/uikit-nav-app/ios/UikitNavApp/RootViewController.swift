import UIKit

// Pure UIKit navigation: a tab-bar root embedded in a navigation controller.
// Deliberately NO SwiftUI navigation APIs anywhere in this fixture — this is
// what the pre-fix scanner (SwiftUI-only pattern) misses (§12 FP).
class Root: UITabBarController {}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let nav = UINavigationController(rootViewController: Root())
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = nav
    window?.makeKeyAndVisible()
    return true
  }
}
