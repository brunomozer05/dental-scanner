AGENT_ROLE: red-team
DATE_UTC: 2026-09-10
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED: 4b223ae57627ee316191e03cddde8fd8a580a097
RELATED_ISSUE: #1
REPORT_STATUS: complete

# TARGET

Independent review of GitHub Issue #1, `[P0][Bug] Não auto-exportar quando a finalização não atinge maturidade/estabilidade`, before Codex implementation.

The review asks whether the timeout bug still exists in current `main`, whether the Issue is stale, whether its acceptance criteria are sufficient, and what the narrowest safe fix should preserve.

# CURRENT CODE CHECK

EVIDENCE:

- `main` HEAD inspected: `4b223ae57627ee316191e03cddde8fd8a580a097`.
- `AGENTS.md` requires production code to take precedence over specs and forbids unrelated geometry/finalization scope expansion.
- Issue #19 still places #1 in Phase 0 before live capture-maturity promotion.
- `ScannerViewModel.updateNormalScanFinalizationIfNeeded` still computes:
  - `hasStableWindow` from `normalFinalizationStableSecondsCollected >= normalFinalizationStableSeconds`;
  - `maturityGatePassed` from minimum observations, average observations, normal gate, and reprojection gate;
  - then sets `autoExportReason = "maturity_gate_passed"` when both stable window and maturity pass;
  - but independently sets `autoExportReason = "max_seconds_reached_export_gate_valid"` when `hitMaxWindow` is true.
- `normalFinalizationCanAutoExport` becomes true whenever an `autoExportReason` exists and all expected markers are at 100%, so the timeout branch bypasses both `hasStableWindow` and `maturityGatePassed`.
- The current configuration is `normalFinalizationStableSeconds = 5.0` seconds and `normalFinalizationMaxSeconds = 12.0` seconds.
- The timeout fallback is historical, not accidental dead code. Commit `92eff4903cfff545bc90f0fa141e2ccf586bc23a` introduced auto-finalization with `hasStableWindow || hitMaxWindow`. Commit `ba08d50e46362d6a859e06eedee6f86db5e17c1b` later tightened the maturity gate but explicitly retained the max-seconds fallback.
- No later commit found by the targeted `finalization` history search removes this live fallback. The July commits at the current HEAD are replay/capture-maturity work and do not fix this production path.

Conclusion: the problem still exists. Issue #1 is not stale.

# CONFIRMED

EVIDENCE:

1. **Timeout currently acts as an alternative success path.** The branch `else if hitMaxWindow` creates a success reason even when the normal success predicate `hasStableWindow && maturityGatePassed` is false.
2. **The Issue scope is directionally correct.** This is a finalization/control-flow bug. No PnP, OpenCV, accumulator, pose geometry, Pre-Gate blocking, Best Final Pose Candidate promotion, or Bundle Adjustment change is needed.
3. **Spec 20 cannot be promoted as part of this fix.** `20_capture_maturity_replay.md` explicitly states that the offline maturity replay does not authorize changes to live progress, readiness, accumulation, finalization, or export.
4. **Four-marker export remains a separate invariant.** Current normal finalization additionally requires all expected markers at 100%; the Issue should not weaken the existing export gate or expected-marker requirements.
5. **Direct finalization tests are absent from the current test directory.** `DentalScannerTests` currently contains replay/capture-maturity/STL-comparison test files, not a focused `ScannerViewModel` normal-finalization test suite.

INFERENCE:

- The safest semantic correction is to make timeout a non-success condition while preserving the ability for later frames to satisfy the existing normal success predicate.
- A small decision-oriented helper or narrowly testable policy would reduce risk compared with broad `ScannerViewModel` restructuring.

# CONTRADICTIONS

EVIDENCE:

- There is no contradiction between Issue #1 and current code; the Issue accurately describes the live fallback.
- The historical implementation does show that timeout was deliberately designed as a UX escape hatch. Therefore removing it changes product behavior even though it corrects unsafe success semantics. The implementation must define what happens after timeout rather than simply deleting the branch and leaving ambiguous UI/diagnostics.
- Issue #19 and Spec 20 contradict any proposal that uses this bug fix to promote offline capture maturity into the live pipeline. That promotion belongs to later Issues and requires physical validation.

# MATHEMATICAL / GEOMETRIC REVIEW

EVIDENCE:

- No SE(3) transformation, coordinate-frame composition, or camera/marker pose convention needs to change for Issue #1.
- No use of Euler angles is required.
- No M0 special case is present or justified in the finalization predicates reviewed; observation counts and normal diagnostics operate over expected marker IDs.
- `normalFinalizationMaxSeconds` and `normalFinalizationStableSeconds` are time quantities in seconds.
- The normal-stability threshold is explicitly named/stored in degrees (`normalFinalizationMaxNormalStdDegrees`).
- Reprojection gating is a pre-existing image-space quality criterion; this Issue must not reinterpret a lower reprojection error as evidence of absolute geometric accuracy.
- mm / px / rad conventions are not modified by the narrow timeout fix. Any proposal that changes those thresholds is out of scope.
- Frame identity, gauge freedom, marker-graph connectivity, and bundle-adjustment determinism are not part of this control-flow bug and should remain untouched.

INFERENCE:

