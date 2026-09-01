import ActivityKit
import WidgetKit
import SwiftUI

/// The Voyplan trip Live Activity: A premium delivery-tracker-style Live Activity
/// (Zomato-style) with a custom moving vehicle avatar along a solid-to-dashed
/// route line, intermediate stop badges, and destination node.
@available(iOS 16.1, *)
struct VoyplanTripActivityLiveActivity: Widget {
    private static let greenAccent = Color(red: 0.30, green: 0.82, blue: 0.45)
    private static let teal = Color(red: 0.20, green: 0.83, blue: 0.75)
    private static let amber = Color(red: 0.98, green: 0.65, blue: 0.15)

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
            // MARK: Lock screen / Banner View
            LockScreenView(context: context)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .activityBackgroundTint(Color(red: 0.10, green: 0.10, blue: 0.11))
                .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            let activeVehicle = context.state.currentVehicleType ?? context.attributes.vehicleType
            let iconName = vehicleIcon(for: activeVehicle)
            let allStops = (context.state.activeStops != nil && !context.state.activeStops!.isEmpty)
                ? context.state.activeStops!
                : (!context.attributes.stops.isEmpty ? context.attributes.stops : (context.state.nextStopName != nil ? [context.state.nextStopName!] : []))
            
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: iconName)
                            .foregroundColor(Self.greenAccent)
                            .font(.system(size: 16, weight: .bold))
                        Text(context.state.arriving ? "Arrived" : context.state.eta)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("voyplan")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(String(format: "%.1f", context.state.distanceLeftKm)) km left")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("On time")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Self.greenAccent)
                            Text("|")
                                .foregroundColor(.white.opacity(0.3))
                                .font(.system(size: 11))
                            if let nextStop = context.state.nextStopName, !nextStop.isEmpty {
                                Text("Next: \(shortName(nextStop))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Self.amber)
                            } else {
                                Text("To \(shortName(context.attributes.destination))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        
                        // Zomato-style track in Dynamic Island
                        TrackerLineView(
                            progress: CGFloat(max(0.02, min(0.98, context.state.progress))),
                            iconName: iconName,
                            stops: allStops,
                            nextStop: context.state.nextStopName
                        )
                    }
                }
            } compactLeading: {
                Image(systemName: iconName).foregroundColor(Self.greenAccent)
            } compactTrailing: {
                Text(context.state.arriving ? "•" : context.state.eta)
                    .font(.caption2.weight(.bold)).foregroundColor(.white)
            } minimal: {
                Image(systemName: iconName).foregroundColor(Self.greenAccent)
            }
            .keylineTint(Self.greenAccent)
        }
    }
}

