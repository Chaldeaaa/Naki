---
name: release-notes
description: 寫 Naki GitHub release notes／整理變更紀錄時使用。給定上一個 tag 產草稿、照統一模板整理、用 lint 驗格式，再交給 release-manager 的 --notes-file。
allowed-tools: Read, Glob, Grep, Write, Bash
---

# Release Notes

Naki 每個 release 的說明都照同一個模板，使用者在任何一版都能在同樣的位置找到「差別、限制、檔案」。
與 `release-manager` 搭配：本 skill 負責**寫**，release-manager 負責**發**。

## 流程

```bash
S=.claude/skills/release-notes/scripts
bash $S/draft-notes.sh <prev-tag> [<ref>] > notes.md   # 依 commit 前綴初分的骨架，含 TODO
# 人工整理：摘要、改寫每一條、補已知限制、核對下載表
python3 $S/lint-notes.py notes.md                      # 非零退出就改到過
bash .claude/skills/release-manager/scripts/release.sh <version> --yes --notes-file notes.md
```

草稿只是 commit 標題的分類，**不是成品**；每條都要改寫成使用者看得到的影響，並刪掉所有 `TODO`（lint 會擋）。
事實來源只有三個：commit（`git log <prev>..<ref>`）、該版的 implementation notes、實際的 release 資產。

## 模板（標題文字固定）

```
## 摘要
<一句話>

## 變更
### 新功能
- …
### 修正
- …
### 行為變更
- …

## 已知限制
- …

## 下載
| 平台 | 檔案 | 說明 |
|---|---|---|
| macOS 26+ | `Naki.dmg` | 安裝映像檔，拖進 Applications |
| macOS 26+ | `Naki.zip` | 應用程式壓縮檔 |
| iOS 17+ | `Naki-M.ipa` | 未簽名，用 AltStore／Sideloadly 自行簽名側載 |

## 完整變更
https://github.com/Sunalamye/Naki/compare/<prev-tag>...<tag>
```

三個變更小節有內容才出現，順序固定；`已知限制` 沒有就整節省略；其餘二級標題一定要有。

## 各節怎麼寫

**摘要**：一句話回答「這版為什麼存在、對使用者最大的影響」。判準：只看這一句的人能決定要不要升級。不是 commit 標題、不是版本號宣告。

**分類**
- 新功能：使用者能做到以前做不到的事（含新增的設定、MCP 工具、腳本）。
- 修正：以前壞掉、現在正常。寫**症狀**（「一碰畫面就崩潰」），不寫 commit 標題（「移除隱式動畫」）。
- 行為變更：同一件事現在做法或預設不同，使用者可能注意到；例如延遲數值、預設值、面板順序、需求門檻、功能移交他處。
  純內部重構沒有使用者可見差別的，以「內部：」開頭，一版最多一兩行。
- docs／chore／test／CI 的 commit 預設不收，除非改變使用者可見的需求或操作。

**已知限制**：來自該版 implementation notes 的「未驗證」與「已知風險」段，加上下載相關的事實（未簽名、首次開啟要放行、IPA 無實機回饋）。寫出來比事後收 issue 便宜。注意：只寫確實未驗證／確實有風險的，不要為了顯得誠實而湊數。

**下載**：用 `gh release view <tag> --json assets -q '.assets[].name'` 查實際資產，表格只列真的存在的檔案；檔名照實際名稱。最低版本照該版文件寫的（目前 macOS 26+、iOS 17+），查不到就只寫「macOS」「iOS」，不要猜。

**完整變更**：compare 連結，`<prev-tag>` 用 `git tag --sort=v:refname` 的前一個；第一版沒有 prev，用 `commits/v1.0.0`。

## 用語

- 雀魂術語照遊戲：副露、立直、和牌（榮和／自摸）、振聽、赤五、本場、供託、莊家、三麻／四麻；「跳過」指放棄副露（程式稱 pass）。
- UI 用詞與 App 及 README 一致：側欄、工具列、插件、信任分頁、進階設定、隱藏玩家名稱。
- 使用者會直接輸入或看到的名稱（端點、腳本、MCP 工具、設定項、錯誤碼）保留原文並加反引號。
- 專有名詞（Mortal、Core ML、MortalSwift、MCP、Akagi）保留英文。
- 全繁體中文，句子精簡，每條變更**一行**。

## 禁止事項

- 不寫內部檔名、類別名、函式名；描述它的職責或效果。
- 不寫內部 agent、審查輪次、測試數量等開發流程（例如「三輪獨立復驗」「494 tests 通過」）。
- 不捏造：原文、commit、implementation notes 都沒有的內容不寫；沒驗證的標「未驗證」，不寫成「已確認」。
- 不放 emoji 或圖示符號。
- 不重複展開完整 changelog，給連結即可。
- 不寫 Co-Authored-By／「Generated with」之類署名行。

## 與 release-manager 的分工

release-manager 的「release notes 是寫出來的」段說明為什麼不能機械倒 `git log`；本 skill 規定寫成什麼樣，模板以本檔為準。
