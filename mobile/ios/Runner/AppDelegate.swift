import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let tripNotifId = "trip_progress"
  private var notificationChannel: FlutterMethodChannel?
  private var pendingNotificationArgs: [String: Any]?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    UNUserNotificationCenter.current().delegate = self
    // Register our channels here — in the new Flutter iOS engine the
    // FlutterViewController isn't the window's rootViewController at
    // didFinishLaunching, so registering there silently no-ops. The plugin
    // registry's messenger is always available at this point.
    if let messenger = engineBridge.pluginRegistry
        .registrar(forPlugin: "VoyplanChannels")?.messenger() {
      setupChannels(messenger)
    }
  }

  private func setupChannels(_ messenger: FlutterBinaryMessenger) {
    let notifChannel = FlutterMethodChannel(name: "com.travelapp.notification", binaryMessenger: messenger)
    self.notificationChannel = notifChannel
    if let pending = pendingNotificationArgs {
      notifChannel.invokeMethod("onNotificationTapped", arguments: pending)
      pendingNotificationArgs = nil
    }
    notifChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleNotification(call)
      result(nil)
    }
    FlutterMethodChannel(name: "com.travelapp.liveactivity", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        Self.handleLiveActivity(call)
        result(nil)
      }
    let carChannel = FlutterMethodChannel(name: "com.example.travel_app.car", binaryMessenger: messenger)
    CarPlayNavigationManager.shared.carMethodChannel = carChannel
    carChannel.setMethodCallHandler { call, result in
      Self.handleCarPlatformChannel(call, result: result)
    }
  }

  // MARK: - CarPlay Turn-by-Turn Platform Channel

  private static func handleCarPlatformChannel(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("VOYPLAN CarPlay channel: \(call.method)")
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "setRoute":
      let start = args["start"] as? [String: Any] ?? [:]
      let end = args["end"] as? [String: Any] ?? [:]
      let waypoints = args["waypoints"] as? [[String: Any]] ?? []
      let coordinates = args["coordinates"] as? [[String: Any]] ?? []
      let fuelStops = args["fuelStops"] as? [[String: Any]]
      let destinationName = end["name"] as? String
      CarPlayNavigationManager.shared.setRoute(
        start: start,
        end: end,
        waypoints: waypoints,
        coordinates: coordinates,
        fuelStops: fuelStops,
        destinationName: destinationName
      )
      result(nil)
    case "updateNavigation":
      CarPlayNavigationManager.shared.updateNavigation(args: args)
      result(nil)
    case "setNavigationState":
      let isNavigating = args["isNavigating"] as? Bool ?? false
      CarPlayNavigationManager.shared.setNavigationState(isNavigating: isNavigating)
      result(nil)
    case "stopNavigation":
      CarPlayNavigationManager.shared.stopNavigation(fromCar: false)
      result(nil)
    case "speakNavigation":
      let phrase = (args["phrase"] as? String) ?? (call.arguments as? String) ?? ""
      CarPlayVoiceGuidance.shared.speak(phrase)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - iOS Live Activity (Dynamic Island + lock screen)

  private static func handleLiveActivity(_ call: FlutterMethodCall) {
    NSLog("VOYPLAN liveactivity channel: \(call.method)")
    guard #available(iOS 16.1, *) else {
      NSLog("VOYPLAN liveactivity: iOS < 16.1, unsupported")
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      let dest = args["destination"] as? String ?? "Trip"
      let vehicle = args["vehicleType"] as? String ?? "car"
      let startPoint = args["startPoint"] as? String ?? "Start"
      let stops = args["stops"] as? [String] ?? []
      let isRoundTrip = args["isRoundTrip"] as? Bool ?? false
      LiveActivityManager.shared.start(
        destination: dest,
        vehicleType: vehicle,
        startPoint: startPoint,
        stops: stops,
        isRoundTrip: isRoundTrip
      )
    case "update":
      LiveActivityManager.shared.update(
        eta: args["eta"] as? String ?? "",
        distanceLeftKm: args["distanceLeftKm"] as? Double ?? 0,
        progress: args["progress"] as? Double ?? 0,
        arriving: args["arriving"] as? Bool ?? false,
        nextStopName: args["nextStopName"] as? String,
        nextStopDistanceKm: args["nextStopDistanceKm"] as? Double,
        remainingStopsCount: args["remainingStopsCount"] as? Int,
        currentVehicleType: args["currentVehicleType"] as? String,
        activeStops: args["activeStops"] as? [String]
      )
    case "end":
      LiveActivityManager.shared.end()
    default:
      break
    }
  }

  // MARK: - Live trip-progress & Pre-trip departure reminders

  private func handleNotification(_ call: FlutterMethodCall) {
    NSLog("VOYPLAN notification channel: \(call.method)")
    switch call.method {
    case "requestPermissions":
      requestAuth()
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
    case "scheduleReminder":
      scheduleDepartureReminder(call)
    case "cancelReminder":
      let args = call.arguments as? [String: Any] ?? [:]
      let notifId = args["id"] as? String ?? ""
      if !notifId.isEmpty {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notifId])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notifId])
      }
    default:
      break
    }
  }

  private func requestAuth() {
    UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
  }

  private func scheduleDepartureReminder(_ call: FlutterMethodCall) {
    requestAuth()
    let args = call.arguments as? [String: Any] ?? [:]
    let notifId = args["id"] as? String ?? "reminder_\(Date().timeIntervalSince1970)"
    let title = args["title"] as? String ?? "🚗 Trip Departure Reminder"
    let body = args["body"] as? String ?? "Your trip begins in 30 minutes. Time to get ready!"
    let seconds = max(1.0, (args["secondsFromNow"] as? Double ?? 1.0))

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = UNNotificationSound.default
    content.userInfo = args
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .timeSensitive
    }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
    let request = UNNotificationRequest(identifier: notifId, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        NSLog("VOYPLAN reminder error: \(error.localizedDescription)")
      } else {
        NSLog("VOYPLAN departure reminder scheduled in \(seconds)s: \(notifId)")
      }
    }
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
    content.body = "To \(destination) · \(String(format: "%.1f", distance)) km remaining"
    content.sound = nil

    // Same identifier → each update replaces the previous banner in place.
    let request = UNNotificationRequest(identifier: tripNotifId, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  // Handle notification tap to bring user directly into Trip Confirmation popup
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let tripId = (userInfo["tripId"] as? String) ?? (userInfo["id"] as? String) ?? ""
    if !tripId.isEmpty {
      let args: [String: Any] = [
        "tripId": tripId,
        "action": userInfo["actionType"] as? String ?? "trip_start",
        "destination": userInfo["destination"] as? String ?? "",
        "departureTime": userInfo["departureTime"] as? String ?? ""
      ]
      if let channel = notificationChannel {
        channel.invokeMethod("onNotificationTapped", arguments: args)
      } else {
        pendingNotificationArgs = args
      }
    }
    completionHandler()
  }

  // Show the banner even while the app is foregrounded.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}
