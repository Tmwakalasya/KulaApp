import SwiftUI
import Observation

struct QuoteRequestItem: Encodable, Sendable {
    let menu_item_id: String
    let quantity: Int
}

struct CartQuote: Decodable, Sendable {
    struct Line: Decodable, Identifiable, Sendable {
        let menu_item_id: String
        let name: String
        let quantity: Int
        let unit_price_tzs: Int
        let line_total_tzs: Int
        var id: String { menu_item_id }
    }
    let restaurant_id: String
    let restaurant_name: String
    let currency: String
    let items: [Line]
    let subtotal_tzs: Int
    let expires_at: Date
    let demo: Bool
}

@MainActor @Observable
final class CartStore {
    struct Line: Identifiable {
        let item: MenuItem
        var quantity: Int
        var id: String { item.id }
    }
    enum AddResult { case added, differentRestaurant, limitReached }
    private(set) var restaurantID: String?
    private(set) var restaurantName = ""
    private(set) var lines: [Line] = []
    private(set) var quote: CartQuote?
    private(set) var errorMessage: String?
    private(set) var isQuoting = false
    private var revision = 0

    var count: Int { lines.reduce(0) { $0 + $1.quantity } }

    func add(_ item: MenuItem, from restaurant: Restaurant) -> AddResult {
        if let restaurantID, restaurantID != restaurant.id { return .differentRestaurant }
        guard count < 50 else { return .limitReached }
        if let index = lines.firstIndex(where: { $0.id == item.id }) {
            guard lines[index].quantity < 20 else { return .limitReached }
            lines[index].quantity += 1
        } else {
            guard lines.count < 30 else { return .limitReached }
            lines.append(Line(item: item, quantity: 1))
        }
        restaurantID = restaurant.id
        restaurantName = restaurant.name
        invalidateQuote()
        return .added
    }

    func replace(with item: MenuItem, from restaurant: Restaurant) {
        restaurantID = restaurant.id
        restaurantName = restaurant.name
        lines = [Line(item: item, quantity: 1)]
        invalidateQuote()
    }

    func changeQuantity(id: String, by delta: Int) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        let quantity = lines[index].quantity + delta
        guard quantity >= 0, quantity <= 20, count + delta <= 50 else { return }
        if quantity == 0 { lines.remove(at: index) } else { lines[index].quantity = quantity }
        if lines.isEmpty { restaurantID = nil; restaurantName = "" }
        invalidateQuote()
    }

    private func invalidateQuote() {
        revision += 1
        quote = nil
        errorMessage = nil
    }

    func requestQuote() async {
        guard let restaurantID, !lines.isEmpty, !isQuoting else { return }
        isQuoting = true
        quote = nil
        errorMessage = nil
        let requestedRevision = revision
        let items = lines.map { QuoteRequestItem(menu_item_id: $0.id, quantity: $0.quantity) }
        defer { isQuoting = false }
        do {
            let result = try await CatalogAPI().quote(restaurantID: restaurantID, items: items)
            try Task.checkCancellation()
            // A cart edit while the request is in flight invalidates that response.
            guard revision == requestedRevision else { return }
            quote = result
        } catch is CancellationError {
        } catch {
            if revision == requestedRevision { errorMessage = error.localizedDescription }
        }
    }
}

func formatTZS(_ value: Int) -> String {
    "TZS \(value.formatted(.number.locale(Locale(identifier: "en_TZ"))))"
}

struct CartView: View {
    @Environment(CartStore.self) private var cart
    @Environment(\.dismiss) private var dismiss
    @State private var quoteRequest: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if cart.lines.isEmpty {
                        ContentUnavailableView("Something delicious belongs here", systemImage: "basket", description: Text("Add dishes from a sample menu to try a food quote."))
                    } else {
                        Text(cart.restaurantName).font(KulaType.heading)
                        Text("Sample cart · no order or payment will be made.")
                            .font(KulaType.caption).foregroundStyle(.secondary)
                        ForEach(cart.lines) { line in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(line.item.name).font(KulaType.emphasized)
                                HStack(spacing: 20) {
                                    Button { cart.changeQuantity(id: line.id, by: -1) } label: {
                                        Image(systemName: line.quantity == 1 ? "trash" : "minus")
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Remove one \(line.item.name)")
                                    Text("\(line.quantity)").monospacedDigit()
                                    Button { cart.changeQuantity(id: line.id, by: 1) } label: {
                                        Image(systemName: "plus").frame(width: 44, height: 44)
                                    }
                                    .disabled(line.quantity >= 20 || cart.count >= 50)
                                    .accessibilityLabel("Add one \(line.item.name)")
                                }
                                .background(Palette.surface, in: Capsule())
                            }
                            Divider()
                        }
                        if let quote = cart.quote {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                if context.date >= quote.expires_at {
                                    Label("This quote has expired. Refresh it for current prices.", systemImage: "clock")
                                        .font(KulaType.body)
                                } else {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Text("Food quote").font(KulaType.heading)
                                        ForEach(quote.items) { line in
                                            HStack {
                                                Text("\(line.quantity) × \(line.name)")
                                                Spacer()
                                                Text(formatTZS(line.line_total_tzs))
                                            }
                                            .font(KulaType.caption)
                                        }
                                        Divider()
                                        HStack {
                                            Text("Food subtotal")
                                            Spacer()
                                            Text(formatTZS(quote.subtotal_tzs))
                                        }.font(KulaType.emphasized)
                                        Text("Valid until \(quote.expires_at.formatted(date: .omitted, time: .shortened)). Delivery, service fees and taxes are not calculated. This is not a checkout total.")
                                            .font(KulaType.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(18)
                                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                                }
                            }
                        }
                        if let message = cart.errorMessage {
                            Text(message).font(KulaType.body).foregroundStyle(Palette.accent)
                        }
                        Button {
                            quoteRequest = Task { await cart.requestQuote() }
                        } label: {
                            HStack {
                                if cart.isQuoting { ProgressView().tint(.white) }
                                Text(cart.isQuoting ? "Checking prices…" : "Get fresh food quote")
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(cart.isQuoting)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Your cart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onDisappear { quoteRequest?.cancel() }
    }
}
