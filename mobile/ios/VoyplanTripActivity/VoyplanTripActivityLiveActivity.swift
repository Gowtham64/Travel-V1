import ActivityKit
import WidgetKit
import SwiftUI

/// The Voyplan trip Live Activity: a delivery-tracker-style ETA card on the
/// lock screen and a compact route indicator in the Dynamic Island.
@available(iOS 16.1, *)
struct VoyplanTripActivityLiveActivity: Widget {
    private static let teal = Color(red: 0.20, green: 0.83, blue: 0.75)

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
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            let iconName = vehicleIcon(for: context.attributes.vehicleType)
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
                    Text("\(String(format: "%.1f", context.state.distanceLeftKm)) km")
                        .font(.subheadline).foregroundColor(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: context.state.progress)
                            .tint(Self.teal)
                        Text(context.attributes.destination)
                            .font(.caption).foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: iconName).foregroundColor(Self.teal)
            } compactTrailing: {
                Text(context.state.arriving ? "•" : context.state.eta)
                    .font(.caption2).foregroundColor(.white)
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
        let iconName = vehicleIcon(for: context.attributes.vehicleType)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName).foregroundColor(teal)
                Text(context.attributes.destination)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white).lineLimit(1)
                Spacer()
                Text("Voyplan").font(.caption2.weight(.bold)).foregroundColor(teal)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.state.arriving ? "Arriving now"
                                            : "Arriving in \(context.state.eta)")
                    .font(.title3.weight(.bold)).foregroundColor(.white)
                Spacer()
                Text("\(String(format: "%.1f", context.state.distanceLeftKm)) km left")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
            }
            ProgressView(value: context.state.progress).tint(teal)
        }
    }
}
