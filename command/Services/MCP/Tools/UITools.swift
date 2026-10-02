//
//  UITools.swift
//  Naki
//
//  Created by Claude on 2025/12/05.
//  Updated 2026-07-31：雀魂改用 Unity WebGL，DOM/Laya 探測類工具全數移除。
//
//  移除的工具與理由（實測 `window.Laya` / `GameMgr` / `uiscript` / `view.DesktopMgr`
//  在 Unity 客戶端不存在，見 docs/majsoul-unity-protocol.md）：
//
//  | 舊工具 | 依賴 | 為何移除而不是回失敗 |
//  |--------|------|----------------------|
//  | detect / explore | `__nakiDetectGameAPI` / `__nakiExploreGameObjects`（列舉 Laya 物件）| 沒有替代面可指；要探測就用 `execute_js` |
//  | test_indicators / click / calibrate | 座標點擊 Laya 牌面 | Unity 只有單一 `<canvas>`，沒有 per-tile 元素；動作改走 protobuf |
//  | ui_names_status / hide / show / toggle | `uiscript.UI_DesktopInfo._player_infos` | UI 層搬進 wasm，JS 完全碰不到 |
//
//  判準：**有替代做法可指的才留失敗樁**（例如高亮 → 原生推薦面板），
//  純 Laya 除錯輔助沒有替代面，留著只會在每次 tools/list 佔 token 並誘導 agent 白試。
//  呼叫已移除的工具會得到 `Unknown tool: <name>`（MCPToolRegistry 的既有行為），
//  那本身就是明確的機械失敗。
//

import Foundation
import MCPKit

// MARK: - Execute JS Tool

/// 執行 JavaScript
///
/// Unity 遷移後**唯一保留**的 JS 工具：頁面本身仍是網頁，`window.__nakiWebSocket`
/// 等 Naki 自己注入的模組仍在，所以 ad-hoc 探測仍有意義。
/// 但注意：遊戲狀態與動作**不要**再用它（遊戲物件已不存在），請改用
/// `game_state` / `game_hand` / `game_ops`（Swift 協定層）與 `game_action`（Liqi protobuf）。
struct ExecuteJSTool: MCPTool {
    static let name = "execute_js"
    static let description = """
        在遊戲 WebView 中執行 JavaScript 代碼。⚠️ 必須使用 return 語句才能獲取返回值\
        （例：'return 1+1' → 2）。返回 Object 時使用 JSON.stringify()。\
        ⚠️ Unity 客戶端下 window.Laya / GameMgr / uiscript / view.DesktopMgr 都不存在，\
        讀遊戲狀態請改用 game_state / game_hand / game_ops，執行動作請用 game_action。
        """
    static let inputSchema = MCPInputSchema(
        properties: [
            "code": .string("要執行的 JavaScript 代碼（函數體格式，需要 return 語句才能獲取返回值）"),
            "timeout": .integer("逾時秒數（預設 30，上限 60）；逾時回錯誤，頁面端的 Promise 仍可能在背景執行")
        ],
        required: ["code"]
    )

    private let context: MCPContext

    init(context: MCPContext) {
        self.context = context
    }

    func execute(arguments: [String: Any]) async throws -> Any {
        guard let code = arguments["code"] as? String, !code.isEmpty else {
            throw MCPToolError.missingParameter("code")
        }

        let seconds = min(max(arguments["timeout"] as? Int ?? Self.defaultTimeout, 1), Self.maxTimeout)
        let result = try await Self.race(seconds: seconds) { try await context.executeJavaScript(code) }
        return ["result": JSONSanitizer.sanitize(result ?? NSNull())]
    }

    static let defaultTimeout = 30
    static let maxTimeout = 60

    /// 不用 task group：group 會等所有子任務結束，而永不 resolve 的 Promise 正是要逃掉的情況。
    /// 逾時後 `work` 那個 Task 仍會掛著（`callJavaScript` 不可取消），但呼叫端與連線會結束。
    private static func race(seconds: Int,
                             _ work: @escaping () async throws -> Any?) async throws -> Any? {
        let gate = ResumeOnce()
        let box: Box = try await withCheckedThrowingContinuation { continuation in
            let timer = Task {
                try? await Task.sleep(for: .seconds(seconds))
                gate.resume(continuation, .failure(MCPToolError.executionFailed("execute_js 逾時（\(seconds) 秒）")))
            }
            Task {
                do { gate.resume(continuation, .success(Box(value: try await work()))) }
                catch { gate.resume(continuation, .failure(error)) }
                timer.cancel()
            }
        }
        return box.value
    }

    private struct Box: @unchecked Sendable { let value: Any? }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func resume(_ continuation: CheckedContinuation<Box, Error>, _ result: Result<Box, Error>) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { continuation.resume(with: result) }
        }
    }
}
