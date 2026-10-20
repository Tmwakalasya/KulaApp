import SwiftUI

// Adaptive neutrals keep the same hierarchy in light and dark appearance.
enum Palette {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let accent = Color(red: 0.82, green: 0.24, blue: 0.08)
    static let peach = Color(red: 1.0, green: 0.93, blue: 0.85)
    static let ink = Color(red: 0.20, green: 0.13, blue: 0.09)
}

// Built-in typefaces, scaled with the user's preferred text size.
enum KulaType {
    static let wordmark = Font.custom("AvenirNext-Heavy", size: 32, relativeTo: .title)
    static let title = Font.custom("AvenirNext-Bold", size: 29, relativeTo: .largeTitle)
    static let heading = Font.custom("AvenirNext-Bold", size: 21, relativeTo: .title3)
    static let feature = Font.custom("Georgia-Bold", size: 25, relativeTo: .title2)
    static let body = Font.custom("AvenirNext-Regular", size: 15, relativeTo: .subheadline)
    static let emphasized = Font.custom("AvenirNext-DemiBold", size: 15, relativeTo: .subheadline)
    static let caption = Font.custom("AvenirNext-Medium", size: 12, relativeTo: .caption)
    static let small = Font.custom("AvenirNext-DemiBold", size: 11, relativeTo: .caption2)
    static let eyebrow = Font.custom("AvenirNext-Bold", size: 10, relativeTo: .caption2)
}

enum Cuisine: String, CaseIterable {
    case all = "All food"
    case swahili = "Swahili"
    case seafood = "Seafood"
    case grills = "Grills"

    var photo: String? {
        switch self {
        case .all: nil
        case .swahili: "kivuli-food"
        case .seafood: "bahari-food"
        case .grills: "ember-food"
        }
    }

    func includes(_ restaurant: Restaurant) -> Bool {
        switch self {
        case .all: true
        case .swahili: restaurant.cuisine.localizedStandardContains("Swahili")
        case .seafood: restaurant.cuisine.localizedStandardContains("Coastal")
        case .grills: restaurant.cuisine.localizedStandardContains("Grills")
        }
    }
}

extension Restaurant {
    // Presentation assets for these fictional fixtures; no API changes required.
    var photoName: String? {
        switch id {
        case "kivuli-kitchen": "kivuli-food"
        case "bahari-table": "bahari-food"
        case "ember-grain": "ember-food"
        default: nil
        }
    }

    var lowestPrice: Int? { menu.map(\.priceTZS).min() }

    var startingPrice: String? {
        lowestPrice.map { "From TZS \($0.formatted(.number.locale(Locale(identifier: "en_TZ"))))" }
    }
}

struct RestaurantListView: View {
    @Environment(CartStore.self) private var cart
    @State private var showCart = false
    @State private var showNearby = false
    @State private var restaurants: [Restaurant] = []
    @State private var area = "All"
    @State private var cuisine = Cuisine.all
    @State private var query = ""
    @State private var savedOnly = false
    @State private var lowestPriceFirst = false
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @AppStorage("kula.savedRestaurantIDs") private var savedIDs = ""
    @FocusState private var searchFocused: Bool
    private let api = CatalogAPI()

    private var saved: Set<String> { Set(savedIDs.split(separator: "|").map(String.init)) }
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isBrowsing: Bool { !savedOnly && searchTerm.isEmpty && cuisine == .all }

    private var visibleRestaurants: [Restaurant] {
        let matches = restaurants.filter { restaurant in
            (area == "All" || restaurant.area == area)
            && cuisine.includes(restaurant)
            && (!savedOnly || saved.contains(restaurant.id))
            && (searchTerm.isEmpty || ([restaurant.name, restaurant.cuisine]
                + restaurant.menu.map(\.name)).contains { $0.localizedStandardContains(searchTerm) })
        }
        guard lowestPriceFirst else { return matches }
        return matches.sorted {
            if $0.lowestPrice == $1.lowestPrice { return $0.name < $1.name }
            return ($0.lowestPrice ?? .max) < ($1.lowestPrice ?? .max)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchBar
                    if !savedOnly { cuisinePicker }
                    if isBrowsing { welcomeCard }
                    catalogContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Palette.background)
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { neighbourhoodHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
            .refreshable { await load() }
            .task { if !hasLoaded { await load() } }
        }
        .sheet(isPresented: $showCart) { CartView() }
        .sheet(isPresented: $showNearby) { DiscoveryView() }
    }

