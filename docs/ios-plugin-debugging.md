# iOS plugin diagnostics

The iOS toolbar uses a single row of six buttons. On narrow screens, swipe right
within the toolbar to reveal the Plugins button.

## Recommendation and lifecycle hooks

`onRecommendations(ctx)` receives isolated `recommendations` and `context`
snapshots when the application publishes AI recommendations. Registering a plugin
also replays the current snapshot, including an empty recommendation list.
`ctx.context.hand` contains MJAI tile strings including the separately stored
drawn tile; `callTiles` contains the matching call combination, and
`isCallOpportunity` identifies the matching call window. Call context is included
only when its operation sequence matches the recommendation sequence.
An ambiguous pon or kan combination is left unmarked.

`onDisable(ctx)` runs on explicit disable, reload, and automatic removal after
consecutive failures. Plugins should clear any visual state in this hook.
Settings changes remove the previous registration before loading the new source.

Blob WebSocket payloads are copied into bytes for observers and marked
`mutable: false`; these copies cannot rewrite the original WebSocket message.

## Inspecting a page

In Plugins → Log, refresh diagnostics to inspect registered plugins, WebSocket
payload counts, dispatch and parsing counts, the last method and error,
recommendation updates, highlight state, and name-mask calibration.
Re-inject enabled plugins to reload them in the current page.

If highlight targets exist but the tinted draw count does not increase, inspect
`uvSamples` and `tileCandidates/rejectedTiles`. An installed hook alone does not
indicate that a tile draw was matched.
NOTIFY messages such as `.lq.ActionPrototype` have no message ID.

## Running regression checks

With the updated naki-plugins repository checked out alongside Naki:

```sh
node scripts/plugin-regression.cjs ../naki-plugins
```

The suite uses Node VM contexts and simulated WebGL calls.
