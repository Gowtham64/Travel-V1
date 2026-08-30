import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let tripNotifId = "trip_progress"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.travelapp.notification",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleNotification(call)
        result(nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Live trip-progress local notification

  private func handleNotification(_ call: FlutterMethodCall) {
    switch call.method {
    case "start":
      requestAuth()
      showTrip(call, arriving: false)
    case "update":
      let arriving = (call.arguments as? [String: Any])?["arriving"] as? Bool ?? false
      showTrip(call, arriving: arriving)
    case "end":
      UNUserNotificationCenter.current()
        .removeDeliveredNotifications(withIdentifiers: [tripNotifId])
      UNUserNotificationCenter.current()
        .removePendingNotificationRequests(withIdentifiers: [tripNotifId])
    default:
      break
    }
  }

  private func requestAuth() {
    UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert]) { _, _ in }
  }

  private func showTrip(_ call: FlutterMethodCall, arriving: Bool) {
    let args = call.arguments as? [String: Any] ?? [:]
    let destination = args["destination"] as? String ?? "Trip"
    let eta = args["eta"] as? String ?? ""
    let distance = args["distanceLeftKm"] as? Double ?? 0
    let progress = Int((args["progress"] as? Double ?? 0) * 100)

    let content = UNMutableNotificationContent()
    content.title = arriving ? "Arriving now"
      : (eta.isEmpty ? "Trip in progress" : "Arriving in \(eta)")
    content.body = arriving
      ? "You have reached \(destination)"
      : String(format: "%.1f km left · %d%% · %@", distance, progress, destination)
    content.sound = nil
    if #available(iOS 15.0, *) { content.interruptionLevel = .passive }

    // Same identifier → each update replaces the previous banner in place.
    let request = UNNotificationRequest(identifier: tripNotifId, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  // Show the banner even while the app is foregrounded.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list])
    } else {
      completionHandler([.alert])
    }
  }
}
