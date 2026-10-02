//
//  LiqiEnvelopeTests.swift
//  NakiTests
//
//  p4-2 回歸鎖：envelope 的「解」與「編」是同一份定義的兩個方向。
//
//  收斂之前這份知識有兩份 Swift 實作（`LiqiParser.parse` 拆、`LiqiEncoder.encodeEnvelope` 組）
//  加一份 JS（`naki-websocket.js`）。兩份 Swift 實作實際上已經漂了一項：
//  encoder 連 NOTIFY 都寫 2 bytes msgId，而 parser 讀 NOTIFY 是從 offset 1 開始，
//  也就是自己編出來的 notify 自己解不開。本檔用 round-trip 把這件事鎖住。
//

import XCTest

@testable import Naki

final class LiqiEnvelopeTests: XCTestCase {

    // MARK: - Ground truth

    /// 實測封包：`.lq.Route.heartbeat`，msgId = 141
    private let heartbeatRequestHex =
        "028d000a132e6c712e526f7574652e686561727462656174120808001000180b200f"

    private func bytes(fromHex hex: String) -> Data {
        var out = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return Data(out)
    }

    // MARK: - 解實測封包

    func testDecodesCapturedHeartbeatRequest() {
        guard case let .success(envelope) = LiqiEnvelope.decode(bytes(fromHex: heartbeatRequestHex)) else {
            return XCTFail("實測封包必須解得開")
        }

        XCTAssertEqual(envelope.type, .request)
        XCTAssertEqual(envelope.msgId, 141)
        XCTAssertEqual(envelope.method, ".lq.Route.heartbeat")
        XCTAssertEqual(LiqiEncoder.hexString([UInt8](envelope.payload)), "08001000180b200f")
    }

    // MARK: - Round-trip（解 ↔ 編）

    /// REQUEST：編出來的 bytes 必須與實測封包逐位元組相同，且解回來一樣
    func testRequestRoundTripsByteForByte() {
        let original = bytes(fromHex: heartbeatRequestHex)
        guard case let .success(envelope) = LiqiEnvelope.decode(original) else {
            return XCTFail("解不開")
        }

        XCTAssertEqual(Data(envelope.encoded), original)
    }

    /// NOTIFY **沒有 msgId**：編出 1 byte 標頭，而且自己解得回來。
    ///
    /// 舊的 `encodeEnvelope` 無條件寫 3 bytes 標頭，產生的 notify 餵回 parser 會
    /// 把 msgId 的兩個 byte 當成 protobuf tag——解出來的東西與真訊息無法區分。
    func testNotifyHasNoMsgIdAndRoundTrips() {
        let payload: [UInt8] = [0x08, 0x07]
        let bytes = LiqiEncoder.encodeEnvelope(type: .notify,
                                               msgId: 141,
                                               method: ".lq.ActionPrototype",
                                               payload: payload)

        XCTAssertEqual(bytes[0], LiqiMsgType.notify.rawValue)
        XCTAssertEqual(bytes[1], 0x0a, "notify 的第二個 byte 就是 protobuf tag（field 1），不是 msgId")

        guard case let .success(envelope) = LiqiEnvelope.decode(Data(bytes)) else {
            return XCTFail("自己編的 notify 自己要解得開")
        }
        XCTAssertEqual(envelope.type, .notify)
        XCTAssertNil(envelope.msgId, "NOTIFY 沒有 msgId")
        XCTAssertEqual(envelope.method, ".lq.ActionPrototype")
        XCTAssertEqual([UInt8](envelope.payload), payload)
    }

    /// RESPONSE 的 envelope 不帶方法名（要靠 msgId 對照）
    func testResponseCarriesNoMethodName() {
        let bytes = LiqiEncoder.encodeEnvelope(type: .response, msgId: 141, method: "", payload: [])

        XCTAssertEqual(LiqiEncoder.hexString(bytes), "038d000a001200")

        guard case let .success(envelope) = LiqiEnvelope.decode(Data(bytes)) else {
            return XCTFail("解不開")
        }
        XCTAssertEqual(envelope.type, .response)
        XCTAssertEqual(envelope.msgId, 141)
        XCTAssertNil(envelope.method)
        XCTAssertTrue(envelope.payload.isEmpty)
    }

    /// msgId 是 little-endian，而且整個 UInt16 範圍都要對得回來
    func testMsgIdIsLittleEndianAcrossRange() {
        for msgId: UInt16 in [0, 1, 141, 255, 256, 60000, 65500, 65535] {
            let bytes = LiqiEncoder.encodeEnvelope(type: .request, msgId: msgId,
                                                   method: ".lq.Lobby.fetchServerTime", payload: [])
            XCTAssertEqual(bytes[1], UInt8(msgId & 0x00FF))
            XCTAssertEqual(bytes[2], UInt8((msgId >> 8) & 0x00FF))

            guard case let .success(envelope) = LiqiEnvelope.decode(Data(bytes)) else {
                return XCTFail("msgId \(msgId) 解不開")
            }
            XCTAssertEqual(envelope.msgId, msgId)
        }
    }

