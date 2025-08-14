import Foundation

enum PlacesAPI {
    static func search(query: String, lat: Double, lng: Double, radius: Int = 3000, openNow: Bool = true, completion: @escaping (Result<ClientAPI.PlacesSearchResponse, Error>) -> Void) {
        ClientAPI.shared.placesSearch(query: query, lat: lat, lng: lng, radius: radius, openNow: openNow, completion: completion)
    }
}


