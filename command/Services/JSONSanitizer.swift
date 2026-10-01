//
//  JSONSanitizer.swift
//  Naki
//
//  JSON 序列化前的清理（NaN／Infinity／非 JSON 型別）——單一來源
//

import Foundation

/// `JSONSerialization` 碰到 NaN／Infinity 或非 JSON 型別（`Date` 等）會丟 ObjC 例外，
/// Swift 的 `try` 攔不到，整個 App 直接 abort。推薦機率、期望值這類 Double 有機會算出
/// NaN，`/js` 也可能回 `new Date()`，所以送出前一律先過這裡：NaN／Inf 換成 `null`，
/// `Date` 換成 ISO8601 字串，其餘非 JSON 型別換成 `String(describing:)`。
///
/// 先前 `DebugServer` 與 `MCPHandler` 各有一份逐字相同的 `private func sanitizeForJSON`：
/// 兩處都在同一條 HTTP 回應鏈上，改一邊另一邊不會跟著動。收斂成這一份。
enum JSONSanitizer {

    /// 遞迴清理任意 JSON 值
    nonisolated static func sanitize(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues { sanitize($0) }
        case let array as [Any]:
            return array.map { sanitize($0) }
        case let d as Double where d.isNaN || d.isInfinite:
            return NSNull()
        case let f as Float where f.isNaN || f.isInfinite:
            return NSNull()
        case let n as NSNumber:
            let d = n.doubleValue
            if d.isNaN || d.isInfinite {
                return NSNull()
            }
            return n
        case is String, is NSNull:
            return value
        case let date as Date:
            return isoFormatter.string(from: date)
        default:
            return String(describing: value)
        }
    }

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 清理後序列化。連 `isValidJSONObject` 都不過（例如非 String 的 dictionary key）
    /// 就 throw，讓呼叫端走 500，而不是讓 `JSONSerialization` 丟例外。
    nonisolated static func data(_ dict: [String: Any],
                                 options: JSONSerialization.WritingOptions = []) throws -> Data {
        let clean = sanitize(dict)
        guard JSONSerialization.isValidJSONObject(clean) else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        return try JSONSerialization.data(withJSONObject: clean, options: options)
    }

    /// dictionary 版本。
    ///
    /// 呼叫端原本寫 `sanitizeForJSON(data) as! [String: Any]`——`sanitize` 對 dictionary
    /// 一定回 dictionary，所以那個 `as!` 只是把型別資訊丟掉再強轉回來。這裡直接保型別。
    nonisolated static func sanitize(_ dict: [String: Any]) -> [String: Any] {
        dict.mapValues { sanitize($0) }
    }
}
