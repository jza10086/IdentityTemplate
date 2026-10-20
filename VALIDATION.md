# Validation report

Validated 2026-10-19 UTC with Godot 4.7.2 stable, Linux, OpenGL Compatibility renderer (Mesa llvmpipe).

## Passed

- Editor import and project script compilation: no errors.
- `test_rules.gd`: 10,812 assertions, including 170 full seeded simulations across 4–8 players. Covers private view isolation, malformed/duplicate/dead actions, role presets, 4-player first-night peace, voting tie/abstention, wolf tie break, victories, rematch reset, and nonsequential network ID seat labels.
- `test_session.gd`: 1,221 checks. Local complete games, rematch, independent viewer snapshots, invalid names/counts/ports, clean leave, game catalog factory and supported game metadata.
- `test_ui.gd`: 82 checks on the final run. Real Godot Control trees, navigation, duplicate-name validation, privacy before role reveal and each action, full local game, public-note concealment, abstain selection, rematch, leave confirmation, cancel and cleanup. The total varies with randomly assigned roles and survival count.
- `run_network_smoke.py`: real independent-process ENet connections. Four players complete a game; sender authorization, private views, late join rejection, rematch and client disconnect verified. Separate eight-player scenario verifies capacity, ninth-player refusal, duplicate/invalid names, readiness/minimum player gates and host disconnect.
- `capture_screens.gd`: 11 actual in-engine screenshots at 1280×800. Home, eight-player local setup, privacy handoff, seer card, night action, dawn, discussion, vote, ending, network setup and rules.
- `capture_lan.gd`: actual host plus seven independent clients; all eight connected and ready, rendered LAN lobby captured.
- Visually inspected home, local setup, seer card, night target selection, public discussion, network setup and eight-player LAN lobby. No debug UI appears in the game viewport.

## Verification boundaries

- No cross-device/router/firewall LAN test was possible; real ENet loopback processes passed.
- No Windows/macOS executable export, mobile/Web export, WAN matchmaking, audio/chat, reconnect or host migration is claimed.
- Native renderer emits one environment-only V-Sync unsupported warning under software rendering; no script/runtime errors were present in screenshot runs.
- This is a trusted-friends LAN prototype, not an encrypted or adversarially audited service. The host owns complete role data.

## Geometric theatre addition · 2026-10-20 UTC

- Original SVG art remains byte-for-byte unchanged; first launch still uses the moonlit theme.
- Original UI flow: 82 checks passed. Geometric UI flow: 82 checks passed, including complete private hot-seat play, voting, rematch and leave/cancel.
- `test_geometry.gd`: 21 checks passed for the 960×640 window, both themes, five navigation pages, same-session switching, unchanged game snapshot, hidden role handoff, day/night text palettes, readable daylight error color, and saved visual preference with test cleanup.
- Final geometric screenshots were rendered at 1280×800 through the actual Godot 4.7.2 OpenGL Compatibility renderer (Mesa llvmpipe), not mocked HTML or a screenshot reconstruction. All 11 capture stages succeeded. Home, day discussion, night selection, and privacy handoff were visually reviewed; all inspected controls and text fit.
- Core rules/session/network code was not modified. The existing rules, session and independent-process ENet suites were rerun successfully for this addition.
- The existing software-renderer V-Sync warning remains environment-only. Screenshot capture produced no script errors.
