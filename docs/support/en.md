# TwinKeys Remote Support

TwinKeys Remote is a free iPhone and iPad app for sound operators. It controls Live on a main Mac and a backup Mac at the same time, through the free Mac app TwinKeys.

## What you need

- Two Macs (main and backup) with [TwinKeys](https://github.com/kajisho5/ableton-twinkeys/releases/latest) 2.1 or later. TwinKeys is free.
- Ableton Live 11 or Live 12 on both Macs, with TwinKeysBridge chosen as a Control Surface.
- An iPhone or iPad with iOS 17 or later, on the same network as the Macs.

TwinKeys Remote cannot do anything on its own: it needs TwinKeys running on your Macs.

## Getting started

1. On both Macs, open TwinKeys Settings, click **Install into Live** under Live, restart Live and choose **TwinKeysBridge** in a free Control Surface slot.
2. On the main Mac, turn on **Allow TwinKeys Remote to connect**.
3. On the iPhone, type the same pairing code as on the Macs, tap **Save**, allow Local Network access, and tap **Connect** next to the main Mac.
4. Check that the iPhone and the Mac show the same 4 digits, then click **Allow** on the Mac.

All the steps: [Controlling Live from an iPhone or iPad](https://kajisho5.github.io/ableton-twinkeys/guide/#controlling-live-from-an-iphone-or-ipad-twinkeys-remote).

## Common problems

**The Mac does not appear on the iPhone**
- Check that the iPhone and the Mac are on the same network. Public Wi-Fi (venues, hotels) often hides devices from each other: use your own router or a cable.
- On the iPhone, turn on TwinKeys Remote in Settings > Privacy & Security > Local Network.
- On the main Mac, check that **Allow TwinKeys Remote to connect** is on.

**The iPhone says the pairing code does not match the Mac**
- Use the same pairing code as in the Mac's Settings > Pairing Code.

**Nothing happens in Live**
- Check that TwinKeys Settings on the Mac shows **Live: Connected**. If not, choose TwinKeysBridge as a Control Surface in Live.
- While the show lock is on, tempo and the mixer do not move. Hold the lock for 1 second to unlock.

**The top bar shows "Live ✗ no answer" for the backup**
- On the backup Mac, check that Live is open and TwinKeysBridge is chosen.

More answers: [Troubleshooting](https://kajisho5.github.io/ableton-twinkeys/guide/#troubleshooting).

## Contact

Open an issue at [github.com/kajisho5/ableton-twinkeys/issues](https://github.com/kajisho5/ableton-twinkeys/issues) (a free GitHub account is needed). Please include:

- The iPhone or iPad model and its iOS version
- The TwinKeys Remote version, and the TwinKeys version on both Macs
- The Live version
- What you did, what you expected, and what happened

Issues are public: **never post your pairing code**. Answers may take a few days.

## Privacy

TwinKeys Remote collects no data. It talks only to TwinKeys on your own Macs on your local network. See the [privacy policy](https://kajisho5.github.io/ableton-twinkeys/privacy/).

## About

TwinKeys and TwinKeys Remote are made by Shogo Kajiyama / SEVENTHWELL and released under the MIT License. They are unofficial tools, not made, endorsed or supported by Ableton. Ableton and Live are trademarks of Ableton AG.
