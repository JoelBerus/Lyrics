import Foundation
import Combine

@MainActor
final class CarPlaySettingsViewModel: ObservableObject {
    @Published var fontSize: Double = CarPlayDisplayPreferences.default.fontSize
    @Published var centeredText: Bool = CarPlayDisplayPreferences.default.centeredText
    @Published var showOnlyCurrentLine: Bool = CarPlayDisplayPreferences.default.showOnlyCurrentLine
    private var cancellables = Set<AnyCancellable>()

    init() {
        let current = CarPlayPreferencesStore.shared.preferences
        fontSize = current.fontSize
        centeredText = current.centeredText
        showOnlyCurrentLine = current.showOnlyCurrentLine

        Publishers.CombineLatest3($fontSize, $centeredText, $showOnlyCurrentLine)
            .sink { fontSize, centeredText, showOnlyCurrentLine in
                let updated = CarPlayDisplayPreferences(
                    fontSize: fontSize,
                    centeredText: centeredText,
                    showOnlyCurrentLine: showOnlyCurrentLine
                )
                CarPlayPreferencesStore.shared.update(updated)
            }
            .store(in: &cancellables)
    }
}
