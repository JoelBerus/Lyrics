import Foundation

protocol SpotifyPlaybackServiceProtocol {
    func fetchNowPlaying() async throws -> PlaybackState
    func play() async throws
    func pause() async throws
    func skipToNext() async throws
    func skipToPrevious() async throws
    func seek(to positionMS: Int) async throws
    func isTrackSaved(trackID: String) async throws -> Bool
    func saveTrack(trackID: String) async throws
    func removeTrack(trackID: String) async throws
}

enum SpotifyPlaybackError: Error {
    case noActivePlayback
    case invalidResponse
    case commandRejected(statusCode: Int)
    case malformedRequest
}

final class SpotifyPlaybackService: SpotifyPlaybackServiceProtocol {
    private let authService: SpotifyAuthServiceProtocol
    private let session: URLSession

    init(authService: SpotifyAuthServiceProtocol, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func fetchNowPlaying() async throws -> PlaybackState {
        do {
            let accessToken = try await authService.validAccessToken()
            return try await requestNowPlaying(with: accessToken)
        } catch {
            let refreshed = try await authService.refreshAccessToken()
            return try await requestNowPlaying(with: refreshed)
        }
    }

    func play() async throws {
        try await sendPlaybackCommand(path: "/me/player/play", method: "PUT")
    }

    func pause() async throws {
        try await sendPlaybackCommand(path: "/me/player/pause", method: "PUT")
    }

    func skipToNext() async throws {
        try await sendPlaybackCommand(path: "/me/player/next", method: "POST")
    }

    func skipToPrevious() async throws {
        try await sendPlaybackCommand(path: "/me/player/previous", method: "POST")
    }

    func seek(to positionMS: Int) async throws {
        var components = URLComponents(string: "\(AppConstants.spotifyBaseURL)/me/player/seek")
        components?.queryItems = [
            URLQueryItem(name: "position_ms", value: String(max(positionMS, 0)))
        ]
        guard let url = components?.url else {
            throw SpotifyPlaybackError.malformedRequest
        }
        try await sendAuthorizedRequest(
            url: url,
            method: "PUT",
            acceptedStatusCodes: [200, 202, 204]
        )
    }

    func isTrackSaved(trackID: String) async throws -> Bool {
        var components = URLComponents(string: "\(AppConstants.spotifyBaseURL)/me/tracks/contains")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: trackID)
        ]
        guard let url = components?.url else {
            throw SpotifyPlaybackError.malformedRequest
        }

        let data = try await sendAuthorizedRequest(
            url: url,
            method: "GET",
            acceptedStatusCodes: [200]
        )
        let values = try JSONDecoder().decode([Bool].self, from: data)
        return values.first ?? false
    }

    func saveTrack(trackID: String) async throws {
        var components = URLComponents(string: "\(AppConstants.spotifyBaseURL)/me/tracks")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: trackID)
        ]
        guard let url = components?.url else {
            throw SpotifyPlaybackError.malformedRequest
        }
        _ = try await sendAuthorizedRequest(
            url: url,
            method: "PUT",
            acceptedStatusCodes: [200, 201, 202, 204]
        )
    }

    func removeTrack(trackID: String) async throws {
        var components = URLComponents(string: "\(AppConstants.spotifyBaseURL)/me/tracks")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: trackID)
        ]
        guard let url = components?.url else {
            throw SpotifyPlaybackError.malformedRequest
        }
        _ = try await sendAuthorizedRequest(
            url: url,
            method: "DELETE",
            acceptedStatusCodes: [200, 201, 202, 204]
        )
    }

    private func requestNowPlaying(with accessToken: String) async throws -> PlaybackState {
        guard let url = URL(string: "\(AppConstants.spotifyBaseURL)/me/player/currently-playing") else {
            throw SpotifyPlaybackError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyPlaybackError.invalidResponse
        }

        if httpResponse.statusCode == 204 {
            throw SpotifyPlaybackError.noActivePlayback
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw SpotifyPlaybackError.invalidResponse
        }

        let payload = try JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data)
        guard let item = payload.item else {
            throw SpotifyPlaybackError.noActivePlayback
        }

        return PlaybackState(
            isPlaying: payload.isPlaying,
            progressMS: payload.progressMS ?? 0,
            track: Track(
                id: item.id,
                title: item.name,
                artist: item.artists.map(\.name).joined(separator: ", "),
                album: item.album.name,
                artworkURL: URL(string: item.album.images.first?.url ?? ""),
                durationMS: item.durationMS
            )
        )
    }

    private func sendPlaybackCommand(path: String, method: String) async throws {
        guard let url = URL(string: "\(AppConstants.spotifyBaseURL)\(path)") else {
            throw SpotifyPlaybackError.invalidResponse
        }
        _ = try await sendAuthorizedRequest(
            url: url,
            method: method,
            acceptedStatusCodes: [200, 202, 204]
        )
    }

    func sendAuthorizedRequest(
        url: URL,
        method: String,
        acceptedStatusCodes: [Int]
    ) async throws -> Data {
        do {
            let accessToken = try await authService.validAccessToken()
            do {
                return try await performRequest(
                    url: url,
                    method: method,
                    accessToken: accessToken,
                    acceptedStatusCodes: acceptedStatusCodes
                )
            } catch let error as SpotifyPlaybackError {
                if case .commandRejected(let statusCode) = error, statusCode == 401 {
                    let refreshedToken = try await authService.refreshAccessToken()
                    return try await performRequest(
                        url: url,
                        method: method,
                        accessToken: refreshedToken,
                        acceptedStatusCodes: acceptedStatusCodes
                    )
                }
                throw error
            }
        } catch {
            let refreshedToken = try await authService.refreshAccessToken()
            return try await performRequest(
                url: url,
                method: method,
                accessToken: refreshedToken,
                acceptedStatusCodes: acceptedStatusCodes
            )
        }
    }

    func performRequest(
        url: URL,
        method: String,
        accessToken: String,
        acceptedStatusCodes: [Int]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyPlaybackError.invalidResponse
        }

        guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            print("[SpotifyPlaybackService] Command rejected \(method) \(url.absoluteString) status=\(httpResponse.statusCode) body=\(body)")
            #endif
            throw SpotifyPlaybackError.commandRejected(statusCode: httpResponse.statusCode)
        }

        return data
    }
}

private extension SpotifyPlaybackService {
    struct CurrentlyPlayingResponse: Decodable {
        let isPlaying: Bool
        let progressMS: Int?
        let item: Item?

        enum CodingKeys: String, CodingKey {
            case isPlaying = "is_playing"
            case progressMS = "progress_ms"
            case item
        }
    }

    struct Item: Decodable {
        let id: String
        let name: String
        let durationMS: Int
        let artists: [Artist]
        let album: Album

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case durationMS = "duration_ms"
            case artists
            case album
        }
    }

    struct Artist: Decodable {
        let name: String
    }

    struct Album: Decodable {
        let name: String
        let images: [Artwork]
    }

    struct Artwork: Decodable {
        let url: String
    }
}
