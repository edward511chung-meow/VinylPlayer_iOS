import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(statusCode: Int)
    case decodingError(Error)
    case rateLimited
    case unauthorized
    case notFound
    case noData
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited — please try again later"
        case .unauthorized:
            return "Unauthorized — check API credentials"
        case .notFound:
            return "Resource not found"
        case .noData:
            return "No data received"
        case .unknown(let message):
            return message
        }
    }
}
