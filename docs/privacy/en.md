# Privacy Policy

Last updated: November 14, 2026

This policy covers **TwinKeys Remote** (the iPhone and iPad app) and **TwinKeys** (the Mac and Windows apps), made by Shogo Kajiyama / SEVENTHWELL.

## In short

- TwinKeys Remote **collects no data**. Nothing is sent to us or to anyone else.
- No accounts, no analytics, no advertising, no tracking, no in-app purchases.
- The app talks only to TwinKeys on **your own computers** (Mac or Windows), on your local network. It does not connect to the internet.

## What TwinKeys Remote keeps on your iPhone or iPad

- **Pairing code** — proves to your Mac that you know its pairing code. Stored in the iOS Keychain, on this device only.
- **Device key** (a private key made on the device) — lets your Mac recognize this iPhone after you allowed it once. Stored in the iOS Keychain; it never leaves the device.
- **A random device ID, the name of the Mac used last, and your settings** (for example "Faders stop at 0 dB") — for reconnecting and remembering your choices. Stored in the app's own storage on the device.

## What it sends, and where

- It sends data **only to TwinKeys on your Macs** on the same local network. It finds them with Bonjour and connects with TCP.
- When it connects, it sends the random device ID, the device's name as iOS reports it (usually just "iPhone" or "iPad"), and the public half of the device key. After that it sends your commands (play, stop, clips, faders, cues and so on) and receives the state of Live (tracks, scenes, clip names, tempo and so on).
- The connection is encrypted with Apple CryptoKit (X25519 key agreement, HKDF, ChaCha20-Poly1305). Only a device with the same pairing code, and only one you allowed on the Mac, can connect.
- Your main Mac keeps a list of allowed devices (ID, name, public key, date) so the iPhone can reconnect. You can remove a device there at any time.

**Local Network permission:** iOS asks whether TwinKeys Remote may find devices on your local network. It is used only to find and connect to TwinKeys on your Macs.

## What we can see

Nothing. We do not run any server for these apps and we receive no data from them. If you choose in iOS Settings to share analytics with app developers, Apple may give us anonymous crash reports and usage numbers. You can turn this off in Settings > Privacy & Security > Analytics & Improvements.

## Keeping and deleting data

- Everything stays on your devices until you remove it. We have nothing to delete, because we never receive anything.
- To remove an iPhone from your Mac: on the main Mac, open TwinKeys Settings and click **Remove** next to it under Allowed devices.
- To remove the data on the iPhone: delete the app. iOS may keep Keychain items (the pairing code and the device key) on the device after the app is deleted; they stay on that device and are used again only if you install the app again.

## TwinKeys for Mac

- TwinKeys sends cues and notes only to your other Mac and to TwinKeys Remote on your local network.
- To check for updates, TwinKeys asks GitHub (api.github.com) for the list of releases and downloads new versions from GitHub. GitHub receives your IP address, as with any web request; see the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). You can turn automatic checks off in TwinKeys Settings > Updates.
- Settings and logs stay on your Mac (`~/Library/Application Support/TwinKeys/` and `~/Library/Logs/TwinKeys/`).

## TwinKeys for Windows

- TwinKeys sends cues and notes only to the other computer (Mac or Windows) on the same network and to TwinKeys Remote. On the PC itself, it talks only to Ableton Live (TwinKeysBridge) and to MIDI ports.
- **About the keyboard:** to tell whether a key pressed during a show is a cue key, TwinKeys uses Windows' keyboard hook. It only checks whether the key is a cue key. It never records what you type and never sends it anywhere; the log holds cue key names only.
- The pairing code is encrypted with Windows' DPAPI and kept for this Windows user on this PC only.
- Settings and logs stay on the PC (`%LOCALAPPDATA%\TwinKeys\`; the Microsoft Store version keeps them in the app's own folder).
- TwinKeys does not talk to any server of ours. The Microsoft Store version is updated by the Microsoft Store; for what the Store collects, see the [Microsoft Privacy Statement](https://privacy.microsoft.com/en-us/privacystatement).
- When Windows asks whether to allow network access, it is used only to connect to the other computer and the iPhone on the same network.

## This website

This website is hosted on GitHub Pages. It uses no cookies, no analytics and no advertising. GitHub may log visitors' IP addresses for security; see the GitHub Privacy Statement linked above.

## Children

The apps collect no data from anyone, including children.

## Changes

If this policy changes, the new version will be posted on this page with a new date.

## Contact

Questions about privacy: open an issue at [github.com/kajisho5/ableton-twinkeys/issues](https://github.com/kajisho5/ableton-twinkeys/issues) (a free GitHub account is needed). Issues are public, so never post your pairing code.
