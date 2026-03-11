// NetworkClient.swift – Async HTTP client with retry + rate limiting
// BIST Radar AI

import Foundation

enum HTTPMethod: String {
    case GET, POST, PUT, DELETE
}

struct APIRequest {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?
    let body: Data?
    let headers: [String: String]

    init(
        path: String,
        method: HTTPMethod = .GET,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
        self.headers = headers
    }
}

actor NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession
    private let baseURL: URL
    private let maxRetries = 3
    private let decoder: JSONDecoder

    // Rate limiting: minimum interval between requests (ms)
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 0.1  // 100ms

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)

        // Base URL: replace with actual API endpoint
        // When switching to LiveMarketProvider, set via remote config / plist
        baseURL = URL(string: "https://api.bistapp.example.com/v1")!

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func request<T: Decodable>(_ apiRequest: APIRequest, as type: T.Type) async throws -> T {
        var attempt = 0
        var delay: TimeInterval = 0.5

        while attempt <= maxRetries {
            do {
                let urlRequest = try buildRequest(apiRequest)
                await throttle()
                let (data, response) = try await session.data(for: urlRequest)
                try validate(response: response)
                return try decoder.decode(T.self, from: data)
            } catch ProviderError.rateLimited(let retryAfter) {
                let waitTime = retryAfter ?? delay
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                delay = min(delay * 2, 30)
                attempt += 1
            } catch ProviderError.serverError(let code) where code >= 500 {
                if attempt == maxRetries { throw ProviderError.serverError(code) }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay * 2, 30)
                attempt += 1
            } catch {
                throw error
            }
        }
        throw ProviderError.unknown("Max retries exceeded")
    }

    // MARK: - Private
    private func buildRequest(_ apiRequest: APIRequest) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(apiRequest.path), resolvingAgainstBaseURL: true)
        components?.queryItems = apiRequest.queryItems
        guard let url = components?.url else {
            throw ProviderError.unknown("Invalid URL: \(apiRequest.path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = apiRequest.method.rawValue
        req.httpBody = apiRequest.body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("BISTRadarAI/1.0 iOS", forHTTPHeaderField: "User-Agent")
        apiRequest.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return req
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.unknown("Non-HTTP response")
        }
        switch httpResponse.statusCode {
        case 200..<300: return
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        case 404: throw ProviderError.notFound("Resource")
        case 500...: throw ProviderError.serverError(httpResponse.statusCode)
        default:    throw ProviderError.serverError(httpResponse.statusCode)
        }
    }

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            let wait = minRequestInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
}
