# Verification report (v1 core)

Date: 2026-11-09. What could be checked without real Macs and Live. Items that need two physical Macs are in [manual-test.md](manual-test.md) and are **not yet done**.

## Environments used

| Where | What |
|---|---|
| Linux (development container), Swift 6.4.2 | `swift test` of the platform-independent core |
| GitHub Actions `macos-26` runner, Xcode 26.6 (macOS 26 SDK) | `swift test`, universal build, bundle check, launch check, memory, screenshots |

CI run with these results: https://github.com/kajisho5/ableton-twinkeys/actions/runs/42554155404

## Results

| Area | How it was checked | Result |
|---|---|---|
| Unit tests (51) | `swift test` on Linux and macOS | **Pass** (0 failures) |
| Key → note mapping (layout, key codes, repeat, chords, modifiers, octave/velocity limits, JSON) | `MappingTests` | Pass |
| Protocol encode/decode, bad packets, duplicate / reordered / wrap-around sequence numbers | `ProtocolTests` | Pass |
| Reconnect state machine (handshake, 1 s heartbeat, 3 s timeout, 1→2→4→5 s retry, bye, manual disconnect) | `LinkTests` | Pass |
| All Notes Off conditions (panic, quit, disconnect, link lost, send/capture off) and 10 s auto note-off | `SafetyTests`, `ConductorTests` | Pass |
| Main flow: key press plays the same note on both Macs (two simulated Macs over a fake network) | `ConductorTests.testKeyPressPlaysSameNoteOnBothMacs` | Pass |
| Network loss: backup ends notes from main, main keeps its own note, both reconnect | `ConductorTests.testNetworkLoss…` | Pass |
| Universal binary | `lipo -info` | Pass: `x86_64 arm64` |
| Info.plist (bundle ID, macOS 13.0, NSLocalNetworkUsageDescription, NSBonjourServices `_twinkeys._udp`) | `plutil -lint`, `plutil -p` | Pass |
| Ad-hoc signature | `codesign --verify` | Pass |
| App icon (.icns 16–512 px + @2x) | Parsed icns: icp4, icp5, ic11, ic12, ic07, ic13, ic08, ic14, ic09, ic10 | Pass |
| App starts and keeps running | Launched on the runner, alive after 5 s; settings.json, mapping.json and the log file were created | Pass |
| Memory while running | `footprint` / `vmmap` (same measure as Activity Monitor "Memory") | **25 MB** (target ≤ 50 MB). RSS incl. shared system pages: 90 MB |
| Start-up time | Not measured precisely in CI | Unknown → manual-test 0-5 |
| Input Monitoring not granted | On the runner the app had no permission and kept running (no crash). Window state shown in `deliverables/screenshots/min-size-*.png` (rendered from the real view) | Pass (no crash); the real System Settings flow → manual-test 1-1, 1-2 |
| Local Network not granted | Cannot be simulated in CI | Not checked → manual-test 1-3, 1-4 |
| No peer found (empty state) | Screenshot `min-size-light.png` / `min-size-dark.png` | Pass (layout) |
| Dark mode | Screenshots `*-dark.png`; all text colors are WCAG AA (design.md 3.5) | Pass |
| Minimum window size 440×330 | Screenshots `min-size-*.png`: status, All Notes Off, Connect/Disconnect visible | Pass |
| Virtual port visible in Audio MIDI Setup / Live 11 / Live 12 | Needs real Mac + Live | Not checked → manual-test 0-2, 0-3 |
| Two-Mac discovery, latency, reconnect over a real network | Needs two Macs | Not checked → manual-test 2, 4 |
| Added latency ≤ 5 ms | Code path: key event → local port and network send happen right away on the key thread (no UI hop). Real measurement needs two Macs | Not checked → manual-test 3-9 |
| VoiceOver | Labels and hints are set in code; not listened to | Not checked → manual-test 6-3 |

## Notes on the screenshots

The screenshots are rendered by the app itself on the macOS runner (`TwinKeys --snapshot <folder>`), using the real SwiftUI view, real AppKit controls and a real window with title bar, filled with fictional sample data. The window is shown inactive (gray window buttons) because the runner has no active user session.

## Not checked / known gaps

- Everything that needs two physical Macs, Live 11 / Live 12, or System Settings dialogs (see manual-test.md).
- The GitHub **Release** workflow has not been run yet (it runs when a `v*` tag is pushed). Its build steps are the same as CI.
- Because the app is signed ad hoc, macOS may ask for Input Monitoring again after each update.
