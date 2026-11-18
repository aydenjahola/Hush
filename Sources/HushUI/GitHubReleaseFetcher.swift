import Foundation
import HushCore

/// Asks GitHub's public API for Hush's latest release: one anonymous GET with only generic headers
/// (a "Hush/<version>" user agent, which GitHub requires, Accept, Accept-Language: en, the API
/// version and, after the first response, If-None-Match). No cookies, cache or credentials.
nonisolated public struct GitHubReleaseFetcher: ReleaseFetching {
    public static let endpoint = URL(string: "https://api.github.com/repos/aydenjahola/Hush/releases/latest")!

    private static let maximumRetryAfter: TimeInterval = 24 * 60 * 60

    private let session: URLSession
    private let userAgent: String

    public init(appVersion: String, session: URLSession = GitHubReleaseFetcher.makeSession()) {
        self.session = session
        self.userAgent = "Hush/\(appVersion)"
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    func makeRequest(ifNoneMatch etag: String?) -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return request
    }

    @concurrent public func latestRelease(ifNoneMatch etag: String?) async throws -> ReleaseFetchResult {
        let (data, response) = try await session.data(for: makeRequest(ifNoneMatch: etag))
        return try Self.result(from: data, response: response, now: Date())
    }

    /// 200 → the release and its ETag; 304 → not modified; 404 → no release yet; 429, or 403 with a
    /// Retry-After or exhausted rate limit → rate limited; anything else throws its status.
    static func result(from data: Data, response: URLResponse, now: Date) throws -> ReleaseFetchResult {
        guard let http = response as? HTTPURLResponse else { throw ReleaseFetchError.notHTTP }
        switch http.statusCode {
        case 200:
            return .release(try GitHubRelease.decode(from: data), etag: http.value(forHTTPHeaderField: "ETag"))
        case 304:
            return .notModified
        case 404:
            return .release(nil, etag: nil)
        case 403, 429:
            let delay = retryDelay(http, now: now)
            if http.statusCode == 429 || delay != nil { throw ReleaseFetchError.rateLimited(retryAfter: delay) }
            throw ReleaseFetchError.status(403)
        default:
            throw ReleaseFetchError.status(http.statusCode)
        }
    }

    /// Seconds from Retry-After, or until x-ratelimit-reset when the limit is used up; 0...24 h.
    private static func retryDelay(_ http: HTTPURLResponse, now: Date) -> TimeInterval? {
        let delay: TimeInterval
        if let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
            delay = retryAfter
        } else if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
                  let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) {
            delay = reset - now.timeIntervalSince1970
        } else {
            return nil
        }
        return min(max(delay, 0), maximumRetryAfter)
    }
}
