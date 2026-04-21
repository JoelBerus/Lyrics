import Foundation
import CryptoKit

protocol SpotifyAuthServiceProtocol {
    func authorizationURL() -> URL?
    func hasValidSession() -> Bool
    func handleRedirectURL(_ url: URL) async throws
    func validAccessToken() async throws -> String
    func refreshAccessToken() async throws -> String
    func signOut()
}

enum SpotifyAuthError: Error {
    case notConfigured
    case invalidRedirect
    case authorizationRejected
    case codeVerifierNotFound
    case stateMismatch
    case missingAuthorizationCode
    case invalidTokenResponse
    case missingRefreshToken
}

final class SpotifyAuthService: SpotifyAuthServiceProtocol {
    private let environment: AppEnvironment
    private let tokenStore: TokenStoreProtocol
    private var pendingState: String?
    private var pendingCodeVerifier: String?
    private let session: URLSession
    private let spotifyScopes = [
        "user-read-currently-playing",
        "user-read-playback-state"
    ]

    init(
        environment: AppEnvironment,
        tokenStore: TokenStoreProtocol,
        session: URLSession = .shared
    ) {
        self.environment = environment
        self.tokenStore = tokenStore
        self.session = session
    }

    func authorizationURL() -> URL? {
        let clientID = resolvedClientID()
        #if DEBUG
        print("[SpotifyAuthService] authorizationURL - envClientID=\(masked(environment.spotifyClientID)) bundleClientID=\(masked(bundleClientID())) processEnvClientID=\(masked(processClientID())) resolvedClientID=\(masked(clientID))")
        #endif
        guard !clientID.isEmpty else { return nil }
        let state = randomURLSafeString()
        let codeVerifier = randomURLSafeString(length: 96)
        let codeChallenge = codeChallenge(for: codeVerifier)

        pendingState = state
        pendingCodeVerifier = codeVerifier

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: AppConstants.spotifyRedirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "scope", value: spotifyScopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        return components?.url
    }

    func hasValidSession() -> Bool {
        tokenStore.readToken() != nil
    }

    func handleRedirectURL(_ url: URL) async throws {
        guard url.absoluteString.starts(with: AppConstants.spotifyRedirectURI) else {
            throw SpotifyAuthError.invalidRedirect
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SpotifyAuthError.invalidRedirect
        }

        if components.queryItems?.first(where: { $0.name == "error" })?.value != nil {
            throw SpotifyAuthError.authorizationRejected
        }

        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        guard state == pendingState else {
            throw SpotifyAuthError.stateMismatch
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw SpotifyAuthError.missingAuthorizationCode
        }

        guard let codeVerifier = pendingCodeVerifier else {
            throw SpotifyAuthError.codeVerifierNotFound
        }

        let token = try await exchangeCodeForToken(code: code, codeVerifier: codeVerifier)
        _ = tokenStore.save(token: token)
        pendingCodeVerifier = nil
        pendingState = nil
    }

    func validAccessToken() async throws -> String {
        guard let token = tokenStore.readToken() else {
            throw SpotifyAuthError.notConfigured
        }

        if token.isExpired {
            return try await refreshAccessToken()
        }

        return token.accessToken
    }

    func refreshAccessToken() async throws -> String {
        guard let token = tokenStore.readToken() else {
            throw SpotifyAuthError.notConfigured
        }
        guard !token.refreshToken.isEmpty else {
            throw SpotifyAuthError.missingRefreshToken
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = formEncoded([
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken,
            "client_id": resolvedClientID()
        ])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw SpotifyAuthError.invalidTokenResponse
        }

        let parsed = try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
        let updated = SpotifyToken(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken ?? token.refreshToken,
            tokenType: parsed.tokenType,
            scope: parsed.scope ?? token.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(parsed.expiresIn))
        )
        _ = tokenStore.save(token: updated)
        return updated.accessToken
    }

    func signOut() {
        tokenStore.clear()
    }
}

private extension SpotifyAuthService {
    struct TokenResponse: Decodable {
        let accessToken: String
        let tokenType: String
        let scope: String
        let expiresIn: Int
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    struct RefreshTokenResponse: Decodable {
        let accessToken: String
        let tokenType: String
        let scope: String?
        let expiresIn: Int
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    func exchangeCodeForToken(code: String, codeVerifier: String) async throws -> SpotifyToken {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = formEncoded([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AppConstants.spotifyRedirectURI,
            "client_id": resolvedClientID(),
            "code_verifier": codeVerifier
        ])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw SpotifyAuthError.invalidTokenResponse
        }

        let parsed = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SpotifyToken(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken,
            tokenType: parsed.tokenType,
            scope: parsed.scope,
            expiresAt: Date().addingTimeInterval(TimeInterval(parsed.expiresIn))
        )
    }

    func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    func randomURLSafeString(length: Int = 64) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    func formEncoded(_ payload: [String: String]) -> String {
        payload
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
    }

    func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func resolvedClientID() -> String {
        if !environment.spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environment.spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let bundleValue = bundleClientID()
        if !bundleValue.isEmpty {
            return bundleValue
        }
        let processValue = processClientID()
        if !processValue.isEmpty {
            return processValue
        }
        return AppConstants.spotifyClientIDFallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func bundleClientID() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func processClientID() -> String {
        ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func masked(_ value: String) -> String {
        guard !value.isEmpty else { return "<empty>" }
        if value.count <= 8 { return value }
        return "\(value.prefix(4))...\(value.suffix(4)) (len:\(value.count))"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
