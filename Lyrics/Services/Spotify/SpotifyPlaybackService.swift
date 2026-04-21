import Foundation

protocol SpotifyPlaybackServiceProtocol {
    func fetchNowPlaying() async throws -> PlaybackState
}

enum SpotifyPlaybackError: Error {
    case noActivePlayback
    case invalidResponse
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
