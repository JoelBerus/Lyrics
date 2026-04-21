import SwiftUI
import Combine

final class AppRouter: ObservableObject {
    enum Tab: Hashable {
        case carPlaySettings
        case nowPlaying
        case settings
    }

    @Published var selectedTab: Tab = .nowPlaying
}
