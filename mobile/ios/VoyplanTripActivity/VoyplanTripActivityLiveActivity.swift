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

    private func shortName(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "Stop" }
        return clean.components(separatedBy: ",").first ?? clean
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            // MARK: Lock screen / banner
            LockScreenView(context: context)
                .padding(14)
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
                            Text("📍 \(shortName(nextStop))")
                                .font(.system(size: 9, weight: .bold)).foregroundColor(Self.amber)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: context.state.progress)
                            .tint(Self.teal)
                        HStack(spacing: 3) {
                            Text(shortName(context.attributes.startPoint))
                                .font(.caption2).foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                            
                            if !context.attributes.stops.isEmpty {
                                ForEach(context.attributes.stops, id: \.self) { stop in
                                    Image(systemName: "arrow.right").font(.system(size: 7)).foregroundColor(.white.opacity(0.35))
                                    Text(shortName(stop))
                                        .font(.caption2.weight(.bold)).foregroundColor(Self.amber)
                                        .lineLimit(1)
                                }
                            } else if let nextStop = context.state.nextStopName, !nextStop.isEmpty {
                                Image(systemName: "arrow.right").font(.system(size: 7)).foregroundColor(.white.opacity(0.35))
                                Text(shortName(nextStop))
                                    .font(.caption2.weight(.bold)).foregroundColor(Self.amber)
                                    .lineLimit(1)
                            }
                            
                            Image(systemName: "arrow.right").font(.system(size: 7)).foregroundColor(.white.opacity(0.35))
                            Text(shortName(context.attributes.destination))
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

    private func shortName(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "Stop" }
        return clean.components(separatedBy: ",").first ?? clean
    }

    var body: some View {
        let activeVehicle = context.state.currentVehicleType ?? context.attributes.vehicleType
        let iconName = vehicleIcon(for: activeVehicle)
        let allStops = context.attributes.stops.isEmpty && context.state.nextStopName != nil
            ? [context.state.nextStopName!]
            : context.attributes.stops
        
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Vehicle Icon + Full Route Trail + Badges
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(teal)
                    .font(.system(size: 15, weight: .bold))
                
                HStack(spacing: 3) {
                    Text(shortName(context.attributes.startPoint))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    if !allStops.isEmpty {
                        ForEach(allStops.prefix(2), id: \.self) { st in
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.35))
                            Text(shortName(st))
                                .font(.caption.weight(.bold))
                                .foregroundColor(amber)
                                .lineLimit(1)
                        }
                        if allStops.count > 2 {
                            Text("+\(allStops.count - 2)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(amber)
                        }
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.35))
                    Text(shortName(context.attributes.destination))
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

            // Visual Stop Points Timeline Bar (Nodes)
            if !allStops.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // Visual Node Line
                    HStack(spacing: 0) {
                        // Start Node
                        Circle()
                            .fill(teal)
                            .frame(width: 8, height: 8)
                        
                        Rectangle()
                            .fill(teal.opacity(0.5))
                            .frame(height: 2)
                        
                        // Intermediate Stop Nodes
                        ForEach(0..<allStops.count, id: \.self) { idx in
                            let isNext = (context.state.nextStopName != nil && allStops[idx].contains(context.state.nextStopName!)) || idx == 0
                            HStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(isNext ? amber : Color.white.opacity(0.3))
                                        .frame(width: isNext ? 12 : 8, height: isNext ? 12 : 8)
                                    if isNext {
                                        Circle()
                                            .fill(Color.black)
                                            .frame(width: 4, height: 4)
                                    }
                                }
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(height: 2)
                            }
                        }
                        
                        // Destination Node
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    
                    // Stop Point Pill Card
                    if let nextStop = context.state.nextStopName, !nextStop.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(amber)
                                .font(.system(size: 12, weight: .bold))
                            
                            Text("Next Stop: \(nextStop)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(amber)
                                .lineLimit(1)
                            
                            if let d = context.state.nextStopDistanceKm, d > 0 {
                                Text("· \(String(format: "%.1f", d)) km")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            if let remaining = context.state.remainingStopsCount, remaining > 1 {
                                Text("(\(remaining) stops total)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(amber.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(amber.opacity(0.35), lineWidth: 1))
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 2)
            }
            
            // Route Travel Progress Bar
            ProgressView(value: context.state.progress)
                .tint(teal)
        }
    }
}
