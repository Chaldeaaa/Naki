//
//  LiqiResponseStoreTests.swift
//  NakiTests
//
//  Naki 自送請求的回應以「配發登記」認領，而不是看 msgId 號段：
//  遊戲自己的 msgId 跑久了也會進入 60000+。
//

import XCTest

@testable import Naki

final class LiqiResponseStoreTests: XCTestCase {

    private func response(_ msgId: Int) -> [String: Any] {
        ["type": "response", "id": msgId, "method": ".lq.Lobby.fetchServerTime", "data": [:] as [String: Any]]
    }

    func testCapturesOnlyIssuedMsgIdsOnce() {
        let allocator = LiqiMsgIdAllocator()
        let store = LiqiResponseStore(allocator: allocator)
        let issued = Int(allocator.next())

        XCTAssertFalse(store.capture(response(issued + 100)), "沒配發過的號段內 msgId 是遊戲自己的")
        XCTAssertTrue(store.capture(response(issued)))
        XCTAssertNotNil(store.response(forMsgId: UInt16(issued)))
        XCTAssertFalse(store.capture(response(issued)), "同一筆只認領一次")
    }

    func testIgnoresLowMsgIds() {
        let allocator = LiqiMsgIdAllocator()
        let store = LiqiResponseStore(allocator: allocator)
        _ = allocator.next()
        XCTAssertFalse(store.capture(response(141)))
        XCTAssertFalse(store.capture(response(70000)), "超出 UInt16 也不能 trap")
    }

    func testRegistryKeepsOnlyRecentIssues() {
        let allocator = LiqiMsgIdAllocator()
        let first = allocator.next()
        for _ in 0..<300 { _ = allocator.next() }
        XCTAssertFalse(allocator.claim(first), "超過登記上限的舊筆被淘汰")
        XCTAssertTrue(allocator.claim(allocator.peek &- 1))
    }

    func testIsIssuedDoesNotConsumeRegistration() {
        let allocator = LiqiMsgIdAllocator()
        let issued = allocator.next()
        XCTAssertTrue(allocator.isIssued(issued))
        XCTAssertTrue(allocator.isIssued(issued), "查詢不消耗登記")
        XCTAssertFalse(allocator.isIssued(issued &+ 1))
        XCTAssertTrue(allocator.claim(issued), "查詢後仍可認領")
        XCTAssertFalse(allocator.isIssued(issued))
    }

    /// 學 match_sid 時判斷「是不是 Naki 送的」：看登記而不是號段，插件區段仍排除
    func testIsNakiSentFollowsRegistryNotMsgIdRange() {
        let issued = LiqiMsgIdAllocator.shared.next()
        defer { _ = LiqiMsgIdAllocator.shared.claim(issued) }
        XCTAssertTrue(LiqiParser.isNakiSent(msgId: Int(issued)))
        XCTAssertFalse(LiqiParser.isNakiSent(msgId: 141), "遊戲自己的低位號")
        XCTAssertFalse(LiqiParser.isNakiSent(msgId: 63000),
                       "遊戲號碼跑進 60000+ 但沒登記過，仍是遊戲自己的")
        XCTAssertTrue(LiqiParser.isNakiSent(msgId: Int(LiqiMsgIdAllocator.pluginRangeStart)))
        XCTAssertFalse(LiqiParser.isNakiSent(msgId: 70000), "超出 UInt16 不能 trap")
    }
}
