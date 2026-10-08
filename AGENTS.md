# Turntable Mixer

A native macOS app (Swift + SwiftUI) that looks like a DJ mixer: one strip per audio source, mixed to the default output. Personal use: one owner, one Mac.

## Sources of truth

- **Spec**: `docs/spec.md`. Where a resolved ticket differs from the spec, the ticket wins.
- **Map**: [Map: Turntable Mixer v1](https://github.com/qaid/apv-mixer/issues/1) indexes decisions; its sub-issues are the tickets. Read the map before you choose work.
- **Glossary**: `CONTEXT.md`. Use its terms in code, UI copy and tickets.
- **Deviations**: log every departure from the spec, with its reason, under "Deviations" in `implementation-notes.md`.

## Agent skills

### Issue tracker

GitHub Issues on `qaid/apv-mixer`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `CONTEXT.md` at the repo root; ADRs go in `docs/adr/` when one is needed.

## Hardware gate

Agents cannot hear audio. A phase (P1 to P4) is done only when the owner passes its acceptance checks on the real turntable. At the end of each phase, run the `phase-check` skill and stop until the owner reports results.

## Audio thread

Code on the audio thread (IOProc, render callbacks) is real-time: it reads parameters from atomics, writes meter peaks to atomics, and does nothing else. It allocates no memory, takes no locks, logs nothing, does no file I/O and touches no Swift or Objective-C objects. After any change to audio-thread code, run the `audio-thread-reviewer` agent on the diff.

## Core Audio names

Process tap APIs are new and thinly documented (spec R5). Check every Core Audio symbol against the SDK headers before you use it: `$(xcrun --show-sdk-path)/System/Library/Frameworks/CoreAudio.framework/Headers/`.

## README audience

The README is for a non-engineer. Write setup steps (signing, permissions, running from Xcode) in plain language.
