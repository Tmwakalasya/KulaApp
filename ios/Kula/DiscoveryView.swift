import SwiftUI

struct NearbyRestaurant: Decodable, Identifiable, Sendable {
    struct Attribution: Decodable, Sendable {
        let provider: String
        let providerUri: String?
    }
    let place_id: String
    let name: String
    let address: String
    let maps_url: String
    let attributions: [Attribution]
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
                    Text("Around Oyster Bay & Masaki").font(KulaType.heading)
                    Text("Discover nearby restaurants. These listings are not Kula partners; menus, prices and ordering are not available here.")
                        .font(KulaType.body).foregroundStyle(.secondary)
                    if isLoading {
                        ProgressView("Finding nearby restaurants…").frame(maxWidth: .infinity, minHeight: 100)
                    } else if let message {
                        RetryView(message: message) { await load() }
                    } else if loaded && restaurants.isEmpty {
                        ContentUnavailableView("No nearby listings returned", systemImage: "mappin", description: Text("Please try again later."))
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            // Google content is visually separated from sample menus.
                            Text("Google Maps")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .accessibilityLabel("Restaurant listings provided by Google Maps")
                            ForEach(restaurants) { restaurant in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(restaurant.name).font(KulaType.emphasized)
                                    Text(restaurant.address).font(KulaType.body).foregroundStyle(.secondary)
                                    if let url = safeHTTPSURL(restaurant.maps_url) {
                                        Link(destination: url) { Label("View on Google Maps", systemImage: "arrow.up.right.square") }
                                            .font(KulaType.caption)
                                    }
                                    ForEach(Array(restaurant.attributions.enumerated()), id: \.offset) { _, attribution in
                                        if let uri = attribution.providerUri, let url = safeHTTPSURL(uri) {
                                            Link(attribution.provider, destination: url).font(KulaType.caption)
                                        } else {
                                            Text(attribution.provider).font(KulaType.caption)
                                        }
                                    }
                                }
                                Divider()
                            }
                        }
                        .padding(16)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
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

    private func safeHTTPSURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
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
