//
//  UpdateCheckerTests.swift
//  NakiTests
//

import XCTest
@testable import Naki

/// 腳本化 `/releases/latest` 回應並捕獲 request。
private final class ReleaseMockURLProtocol: URLProtocol {

    nonisolated(unsafe) static var response: (status: Int, body: String) = (200, "")
    nonisolated(unsafe) static var captured: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.captured = request
        let http = HTTPURLResponse(url: request.url!, statusCode: Self.response.status,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class UpdateCheckerTests: XCTestCase {

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func release(tag: String = "v2.14.0", draft: Bool = false, prerelease: Bool = false) -> String {
        #"{"tag_name":"\#(tag)","html_url":"https://github.com/Sunalamye/Naki/releases/tag/\#(tag)","draft":\#(draft),"prerelease":\#(prerelease)}"#
    }

    // MARK: 純函式

    func test_normalize_stripsVPrefix() {
        XCTAssertEqual(UpdateChecker.normalize(tag: "v2.14.0"), "2.14.0")
        XCTAssertEqual(UpdateChecker.normalize(tag: "V2.14.0"), "2.14.0")
        XCTAssertEqual(UpdateChecker.normalize(tag: "2.14.0"), "2.14.0")
    }

    func test_isNewer_comparesNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("2.14.0", than: "2.13.0"))
        XCTAssertFalse(UpdateChecker.isNewer("2.9.0", than: "2.13.0"), "字串比會判反")
        XCTAssertFalse(UpdateChecker.isNewer("2.13.0", than: "2.13.0"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0", than: "2.13.0"))
    }

    func test_shouldAutoCheck_throttlesAndHonorsToggle() {
        let now = Date()
        XCTAssertTrue(UpdateChecker.shouldAutoCheck(enabled: true, last: nil, now: now))
        XCTAssertFalse(UpdateChecker.shouldAutoCheck(enabled: false, last: nil, now: now))
        XCTAssertFalse(UpdateChecker.shouldAutoCheck(enabled: true, last: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateChecker.shouldAutoCheck(enabled: true, last: now.addingTimeInterval(-24 * 3600), now: now))
    }

    func test_shouldSurface_skipAppliesOnlyToAutoCheck() throws {
        let info = ReleaseInfo(version: "2.14.0", url: try XCTUnwrap(URL(string: "https://example.com")))
        XCTAssertTrue(UpdateChecker.shouldSurface(info, local: "2.13.0", skipped: nil, manual: false))
        XCTAssertFalse(UpdateChecker.shouldSurface(info, local: "2.13.0", skipped: "2.14.0", manual: false))
        XCTAssertTrue(UpdateChecker.shouldSurface(info, local: "2.13.0", skipped: "2.14.0", manual: true))
        XCTAssertTrue(UpdateChecker.shouldSurface(info, local: "2.13.0", skipped: "2.13.5", manual: false),
                      "略過舊版不影響更新的版本")
        XCTAssertFalse(UpdateChecker.shouldSurface(info, local: "2.14.0", skipped: nil, manual: true))
    }

    // MARK: fetchLatest

    func test_fetchLatest_parsesRelease_andSendsNoCredentials() async throws {
        ReleaseMockURLProtocol.response = (200, release())
        let info = try await UpdateChecker.fetchLatest(session: session())
        XCTAssertEqual(info?.version, "2.14.0")
        XCTAssertEqual(info?.url.absoluteString, "https://github.com/Sunalamye/Naki/releases/tag/v2.14.0")

        let request = try XCTUnwrap(ReleaseMockURLProtocol.captured)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url, UpdateChecker.latestReleaseURL)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func test_fetchLatest_ignoresPrereleaseAndDraft() async throws {
        ReleaseMockURLProtocol.response = (200, release(prerelease: true))
        let prerelease = try await UpdateChecker.fetchLatest(session: session())
        XCTAssertNil(prerelease)
        ReleaseMockURLProtocol.response = (200, release(draft: true))
        let draft = try await UpdateChecker.fetchLatest(session: session())
        XCTAssertNil(draft)
    }

    func test_fetchLatest_throwsOnNon200() async {
        ReleaseMockURLProtocol.response = (404, #"{"message":"Not Found"}"#)
        do {
            _ = try await UpdateChecker.fetchLatest(session: session())
            XCTFail("404 應該丟錯")
        } catch {}
    }

    func test_fetchLatest_throwsOnMalformedJSON() async {
        ReleaseMockURLProtocol.response = (200, "not json")
        do {
            _ = try await UpdateChecker.fetchLatest(session: session())
            XCTFail("壞 JSON 應該丟錯")
        } catch {}
    }
}