    // MARK: - 失敗要帶得出上下文

    func testTooShortFrameReportsByteCount() {
        guard case let .failure(failure) = LiqiEnvelope.decode(Data([0x02, 0x00])) else {
            return XCTFail("2 bytes 不可能是合法 envelope")
        }
        XCTAssertTrue("\(failure)".contains("2 bytes"), "失敗訊息要帶得出長度：\(failure)")
    }

    func testUnknownTypeIsReportedWithRawValue() {
        guard case let .failure(failure) = LiqiEnvelope.decode(Data([0x09, 0x00, 0x00, 0x00])) else {
            return XCTFail("type 9 不是 1/2/3")
        }
        XCTAssertTrue("\(failure)".contains("9"), "失敗訊息要帶得出 type：\(failure)")
    }

    /// REQUEST 少了 method block → 顯式失敗（不得回半個信封）
    func testRequestWithoutMethodBlockFails() {
        var frame: [UInt8] = [LiqiMsgType.request.rawValue, 0x01, 0x00]
        frame += LiqiEncoder.encodeLengthDelimited(field: 2, bytes: [0x08, 0x01])

        guard case let .failure(failure) = LiqiEnvelope.decode(Data(frame)) else {
            return XCTFail("沒有 method 不算完整 wrapper")
        }
        XCTAssertTrue("\(failure)".contains("block"), "\(failure)")
    }

    /// NOTIFY／REQUEST 的 payload 缺席（重新序列化的封包省略預設值欄位）視為空 payload，
    /// 與 RESPONSE 一致，不得因為「只有一個 block」而失敗。
    func testNotifyAndRequestWithoutPayloadDecodeAsEmpty() {
        let notify = [LiqiMsgType.notify.rawValue] + LiqiEncoder.encodeStringField(field: 1, value: ".lq.NotifyX")
        guard case let .success(envelope) = LiqiEnvelope.decode(Data(notify)) else {
            return XCTFail("只有 field 1 的 NOTIFY 必須解得開")
        }
        XCTAssertEqual(envelope.method, ".lq.NotifyX")
        XCTAssertTrue(envelope.payload.isEmpty)

        let request = [LiqiMsgType.request.rawValue, 0x01, 0x00]
            + LiqiEncoder.encodeStringField(field: 1, value: ".lq.Lobby.fetchRoom")
        guard case let .success(requestEnvelope) = LiqiEnvelope.decode(Data(request)) else {
            return XCTFail("只有 field 1 的 REQUEST 必須解得開")
        }
        XCTAssertTrue(requestEnvelope.payload.isEmpty)
    }

    /// payload 按欄位號取：field 2 在前、field 1 在後也解得對
    func testNotifyFieldsAreReadByFieldNumberNotPosition() {
        let payload: [UInt8] = [0x08, 0x05]
        let frame = [LiqiMsgType.notify.rawValue]
            + LiqiEncoder.encodeLengthDelimited(field: 2, bytes: payload)
            + LiqiEncoder.encodeStringField(field: 1, value: ".lq.NotifyX")

        guard case let .success(envelope) = LiqiEnvelope.decode(Data(frame)) else {
            return XCTFail("欄位順序顛倒仍是合法 protobuf")
        }
        XCTAssertEqual(envelope.method, ".lq.NotifyX")
        XCTAssertEqual([UInt8](envelope.payload), payload)
    }

    // MARK: - varint 只有一份實作

    /// `LiqiWire` 的解與編互為反向；`parseVarint` 只是它的舊名薄殼。
    func testVarintDecodeAndEncodeAreInverses() {
        for value in [0, 1, 127, 128, 300, 16383, 16384, 2_097_152, 1_000_000_007] {
            let encoded = LiqiWire.encodeVarint(UInt64(value))
            XCTAssertEqual(LiqiWire.decodeVarint(Data(encoded), offset: 0)?.value, value)
            XCTAssertEqual(parseVarint(Data(encoded), offset: 0)?.value, value,
                           "parseVarint 必須與 LiqiWire.decodeVarint 是同一份實作")
        }
    }

    /// 從中間 offset 起解（`LiqiResponseRecord.errorCode` 就是這樣用的）
    func testVarintDecodeFromOffset() {
        // `08 96 01` = field 1 varint 150
        let data = Data([0x08, 0x96, 0x01])

        XCTAssertEqual(LiqiWire.decodeVarint(data, offset: 1)?.value, 150)
        XCTAssertEqual(LiqiWire.decodeVarint(data, offset: 1)?.newOffset, 3)
    }

    // MARK: - 溢位

