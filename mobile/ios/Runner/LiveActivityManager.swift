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

    func start(destination: String) {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        NSLog("VOYPLAN LiveActivity start: enabled=\(enabled) dest=\(destination)")
        guard enabled else {
            NSLog("VOYPLAN LiveActivity: Live Activities are DISABLED in Settings")
            return
        }
        // Replace any stale activity first.
        end()
        let attributes = TripActivityAttributes(destination: destination)
        let state = TripActivityAttributes.ContentState(
            eta: "…", distanceLeftKm: 0, progress: 0, arriving: false)
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

    func update(eta: String, distanceLeftKm: Double, progress: Double, arriving: Bool) {
        guard let activity = activity else { return }
        let state = TripActivityAttributes.ContentState(
            eta: eta, distanceLeftKm: distanceLeftKm, progress: progress, arriving: arriving)
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
