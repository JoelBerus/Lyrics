import Foundation
import Combine

@MainActor
final class CarPlaySettingsViewModel: ObservableObject {
    @Published var fontSize: Double = CarPlayDisplayPreferences.default.fontSize
    @Published var centeredText: Bool = CarPlayDisplayPreferences.default.centeredText
    @Published var showOnlyCurrentLine: Bool = CarPlayDisplayPreferences.default.showOnlyCurrentLine
}