    /// **絕不回傳負數。**
    ///
    /// 舊版的溢位保護寫在 `shift += 7` 之後、而且是 `> 63`：第 9 個 byte 把 shift
    /// 推到 63，`63 > 63` 為 false 於是放行；第 10 個 byte 的 `<< 63` 正好打在 `Int`
    /// 的符號位上，那個 byte 的最高位是 0 時就直接把負數回傳出去。
    ///
    /// 下游沒有一處預期負值——`BAKAZE_NAMES[chang % 4]` 對負 `chang` 會取到負索引，
    /// 而 Swift 的陣列越界是 trap，接不住，整個 App 當場結束。
    func testTenByteVarintIsRejectedInsteadOfOverflowingToNegative() {
        // 9 個帶續位元的 byte 把 shift 推到 63，第 10 個 byte（0x01，最高位 0）
        // 在舊實作裡會讓 `1 << 63` 設定符號位。
        let overflowing = Data([0x83, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01])

        let decoded = LiqiWire.decodeVarint(overflowing, offset: 0)

        XCTAssertNil(decoded, "超過 63 bit 的 varint 必須被拒絕，不能解成負數")
        if let value = decoded?.value {
            XCTAssertGreaterThanOrEqual(value, 0, "無論如何都不得回傳負值（實際 \(value)）")
        }
    }

    /// 只有續位元、永遠不結束的 varint 也要收斂成 nil（而不是把 shift 一直加下去）。
    func testUnterminatedVarintIsRejected() {
        let unterminated = Data(repeating: 0xFF, count: 12)

        XCTAssertNil(LiqiWire.decodeVarint(unterminated, offset: 0))
    }

    /// 邊界的另一側：9 bytes 之內的大值仍然要正常解出來，
    /// 修溢位不能把合法輸入一起擋掉。
    func testLargeButValidVarintStillDecodes() {
        for value in [Int(Int32.max), 1 << 40, (1 << 62) - 1] {
            let encoded = LiqiWire.encodeVarint(UInt64(value))
            XCTAssertLessThanOrEqual(encoded.count, 9, "測資本身必須在 9 bytes 內")
            XCTAssertEqual(LiqiWire.decodeVarint(Data(encoded), offset: 0)?.value, value)
        }
    }

    // MARK: - 有號 varint（int32／int64 負數）

    /// 2026-09 live：`ActionHule.delta_scores` 的 packed bytes，負分是 10 bytes 二補數
    func testSignedVarintDecodesLiveDeltaScores() {
        let live = bytes(fromHex: "00ecc3ffffffffffffff0100943c")

        var values: [Int] = []
        var offset = 0
        while offset < live.count {
            guard let (value, next) = LiqiWire.decodeSignedVarint(live, offset: offset) else {
                return XCTFail("live bytes 必須解得完")
            }
            values.append(value)
            offset = next
        }
        XCTAssertEqual(values, [0, -7700, 0, 7700])
    }

    func testSignedVarintRoundTripsAndMatchesUnsignedForNonNegative() {
        for value in [0, 1, 300, 25000, -1, -7700, Int(Int32.min), Int(Int32.max)] {
            let encoded = LiqiEncoder.encodeVarint(UInt64(bitPattern: Int64(value)))
            XCTAssertEqual(LiqiWire.decodeSignedVarint(Data(encoded), offset: 0)?.value, value)
        }
        for value in [0, 127, 128, 300, 1 << 40] {
            let data = Data(LiqiWire.encodeVarint(UInt64(value)))
            XCTAssertEqual(LiqiWire.decodeSignedVarint(data, offset: 0)?.value,
                           LiqiWire.decodeVarint(data, offset: 0)?.value)
        }
    }

    /// 第 10 個 byte 大於 1 超過 64 bits，是畸形；無號版本仍一律拒絕負數
    func testSignedVarintRejectsMalformedTenthByte() {
        let tooBig = Data([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x02])
        XCTAssertNil(LiqiWire.decodeSignedVarint(tooBig, offset: 0))
        XCTAssertNil(LiqiWire.decodeSignedVarint(Data(repeating: 0xFF, count: 12), offset: 0))
        XCTAssertNil(LiqiWire.decodeSignedVarint(Data([0xFF, 0xFF]), offset: 0), "沒有結尾")

        let negative = Data(LiqiEncoder.encodeVarint(UInt64(bitPattern: -1)))
        XCTAssertNil(LiqiWire.decodeVarint(negative, offset: 0), "無號版本的非負契約不得破壞")
    }

    /// 切 block 要跳得過 10-byte varint：負數欄位之後的欄位不得丟失
    func testNegativeVarintFieldDoesNotDropFollowingFields() {
        let data = Data(LiqiEncoder.encodeFields([
            .int(field: 1, value: -7700),
            .string(field: 2, value: "after"),
            .varint(field: 3, value: 9)
        ]))

        let blocks = parseProtobufBlocks(data)

        XCTAssertEqual(blocks.map(\.fieldId), [1, 2, 3])
        XCTAssertEqual(blocks[1].stringValue, "after")
    }
}
