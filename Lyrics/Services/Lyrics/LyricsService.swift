import Foundation

protocol LyricsServiceProtocol {
    func fetchLyrics(for track: Track) async throws -> LyricsPayload
}

enum LyricsServiceError: Error {
    case invalidURL
    case invalidResponse
    case noLyricsFound
}

final class LyricsService: LyricsServiceProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(for track: Track) async throws -> LyricsPayload {
        let candidate = try await fetchBestMatch(track: track)

        if let syncedLyrics = candidate.syncedLyrics, !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let syncedLines = parseSyncedLyrics(syncedLyrics)
            if !syncedLines.isEmpty {
                return LyricsPayload(isSynced: true, lines: syncedLines)
            }
        }

        if let plainLyrics = candidate.plainLyrics, !plainLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let plainLines = plainLyrics
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { LyricsLine(timestampMS: nil, text: $0) }
            if !plainLines.isEmpty {
                return LyricsPayload(isSynced: false, lines: plainLines)
            }
        }

        throw LyricsServiceError.noLyricsFound
    }
}

private extension LyricsService {
    struct LRCLIBLyrics: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?

        enum CodingKeys: String, CodingKey {
            case syncedLyrics
            case plainLyrics
        }
    }

    func fetchBestMatch(track: Track) async throws -> LRCLIBLyrics {
        var components = URLComponents(string: "\(AppConstants.lrclibBaseURL)/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(track.durationMS))
        ]
        guard let url = components?.url else {
            throw LyricsServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsServiceError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw LyricsServiceError.noLyricsFound
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw LyricsServiceError.invalidResponse
        }

        return try JSONDecoder().decode(LRCLIBLyrics.self, from: data)
    }

    func parseSyncedLyrics(_ rawLyrics: String) -> [LyricsLine] {
        rawLyrics
            .split(separator: "\n")
            .compactMap { parseSyncedLine(String($0)) }
    }

    func parseSyncedLine(_ line: String) -> LyricsLine? {
        guard let startBracket = line.firstIndex(of: "["),
              let endBracket = line.firstIndex(of: "]"),
              startBracket < endBracket else {
            return nil
        }

        let timestampToken = String(line[line.index(after: startBracket)..<endBracket])
        let lyricText = String(line[line.index(after: endBracket)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lyricText.isEmpty, let timestampMS = milliseconds(from: timestampToken) else {
            return nil
        }

        return LyricsLine(timestampMS: timestampMS, text: lyricText)
    }

    func milliseconds(from token: String) -> Int? {
        let parts = token.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]) else {
            return nil
        }

        let secondsAndFractions = parts[1].split(separator: ".")
        guard let seconds = Int(secondsAndFractions[0]) else {
            return nil
        }

        let milliseconds: Int
        if secondsAndFractions.count > 1 {
            let fraction = String(secondsAndFractions[1])
            let normalized: String
            if fraction.count >= 3 {
                normalized = String(fraction.prefix(3))
            } else if fraction.count == 2 {
                normalized = fraction + "0"
            } else if fraction.count == 1 {
                normalized = fraction + "00"
            } else {
                normalized = "000"
            }
            milliseconds = Int(normalized) ?? 0
        } else {
            milliseconds = 0
        }

        return (minutes * 60 * 1000) + (seconds * 1000) + milliseconds
    }
}
