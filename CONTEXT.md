# Turntable Mixer

A mixer window for the Mac's audio sources and Sound settings, styled as a DJ mixer.

## Language

### Sources and strips

**Source**:
Something that produces audio the mixer can carry: an input device or an app.
_Avoid_: input (alone), stream

**Strip**:
The vertical column of controls for one source, or for Sound Effects, or for the master output.
_Avoid_: channel, track, lane

**Input strip**:
A strip for one hardware input device.

**App strip**:
A strip for one running app that produces audio.

**Master strip**:
The strip for the default output device: output menu, master fader, balance, mute, meter.

**Channel**:
One audio channel inside a signal (left, right). Never a strip.

### Devices

**Hardware device**:
An audio device backed by real hardware (built-in, USB, Bluetooth, HDMI). Only hardware input devices get input strips.

**Software device**:
An audio device made by software, such as an audio routing app or a conferencing app driver. The mixer hides it.
_Avoid_: virtual device

**Turntable**:
The Audio-Technica LP120's USB codec, which macOS names "USB AUDIO  CODEC".

### Gain stages

**Device gain**:
The macOS input volume of a device. It changes the level for every app that records from the device.
_Avoid_: input gain

**Trim**:
A mixer-only gain knob on a strip, -24 to +24 dB.

**Fader**:
A mixer-only level slider on a strip, -∞ to +10 dB. On the master strip, the fader is the system output volume.

### Work

**Phase**:
One of the spec's build stages, P1 to P4.

**Acceptance check**:
A check the owner does on the real hardware (spec AC1 to AC12). Agents cannot do it, because they cannot hear audio.
_Avoid_: test (for owner checks)
