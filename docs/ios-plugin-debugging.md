# iOS plugin debugging — 2026-09-28

Base: `fix/plugin-highlight-timing` at `affe8e5d9c4e699b0649f4c128c7619a11f1c4bf`.
The Blob dispatch fix is already on main at `202f973728bd5e477618f5f4e39a238abb8ccbd4`.
The observed `gist .lq.ActionPrototype msgId=null` confirms the observer chain;
NOTIFY messages have no message ID.

## Changes in this batch

- Fix missing Swift interpolation in the recommendation injection script. The
  previous branch emitted `(json)` as literal JavaScript and silently swallowed
  the resulting error. Sync failures now appear in the plugin log.
- Publish hand and call context alongside recommendations. Call context is only
  provided when its oplist sequence matches the recommendation sequence. Chi uses
  the protocol combination index; ambiguous multi-combination kan/pon is left
  unmarked instead of choosing an arbitrary combination.
- `onRecommendations(ctx)` gets isolated `recommendations` and `context` snapshots.
  `context.hand` and `context.callTiles` contain MJAI strings;
  `context.isCallOpportunity` identifies the matching call window.
- `onDisable(ctx)` runs on explicit disable, reload, and automatic failure removal.
  Setting changes first remove the old registration before registering new source.
- Log tab: refresh diagnostics and re-inject enabled plugins in the current page.
  Counters are per page, split by send/receive message type. Runtime diagnostics
  show dispatch/parse/hook counts, last method/error, recommendation updates,
  registered IDs, top recommendation, highlight state and name-mask calibration.
- Renderer: WebGL1 context fallback, invalid atlas offset rejection, bounded UV
  samples, and uniform restoration when a tinted draw throws. Name calibration
  cancels on disable and retries after canvas resizing; fixes one extra probe.
- Highlighter v1.2.0 is maintained in `Chaldeaaa/naki-plugins`; the copy in this
  branch is synchronized. It uses the actual top action, native green/dimming,
  riichi's accompanying discard, and orange call tiles. Empty/pass/win clears
  marks. Legacy runtimes retain packet-triggered fallback with its timing limits.
- Name hider v1.1.0 respects renderer retry cooldown and clears on disable.

## Validation

From this repository:

```text
node scripts/plugin-regression.cjs ../naki-plugins-master
```

Without a second checkout the same suite uses this branch's highlighter copy:

```text
node scripts/plugin-regression.cjs
```

From the plugin repository:

```text
node --test tests/name-hider.cjs
```

These are Node VM/GL-stub regression tests, not WebKit rendering evidence.
Swift/Xcode compilation and device verification have not been performed on the
Windows editing host. No IPA workflow or merge is part of this batch.

## Next device check (one combined build when ready)

1. Enable the updated highlighter and enter a game in recommendation mode.
2. In Plugins → Log, refresh diagnostics and capture the result during a decision.
3. Confirm actual registration, receive Blob counts, parsed methods, recommendation
   hook counts, and target tiles. Refresh a second time to see whether `tinted`
   increases. `installed=true` alone does not prove any draw was matched.
4. If targets exist but tinted stays zero, capture `uvSamples` and
   `tileCandidates/rejectedTiles`; do not relax atlas checks without device evidence.
5. Check auto mode delay, off mode, red fives, riichi, a call and pass, then toggle
   the plugin and change its color without reloading the game.
6. Check name-mask calibration, turn it off before calibration finishes, and rotate
   the device. Pixel-based identification remains unverified on iOS.

Popup tinting stays **off by default**. Its old unseen-draw heuristic can mistake
effects or overlays for call buttons. The `experimentalPopup` setting is explicit
opt-in; tile coloring and call-tile hints do not require it.
