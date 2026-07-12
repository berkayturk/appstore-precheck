import CoreLocation

final class RunSessionManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var route: [CLLocation] = []

    func startRun() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        route.append(contentsOf: locations)
    }
}
