import Foundation

struct MenuItem: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let priceTZS: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case priceTZS = "price_tzs"
    }

    var formattedPrice: String {
        "TZS \(priceTZS.formatted(.number.locale(Locale(identifier: "en_TZ"))))"
    }
}

struct Restaurant: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let area: String
    let cuisine: String
    let description: String
    let menu: [MenuItem]
}

enum CatalogError: LocalizedError {
    case unavailable
    case invalidResponse
    case missingRestaurant
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "We couldn’t reach Kula. Please try again shortly."
        case .invalidResponse:
            "We couldn’t load this menu. Please try again."
        case .missingRestaurant:
            "This restaurant is no longer available."
        case .server(let message):
            message
        }
    }
}

struct CatalogAPI: Sendable {
    private struct Failure: Decodable { let error: String }
    // Simulator-only endpoint. Release builds deliberately have no HTTP fallback.
    private var baseURL: URL? {
        #if DEBUG && targetEnvironment(simulator)
        URL(string: "http://localhost:8087/v1/")
        #else
        nil
        #endif
    }

    /// Fetches the sample restaurant catalog, propagating request and decoding errors.
    func restaurants() async throws -> [Restaurant] {
        struct Response: Decodable { let restaurants: [Restaurant] }
        let response: Response = try await fetch("restaurants")
        return response.restaurants
    }

    /// Fetches a sample restaurant and its menu by catalog ID, propagating request and decoding errors.
    func restaurant(id: String) async throws -> Restaurant {
        try await fetch("restaurants/\(id)")
    }

    /// Posts dish IDs and quantities for one restaurant and returns a server-priced quote, or throws on failure.
    func quote(restaurantID: String, items: [QuoteRequestItem]) async throws -> CartQuote {
        struct Request: Encodable {
            let restaurant_id: String
            let items: [QuoteRequestItem]
        }
        return try await fetch("quotes", body: JSONEncoder().encode(Request(restaurant_id: restaurantID, items: items)))
    }

    /// Fetches live listings for the fixed pilot area, propagating discovery and decoding errors.
    func nearbyRestaurants() async throws -> [NearbyRestaurant] {
        struct Response: Decodable { let restaurants: [NearbyRestaurant] }
        let response: Response = try await fetch("discovery/restaurants")
        return response.restaurants
    }

    /// Resolves a Places photo resource and downloads its image, propagating resolution and download errors.
    func nearbyPhoto(name: String) async throws -> Data {
        struct Response: Decodable { let url: String }
        let response: Response = try await fetch("discovery/photo", query: [URLQueryItem(name: "name", value: name)])
        return try await GoogleImageLoader.data(from: response.url)
    }

    /// Sends a GET, or a JSON POST when a body is supplied, and decodes a successful response with ISO 8601 dates.
    /// Throws cancellation, server, availability or decoding errors as appropriate.
    private func fetch<T: Decodable>(_ path: String, body: Data? = nil, query: [URLQueryItem] = []) async throws -> T {
        guard let baseURL else { throw CatalogError.unavailable }
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw CatalogError.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw CatalogError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CatalogError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                throw CatalogError.server(failure.error)
            }
            throw CatalogError.unavailable
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CatalogError.invalidResponse
        }
    }
}
