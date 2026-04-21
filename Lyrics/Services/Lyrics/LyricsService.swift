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
        let trackName: String?
        let artistName: String?
        let syncedLyrics: String?
        let plainLyrics: String?

        enum CodingKeys: String, CodingKey {
            case trackName
            case trackNameSnake = "track_name"
            case artistName
            case artistNameSnake = "artist_name"
            case syncedLyrics
            case plainLyrics
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            trackName = try container.decodeIfPresent(String.self, forKey: .trackName) ??
                container.decodeIfPresent(String.self, forKey: .trackNameSnake)
            artistName = try container.decodeIfPresent(String.self, forKey: .artistName) ??
                container.decodeIfPresent(String.self, forKey: .artistNameSnake)
            syncedLyrics = try container.decodeIfPresent(String.self, forKey: .syncedLyrics)
            plainLyrics = try container.decodeIfPresent(String.self, forKey: .plainLyrics)
        }
    }

    func fetchBestMatch(track: Track) async throws -> LRCLIBLyrics {
        do {
            return try await fetchBestMatch(track: track, artistName: track.artist)
        } catch LyricsServiceError.noLyricsFound {
            let primaryArtist = primaryArtist(from: track.artist)
            if primaryArtist != track.artist {
                return try await fetchBestMatch(track: track, artistName: primaryArtist)
            }
            throw LyricsServiceError.noLyricsFound
        }
    }

    func fetchBestMatch(track: Track, artistName: String) async throws -> LRCLIBLyrics {
        do {
            return try await fetchStrictMatch(track: track, artistName: artistName)
        } catch LyricsServiceError.noLyricsFound {
            return try await searchBestCandidate(track: track, artistName: artistName)
        }
    }

    func fetchStrictMatch(track: Track, artistName: String) async throws -> LRCLIBLyrics {
        var components = URLComponents(string: "\(AppConstants.lrclibBaseURL)/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: artistName),
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

    func searchBestCandidate(track: Track, artistName: String) async throws -> LRCLIBLyrics {
        var components = URLComponents(string: "\(AppConstants.lrclibBaseURL)/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: artistName)
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

        guard 200..<300 ~= httpResponse.statusCode else {
            throw LyricsServiceError.noLyricsFound
        }

        let candidates = try JSONDecoder().decode([LRCLIBLyrics].self, from: data)
        guard let candidate = bestCandidate(from: candidates, track: track, artistName: artistName) else {
            throw LyricsServiceError.noLyricsFound
        }
        return candidate
    }

    func bestCandidate(from candidates: [LRCLIBLyrics], track: Track, artistName: String) -> LRCLIBLyrics? {
        let normalizedTrack = normalize(track.title)
        let normalizedArtist = normalize(artistName)

        return candidates
            .filter { candidate in
                let hasLyrics = !(candidate.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
                    !(candidate.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                return hasLyrics
            }
            .sorted { lhs, rhs in
                score(lhs, track: normalizedTrack, artist: normalizedArtist) >
                    score(rhs, track: normalizedTrack, artist: normalizedArtist)
            }
            .first
    }

    func score(_ candidate: LRCLIBLyrics, track: String, artist: String) -> Int {
        let candidateTrack = normalize(candidate.trackName ?? "")
        let candidateArtist = normalize(candidate.artistName ?? "")
        var score = 0

        if candidateTrack == track { score += 6 }
        else if candidateTrack.contains(track) || track.contains(candidateTrack) { score += 3 }

        if candidateArtist == artist { score += 6 }
        else if candidateArtist.contains(artist) || artist.contains(candidateArtist) { score += 3 }

        if !(candidate.syncedLyrics?.isEmpty ?? true) { score += 2 }
        if !(candidate.plainLyrics?.isEmpty ?? true) { score += 1 }

        return score
    }

    func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func primaryArtist(from artists: String) -> String {
        let separators = [",", "&", " feat.", " feat ", " ft.", " ft "]
        var candidate = artists
        for separator in separators {
            if let range = candidate.range(of: separator, options: .caseInsensitive) {
                candidate = String(candidate[..<range.lowerBound])
                break
            }
        }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
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
