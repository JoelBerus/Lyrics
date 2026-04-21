import Foundation

protocol APIClientProtocol {
    func send<T: Decodable>(_ request: URLRequest) async throws -> T
}

enum APIClientError: Error {
    case invalidResponse
}

struct APIClient: APIClientProtocol {
    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIClientError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
