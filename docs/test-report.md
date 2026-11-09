# Verification report

TwinKeys is an unofficial third-party tool, not affiliated with Ableton.

Covers version 0.5.0 (branch `claude/new-session-k8s13h`). Earlier versions: see git history.

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
| Unit tests (85) | `swift test` on Linux and macOS | **Pass** (0 failures) |
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
| Virtual MIDI source "TwinKeys" exists | CI end-to-end check (`scripts/e2e-midi.swift`): lists CoreMIDI sources while TwinKeys runs | **Pass**: sources = ["TwinKeys"] |
| Receiving side end to end: Bonjour discovery → hello/ack → note-on/off over UDP → same notes out of the TwinKeys MIDI source | Same script acts as a second Mac on the macOS runner | **Pass**: received [0x90 60 100], [0x80 60 0]. Runs the plain executable, because macOS blocks Bonjour for the .app until someone answers the Local Network prompt (no user on CI) |
| Port visible in Audio MIDI Setup / Live 11 / Live 12 | Needs real Mac + Live | Not checked → manual-test 0-2, 0-3 |
| Two-Mac discovery, latency, reconnect over a real network | Needs two Macs | Not checked → manual-test 2, 4 |
| Added latency ≤ 5 ms | Code path: key event → local port and network send happen right away on the key thread (no UI hop). Real measurement needs two Macs | Not checked → manual-test 3-9 |
| Network edge cases (hellos from unknown Macs, route takeover, lost note-off repaired by the held list, peer switching, previous-session packets) | `ConductorTests`, `LinkTests`, `ProtocolTests` | Pass |
| Pairing code and encryption (0.5.0): PBKDF2 against RFC 7914 test vectors, signed hellos, ChaCha20-Poly1305 traffic, wrong code / no code cannot link, tampered and replayed packets dropped, connect by address learns the real peer | `PairingTests`, `ConductorTests` | Pass |
| End to end with encryption: a fake second Mac with the same code links over Bonjour and its encrypted notes come out of the TwinKeys MIDI source; listener on UDP 47801 | CI `scripts/e2e-midi.swift` | Pass |
| Japanese UI | Screenshots `*-ja.png` rendered by the app on macOS (window, all sections, empty state, permission banner) | Pass (layout and wording). Live switching in Settings → manual-test 6-6 |
| Author credit | About panel credits text and copyright set in code / Info.plist / LICENSE; panel itself not viewed | Not viewed → manual-test 6-7 |
| VoiceOver | Labels and hints are set in code; not listened to | Not checked → manual-test 6-3 |

## Notes on the screenshots

The screenshots are rendered by the app itself on the macOS runner (`TwinKeys --snapshot <folder>`), using the real SwiftUI view, real AppKit controls and a real window with title bar, filled with fictional sample data. The window is shown inactive (gray window buttons) because the runner has no active user session.

## Not checked / known gaps

- Everything that needs two physical Macs, Live 11 / Live 12, or System Settings dialogs (see manual-test.md).
- Releases run when the VERSION file changes (also on `v*` tags or by hand). From 0.4.0 the release is signed with a Developer ID and notarized through kajisho5/runway, and the .dmg is opened and checked on a clean macOS runner before publishing (Gatekeeper, signature, version, launch).
- A multi-angle review (logic, threading, network, UI/accessibility/Japanese, security/release/docs) was done for 0.4.0; its fixes are covered by the unit tests above and by manual-test section 7.
