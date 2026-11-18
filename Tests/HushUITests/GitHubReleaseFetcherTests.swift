import Foundation
import HushCore
import Testing
@testable import HushUI

@Suite struct GitHubReleaseFetcherTests {
    private let endpoint = URL(string: "https://api.github.com/repos/aydenjahola/Hush/releases/latest")!

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    @Test func requestIsAnAnonymousGETToTheLatestRelease() {
        let request = GitHubReleaseFetcher(appVersion: "0.1.0").makeRequest()
        #expect(request.url == endpoint)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Hush/0.1.0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.httpShouldHandleCookies == false)
        #expect(Set(request.allHTTPHeaderFields?.keys.map { $0.lowercased() } ?? []) ==
                ["user-agent", "accept", "x-github-api-version"])
    }

    @Test func sessionKeepsNoCookiesOrCache() {
        let configuration = GitHubReleaseFetcher.makeSession().configuration
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
    }

    @Test func okResponseDecodesTheRelease() throws {
        let json = #"{"tag_name": "v0.2.0", "html_url": "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0", "draft": false, "prerelease": false, "assets": []}"#
        let release = try GitHubReleaseFetcher.release(from: Data(json.utf8), response: response(200))
        #expect(release?.tagName == "v0.2.0")
    }

    @Test func notFoundMeansNoReleaseYet() throws {
        #expect(try GitHubReleaseFetcher.release(from: Data(#"{"message": "Not Found"}"#.utf8), response: response(404)) == nil)
    }

    @Test func rateLimitAndServerErrorsThrow() {
        #expect(throws: GitHubReleaseFetcher.FetchError.status(403)) {
            try GitHubReleaseFetcher.release(from: Data(#"{"message": "API rate limit exceeded"}"#.utf8), response: response(403))
        }
        #expect(throws: GitHubReleaseFetcher.FetchError.status(503)) {
            try GitHubReleaseFetcher.release(from: Data(), response: response(503))
        }
    }

    @Test func badJSONThrows() {
        #expect(throws: (any Error).self) {
            try GitHubReleaseFetcher.release(from: Data("<html>oops</html>".utf8), response: response(200))
        }
    }

    @Test func nonHTTPResponseThrows() {
        let plain = URLResponse(url: endpoint, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(throws: GitHubReleaseFetcher.FetchError.notHTTP) {
            try GitHubReleaseFetcher.release(from: Data(), response: plain)
        }
    }
}
