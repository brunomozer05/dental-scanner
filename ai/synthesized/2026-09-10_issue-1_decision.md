AGENT_ROLE: orchestrator
DATE_UTC: 2026-09-10
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED: 4b223ae57627ee316191e03cddde8fd8a580a097
RELATED_ISSUE: #1
REPORT_STATUS: complete

# INPUT REPORTS

- `ai/inbox/red-team/2026-09-10_issue-1_finalization-timeout.md`
- GitHub Issue #1
- GitHub Issue #19
- `DentalScanner/ScannerMVP/UI/ScannerViewModel.swift` at `4b223ae57627ee316191e03cddde8fd8a580a097`

# SUPPORTED FINDINGS

- The timeout bug is confirmed in current production code and Issue #1 is not stale.
- Normal automatic success requires `hasStableWindow && maturityGatePassed`, but the independent `hitMaxWindow` branch assigns `max_seconds_reached_export_gate_valid` even when those predicates are false.
- `normalFinalizationCanAutoExport` then becomes true when an auto-export reason exists and all expected markers are at 100%, so the 12 s timeout can bypass both the stable-window requirement and maturity gate.
- The UI currently describes that path as `Tempo maximo atingido; finalizando com dados validos`, which overstates the quality semantics when the maturity/stability predicates failed.
- Frame acceptance/rejection and stable-time accounting are guarded by `normalFinalizationState == .stabilizing`; therefore a naive terminal `.timedOut` state could prevent later recovery.
- This is a control-flow/state-machine fix. No PnP, accumulator, OpenCV, Pre-Gate, BA or live capture-maturity promotion is required.

# REJECTED OR WEAK CLAIMS

- Timeout failure does not prove the current pose geometry is metrically wrong in every affected scan; it proves the software is allowing export without satisfying its own stronger finalization predicates.
- A new terminal timeout enum is not automatically the correct solution. Without changes to the existing guards it can freeze the recovery path.
- The separate `normalGatePassed` nil-fallback behavior is not established as part of this P0 bug and should not be changed opportunistically.

# UNRESOLVED QUESTIONS

- Final product UX after timeout: continue scanning automatically versus explicit manual acknowledgement.
- Whether missing normal diagnostics should later fail closed is a separate investigation.

# DECISION

Fix Issue #1 before using finalization behavior as a quality signal. Use a narrow decision-policy change: timeout is a non-success diagnostic, not a precision-success path. Preserve continued collection after timeout so later valid frames may still satisfy the existing normal success predicate, unless a separate product decision explicitly chooses a terminal/manual policy.

# ISSUE ACTION

UPDATE_ISSUE #1

Add acceptance coverage for the independent stable-window bypass, post-timeout recovery, one-shot timeout diagnostics and the state-machine guardrail.

# RECOMMENDED CODEX SCOPE

- Extract or narrowly modify only the normal-finalization decision policy needed for testability.
- Make `hasStableWindow && maturityGatePassed` the only normal automatic-success condition.
- Treat max-window expiry as a non-success, latched diagnostic/UX condition.
- Preserve continued finalization frame accounting after timeout.
- Add focused tests for timeout with maturity false, timeout with maturity true but stable false, normal success, recovery after timeout and four-marker invariants.
- Do not alter pose math, PnP, accumulator, Pre-Gate blocking, Best Final Pose Candidate promotion, capture-maturity live semantics or BA.

# CODEX EFFORT

HIGH

# VALIDATION GATE

- Focused unit tests for finalization policy/state transitions.
- Existing test suite passes.
- Apple CI passes.
- Diff review confirms no geometry or live maturity promotion was bundled into the fix.
