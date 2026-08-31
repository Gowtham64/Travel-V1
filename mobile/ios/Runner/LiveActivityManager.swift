import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// App-side controller for the trip Live Activity. Started/updated/ended from
/// Flutter over the `com.travelapp.liveactivity` MethodChannel (see the wiring
/// in AppDelegate described in ios/LIVE_ACTIVITY_SETUP.md).
///
/// NOTE: This file must be added to the Runner target in Xcode, together with
/// TripActivityAttributes.swift (shared with the widget extension). Until then
/// the Flutter bridge simply no-ops.
@available(iOS 16.1, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<TripActivityAttributes>?

    func start(
        destination: String,
        vehicleType: String = "car",
        startPoint: String = "Start",
        stops: [String] = [],
        isRoundTrip: Bool = false
    ) {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        NSLog("VOYPLAN LiveActivity start: enabled=\(enabled) dest=\(destination) vehicle=\(vehicleType) stops=\(stops)")
        guard enabled else {
            NSLog("VOYPLAN LiveActivity: Live Activities are DISABLED in Settings")
            return
        }
        // Replace any stale activity first.
        end()
        let attributes = TripActivityAttributes(
            destination: destination,
            vehicleType: vehicleType,
            startPoint: startPoint,
            stops: stops,
            isRoundTrip: isRoundTrip
        )
        let state = TripActivityAttributes.ContentState(
            eta: "…",
            distanceLeftKm: 0,
            progress: 0,
            arriving: false,
            nextStopName: stops.first,
            nextStopDistanceKm: nil,
            remainingStopsCount: stops.count,
            currentVehicleType: vehicleType
        )
        do {
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil))
            } else {
                activity = try Activity.request(
                    attributes: attributes, contentState: state)
            }
            NSLog("VOYPLAN LiveActivity: started id=\(activity?.id ?? "nil")")
        } catch {
            NSLog("VOYPLAN LiveActivity start FAILED: \(error)")
        }
    }

    func update(
        eta: String,
        distanceLeftKm: Double,
        progress: Double,
        arriving: Bool,
        nextStopName: String? = nil,
        nextStopDistanceKm: Double? = nil,
        remainingStopsCount: Int? = nil,
        currentVehicleType: String? = nil
    ) {
        guard let activity = activity else { return }
        let state = TripActivityAttributes.ContentState(
            eta: eta,
            distanceLeftKm: distanceLeftKm,
            progress: progress,
            arriving: arriving,
            nextStopName: nextStopName,
            nextStopDistanceKm: nextStopDistanceKm,
            remainingStopsCount: remainingStopsCount,
            currentVehicleType: currentVehicleType
        )
        Task {
            if #available(iOS 16.2, *) {
                await activity.update(.init(state: state, staleDate: nil))
            } else {
                await activity.update(using: state)
            }
        }
    }

    func end() {
        guard let activity = activity else { return }
        let finished = activity
        self.activity = nil
        Task {
            if #available(iOS 16.2, *) {
                await finished.end(nil, dismissalPolicy: .immediate)
            } else {
                await finished.end(dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
