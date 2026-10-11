# Turntable Mixer

A Mac app that looks like a DJ mixer. Each sound source gets its own strip: the turntable, the other inputs (for example the built-in microphone), and each app that plays sound. Everything plays through your speakers or headphones. The Master strip at the right controls the Mac's output, the same as System Settings > Sound.

Main use: turn on the turntable, open the app, turn up the turntable's Level knob, hear the record.

The app needs macOS 27. It is for personal use on one Mac.

## Set up once

You need Xcode and an Apple Developer account (the paid "Apple Development" kind). macOS remembers the Microphone and System Audio Recording permissions for one signature only. A free or missing signature can make macOS ask for permission again after every build.

1. Open Xcode once, go to Xcode > Settings > Accounts, and sign in with your Apple Developer account.
2. Find your team ID. It is the 10-character code next to your team in Xcode > Settings > Accounts, or in your account on developer.apple.com.
3. In the project folder, make a text file named `Local.xcconfig` with one line: `DEVELOPMENT_TEAM = ` followed by your team ID. Git ignores this file, so your team ID stays on your Mac.

## Build and open the app

1. Open Terminal in the project folder.
2. Run `scripts/build.sh`. It builds the app, checks its signature, and puts it in the Applications folder in your home folder.
3. Open Turntable Mixer from that folder, or from the Dock after the first time.

Always build with `scripts/build.sh`. A build made another way leaves a second copy of the app on the Mac, and macOS can open that old copy instead.

If the script says "FAIL", read the line after it. A missing `Local.xcconfig` or a missing team is the usual cause.

## Give permissions

macOS asks for two permissions. The app needs both.

- **Microphone**: macOS asks the first time you open the app. Click Allow. Without it, the app cannot hear the turntable or any other input, and it shows an orange note with a button to the right Settings page.
- **System Audio Recording**: macOS asks the first time an app plays sound while the mixer is open. Click Allow. Without it, app strips stay silent, and the mixer shows an orange note with a button to the right Settings page. After you allow it, macOS may offer "Quit & Reopen": click it.

To change a permission later: System Settings > Privacy & Security > Microphone, or > Screen & System Audio Recording.

## Use the mixer

- **Level knob** (the large silver knob): drag up or down, or scroll over it. The bottom is silent. Double-click to go to 0 dB (no change in loudness). New inputs start at the bottom, so the microphone cannot feed back into the speakers.
- **Trim**: a small extra boost or cut for one strip. Double-click to reset it.
- **Device gain**: the Mac's own input level for that device. It also changes the level that other apps record. It is grey when the device has none (the turntable has none).
- **Default**: lights on the input that the Mac uses by default. Click it to make that input the default.
- **Mute**: glows red when on.
- **Clip light**: the small red light in the meter. It comes on when a strip is too loud, then fades out. Turn that strip down.
- **Master strip**: the Output menu picks where all sound plays (the Mac's output). "Sound effects through" picks where alert sounds play. The Balance knob moves the sound left or right (double-click to centre it). The Level knob is the Mac's volume, the same as the volume keys. If the output has no volume of its own (some monitors and TVs), the mixer sets the volume itself and shows "Software".
- **Status line** (bottom of the window): the sample rate, the delay from turntable to speakers, and how hard the mixer works (CPU).

Closing the window keeps the music playing. Click the Dock icon to open the window again. Command-Q quits.

The mixer remembers names, knob positions and mutes for each input and each app.

## Rename the turntable strip

The turntable shows up as "USB AUDIO CODEC". Double-click that name, type "Turntable", and press Return. The new name stays after you quit and reopen the app.

## If you use Loopback

If Loopback also sends the turntable to your speakers, the record plays twice or with an echo. In Loopback, remove the Monitor for the turntable, or quit Loopback while you use the mixer.

## If something sounds wrong

- **App sound is gone after the mixer crashed**: open the mixer once. It cleans up and the app's sound comes back.
- **A strip shows "No signal"**: the mixer gets only silence from that input. Check that the turntable is on, the needle is on the record, and the USB cable is in. If the strip shows "Disconnected", the Mac cannot see the device: plug the USB cable in again.
- **The turntable meter does not move and there is no "No signal" label**: its Level knob is at the bottom, so the mixer has not opened the turntable yet. Turn the knob up.
- **App strips are silent**: check System Audio Recording (see "Give permissions").
