# Implementation notes

## Deviations

- **P1 finds the turntable by name on first sight.** P1 picks the device named "USB AUDIO  CODEC" that has input streams, saves its UID, then uses the saved UID only. Reason: no other fact separates it from other USB input devices before its UID is known. P2 (strips for all hardware inputs) removes the name rule.
- **Powering off the turntable does not remove its USB audio device, so "Disconnected" cannot mean power-off.** Core Audio sends no device-list change and the device stays alive, so spec §7.7 and AC1/AC5 "power on/off" cannot show or hide the strip. "Disconnected" now means the USB device is gone (cable unplugged). A powered-off turntable shows "No signal": raw input peak below -75 dBFS for 3 s (measured off about -78 dBFS peak, on with needle up above -72 dBFS). AC1's power-on check becomes "No signal goes away within 2 s"; AC5's power-off check becomes "strip shows No signal", plus a USB-unplug check for "Disconnected".

## Phase checks

### 2026-10-10, P1

Commit: `ddefdb4` (tested build: the same code, before the commit).

Round 1:
- AC8: pass
- AC1: pass (the strip was already present at launch; see round 2)
- AC2: pass
- AC3: pass
- AC5: fail. Turntable power-off did not remove the USB audio device, so the strip did not show "Disconnected".
- AC4: not done

Round 2 (after the "No signal" change, see Deviations):
- AC1: pass ("No signal" goes away within 2 s of power-on; name restored after relaunch)
- AC5: pass (power-off shows "No signal"; USB unplug shows "Disconnected"; level restored after power-on and after replug)
- AC4: pass (30 minutes, no dropouts or clicks)

Result: P1 done.
