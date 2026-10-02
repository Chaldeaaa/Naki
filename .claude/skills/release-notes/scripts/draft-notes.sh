#!/usr/bin/env bash
# 用法：draft-notes.sh <prev-tag> [<ref>]   產 release notes 草稿到 stdout
# ref 預設 HEAD；ref 不是 tag 時，完整變更連結的版本號留 TODO，lint 會擋。
set -euo pipefail

PREV="${1:?用法: draft-notes.sh <prev-tag> [<ref>]}"
REF="${2:-HEAD}"
REPO=Sunalamye/Naki

git rev-parse -q --verify "${PREV}^{commit}" >/dev/null || { echo "找不到 ${PREV}" >&2; exit 1; }
git rev-parse -q --verify "${REF}^{commit}" >/dev/null || { echo "找不到 ${REF}" >&2; exit 1; }

feat=() fix=() beh=() skip=()
while IFS=$'\t' read -r hash subject; do
  line="TODO ${subject#*: }（${hash}）"
  case "$subject" in
    feat*)                        feat+=("$line") ;;
    fix*)                         fix+=("$line") ;;
    refactor*|perf*|revert*|style*) beh+=("內部：$line") ;;
    *)                            skip+=("${hash} ${subject}") ;;
  esac
done < <(git log --reverse --format='%h%x09%s' "${PREV}..${REF}")

emit() { local title=$1; shift; [ $# -gt 0 ] || return 0; echo "### ${title}"; printf -- '- %s\n' "$@"; }

echo "## 摘要"
echo "TODO 一句話：這版為什麼存在／對使用者最大的影響"
echo
echo "## 變更"
emit 新功能 ${feat[@]+"${feat[@]}"}
emit 修正 ${fix[@]+"${fix[@]}"}
emit 行為變更 ${beh[@]+"${beh[@]}"}
echo
echo "## 已知限制"
echo "- TODO 來自 implementation notes 的「未驗證」與「已知風險」；沒有就整節刪掉"
echo
echo "## 下載"
echo "| 平台 | 檔案 | 說明 |"
echo "|---|---|---|"
echo "| macOS 26+ | \`Naki.dmg\` | 安裝映像檔，拖進 Applications |"
echo "| macOS 26+ | \`Naki.zip\` | 應用程式壓縮檔 |"
echo "| iOS 17+ | \`Naki-M.ipa\` | 未簽名，用 AltStore／Sideloadly 自行簽名側載 |"
echo
echo "## 完整變更"
if git rev-parse -q --verify "refs/tags/${REF}" >/dev/null; then ver="$REF"; else ver="vTODO"; fi
echo "https://github.com/${REPO}/compare/${PREV}...${ver}"

if [ ${#skip[@]} -gt 0 ]; then
  echo "未歸類的 commit（docs／chore／test 等，通常不收，確認後再決定）：" >&2
  printf '  %s\n' "${skip[@]}" >&2
fi
