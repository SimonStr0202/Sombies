import Combine
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    @Published var manager = CLLocationManager()
    
    @Published var lastLocation: CLLocation?
    @Published var heading: Double = 0
    @Published var speed: Double = 0
    var speedInKmh: Double {
        return speed * 3.6
    }
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        
        manager.allowsBackgroundLocationUpdates = false
        #if !os(watchOS)
        manager.pausesLocationUpdatesAutomatically = true
        #endif
        
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdating() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocation = location
            if location.speed >= 0 {
                self.speed = location.speed
            } else {
                self.speed = 0
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading.trueHeading
        }
    }
}
