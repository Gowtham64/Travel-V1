import ActivityKit
import WidgetKit
import SwiftUI

/// The Voyplan trip Live Activity: a delivery-tracker-style ETA card on the
/// lock screen and a compact route indicator in the Dynamic Island with full
/// multi-stop (waypoint), round-trip, and multi-vehicle support.
@available(iOS 16.1, *)
struct VoyplanTripActivityLiveActivity: Widget {
    private static let teal = Color(red: 0.20, green: 0.83, blue: 0.75)
    private static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)

    private func vehicleIcon(for type: String) -> String {
        let t = type.lowercased()
        if t.contains("bike") || t.contains("motorcycle") || t.contains("scooter") || t.contains("two_wheeler") {
            if #available(iOS 17.0, *) {
                return "motorcycle.fill"
            } else {
                return "bicycle"
            }
        } else if t.contains("bus") {
            return "bus.fill"
        } else if t.contains("truck") {
            return "box.truck.fill"
        } else if t.contains("suv") {
            return "car.side.fill"
        } else {
            return "car.fill"
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            // MARK: Lock screen / banner
            LockScreenView(context: context)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            let activeVehicle = context.state.currentVehicleType ?? context.attributes.vehicleType
            let iconName = vehicleIcon(for: activeVehicle)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.arriving ? "Arriving" : context.state.eta)
                            .font(.headline).foregroundColor(.white)
                    } icon: {
                        Image(systemName: iconName).foregroundColor(Self.teal)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(String(format: "%.1f", context.state.distanceLeftKm)) km")
                            .font(.subheadline.weight(.semibold)).foregroundColor(.white.opacity(0.9))
                        if let nextStop = context.state.nextStopName, !nextStop.isEmpty {
                            Text("Next: \(nextStop)")
                                .font(.system(size: 9)).foregroundColor(Self.amber)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: context.state.progress)
                            .tint(Self.teal)
                        HStack {
                            Text(context.attributes.startPoint)
                                .font(.caption2).foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                            if let nextStop = context.state.nextStopName, !nextStop.isEmpty {
                                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.4))
                                Text(nextStop)
                                    .font(.caption2.weight(.semibold)).foregroundColor(Self.amber)
                                    .lineLimit(1)
                            }
                            Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.white.opacity(0.4))
                            Text(context.attributes.destination)
                                .font(.caption2.weight(.medium)).foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: iconName).foregroundColor(Self.teal)
            } compactTrailing: {
                Text(context.state.arriving ? "•" : context.state.eta)
                    .font(.caption2.weight(.semibold)).foregroundColor(.white)
            } minimal: {
                Image(systemName: iconName).foregroundColor(Self.teal)
            }
            .keylineTint(Self.teal)
        }
    }
}

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>
    private var teal: Color { Color(red: 0.20, green: 0.83, blue: 0.75) }
    private var amber: Color { Color(red: 0.96, green: 0.62, blue: 0.04) }

    private func vehicleIcon(for type: String) -> String {
        let t = type.lowercased()
        if t.contains("bike") || t.contains("motorcycle") || t.contains("scooter") || t.contains("two_wheeler") {
            if #available(iOS 17.0, *) {
                return "motorcycle.fill"
            } else {
                return "bicycle"
            }
        } else if t.contains("bus") {
            return "bus.fill"
        } else if t.contains("truck") {
            return "box.truck.fill"
        } else if t.contains("suv") {
            return "car.side.fill"
        } else {
            return "car.fill"
        }
    }

    var body: some View {
        let activeVehicle = context.state.currentVehicleType ?? context.attributes.vehicleType
        let iconName = vehicleIcon(for: activeVehicle)
        
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Vehicle Icon + Origin ➔ Destination + Badges
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(teal)
                    .font(.system(size: 15, weight: .bold))
                
                HStack(spacing: 4) {
                    Text(context.attributes.startPoint)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                    Text(context.attributes.destination)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if context.attributes.isRoundTrip {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                        Text("Round Trip")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.25))
                    .foregroundColor(Color.blue.opacity(0.9))
                    .cornerRadius(6)
                } else {
                    Text("Voyplan")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(teal)
                }
            }
            
            // ETA & Total Distance Row
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.state.arriving ? "Arriving now"
                                            : "Arriving in \(context.state.eta)")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(String(format: "%.1f", context.state.distanceLeftKm)) km left")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.75))
            }

            // Intermediate Stop Points (Waypoints) Highlight
            if let nextStop = context.state.nextStopName, !nextStop.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(amber)
                        .font(.system(size: 12))
                    
                    Text("Next stop: \(nextStop)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(amber)
                        .lineLimit(1)
                    
                    if let d = context.state.nextStopDistanceKm, d > 0 {
                        Text("· \(String(format: "%.1f", d)) km")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    if let remaining = context.state.remainingStopsCount, remaining > 1 {
                        Spacer()
                        Text("\(remaining) stops left")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
            } else if !context.attributes.stops.isEmpty {
                // Show list of waypoints when not navigating towards a specific one
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(teal)
                        .font(.system(size: 10))
                    Text("\(context.attributes.stops.count) stop(s): \(context.attributes.stops.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            
            // Progress Bar
            ProgressView(value: context.state.progress)
                .tint(teal)
        }
    }
}
