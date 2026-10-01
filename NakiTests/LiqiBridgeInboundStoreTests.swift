//
//  LiqiBridgeInboundStoreTests.swift
//  NakiTests
//
//  進站資料的數值轉換不得 trap：`Int(Double)`、`UInt32(Int)` 對超界值都是 crash，
//  而這些值來自對方送來的 bytes。
//

import XCTest

@testable import Naki

final class LiqiBridgeInboundStoreTests: XCTestCase {

    // MARK: - LiqiResponseStore.emojiId

    func testEmojiIdRejectsOutOfRangeAndFractionalDoubles() {
        XCTAssertNil(LiqiResponseStore.emojiId(from: #"{"emo":1e30}"#), "超界不得 trap")
        XCTAssertNil(LiqiResponseStore.emojiId(from: #"{"emo":1.5}"#), "非整數不取整")
        XCTAssertEqual(LiqiResponseStore.emojiId(from: #"{"emo":3}"#), 3)
    }

    // MARK: - LiqiOperationStore.record(fromParsed:)

    func testOversizedOperationTypeIsDropped() {
        let store = LiqiOperationStore()
        let snapshot = store.record(fromParsed: [
            "seat": 0,
            "operationList": [
                ["type": Int(UInt32.max) + 1],
                ["type": -1],
                ["type": 9, "combination": [String]()]
            ]
        ])

        XCTAssertEqual(snapshot?.operations.map(\.rawType), [9], "type 超界的那筆丟棄，其餘照留")
    }

    func testOversizedTimesFallBackToZero() {
        let store = LiqiOperationStore()
        let snapshot = store.record(fromParsed: [
            "seat": 0,
            "operationList": [["type": 9]],
            "timeAdd": Int.max,
            "timeFixed": -5
        ])

        XCTAssertEqual(snapshot?.timeAdd, 0)
        XCTAssertEqual(snapshot?.timeFixed, 0)
    }

    func testAllOperationsOutOfRangeYieldsNoSnapshot() {
        let store = LiqiOperationStore()
        XCTAssertNil(store.record(fromParsed: [
            "operationList": [["type": Int(UInt32.max) + 1]]
        ]))
    }
}
