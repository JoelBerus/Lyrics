import Foundation

struct SpotifyToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let scope: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-30)
    }
}