- Because the fix does not alter pose values, it should not create a new gauge or transform-direction risk. The primary risk is state-machine behavior, not geometry.

# RISKS

EVIDENCE:

1. **Naive `timedOut` state can freeze recovery.** Current frame accounting for finalization is gated on `normalFinalizationState == .stabilizing`:
   - rejected finalization frames are classified only while `.stabilizing`;
   - `recordNormalFinalizationAcceptedFrameIfNeeded` immediately returns unless state is `.stabilizing`;
   - `normalFinalizationStableSecondsCollected` is incremented inside that accepted-frame path.
   If Codex adds a terminal `.timedOut` state at 12 seconds without redesigning these guards, subsequent frames can stop contributing to the very stability/maturity conditions needed for eventual valid export.
2. **Repeated-timeout behavior is unspecified.** If timeout remains non-terminal while evaluation continues, the code needs a one-shot diagnostic/latch or otherwise may repeatedly surface the same timeout condition every frame.
3. **UI behavior after timeout is unspecified.** The current Issue says timeout needs its own state/reason but does not decide whether the user should continue scanning automatically, receive an explicit warning, or require manual action.
4. **Missing normal metric semantics are unresolved.** Current code computes `normalGatePassed = ... ?? true` when no finite worst-normal metric exists. This may be intentional compatibility behavior, but it is not proven safe by the Issue. It should not be silently changed in this task without evidence.
5. **Broad refactor risk.** `ScannerViewModel` is large and finalization is coupled to diagnostics, UI feedback, report fields, and STL save flow. A broad state-machine rewrite is unnecessary for the confirmed bug.

# MISSING EVIDENCE

HYPOTHESIS:

- A dedicated terminal timeout state may be unnecessary; a latched timeout diagnostic while remaining in `.stabilizing` could preserve recovery with less risk.

MISSING EVIDENCE:

- Whether product UX should continue accepting frames indefinitely after the 12-second timeout or require explicit user action.
- Whether `normalGatePassed == true` when worst-normal data is unavailable is a deliberate invariant for `singleArucoV1` or a separate quality bug.
- A repository-tracked physical fixture reproducing the previously observed `framesAccepted = 0`, `maturityGatePassed = false`, max-seconds export case. The current physical evidence is described in Issue/spec text, not available as a deterministic test fixture.

# MISSING TESTS

Required before merge:

1. Timeout reached, all four expected markers/export gate valid, `maturityGatePassed == false` -> no auto-export.
2. Timeout reached, `maturityGatePassed == true` but `hasStableWindow == false` -> no auto-export. This case is missing from the current acceptance criteria and directly covers the second bypassed predicate.
3. Normal success: `hasStableWindow == true` and `maturityGatePassed == true` -> auto-export still occurs with the normal success reason.
4. Recovery after timeout: after timeout without maturity/stability, later valid frames can still advance the required accounting and eventually reach the normal success path, unless the Issue explicitly chooses a manual-recovery product policy.
5. Timeout diagnostic is emitted/latches deterministically and is not reported as precision success.
6. Existing four-marker export invariant is preserved.
7. No promotion of Best Final Pose Candidate, Pre-Gate blocking, capture-maturity live progress, or BA.
8. Apple CI passes.

# SIMPLER ALTERNATIVE

INFERENCE:

Prefer a narrow finalization-policy change over a new architecture:

- keep the existing successful predicate `hasStableWindow && maturityGatePassed` as the only automatic success path;
- treat `hitMaxWindow` as a non-success diagnostic/UX condition;
- preserve continued collection/recovery after timeout unless product requirements explicitly choose a terminal/manual state;
- if testability requires extraction, isolate only the decision policy instead of restructuring the full scanner state machine.

This answers the safety bug without importing Spec 20, changing geometry, or touching the accumulator.

# REQUIRED CHANGES

Before sending Issue #1 to Codex, revise the plan/acceptance criteria to state explicitly:

1. **Stable-window bypass coverage:** add a test where timeout is reached with maturity true but `hasStableWindow == false`; auto-export must remain false.
2. **Post-timeout recovery semantics:** specify whether scanning continues automatically. Recommended default: timeout is non-success and non-terminal, so later valid frames can still satisfy the existing normal success predicate.
3. **State-machine guardrail:** if a new timeout enum state is introduced, require proof/tests that it does not stop finalization frame acceptance/rejection accounting or stable-time accumulation unintentionally.
4. **One-shot diagnostics:** define a deterministic timeout flag/reason/event that does not overwrite the underlying blocker and does not spam repeated events.
5. **Scope guardrail:** explicitly prohibit using this task to promote Spec 20 capture maturity, Pre-Gate blocking, Best Final Pose Candidate export, PnP changes, accumulator changes, or BA.
6. **Missing-normal behavior:** leave `normalGatePassed` nil-fallback semantics unchanged in this Issue unless separate evidence demonstrates it is part of the P0 bug; document it as an open risk instead of silently broadening scope.

# VERDICT

The core bug is confirmed and the task is worth doing immediately, but the current acceptance criteria are not yet sufficient for a safe Codex implementation because they do not cover the independent stable-window bypass and do not define recoverability after timeout. A naive dedicated timeout state can accidentally stop the finalization accounting needed for recovery.

VERDICT: REVISE