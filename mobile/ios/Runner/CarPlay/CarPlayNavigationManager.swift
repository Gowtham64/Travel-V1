import Foundation
import CoreLocation
import MapKit
import CarPlay
import Flutter

/// Represents a fuel stop waypoint on the CarPlay navigation route
struct CarPlayFuelStop {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let fuelType: String
    let refillLiters: Double
    let estimatedCost: Double
    let distanceFromStartKm: Double
}

/// Represents a standard itinerary waypoint
struct CarPlayWaypoint {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let isFuelStop: Bool
}

/// Shared singleton orchestrating CarPlay turn-by-turn navigation state
final class CarPlayNavigationManager: NSObject {
    static let shared = CarPlayNavigationManager()

    // MARK: - Active State
    private(set) var isNavigating: Bool = false
    private(set) var startPoint: CLLocationCoordinate2D?
    private(set) var endPoint: CLLocationCoordinate2D?
    private(set) var destinationName: String = "Destination"
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    private(set) var waypoints: [CarPlayWaypoint] = []
    private(set) var fuelStops: [CarPlayFuelStop] = []

    // Live Telemetry
    private(set) var currentLocation: CLLocationCoordinate2D?
    private(set) var currentBearing: Double = 0.0
    private(set) var currentSpeedMps: Double = 0.0
    private(set) var currentRoadName: String = ""
    private(set) var currentStepCue: String = ""
    private(set) var currentManeuverType: String = ""
    private(set) var maneuverDistanceMeters: Double = 0.0
    private(set) var remainingDistanceKm: Double = 0.0
    private(set) var remainingDurationMin: Double = 0.0
    private(set) var nextFuelStop: String?

    // CarPlay Architecture References
    weak var mapTemplate: CPMapTemplate?
    weak var activeNavigationSession: CPNavigationSession?
    weak var mapViewController: CarPlayMapViewController?
    var carMethodChannel: FlutterMethodChannel?

    private override init() {
        super.init()
    }

