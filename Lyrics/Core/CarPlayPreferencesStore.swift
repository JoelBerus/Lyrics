import Foundation
import Combine

@MainActor
final class CarPlayPreferencesStore: ObservableObject {
    static let shared = CarPlayPreferencesStore()

    @Published private(set) var preferences: CarPlayDisplayPreferences = .default

    private init() {}

    func update(_ newPreferences: CarPlayDisplayPreferences) {
        preferences = newPreferences
    }
}
