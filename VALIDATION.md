# Party minigame validation

Validated 2026-10-20 UTC with Godot 4.7.2 stable, Linux, OpenGL Compatibility software renderer.

## Passed

- `tests/test_rules.gd`: 10,812 assertions, including 170 complete seeded simulations across 4–8 players. No rule changes in this revision.
- `tests/test_session.gd`: 1,221 checks, 0 failures. Local games, rematch, private snapshots, validation and catalog metadata. No ENet protocol changes.
- `tests/test_ui.gd`: 926 checks, 0 failures in the final run (count varies with random roles). Direct eight-player round start, 4–8 perimeter layouts at 1440×900 and 960×640 window sizes, self-relative seats, stable public hotseat anchor, seat/center separation, no overlapping seats or out-of-bounds buttons, private handoffs, full six-player game, public-note concealment, abstention, replay, exit confirmation/cancel and exit signal.
- `tests/test_layout_controls.gd`: 1,320 checks, 0 failures. Every viewer across 4–8 players and 1440×900 / 960×640, non-contiguous IDs through a bound session, bottom-self including dead self, three top/two per side at eight players, genuine pointer input on card corners/artwork/name/lower edge, selection without submission, dead and self-target exclusion, and private night handoff affordances.
- `tests/test_subtitles.gd`: 46 checks, 0 failures. Deterministic fade-in/hold/fade-out/gap boundaries, same-key updates, final-line hold, cancellation, skip, reduced motion, real dawn victim / peaceful text, actual UI snapshot rerender stability, center label only, public privacy, dock/card non-overlap at 1440×900 and 960×640, maximum-length handoff names, exit confirmation.
- `tests/test_integration.gd`: 15 checks, 0 failures. Pre-ready start and session binding; initial viewer; borrowed-session and transport ownership; invalid-roster preservation; same-session rebind privacy reset; 0–3 player waiting snapshots; one-time completion signal.
- `tests/run_network_smoke.py`: both real multi-process ENet scenarios passed. Four-player full game, private views, sender-spoof resistance, late-join rejection, rematch/disconnect; eight-player admission, ninth-player refusal, invalid/duplicate names, readiness gate and host disconnect. Backend waiting state remains, but there is no lobby UI.
- `tests/capture_screens.gd`: real-renderer PNG captures cover direct round start, private handoff, illustrated seer identity, night actions, dawn, discussion, voting, highlighted vote selection at 1280×800 and 960×640, vote result, endgame, four-player perimeter and 960×640 eight-player viewport. Dawn additionally exports native rendered frames and timing/text/opacity metadata for GIF encoding; capture waits through the final line rather than simulating subtitles.
- Current-revision independent QA: 2,060 checks, 0 failures. Native review inspected final dawn text, the private identity view, and 960×640 vote controls. Thirteen native static PNGs and a GIF encoded from 72 actual viewport frames demonstrate the full three-sentence dawn sequence (not a simulated animation).
- Original moonlit backdrop and all three role illustrations remain unchanged. Alternate geometric art and obsolete menu/lobby capture scripts removed.

## Cinematic presentation

- No top/bottom branding or status HUD. All seats keep a 20-logical-pixel outer safety inset; commands sit beside the self seat. The center contains only one borderless narration label.
- Each sentence fades in for 0.9 seconds, holds 1.8 seconds, fades out for 0.9 seconds, then leaves a 0.35-second gap. The final line stays readable. The clock cannot submit or advance rules.
- The persistent narration node is not destroyed by UI rebuilds. Its key includes match, round, phase, intro and exit state; same-phase refreshes do not restart it. New sequences replace prior state synchronously, so no stale timer or callback remains.
- Space skips to the final line; standard focused-button keyboard activation is retained. Hosts can set `reduced_motion` to suppress opacity motion. Escape opens exit confirmation. Role art and secret notes require an explicit opaque privacy view.

## Integration and verification limits

- Clean entry points and host lifecycle signals are implemented and tested; no integration into an unspecified party framework is claimed.
- `start_game` is hotseat. Its viewer ID is not authentication or a network identity.
- `bind_session` expects this project's already-configured GameSession. External session and peer ownership remain with the host, including on exit/free. Host decides what happens after the exit signal.
- No cross-device/router/firewall test, Windows/macOS executable export, mobile/Web export, WAN matchmaking, reconnect, host migration or chat is claimed.
- Screenshots use the real native renderer, not headless framebuffer output. The software renderer may report unsupported V-Sync; it does not affect gameplay captures.
- Trusted-friends model: the host owns complete identities and ENet is not encrypted. Hotseat privacy requires players to respect screen handoffs.
