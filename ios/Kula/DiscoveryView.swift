import SwiftUI

struct NearbyRestaurant: Decodable, Identifiable, Sendable {
    struct Attribution: Decodable, Sendable {
        let provider: String
        let providerUri: String?
    }
    struct Photo: Decodable, Sendable {
        struct Author: Decodable, Sendable {
            let displayName: String
            let uri: String
            let photoUri: String
        }
        let name: String
        let googleMapsUri: String
        let authorAttributions: [Author]
    }
    let place_id: String
    let name: String
    let address: String
    let maps_url: String
    let attributions: [Attribution]
    let photo: Photo?
    var id: String { place_id }
}

struct DiscoveryView: View {
    @State private var restaurants: [NearbyRestaurant] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A little closer.\nA new favourite.")
                            .font(KulaType.feature).tracking(-0.6)
                        Text("Explore around Oyster Bay & Masaki")
                            .font(KulaType.emphasized)
                        Text("Restaurant discovery only. These are not Kula partners, and ordering is not available here.")
                            .font(KulaType.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Palette.peach, in: RoundedRectangle(cornerRadius: 22))
                    .foregroundStyle(Palette.ink)
                    if isLoading {
                        ProgressView("Finding nearby restaurants…").frame(maxWidth: .infinity, minHeight: 100)
                    } else if let message {
                        RetryView(message: message) { await load() }
                    } else if loaded && restaurants.isEmpty {
                        ContentUnavailableView("No nearby listings returned", systemImage: "mappin", description: Text("Please try again later."))
                    } else {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(restaurants) { restaurant in
                                NearbyCard(restaurant: restaurant)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Nearby restaurants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task { if !loaded { await load() } }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading, !Task.isCancelled else { return }
        isLoading = true
        message = nil
        restaurants = [] // Only transient display state; no disk cache or database copy.
        defer { isLoading = false }
        do {
            let result = try await CatalogAPI().nearbyRestaurants()
            try Task.checkCancellation()
            restaurants = result
            loaded = true
        } catch is CancellationError {
        } catch {
            message = error.localizedDescription
        }
    }
}

private func discoveryLink(_ value: String) -> URL? {
    let normalized = value.hasPrefix("//") ? "https:" + value : value
    guard let url = URL(string: normalized), url.scheme == "https", url.host != nil, url.user == nil else { return nil }
    return url
}

private struct NearbyCard: View {
    let restaurant: NearbyRestaurant

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlacePhotoView(photo: restaurant.photo, restaurantName: restaurant.name)
                .frame(height: 205)
                .clipped()
            VStack(alignment: .leading, spacing: 12) {
                Text(restaurant.name).font(KulaType.heading).tracking(-0.4)
                Label(restaurant.address, systemImage: "mappin")
                    .font(KulaType.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = discoveryLink(restaurant.maps_url) {
                    Link(destination: url) {
                        HStack {
                            Text("Explore this place")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(KulaType.emphasized)
                        .padding(.vertical, 8)
                    }
                    .accessibilityLabel("Explore \(restaurant.name) on Google Maps")
                }
                Divider()
                HStack {
                    Text("Google Maps")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    if let photo = restaurant.photo, let url = discoveryLink(photo.googleMapsUri) {
                        Link("Photo source", destination: url).font(KulaType.caption)
                    }
                }
                if let photo = restaurant.photo {
                    ForEach(Array(photo.authorAttributions.enumerated()), id: \.offset) { _, author in
                        PhotoCredit(author: author)
                    }
                }
                ForEach(Array(restaurant.attributions.enumerated()), id: \.offset) { _, attribution in
                    if let uri = attribution.providerUri, let url = discoveryLink(uri) {
                        Link(attribution.provider, destination: url).font(KulaType.caption)
                    } else {
                        Text(attribution.provider).font(KulaType.caption)
                    }
                }
            }
            .padding(18)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct PlacePhotoView: View {
    let photo: NearbyRestaurant.Photo?
    let restaurantName: String
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.surface
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityLabel("Photo of \(restaurantName), provided through Google Maps")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "storefront")
                            .font(.system(size: 34, weight: .light))
                        if photo == nil {
                            Text("A place to discover").font(KulaType.caption)
                        } else if failed {
                            Text("Photo unavailable").font(KulaType.caption)
                            Button("Retry photo") { failed = false; attempt += 1 }
                                .font(KulaType.caption).buttonStyle(.bordered)
                        } else {
                            ProgressView().tint(Palette.accent)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: "\(photo?.name ?? "")-\(attempt)") {
            guard let photo, image == nil, !failed else { return }
            do {
                let data = try await CatalogAPI().nearbyPhoto(name: photo.name)
                try Task.checkCancellation()
                guard let result = UIImage(data: data) else { throw CatalogError.invalidResponse }
                image = result
            } catch is CancellationError {
                // Scrolling away cancels work; the visible card can load later.
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct PhotoCredit: View {
    let author: NearbyRestaurant.Photo.Author
    @State private var avatar: UIImage?

    private var label: some View {
        HStack(spacing: 8) {
            Group {
                if let avatar {
                    Image(uiImage: avatar).resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle").resizable().scaledToFit()
                }
            }
            .frame(width: 24, height: 24).clipShape(Circle()).accessibilityHidden(true)
            Text("Photo by \(author.displayName)").font(KulaType.caption)
        }
    }

    var body: some View {
        Group {
            if let url = discoveryLink(author.uri) {
                Link(destination: url) { label }
            } else {
                label
            }
        }
        .task(id: author.photoUri) {
            guard avatar == nil, !author.photoUri.isEmpty else { return }
            do {
                let data = try await GoogleImageLoader.data(from: author.photoUri)
                try Task.checkCancellation()
                avatar = UIImage(data: data)
            } catch {
                // The author's name/profile credit remains when an avatar fails.
            }
        }
    }
}

// Google image bytes stay in transient view state. There is no disk URL cache,
// cookie store or API key on these requests. Redirects are restricted as well.
enum GoogleImageLoader {
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url.flatMap { allowedURL($0.absoluteString) } == nil ? nil : request)
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }()

    private static func allowedURL(_ value: String) -> URL? {
        guard let url = discoveryLink(value),
              url.host?.lowercased().hasSuffix(".googleusercontent.com") == true,
              url.port == nil else { return nil }
        return url
    }

    static func data(from value: String) async throws -> Data {
        guard let url = allowedURL(value) else { throw CatalogError.invalidResponse }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        let limit = 3 * 1024 * 1024
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.hasPrefix("image/") == true,
              response.expectedContentLength <= limit else { throw CatalogError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw CatalogError.invalidResponse }
            data.append(byte)
        }
        return data
    }
}
