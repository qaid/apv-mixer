---
name: phase-check
description: Hand the owner a phase's acceptance checks to run on the real turntable, then record the results. Use at the end of every build phase (P1 to P4), or when the owner asks to check a phase.
---

Agents cannot hear audio, so only the owner can pass a phase. This skill is the **hardware gate**: build, hand over, stop, record.

1. **Name the phase.** Read its row in spec §9 (`docs/spec.md`) and every acceptance check (AC) that row lists in §10. Done when you hold the full AC list for the phase.
2. **Build.** Build the app and confirm it launches. Done when the build succeeds on the current commit; a failed build goes back to the build work, not to the owner.
3. **Hand over.** Give the owner, in plain language:
   - how to launch this build;
   - one numbered item per AC, keeping its code: the steps to do, then what they should hear or see when it passes.
   Done when every AC from step 1 has one item.
4. **Stop.** End your turn and wait. The owner replies per AC: pass, fail or blocked, with notes.
5. **Record.** Append to `implementation-notes.md` under `## Phase checks`: date, phase, commit hash, and one line per AC with the result and the owner's words verbatim. Done when every AC has a recorded result.
6. **Decide.** If every AC passed, the phase is done. Otherwise the phase stays open: diagnose each failure before you start the next phase.
