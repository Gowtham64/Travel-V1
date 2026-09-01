import ActivityKit
import Foundation

/// Shared model for the Voyplan trip Live Activity. This file MUST be a member
/// of BOTH the Runner app target and the VoyplanTripActivity widget-extension
/// target (tick both in Xcode's File Inspector → Target Membership).
struct TripActivityAttributes: ActivityAttributes {
    /// Values that change over the life of the drive.
    public struct ContentState: Codable, Hashable {
        var eta: String          // e.g. "32 min"
        var distanceLeftKm: Double
        var progress: Double     // 0.0 ... 1.0
        var arriving: Bool
        var nextStopName: String?
        var nextStopDistanceKm: Double?
        var remainingStopsCount: Int?
        var currentVehicleType: String?
        var activeStops: [String]?
    }

    /// Fixed for the whole activity.
    var destination: String
    var vehicleType: String
    var startPoint: String
    var stops: [String]
    var isRoundTrip: Bool
}