    // MARK: - Route Setup from Flutter Channel
    func setRoute(
        start: [String: Any],
        end: [String: Any],
        waypoints: [[String: Any]],
        coordinates: [[String: Any]],
        fuelStops: [[String: Any]]? = nil,
        destinationName: String? = nil
    ) {
        NSLog("VOYPLAN CarPlay: setRoute called with \(coordinates.count) route points")

        if let lat = start["lat"] as? Double, let lng = start["lng"] as? Double {
            self.startPoint = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let lat = end["lat"] as? Double, let lng = end["lng"] as? Double {
            self.endPoint = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let dest = destinationName, !dest.isEmpty {
            self.destinationName = dest
        } else if let name = end["name"] as? String, !name.isEmpty {
            self.destinationName = name
        }

        self.routeCoordinates = coordinates.compactMap { dict in
            guard let lat = dict["lat"] as? Double, let lng = dict["lng"] as? Double else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        self.waypoints = waypoints.compactMap { dict in
            guard let lat = dict["lat"] as? Double, let lng = dict["lng"] as? Double else { return nil }
            let name = dict["name"] as? String ?? ""
            let isFuel = dict["isFuelStop"] as? Bool ?? false
            return CarPlayWaypoint(name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), isFuelStop: isFuel)
        }

        if let stops = fuelStops {
            self.fuelStops = stops.compactMap { dict in
                guard let lat = dict["lat"] as? Double, let lng = dict["lng"] as? Double else { return nil }
                let name = dict["name"] as? String ?? "Fuel Stop"
                let fType = dict["fuelType"] as? String ?? "petrol"
                let refill = dict["refillLiters"] as? Double ?? 0.0
                let cost = dict["estimatedCost"] as? Double ?? 0.0
                let dist = dict["distanceFromStartKm"] as? Double ?? 0.0
                return CarPlayFuelStop(
                    name: name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    fuelType: fType,
                    refillLiters: refill,
                    estimatedCost: cost,
                    distanceFromStartKm: dist
                )
            }
        } else {
            self.fuelStops = []
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.mapViewController?.updateRoute(
                coordinates: self.routeCoordinates,
                waypoints: self.waypoints,
                fuelStops: self.fuelStops
            )
            self.syncTripWithCarPlay()
        }
    }

    // MARK: - Live Navigation Telemetry Updates
    func updateNavigation(args: [String: Any]) {
        if let lat = args["currentLat"] as? Double, let lng = args["currentLng"] as? Double {
            self.currentLocation = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let bearing = args["bearingDeg"] as? Double {
            self.currentBearing = bearing
        }
        if let road = args["roadName"] as? String {
            self.currentRoadName = road
        }
        if let cue = args["stepCue"] as? String {
            self.currentStepCue = cue
        }
        if let mType = args["maneuverType"] as? String {
            self.currentManeuverType = mType
        }
        if let mDist = args["maneuverDistanceMeters"] as? Double {
            self.maneuverDistanceMeters = mDist
        }
        if let rDist = args["remainingDistanceKm"] as? Double {
            self.remainingDistanceKm = rDist
        }
        if let rDur = args["remainingDurationMin"] as? Double {
            self.remainingDurationMin = rDur
        }
        if let nFuel = args["nextFuelStop"] as? String {
            self.nextFuelStop = nFuel
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1. Update Map View vehicle puck & camera
            if let loc = self.currentLocation {
                self.mapViewController?.updateVehicleLocation(loc, bearing: self.currentBearing)
            }

            // 2. Update Active Maneuver in CarPlay banner
            self.updateCarPlayManeuverBanner()
        }
    }

    func setNavigationState(isNavigating: Bool) {
        self.isNavigating = isNavigating
        if !isNavigating {
            stopNavigation(fromCar: false)
        }
    }

    // MARK: - CarPlay Trip & NavigationSession Lifecycle
    func syncTripWithCarPlay() {
        guard let mapTemplate = self.mapTemplate, let destCoord = self.endPoint else { return }

        let destPlacemark = MKPlacemark(coordinate: destCoord)
        let destMapItem = MKMapItem(placemark: destPlacemark)
        destMapItem.name = self.destinationName

        let originCoord = self.currentLocation ?? self.startPoint ?? destCoord
        let originPlacemark = MKPlacemark(coordinate: originCoord)
        let originMapItem = MKMapItem(placemark: originPlacemark)
        originMapItem.name = "Start"

        let routeChoice = CPRouteChoice(
            summaryVariants: [self.destinationName, "Via Voyplan Route"],
            additionalInformationVariants: [
                self.fuelStops.isEmpty ? "Direct Route" : "\(self.fuelStops.count) Fuel Stop(s) Planned"
            ],
            selectionSummaryVariants: ["Fastest Route"]
        )

        let trip = CPTrip(
            origin: originMapItem,
            destination: destMapItem,
            routeChoices: [routeChoice]
        )

        // If navigation is active, start or update the session
        if self.isNavigating {
            if self.activeNavigationSession == nil {
                let session = mapTemplate.startNavigationSession(for: trip)
                self.activeNavigationSession = session
                NSLog("VOYPLAN CarPlay: Navigation session started successfully")
            }
            updateCarPlayManeuverBanner()
        }
    }

    private func updateCarPlayManeuverBanner() {
        guard let session = self.activeNavigationSession else { return }

        let maneuver = CPManeuver()
        maneuver.symbolImage = symbolForManeuver(self.currentManeuverType)

        var instructions: [String] = []
        if !self.currentStepCue.isEmpty {
            instructions.append(self.currentStepCue)
        }
        if !self.currentRoadName.isEmpty {
            instructions.append("Onto \(self.currentRoadName)")
        }
        if instructions.isEmpty {
            instructions.append("Follow Route")
        }
        maneuver.instructionVariants = instructions

        let distanceRemaining = Measurement(value: max(self.maneuverDistanceMeters, 0.0), unit: UnitLength.meters)
        let timeRemaining = max(self.remainingDurationMin * 60.0, 0.0)
        maneuver.initialTravelEstimates = CPTravelEstimates(
            distanceRemaining: distanceRemaining,
            timeRemaining: timeRemaining
        )

        session.upcomingManeuvers = [maneuver]

        // Update overall trip estimates in the bottom status panel
        let tripDistance = Measurement(value: max(self.remainingDistanceKm, 0.0), unit: UnitLength.kilometers)
        let tripEstimates = CPTravelEstimates(distanceRemaining: tripDistance, timeRemaining: timeRemaining)
        mapTemplate?.update(tripEstimates, for: session.trip, with: .default)
    }

    private func symbolForManeuver(_ type: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
        let symbolName: String

        switch type.lowercased() {
        case "turn_left":
            symbolName = "arrow.turn.up.left"
        case "turn_right":
            symbolName = "arrow.turn.up.right"
        case "slight_left":
            symbolName = "arrow.up.left"
        case "slight_right":
            symbolName = "arrow.up.right"
        case "sharp_left":
            symbolName = "arrow.turn.up.left"
        case "sharp_right":
            symbolName = "arrow.turn.up.right"
        case "uturn":
            symbolName = "arrow.uturn.backward"
        case "roundabout":
            symbolName = "arrow.triangle.2.circlepath"
        case "destination":
            symbolName = "flag.checkered"
        default:
            symbolName = "arrow.up"
        }

        if #available(iOS 13.0, *) {
            return UIImage(systemName: symbolName, withConfiguration: config)
        }
        return nil
    }

    // MARK: - Stop Navigation (Driver or Phone initiated)
    func stopNavigation(fromCar: Bool) {
        NSLog("VOYPLAN CarPlay: stopNavigation (fromCar=\(fromCar))")
        self.isNavigating = false
        self.activeNavigationSession?.finishTrip()
        self.activeNavigationSession = nil

        if fromCar {
            DispatchQueue.main.async { [weak self] in
                self?.carMethodChannel?.invokeMethod("stopNavigationFromCar", arguments: nil)
            }
        }
    }
}
