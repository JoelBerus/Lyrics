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

    var grantedScopes: Set<String> {
        Set(
            scope
                .split(separator: " ")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    func containsAllScopes(_ requiredScopes: [String]) -> Bool {
        Set(requiredScopes).isSubset(of: grantedScopes)
    }
}
