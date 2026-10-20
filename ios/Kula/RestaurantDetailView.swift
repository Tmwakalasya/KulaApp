import SwiftUI

struct RestaurantDetailView: View {
    let restaurantID: String
    @Environment(CartStore.self) private var cart
    @State private var showCart = false
    @State private var pendingItem: MenuItem?
    @State private var showReplaceConfirmation = false
    @State private var showCartLimit = false
    @State private var restaurant: Restaurant?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var query = ""
    @AppStorage("kula.savedRestaurantIDs") private var savedIDs = ""
    @Environment(\.dismiss) private var dismiss
    private let api = CatalogAPI()

    private var isSaved: Bool {
        savedIDs.split(separator: "|").contains(Substring(restaurantID))
    }

    var body: some View {
        ScrollView {
            if let restaurant {
                VStack(alignment: .leading, spacing: 0) {
                    FoodPhoto(name: restaurant.photoName)
                        .frame(height: 245)
                        .overlay(alignment: .bottomLeading) {
                            Text(restaurant.area.uppercased())
                                .font(KulaType.eyebrow)
                                .tracking(1.2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(.black)
                                .background(.white, in: Capsule())
                                .padding(20)
                        }
                    VStack(alignment: .leading, spacing: 24) {
                        restaurantIntroduction(restaurant)
                        if let errorMessage {
                            Text(errorMessage).font(KulaType.caption).foregroundStyle(.secondary)
                            Button("Refresh menu") { Task { await load() } }
                                .disabled(isLoading)
                        }
                        menuSection(restaurant)
                        DemoNotice()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .padding(20)
                }
            } else if let errorMessage {
                RetryView(message: errorMessage) { await load() }
            } else {
                ProgressView("Loading something good…")
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .background(Palette.background)
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if cart.count > 0 {
                Button { showCart = true } label: {
                    Label("View cart · \(cart.count) items", systemImage: "basket")
                        .font(KulaType.emphasized)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .padding(16)
                .background(Palette.background)
            }
        }
        .sheet(isPresented: $showCart) { CartView() }
        .confirmationDialog("Start a new cart?", isPresented: $showReplaceConfirmation, titleVisibility: .visible) {
            Button("Replace cart", role: .destructive) {
                if let pendingItem, let restaurant {
                    cart.replace(with: pendingItem, from: restaurant)
                }
                pendingItem = nil
            }
            Button("Keep current cart", role: .cancel) { pendingItem = nil }
        } message: {
            Text("Your cart has dishes from \(cart.restaurantName). Each cart can contain dishes from one restaurant.")
        }
        .alert("Cart limit reached", isPresented: $showCartLimit) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can add up to 20 of each dish and 50 items in total.")
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Palette.surface, in: Circle())
            }
            .accessibilityLabel("Back to restaurants")
            Spacer()
            Text("kula.")
                .font(KulaType.wordmark)
                .tracking(-1.5)
                .foregroundStyle(Palette.accent)
            Spacer()
            Button {
                var saved = Set(savedIDs.split(separator: "|").map(String.init))
                if isSaved { saved.remove(restaurantID) } else { saved.insert(restaurantID) }
                savedIDs = saved.sorted().joined(separator: "|")
            } label: {
                Image(systemName: isSaved ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSaved ? Palette.accent : .primary)
                    .frame(width: 44, height: 44)
                    .background(Palette.surface, in: Circle())
            }
            .disabled(restaurant == nil)
            .accessibilityLabel(isSaved ? "Unsave restaurant" : "Save restaurant")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Palette.background)
    }

    private func restaurantIntroduction(_ restaurant: Restaurant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(restaurant.name)
                .font(KulaType.title)
                .tracking(-1)
            Text(restaurant.cuisine)
                .font(KulaType.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let price = restaurant.startingPrice {
                    Text(price)
                        .font(KulaType.small)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Palette.surface, in: Capsule())
                }
                Text("Sample restaurant")
                    .font(KulaType.small)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Palette.accent.opacity(0.08), in: Capsule())
            }
            Text(restaurant.description)
                .font(KulaType.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            Label("Preview the menu · ordering isn’t available yet", systemImage: "info.circle")
                .font(KulaType.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func menuSection(_ restaurant: Restaurant) -> some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = restaurant.menu.filter {
            term.isEmpty || $0.name.localizedStandardContains(term) || $0.description.localizedStandardContains(term)
        }
        return VStack(alignment: .leading, spacing: 20) {
            Divider()
            HStack {
                Text("On the menu").font(KulaType.heading).tracking(-0.5)
                Spacer()
                Text("\(items.count) dishes").font(KulaType.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search this menu", text: $query)
                    .font(KulaType.body)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 32, height: 44)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear menu search")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            if items.isEmpty {
                ContentUnavailableView("No dishes found", systemImage: "magnifyingglass", description: Text("Try a different search."))
            }
            ForEach(items) { item in
                MenuItemRow(item: item) {
                    switch cart.add(item, from: restaurant) {
                    case .added: break
                    case .differentRestaurant:
                        pendingItem = item
                        showReplaceConfirmation = true
                    case .limitReached:
                        showCartLimit = true
                    }
                }
                Divider()
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading, !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.restaurant(id: restaurantID)
            try Task.checkCancellation()
            restaurant = result
            errorMessage = nil
        } catch is CancellationError {
            // Keep the current menu when navigation cancels a refresh.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MenuItemRow: View {
    let item: MenuItem
    let onAdd: () -> Void

    // Only show a dish photo when it depicts that specific fixture.
    private var photo: String? {
        switch item.id {
        case "beef-pilau": "kivuli-food"
        case "grilled-fish": "bahari-food"
        case "chicken-bowl": "ember-food"
        default: nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name).font(KulaType.emphasized)
                Text(item.description)
                    .font(KulaType.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.formattedPrice)
                    .font(KulaType.emphasized)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                if let photo {
                    FoodPhoto(name: photo)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(KulaType.emphasized)
                        .frame(minWidth: 72, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add \(item.name) to cart")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
