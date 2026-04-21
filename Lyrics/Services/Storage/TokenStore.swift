import Foundation
import Security

protocol TokenStoreProtocol {
    func readToken() -> SpotifyToken?
    func save(token: SpotifyToken) -> Bool
    func clear()
}

final class TokenStore: TokenStoreProtocol {
    private let service = "com.berus.Lyrics.spotify"
    private let account = "oauth_token"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func readToken() -> SpotifyToken? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? decoder.decode(SpotifyToken.self, from: data)
    }

    func save(token: SpotifyToken) -> Bool {
        guard let data = try? encoder.encode(token) else {
            return false
        }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }

        let updateQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let updateData: [CFString: Any] = [kSecValueData: data]
        return SecItemUpdate(updateQuery as CFDictionary, updateData as CFDictionary) == errSecSuccess
    }

    func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
