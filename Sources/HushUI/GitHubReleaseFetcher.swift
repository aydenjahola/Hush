import Foundation
import HushCore

/// Asks GitHub's public API for Hush's latest release: one anonymous GET, with no cookies,
/// cache, credentials or identifying data beyond the "Hush/<version>" user agent GitHub requires.
public struct GitHubReleaseFetcher: ReleaseFetching {
    public static let endpoint = URL(string: "https://api.github.com/repos/aydenjahola/Hush/releases/latest")!

    public enum FetchError: Error, Equatable {
        case notHTTP
        /// Anything but 200 or 404, e.g. 403 when rate-limited.
        case status(Int)
    }

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

    func makeRequest() -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    public func latestRelease() async throws -> GitHubRelease? {
        let (data, response) = try await session.data(for: makeRequest())
        return try Self.release(from: data, response: response)
    }

    /// 200 → the release; 404 → nil (no release published yet); anything else throws.
    static func release(from data: Data, response: URLResponse) throws -> GitHubRelease? {
        guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }
        switch http.statusCode {
        case 200: return try GitHubRelease.decode(from: data)
        case 404: return nil
        default: throw FetchError.status(http.statusCode)
        }
    }
}
