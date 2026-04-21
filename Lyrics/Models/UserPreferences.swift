import Foundation

struct CarPlayDisplayPreferences: Codable, Equatable {
    var fontSize: Double
    var centeredText: Bool
    var showOnlyCurrentLine: Bool

    static let `default` = CarPlayDisplayPreferences(
        fontSize: 20,
        centeredText: true,
        showOnlyCurrentLine: false
    )
}

struct UserPreferences: Codable, Equatable {
    var appThemeRawValue: String
    var carPlay: CarPlayDisplayPreferences

    static let `default` = UserPreferences(
        appThemeRawValue: "system",
        carPlay: .default
    )
}
