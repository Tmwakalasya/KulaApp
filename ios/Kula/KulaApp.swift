import SwiftUI

@main
struct KulaApp: App {
    @State private var cart = CartStore()
    var body: some Scene {
        WindowGroup {
            RestaurantListView()
                .environment(cart)
                .tint(Palette.accent)
                .font(KulaType.body)
        }
    }
}
