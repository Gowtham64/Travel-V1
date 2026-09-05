import UIKit
import MapKit
import CoreLocation

// MARK: - Custom Annotations

class VehiclePuckAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var bearing: Double = 0.0

    init(coordinate: CLLocationCoordinate2D, bearing: Double = 0.0) {
        self.coordinate = coordinate
        self.bearing = bearing
        super.init()
    }
}

class StopPointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let isFuelStop: Bool
    let isDestination: Bool
    let isOrigin: Bool
    let refillLiters: Double?

    init(
        coordinate: CLLocationCoordinate2D,
        title: String?,
        subtitle: String? = nil,
        isFuelStop: Bool = false,
        isDestination: Bool = false,
        isOrigin: Bool = false,
        refillLiters: Double? = nil
    ) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.isFuelStop = isFuelStop
        self.isDestination = isDestination
        self.isOrigin = isOrigin
        self.refillLiters = refillLiters
        super.init()
    }
}

// MARK: - CarPlay Map View Controller

class CarPlayMapViewController: UIViewController, MKMapViewDelegate {
    private var mapView: MKMapView!
    private var vehiclePuck: VehiclePuckAnnotation?
    private var activeRoutePolyline: MKPolyline?
    private var activeCasingPolyline: MKPolyline?

    private var isFollowMode: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapView()
        CarPlayNavigationManager.shared.mapViewController = self
    }

    private func setupMapView() {
        mapView = MKMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.showsUserLocation = false
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll

        // Automotive styling
        mapView.overrideUserInterfaceStyle = .unspecified // Adapts dynamically to car day/night headlights
        view.addSubview(mapView)
    }

    // MARK: - Route & Waypoint Updates
    func updateRoute(
        coordinates: [CLLocationCoordinate2D],
        waypoints: [CarPlayWaypoint],
        fuelStops: [CarPlayFuelStop]
    ) {
        // Clear previous overlays and annotations
        if let existing = activeRoutePolyline { mapView.removeOverlay(existing) }
        if let existingCasing = activeCasingPolyline { mapView.removeOverlay(existingCasing) }
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is VehiclePuckAnnotation) })

        guard coordinates.count > 1 else { return }

        // 1. Add route polyline
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        self.activeRoutePolyline = polyline
        mapView.addOverlay(polyline, level: .aboveRoads)

        // 2. Add Start & Destination Annotations
        if let start = coordinates.first {
            let startAnn = StopPointAnnotation(coordinate: start, title: "Start", isOrigin: true)
            mapView.addAnnotation(startAnn)
        }
        if let end = coordinates.last {
            let destName = CarPlayNavigationManager.shared.destinationName
            let endAnn = StopPointAnnotation(coordinate: end, title: destName, isDestination: true)
            mapView.addAnnotation(endAnn)
        }

        // 3. Add Intermediate Waypoints
        for wp in waypoints where !wp.isFuelStop {
            let wpAnn = StopPointAnnotation(coordinate: wp.coordinate, title: wp.name)
            mapView.addAnnotation(wpAnn)
        }

        // 4. Add Fuel Stops
        for fs in fuelStops {
            let subtitle = String(format: "+%.1f L (Est. ₹%.0f)", fs.refillLiters, fs.estimatedCost)
            let fsAnn = StopPointAnnotation(
                coordinate: fs.coordinate,
                title: fs.name,
                subtitle: subtitle,
                isFuelStop: true,
                refillLiters: fs.refillLiters
            )
            mapView.addAnnotation(fsAnn)
        }

        // Fit map initially
        zoomToOverview()
    }

    // MARK: - Live Vehicle Location & Heading
    func updateVehicleLocation(_ coordinate: CLLocationCoordinate2D, bearing: Double) {
        if vehiclePuck == nil {
            let puck = VehiclePuckAnnotation(coordinate: coordinate, bearing: bearing)
            vehiclePuck = puck
            mapView.addAnnotation(puck)
        } else {
            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.vehiclePuck?.coordinate = coordinate
                self?.vehiclePuck?.bearing = bearing
            }
            // Update rotation of existing annotation view
            if let view = mapView.view(for: vehiclePuck!) {
                let radians = CGFloat(bearing * .pi / 180.0)
                UIView.animate(withDuration: 0.25) {
                    view.transform = CGAffineTransform(rotationAngle: radians)
                }
            }
        }

        // In follow mode, center camera on vehicle with automotive 3D pitch and heading
        if isFollowMode {
            let camera = MKMapCamera(
                lookingAtCenter: coordinate,
                fromDistance: 600, // Close driving distance
                pitch: 50,         // Automotive perspective tilt
                heading: bearing   // Direction of travel
            )
            mapView.setCamera(camera, animated: true)
        }
    }

    // MARK: - Camera Controls
    func recenterOnVehicle() {
        isFollowMode = true
        if let puck = vehiclePuck {
            updateVehicleLocation(puck.coordinate, bearing: puck.bearing)
        }
    }

    func zoomToOverview() {
        isFollowMode = false
        if let poly = activeRoutePolyline {
            let rect = poly.boundingMapRect
            let edgePadding = UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60)
            mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: true)
        }
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            // Vibrant cyan route line matching VoyPlan brand
            renderer.strokeColor = UIColor(red: 6/255.0, green: 182/255.0, blue: 212/255.0, alpha: 0.95)
            renderer.lineWidth = 8
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let puck = annotation as? VehiclePuckAnnotation {
            let identifier = "VehiclePuckView"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if view == nil {
                view = MKAnnotationView(annotation: puck, reuseIdentifier: identifier)
                view?.canShowCallout = false
                view?.frame = CGRect(x: 0, y: 0, width: 36, height: 36)

                // Draw navigation chevron
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36))
                let image = renderer.image { ctx in
                    let cg = ctx.cgContext
                    // Outer glow/shadow ring
                    cg.setFillColor(UIColor.white.cgColor)
                    cg.addEllipse(in: CGRect(x: 4, y: 4, width: 28, height: 28))
                    cg.fillPath()

                    // Navy circle
                    cg.setFillColor(UIColor(red: 15/255.0, green: 23/255.0, blue: 42/255.0, alpha: 1.0).cgColor)
                    cg.addEllipse(in: CGRect(x: 6, y: 6, width: 24, height: 24))
                    cg.fillPath()

                    // Cyan Navigation Triangle Pointer pointing North
                    cg.setFillColor(UIColor(red: 6/255.0, green: 182/255.0, blue: 212/255.0, alpha: 1.0).cgColor)
                    cg.move(to: CGPoint(x: 18, y: 8))
                    cg.addLine(to: CGPoint(x: 25, y: 24))
                    cg.addLine(to: CGPoint(x: 18, y: 20))
                    cg.addLine(to: CGPoint(x: 11, y: 24))
                    cg.closePath()
                    cg.fillPath()
                }
                view?.image = image
            } else {
                view?.annotation = puck
            }
            let radians = CGFloat(puck.bearing * .pi / 180.0)
            view?.transform = CGAffineTransform(rotationAngle: radians)
            return view
        }

        if let stop = annotation as? StopPointAnnotation {
            let identifier = "StopPointView"
            let marker = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: stop, reuseIdentifier: identifier)

            marker.canShowCallout = true

            if stop.isFuelStop {
                // Amber Fuel Stop Badge with ⛽
                marker.glyphText = "⛽"
                marker.markerTintColor = UIColor(red: 245/255.0, green: 158/255.0, blue: 11/255.0, alpha: 1.0)
                marker.displayPriority = .required
            } else if stop.isDestination {
                // Red destination pin
                marker.glyphText = "🏁"
                marker.markerTintColor = UIColor(red: 239/255.0, green: 68/255.0, blue: 68/255.0, alpha: 1.0)
                marker.displayPriority = .required
            } else if stop.isOrigin {
                // Green origin pin
                marker.glyphText = "A"
                marker.markerTintColor = UIColor(red: 16/255.0, green: 185/255.0, blue: 129/255.0, alpha: 1.0)
            } else {
                // Intermediate Waypoint
                marker.glyphText = "•"
                marker.markerTintColor = UIColor(red: 14/255.0, green: 165/255.0, blue: 233/255.0, alpha: 1.0)
            }
            return marker
        }

        return nil
    }
}