    private var neighbourhoodHeader: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Neighbourhood", selection: $area) {
                    Text("Oyster Bay & Masaki").tag("All")
                    Text("Oyster Bay").tag("Oyster Bay")
                    Text("Masaki").tag("Masaki")
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 42, height: 42)
                        .background(Palette.accent.opacity(0.09), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EXPLORE DAR")
                            .font(KulaType.eyebrow)
                            .tracking(1.8)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 5) {
                            Text(area == "All" ? "Oyster Bay & Masaki" : area)
                                .font(KulaType.emphasized)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .accessibilityLabel("Choose neighbourhood, \(area == "All" ? "Oyster Bay and Masaki" : area)")
            Spacer(minLength: 8)
            Text("kula.")
                .font(KulaType.wordmark)
                .tracking(-1.5)
                .foregroundStyle(Palette.accent)
                .accessibilityLabel("Kula")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.background)
    }

    private var searchBar: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .medium))
            TextField("What are you craving?", text: $query)
                .font(KulaType.body)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("catalog-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var cuisinePicker: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Cuisine.allCases, id: \.self) { choice in
                Button {
                    cuisine = choice
                    searchFocused = false
                } label: {
                    VStack(spacing: 8) {
                        Group {
                            if let photo = choice.photo {
                                FoodPhoto(name: photo)
                            } else {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(Palette.accent)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Palette.peach)
                            }
                        }
                        .frame(width: 58, height: 58)
                        .clipShape(Circle())
                        .padding(4)
                        .overlay(Circle().stroke(cuisine == choice ? Palette.accent : .clear, lineWidth: 2))
                        Text(choice.rawValue)
                            .font(KulaType.caption).fontWeight(cuisine == choice ? .bold : .medium)
                            .foregroundStyle(cuisine == choice ? Palette.accent : .primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(cuisine == choice ? .isSelected : [])
            }
        }
    }

    private var welcomeCard: some View {
        Button {
            cuisine = .swahili
            searchFocused = false
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("KARIBU, KULA.")
                        .font(KulaType.eyebrow)
                        .tracking(1.8)
                        .foregroundStyle(Palette.accent)
                    Text("A little taste\nof Dar.")
                        .font(KulaType.feature)
                        .tracking(-0.6)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 6) {
                        Text("Explore Swahili flavours")
                        Image(systemName: "arrow.right")
                    }
                    .font(KulaType.small)
                    .foregroundStyle(Palette.ink)
                }
                .padding(.vertical, 20)
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                FoodPhoto(name: "kivuli-food")
                    .frame(width: 132, height: 132)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 5))
                    .padding(.trailing, 14)
                    .accessibilityHidden(true)
            }
            .background(Palette.peach, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var catalogContent: some View {
        if !hasLoaded && isLoading {
            ProgressView("Finding something good…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if let errorMessage, restaurants.isEmpty {
            RetryView(message: errorMessage) { await load() }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(savedOnly ? "Your favourites" : searchTerm.isEmpty ? "Find your next favourite" : "Search results")
                            .font(KulaType.heading)
                            .tracking(-0.5)
                        Text("\(visibleRestaurants.count) \(visibleRestaurants.count == 1 ? "restaurant" : "restaurants") to explore")
                            .font(KulaType.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Picker("Sort restaurants", selection: $lowestPriceFirst) {
                            Text("Default order").tag(false)
                            Text("Price: low to high").tag(true)
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(lowestPriceFirst ? Palette.accent : .primary)
                            .frame(width: 44, height: 44)
                            .background(Palette.surface, in: Circle())
                    }
                    .accessibilityLabel("Sort restaurants")
                }
                if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage).font(KulaType.caption).foregroundStyle(.secondary)
                        Button("Refresh menus") { Task { await load() } }
                            .font(KulaType.small)
                            .disabled(isLoading)
                    }
                }
                if visibleRestaurants.isEmpty {
                    emptyResults
                } else {
                    LazyVStack(spacing: 26) {
                        ForEach(visibleRestaurants) { restaurant in
                            RestaurantCard(restaurant: restaurant, isSaved: saved.contains(restaurant.id)) {
                                toggleSaved(restaurant.id)
                            }
                        }
                    }
                }
                DemoNotice()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
    }

    private var emptyResults: some View {
        ContentUnavailableView {
            Label(savedOnly && saved.isEmpty ? "Keep the good ones close" : "Nothing on the menu yet", systemImage: savedOnly ? "heart" : "magnifyingglass")
        } description: {
            Text(savedOnly && saved.isEmpty ? "Tap a heart on any restaurant to find it here later." : "Try another cuisine, neighbourhood, or search.")
        } actions: {
            Button("Explore all restaurants") {
                query = ""
                cuisine = .all
                area = "All"
                savedOnly = false
                searchFocused = false
            }
            .buttonStyle(.bordered)
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            navigationItem("Explore", symbol: "house", selected: !savedOnly) {
                savedOnly = false
            }
            navigationItem("Nearby", symbol: "map", selected: false) {
                showNearby = true
            }
            navigationItem("Saved", symbol: "heart", selected: savedOnly) {
                savedOnly = true
                // Saved is the complete collection, not a hidden subset of a search.
                query = ""
                cuisine = .all
                area = "All"
            }
            navigationItem(cart.count == 0 ? "Cart" : "Cart (\(cart.count))", symbol: "basket", selected: false) {
                showCart = true
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Palette.background)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private func navigationItem(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            searchFocused = false
        } label: {
            VStack(spacing: 5) {
                Image(systemName: selected ? symbol + ".fill" : symbol)
                    .font(.system(size: 21, weight: .medium))
                Text(title).font(KulaType.small)
            }
            .foregroundStyle(selected ? Palette.accent : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleSaved(_ id: String) {
        var updated = saved
        if updated.contains(id) { updated.remove(id) } else { updated.insert(id) }
        savedIDs = updated.sorted().joined(separator: "|")
    }

    @MainActor
    private func load() async {
        guard !isLoading, !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.restaurants()
            try Task.checkCancellation()
            restaurants = result
            errorMessage = nil
            hasLoaded = true
        } catch is CancellationError {
            // Navigation cancels the request without replacing the screen with an error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RestaurantCard: View {
    let restaurant: Restaurant
    let isSaved: Bool
    let toggleSaved: () -> Void

    var body: some View {
        NavigationLink {
            RestaurantDetailView(restaurantID: restaurant.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                FoodPhoto(name: restaurant.photoName)
                    .frame(height: 180)
                    .overlay(alignment: .bottomLeading) {
                        Text(restaurant.area)
                            .font(KulaType.small)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.white, in: Capsule())
                            .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(restaurant.name).font(KulaType.heading).tracking(-0.4)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                    }
                    Text(restaurant.cuisine).font(KulaType.body).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if let price = restaurant.startingPrice {
                            Text(price).fontWeight(.semibold)
                            Text("·").foregroundStyle(.tertiary)
                        }
                        Text("Sample menu").foregroundStyle(.secondary)
                    }
                    .font(KulaType.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("restaurant-\(restaurant.id)")
        .overlay(alignment: .topTrailing) {
            Button(action: toggleSaved) {
                Image(systemName: isSaved ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSaved ? Palette.accent : .black)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("\(isSaved ? "Unsave" : "Save") \(restaurant.name)")
        }
    }
}

struct FoodPhoto: View {
    let name: String?

    var body: some View {
        GeometryReader { geometry in
            if let name {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Image(systemName: "fork.knife")
                    .font(.largeTitle)
                    .foregroundStyle(Palette.accent)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Palette.peach)
            }
        }
        .accessibilityHidden(true)
    }
}

struct DemoNotice: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("A taste of what’s coming.").fontWeight(.semibold)
            Text("Sample restaurants · illustrative photos · no orders yet")
        }
        .font(KulaType.small)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct RetryView: View {
    let message: String
    let retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label("Let’s try that again", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button(isRetrying ? "Trying…" : "Try again") {
                Task {
                    isRetrying = true
                    defer { isRetrying = false }
                    await retry()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
    }
}