// MARK: - Lock Screen View (Zomato-Style Delivery Live Activity)
@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>
    private var greenAccent: Color { Color(red: 0.30, green: 0.85, blue: 0.45) }
    private var amber: Color { Color(red: 0.98, green: 0.65, blue: 0.15) }

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
        let dest = shortName(context.attributes.destination)
        let orig = shortName(context.attributes.startPoint)
        let nextStop = context.state.nextStopName != nil ? shortName(context.state.nextStopName!) : nil
        let allStops = (context.state.activeStops != nil && !context.state.activeStops!.isEmpty)
            ? context.state.activeStops!
            : (!context.attributes.stops.isEmpty ? context.attributes.stops : (context.state.nextStopName != nil ? [context.state.nextStopName!] : []))
        let progress = CGFloat(max(0.04, min(0.96, context.state.progress)))

        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Source ➔ Stop Points ➔ Destination Route Trail + Brand Logo
            HStack(spacing: 4) {
                Text(orig)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                
                if !allStops.isEmpty {
                    ForEach(allStops.prefix(2), id: \.self) { st in
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.35))
                        Text(shortName(st))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(amber)
                            .lineLimit(1)
                    }
                    if allStops.count > 2 {
                        Text("+\(allStops.count - 2)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(amber)
                    }
                }
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.35))
                Text(dest)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                
                Spacer()
                
                Text("voyplan")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(-0.3)
            }
            .padding(.bottom, 1)

            // Row 2: Big Main Status Title (e.g. "Heading to Maddur" / "Driving to Mysore")
            Text(context.state.arriving 
                 ? "Arriving at \(dest)"
                 : (nextStop != nil ? "Heading to \(nextStop!)" : "Driving to \(dest)"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)

            // Row 3: Subtitle with Green "On time" + Remaining Time & Distance
            HStack(spacing: 5) {
                Text("On time")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(greenAccent)
                
                Text("|")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                
                Text("Arriving in \(context.state.eta)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("(\(String(format: "%.1f", context.state.distanceLeftKm)) km)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.bottom, 4)

            // Row 4: Custom Moving Vehicle Track (Zomato-Style with Stop Nodes)
            TrackerLineView(
                progress: progress,
                iconName: iconName,
                stops: allStops,
                nextStop: context.state.nextStopName
            )
            .frame(height: 32)

            // Row 5: Next Stop Point Pill Badge (if intermediate stops exist)
            if let ns = nextStop, !ns.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(amber)
                        .font(.system(size: 11, weight: .bold))
                    Text("Next Stop: \(ns)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(amber)
                        .lineLimit(1)
                    if let d = context.state.nextStopDistanceKm, d > 0 {
                        Text("· \(String(format: "%.1f", d)) km")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Spacer()
                    if let rem = context.state.remainingStopsCount, rem > 1 {
                        Text("(\(rem) stops left)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(amber.opacity(0.12))
                .cornerRadius(6)
            }
        }
    }
}

// MARK: - Zomato-Style Delivery / Navigation Track Line
@available(iOS 16.1, *)
private struct TrackerLineView: View {
    let progress: CGFloat
    let iconName: String
    let stops: [String]
    let nextStop: String?

    private func stopSymbol(for raw: String) -> String {
        let st = raw.lowercased()
        if st.contains("temple") || st.contains("mandir") || st.contains("kovil") || st.contains("gudi") || st.contains("shrine") || st.contains("pooja") || st.contains("church") || st.contains("masjid") || st.contains("mosque") {
            return "building.columns.fill"
        } else if st.contains("fuel") || st.contains("petrol") || st.contains("diesel") || st.contains("gas") || st.contains("lpg") || st.contains("cng") || st.contains("shell") || st.contains("ioc") || st.contains("hp") || st.contains("bp") || st.contains("bunk") {
            return "fuelpump.fill"
        } else if st.contains("ev") || st.contains("charging") || st.contains("charge") {
            return "bolt.car.fill"
        } else if st.contains("biryani") || st.contains("food") || st.contains("restaurant") || st.contains("mess") || st.contains("tiffin") || st.contains("maddur") || st.contains("dining") || st.contains("dhaba") || st.contains("kitchen") {
            return "fork.knife"
        } else if st.contains("tea") || st.contains("coffee") || st.contains("chai") || st.contains("cafe") || st.contains("bakery") {
            return "cup.and.saucer.fill"
        } else if st.contains("hotel") || st.contains("resort") || st.contains("stay") || st.contains("lodge") || st.contains("inn") {
            return "bed.double.fill"
        } else if st.contains("hill") || st.contains("peak") || st.contains("mountain") || st.contains("ghat") {
            return "mountain.2.fill"
        } else if st.contains("waterfall") || st.contains("falls") || st.contains("lake") || st.contains("river") || st.contains("dam") {
            return "water.waves"
        } else if st.contains("view") || st.contains("sight") || st.contains("camera") || st.contains("photo") {
            return "camera.fill"
        } else if st.contains("palace") || st.contains("fort") || st.contains("monument") {
            return "crown.fill"
        } else {
            return "mappin"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let currentX = w * progress
            let trackY = h / 2
            let allStops = !stops.isEmpty ? stops : (nextStop != nil ? [nextStop!] : [])

            ZStack(alignment: .leading) {
                // Background Dashed/Dotted Line (Remaining Path)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: trackY))
                    path.addLine(to: CGPoint(x: w - 14, y: trackY))
                }
                .stroke(
                    Color.white.opacity(0.35),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [4, 6])
                )

                // Foreground Solid Line (Completed Path)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: trackY))
                    path.addLine(to: CGPoint(x: currentX, y: trackY))
                }
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )

                // Intermediate Waypoint Stop Nodes with Dynamic Category Symbols
                ForEach(0..<allStops.count, id: \.self) { idx in
                    let stopX = w * (CGFloat(idx + 1) / CGFloat(allStops.count + 1))
                    let sym = stopSymbol(for: allStops[idx])
                    let isPassed = currentX >= (stopX + 6)
                    
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .shadow(color: Color.black.opacity(0.4), radius: 3)
                        
                        if isPassed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(Color(red: 0.15, green: 0.70, blue: 0.35))
                        } else {
                            Image(systemName: sym)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                    .position(x: stopX, y: trackY)
                }

                // Moving Vehicle Avatar (Zomato-style Red Badge with Vehicle Symbol)
                ZStack {
                    Circle()
                        .fill(Color(red: 0.85, green: 0.18, blue: 0.18))
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .position(x: max(14, min(w - 28, currentX)), y: trackY)

                // Destination Node (White Circle with Home/Flag icon)
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: Color.black.opacity(0.4), radius: 3)
                    
                    Image(systemName: "house.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                }
                .position(x: w - 12, y: trackY)
            }
        }
    }
}


