import UIKit
import Flutter
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Where the WebView cookies (the login session) are kept between launches.
  private let cookiesKey = "flangapp_saved_cookies"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    restoreCookies()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Save the cookies as soon as the app leaves the screen, including when the
  // user opens the app switcher to swipe the app away.
  override func applicationWillResignActive(_ application: UIApplication) {
    saveCookies()
    super.applicationWillResignActive(application)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    saveCookies()
    super.applicationDidEnterBackground(application)
  }

  private func saveCookies() {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
      let saved: [[String: Any]] = cookies.compactMap { cookie in
        guard let properties = cookie.properties else { return nil }
        var item: [String: Any] = [:]
        for (key, value) in properties {
          if value is String || value is Date || value is NSNumber {
            item[key.rawValue] = value
          }
        }
        return item
      }
      UserDefaults.standard.set(saved, forKey: self.cookiesKey)
    }
  }

  private func restoreCookies() {
    guard let saved = UserDefaults.standard.array(forKey: cookiesKey) as? [[String: Any]] else { return }
    let store = WKWebsiteDataStore.default().httpCookieStore
    for item in saved {
      var properties: [HTTPCookiePropertyKey: Any] = [:]
      for (key, value) in item {
        properties[HTTPCookiePropertyKey(rawValue: key)] = value
      }
      guard let cookie = HTTPCookie(properties: properties) else { continue }
      // Skip cookies that have already expired.
      if let expires = cookie.expiresDate, expires < Date() { continue }
      store.setCookie(cookie)
    }
  }
}
