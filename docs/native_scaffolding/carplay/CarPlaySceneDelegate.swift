// ============================================================================
// Apple CarPlay — scene delegate scaffolding
// Drop-in target: mobile/ios/Runner/CarPlay/CarPlaySceneDelegate.swift
// Requires: the CarPlay entitlement (com.apple.developer.carplay-maps), the
// Info.plist scene manifest (see Info.plist.additions), and adding these files
// to the Runner target in Xcode.
//
// Implements the CAR side of the `com.travelapp.car` MethodChannel contract in
// lib/services/car_platform_channel.dart. The Flutter engine's binaryMessenger
// is reached via the shared FlutterViewController from AppDelegate.
//
// NOTE: Scaffolding — not compiled here (no local Xcode). Test in the CarPlay
// simulator (iOS Simulator ▸ I/O ▸ External Displays ▸ CarPlay).
// ============================================================================

import CarPlay
import Flutter

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    var interfaceController: CPInterfaceController?
    var mapTemplate: CPMapTemplate?
    private var methodChannel: FlutterMethodChannel?

    // MARK: CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let map = CPMapTemplate()
        map.mapDelegate = nil
        map.showTripPreviews([], textConfiguration: nil)
        self.mapTemplate = map
        interfaceController.setRootTemplate(map, animated: true, completion: nil)

        attachMethodChannel()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.mapTemplate = nil
    }

    // MARK: Flutter bridge

    private func attachMethodChannel() {
        // Reuse the app's running Flutter engine (registered in AppDelegate).
        guard let engine = (UIApplication.shared.delegate as? FlutterAppLifeCycleProvider) as? FlutterEngineProvider,
              let messenger = engine.flutterEngine?.binaryMessenger else {
            return
        }
        let channel = FlutterMethodChannel(name: "com.travelapp.car", binaryMessenger: messenger)
        self.methodChannel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "setRoute":
                // TODO: parse coordinates and draw the route on the CPMapTemplate.
                result(nil)
            case "updateNavigation":
                self.handleNavigationUpdate(call.arguments as? [String: Any] ?? [:])
                result(nil)
            case "setNavigationState":
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleNavigationUpdate(_ args: [String: Any]) {
        // Update the maneuver banner + ETA on the CPMapTemplate / CPNavigationSession.
        // Minimal example using an estimates panel:
        guard mapTemplate != nil else { return }
        // let instruction = args["instruction"] as? String ?? ""
        // let distance = args["distanceMeters"] as? Double ?? 0
        // Build a CPManeuver / CPTravelEstimates and apply to the active
        // CPNavigationSession here.
    }
}

/// Minimal protocol so the scene delegate can reach the app's FlutterEngine.
/// Have AppDelegate conform to this (see Info.plist.additions / README).
protocol FlutterEngineProvider {
    var flutterEngine: FlutterEngine? { get }
}
