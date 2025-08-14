import Foundation
import CoreLocation

final class LocationManager: NSObject, CLLocationManagerDelegate {
	static let shared = LocationManager()
	private let manager = CLLocationManager()
	private(set) var lastCoordinate: CLLocationCoordinate2D?
	private(set) var lastUpdatedAt: Date?

	private override init() {
		super.init()
		manager.delegate = self
		manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
	}

	func start() {
		// Request when-in-use permission and start updates if allowed
		let status = CLLocationManager.authorizationStatus()
		switch status {
#if os(macOS)
		case .authorizedAlways, .authorized:
			manager.startUpdatingLocation()
#else
		case .authorizedAlways, .authorizedWhenInUse:
			manager.startUpdatingLocation()
#endif
		case .notDetermined:
			manager.requestWhenInUseAuthorization()
		default:
			break
		}
	}

	func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
#if os(macOS)
		if status == .authorizedAlways || status == .authorized {
			manager.startUpdatingLocation()
		}
#else
		if status == .authorizedAlways || status == .authorizedWhenInUse {
			manager.startUpdatingLocation()
		}
#endif
	}

	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		guard let loc = locations.last else { return }
		lastCoordinate = loc.coordinate
		lastUpdatedAt = Date()
		// Reduce battery: stop after first fix; resume later if needed
		manager.stopUpdatingLocation()
	}

	func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		// Ignore; we'll simply have no location context
	}
}


