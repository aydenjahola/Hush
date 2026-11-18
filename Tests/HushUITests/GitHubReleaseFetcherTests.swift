import Foundation
import HushCore
import Testing
@testable import HushUI

@Suite(.timeLimit(.minutes(1))) struct GitHubReleaseFetcherTests {
    private let endpoint = URL(string: "https://api.github.com/repos/aydenjahola/Hush/releases/latest")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let releaseJSON = Data(#"{"tag_name": "v0.2.0", "html_url": "https://github.com/aydenjahola/Hush/releases/tag/v0.2.0", "draft": false, "prerelease": false, "assets": []}"#.utf8)

    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func result(_ status: Int, _ data: Data = Data(), headers: [String: String] = [:]) throws -> ReleaseFetchResult {
        try GitHubReleaseFetcher.result(from: data, response: response(status, headers: headers), now: now)
    }

    @Test func requestIsAnAnonymousGETWithOnlyGenericHeaders() {
        let request = GitHubReleaseFetcher(appVersion: "0.1.0").makeRequest(ifNoneMatch: nil)
        #expect(request.url == endpoint)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Hush/0.1.0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.httpShouldHandleCookies == false)
        #expect(Set(request.allHTTPHeaderFields?.keys.map { $0.lowercased() } ?? []) ==
                ["user-agent", "accept", "accept-language", "x-github-api-version"])
    }

    @Test func requestSendsTheLastETag() {
        let request = GitHubReleaseFetcher(appVersion: "0.1.0").makeRequest(ifNoneMatch: #"W/"abc""#)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == #"W/"abc""#)
    }

    @Test func sessionKeepsNoCookiesOrCache() {
        let configuration = GitHubReleaseFetcher.makeSession().configuration
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
    }

    @Test func okResponseDecodesTheReleaseAndItsETag() throws {
        let fetched = try result(200, releaseJSON, headers: ["ETag": #"W/"abc""#])
        guard case .release(let release, let etag) = fetched else { Issue.record("\(fetched)"); return }
        #expect(release?.tagName == "v0.2.0")
        #expect(etag == #"W/"abc""#)
    }

    @Test func notModifiedIsItsOwnResult() throws {
        #expect(try result(304) == .notModified)
    }

    @Test func notFoundMeansNoReleaseYet() throws {
        #expect(try result(404, Data(#"{"message": "Not Found"}"#.utf8)) == .release(nil, etag: nil))
    }

    @Test func retryAfterIsHonored() {
        #expect(throws: ReleaseFetchError.rateLimited(retryAfter: 120)) {
            try result(429, headers: ["Retry-After": "120"])
        }
        #expect(throws: ReleaseFetchError.rateLimited(retryAfter: 120)) {
            try result(403, headers: ["Retry-After": "120"])
        }
    }

    @Test func rateLimitResetIsHonored() {
        #expect(throws: ReleaseFetchError.rateLimited(retryAfter: 300)) {
            try result(403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(Int(now.timeIntervalSince1970) + 300)"])
        }
    }

    @Test func serverRequestedDelaysAreCappedAtADay() {
        #expect(throws: ReleaseFetchError.rateLimited(retryAfter: 86_400)) {
            try result(429, headers: ["Retry-After": "999999"])
        }
        #expect(throws: ReleaseFetchError.rateLimited(retryAfter: 0)) {
            try result(403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(Int(now.timeIntervalSince1970) - 50)"])
        }
    }

    @Test(arguments: ["nan", "inf", "-inf", "NaN", "soon"])
    func nonFiniteRetryAfterIsIgnored(value: String) {
        #expect(throws: ReleaseFetchError.rateLimited(retryAfter: nil)) {
            try result(429, headers: ["Retry-After": value])
        }
        #expect(throws: ReleaseFetchError.rateLimited(retryAfter: nil)) {
            try result(429, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": value])
        }
    }

    @Test func rateLimitWithoutHintsHasNoDelay() {
        #expect(throws: ReleaseFetchError.rateLimited(retryAfter: nil)) { try result(429) }
    }

    @Test func otherErrorsThrowTheirStatus() {
        #expect(throws: ReleaseFetchError.status(403)) { try result(403, Data(#"{"message": "Forbidden"}"#.utf8)) }
        #expect(throws: ReleaseFetchError.status(503)) { try result(503) }
    }

    @Test func badJSONThrows() {
        #expect(throws: (any Error).self) { try result(200, Data("<html>oops</html>".utf8)) }
    }

    @Test func nonHTTPResponseThrows() {
        let plain = URLResponse(url: endpoint, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(throws: ReleaseFetchError.notHTTP) {
            try GitHubReleaseFetcher.result(from: Data(), response: plain, now: now)
        }
    }
}
