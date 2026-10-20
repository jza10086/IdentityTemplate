# Party minigame validation

Validated 2026-10-20 UTC with Godot 4.7.2 stable, Linux, OpenGL Compatibility software renderer.

## Passed

- `tests/test_rules.gd`: 10,812 assertions, including 170 complete seeded simulations across 4–8 players. No rule changes in this revision.
- `tests/test_session.gd`: 1,221 checks, 0 failures. Local games, rematch, private snapshots, validation and catalog metadata. No ENet protocol changes.
- `tests/test_ui.gd`: 786 checks, 0 failures in the final run (count varies with random roles). Direct eight-player round start, 4–8 perimeter layouts at 1440×900 and 960×640 window sizes, seat/center separation, no overlapping seats or out-of-bounds buttons, private handoffs, full six-player game, public-note concealment, abstention, replay, exit confirmation/cancel and exit signal.
- `tests/test_integration.gd`: 15 checks, 0 failures. Pre-ready start and session binding; initial viewer; borrowed-session and transport ownership; invalid-roster preservation; same-session rebind privacy reset; 0–3 player waiting snapshots; one-time completion signal.
- `tests/run_network_smoke.py`: both real multi-process ENet scenarios passed. Four-player full game, private views, sender-spoof resistance, late-join rejection, rematch/disconnect; eight-player admission, ninth-player refusal, invalid/duplicate names, readiness gate and host disconnect. Backend waiting state remains, but there is no lobby UI.
- `tests/capture_screens.gd`: 11 real-renderer PNG captures, covering direct round start, private handoff, illustrated seer identity, night actions, dawn, discussion, voting, vote result, endgame, four-player perimeter and 960×640 eight-player viewport.
- Original moonlit backdrop and all three role illustrations remain unchanged. Alternate geometric art and obsolete menu/lobby capture scripts removed.

## Integration and verification limits

- Clean entry points and host lifecycle signals are implemented and tested; no integration into an unspecified party framework is claimed.
- `start_game` is hotseat. Its viewer ID is not authentication or a network identity.
- `bind_session` expects this project's already-configured GameSession. External session and peer ownership remain with the host, including on exit/free. Host decides what happens after the exit signal.
- No cross-device/router/firewall test, Windows/macOS executable export, mobile/Web export, WAN matchmaking, reconnect, host migration or chat is claimed.
- Screenshots use the real native renderer, not headless framebuffer output. The software renderer may report unsupported V-Sync; it does not affect gameplay captures.
- Trusted-friends model: the host owns complete identities and ENet is not encrypted. Hotseat privacy requires players to respect screen handoffs.
