#!/usr/bin/env python3
"""檢查 release notes 是否符合 release-notes skill 的模板。有問題非零退出。"""
import os
import re
import subprocess
import sys

SECTIONS = ["摘要", "變更", "已知限制", "下載", "完整變更"]
OPTIONAL = {"已知限制"}
SUBS = ["新功能", "修正", "行為變更"]
TABLE_HEAD = ["| 平台 | 檔案 | 說明 |", "|---|---|---|"]
COMPARE = re.compile(r"^https://github\.com/Sunalamye/Naki/(compare/v\d+\.\d+\.\d+\.\.\.v\d+\.\d+\.\d+|commits/v\d+\.\d+\.\d+)$")
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍]")
LEFTOVER = re.compile(r"TODO|TBD|待補|XXX|<!--")


def check_adjacent(link):
    m = re.search(r"compare/(v[\d.]+)\.\.\.(v[\d.]+)$", link)
    if not m:
        return []
    try:
        tags = subprocess.check_output(
            ["git", "-C", os.path.dirname(os.path.abspath(__file__)), "tag", "--sort=v:refname"],
            text=True, stderr=subprocess.DEVNULL).split()
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("警告：無法讀取 git tag，略過 compare 相鄰檢查", file=sys.stderr)
        return []
    prev, cur = m.groups()
    if prev not in tags or cur not in tags:
        return [f"compare 連結的 tag 不存在：{prev} 或 {cur}"]
    if tags.index(cur) - tags.index(prev) != 1:
        return [f"compare 前一個 tag 應為 {tags[tags.index(cur) - 1]}，實際 {prev}"]
    return []


def lint(text):
    errs = []
    lines = text.splitlines()
    for n, l in enumerate(lines, 1):
        if EMOJI.search(l):
            errs.append(f"L{n}: 含 emoji 或圖示符號")
        if LEFTOVER.search(l):
            errs.append(f"L{n}: 殘留 TODO／註解標記")
        if l.startswith("# "):
            errs.append(f"L{n}: 不要有一級標題")

    secs, cur = {}, None
    order = []
    for l in lines:
        if l.startswith("## "):
            cur = l[3:].strip()
            order.append(cur)
            secs[cur] = []
        elif cur is not None:
            secs[cur].append(l)
        elif l.strip():
            errs.append("第一個 `## ` 標題之前不能有內容")
    expect = [s for s in SECTIONS if s in secs or s not in OPTIONAL]
    if order != expect:
        errs.append(f"二級標題應依序為 {expect}，實際 {order}")
    body = {k: [x for x in v if x.strip()] for k, v in secs.items()}

    if "摘要" in body and len(body["摘要"]) != 1:
        errs.append("摘要必須剛好一行")

    if "變更" in body:
        subs, cur = [], None
        for l in body["變更"]:
            if l.startswith("### "):
                cur = l[4:].strip()
                subs.append(cur)
                if cur not in SUBS:
                    errs.append(f"變更小節只能是 {SUBS}，出現 {cur!r}")
            elif not l.startswith("- ") or cur is None:
                errs.append(f"變更內容必須是單行條目，出現 {l[:30]!r}")
        if not subs:
            errs.append("變更至少要有一個小節")
        if [s for s in SUBS if s in subs] != subs:
            errs.append(f"變更小節順序應為 {SUBS}，實際 {subs}")
        for s in subs:
            i = body["變更"].index(f"### {s}")
            nxt = body["變更"][i + 1] if i + 1 < len(body["變更"]) else ""
            if not nxt.startswith("- "):
                errs.append(f"小節 {s} 沒有條目")

    if "已知限制" in body:
        if not body["已知限制"]:
            errs.append("已知限制不得為空，沒有內容就整節刪掉")
        for l in body["已知限制"]:
            if not l.startswith("- "):
                errs.append(f"已知限制必須是單行條目，出現 {l[:30]!r}")

    if "下載" in body:
        d = body["下載"]
        if d[:2] != TABLE_HEAD:
            errs.append(f"下載表頭應為 {TABLE_HEAD}")
        rows = d[2:]
        if not rows:
            errs.append("下載表沒有資料列")
        for r in rows:
            if not r.startswith("|") or r.count("|") != 4:
                errs.append(f"下載表資料列必須 3 欄：{r[:40]!r}")

    if "完整變更" in body:
        c = body["完整變更"]
        if len(c) != 1 or not COMPARE.match(c[0]):
            errs.append("完整變更必須是單行 compare（或 v1.0.0 的 commits）連結")
        else:
            errs += check_adjacent(c[0])
    return errs


def main():
    bad = 0
    for p in sys.argv[1:] or ["-"]:
        text = sys.stdin.read() if p == "-" else open(p, encoding="utf-8").read()
        errs = lint(text)
        for e in errs:
            print(f"{p}: {e}")
        bad += bool(errs)
    sys.exit(1 if bad else 0)


main()
