AGENT_ROLE: orchestrator
DATE_UTC: 2026-09-10
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED: 4b223ae57627ee316191e03cddde8fd8a580a097
RELATED_ISSUE: #2
REPORT_STATUS: complete

# INPUT REPORTS

- `ai/inbox/research/2026-09-10_issue-2_ippe-planar-ambiguity.md`
- GitHub Issue #2
- GitHub Issue #19
- `DentalScanner/ScannerMVP/OpenCV/OpenCVArucoPoseBridge.mm` at `4b223ae57627ee316191e03cddde8fd8a580a097`
- `DentalScanner/ScannerMVP/Replay/ScanSessionCaptureMaturityReplay.swift`
- Existing physical schema-1 session `Scan_2026-07-16_15-22_session.ndjson`, session `5D580A73-28E3-49BD-81B7-4947A421F546`, analyzed locally without adding the physical artifact to Git.

# SUPPORTED FINDINGS

## Production behavior

- Current `singleArucoV1` production pose estimation calls `cv::solvePnP(..., SOLVEPNP_IPPE_SQUARE)` and receives one rvec/tvec.
- The square object-point order in production matches the required IPPE square order; no ordering bug was found.
- The current capture-maturity replay consumes the single persisted pose and therefore cannot observe an alternative planar candidate.
- Schema-1 preserves the ordered image/object points and per-frame intrinsics needed to reconstruct the PnP problem offline.

## Independent physical-session validation

The Orchestrator reran every recorded marker observation from the physical bad session with `solvePnPGeneric(..., SOLVEPNP_IPPE_SQUARE)` using the persisted correspondences, per-frame intrinsics and zero-distortion model matching current production assumptions.

- 3554 / 3554 observations returned exactly two IPPE candidates.
- The persisted production pose matched candidate 0 essentially exactly for every eligible observation; it was closer to the alternate candidate in 0 cases.
- Maximum persisted-vs-candidate-0 rotation mismatch was approximately `0.000129 deg`; maximum translation mismatch approximately `0.000033 mm`.
- Candidate-to-candidate rotation separation was large: median approximately `37.90 deg`, p90 approximately `100.23 deg`, maximum approximately `142.45 deg`.
- Candidate camera-center separation had median approximately `103.25 mm` and maximum approximately `344.69 mm`.
- Yet the alternate-minus-primary DentalScanner-style reprojection-RMS difference had median only approximately `0.392 px`, with some observations nearly tied.

## Temporal discontinuity evidence

Across 3550 consecutive same-marker observation pairs:

- candidate-0 selected rotation delta had median approximately `1.76 deg`, p90 approximately `28.78 deg`, p99 approximately `54.96 deg`, maximum approximately `124.36 deg`;
- in 493 pairs, the current alternate candidate was rotationally closer to the previous persisted pose than the current selected candidate;
- in 442 pairs, the alternate was more than `15 deg` closer to the previous pose.

Using a diagnostic-only immediate-reversal criterion (`selected jump >30 deg`, alternate within `7 deg` of prior, next selected jump >30 deg, and prior-to-next within `7 deg`), 117 immediate reversal events were found.

Representative events include:

- M1 frames 93 -> 94 -> 95: selected jump about `30.63 deg`, alternate about `1.61 deg` from prior, then selected returns by about `30.75 deg`; candidate RMS values were nearly tied (`~0.694` vs `~0.703 px`).
- M1 frames 130 -> 131: selected jump about `59.62 deg` while the alternate is about `1.65 deg` from the prior pose.
- M0 frames 442 -> 443: selected jump about `59.16 deg` while the alternate is about `1.44 deg` from the prior pose.
- M0 frames 531 -> 537: selected jump about `124.36 deg` while the alternate is about `2.80 deg` from the prior pose.

## Multi-marker rigidity evidence

For shared markers in adjacent frames, camera motion was independently computed as `T_Ck_M * inverse(T_Ci_M)`.

Examples show large selected jumps isolated to one marker while another simultaneously observed rigid marker implies only small camera motion:

- frames 111 -> 112: M0 about `1.67 deg / 4.46 mm`, M1 about `43.20 deg / 126.18 mm`, M2 about `0.58 deg / 1.52 mm`;
- frames 130 -> 131: M0 about `2.59 deg / 6.70 mm`, M1 about `59.62 deg / 168.10 mm`.

These motions cannot all describe one rigid camera transition. This is direct evidence that the persisted per-marker candidate sequence contains severe temporal/multi-marker inconsistencies.

# REJECTED OR WEAK CLAIMS

- It is NOT proven that candidate 1 is metrically correct whenever it is temporally smoother.
- It is NOT proven that every large candidate-0 jump is an IPPE branch switch; corner noise, detection error and other model mismatch can contribute.
- Lower temporal variation or better rigid consistency is not proof of absolute trueness.
- No 100 micrometer accuracy claim follows from this analysis.
- No evidence justifies changing live PnP, capture progress or export behavior yet.

# UNRESOLVED QUESTIONS

- How often a deterministic temporal + multi-marker candidate selector changes the final accumulated relative geometry.
- How much current STRICT/REFERENCE_LIKE maturity decreases when discontinuous candidate choices are stabilized.
- Which candidate sequence is metrically closest to independent ground truth; this requires Issue #8 or another characterized fixture.
- Whether zero residual distortion or corner-localization error is a significant independent contributor; keep these separate from the branch experiment.

# DECISION

Issue #2 is strongly justified and should proceed as an offline diagnostic experiment before live capture-maturity promotion. The Research report's core observability concern is not merely theoretical: the recorded bad physical session contains two IPPE candidates for every observation, the production pose corresponds to the first candidate, and that selected sequence exhibits numerous severe transient reversals and cross-marker rigid-motion contradictions while alternate candidates often preserve continuity.

The experiment must determine whether a deterministic candidate-aware policy improves internal consistency and materially changes maturity/accumulator output. It must not claim the smoother branch is true without ground truth.

# ISSUE ACTION

UPDATE_ISSUE #2

Record the physical-session evidence and add explicit acceptance criteria for candidate reconstruction, persisted-pose matching, reprojection metric provenance, immediate-reversal diagnostics and multi-marker motion disagreement.

# RECOMMENDED CODEX SCOPE

Implement diagnostic-only/replay-only support for:

- exposing all valid `IPPE_SQUARE` candidates through a separate OpenCV wrapper;
- reconstructing candidates from schema-1 observations;
- verifying the persisted production pose against the reconstructed candidate set;
- computing DentalScanner-style per-point pixel RMS for every candidate;
- deterministic RAW / lowest-reprojection / temporal-continuity / multi-marker-consensus comparisons;
- explicit SE(3) temporal and rigid-motion disagreement metrics;
- rerunning existing capture-maturity core and a fresh `MultiFramePoseAccumulator` per mode;
- deterministic JSON and diagnostic STL outputs.

Do not modify production `PoseEstimator`, live OpenCV/PnP, live accumulator, progress/readiness/finalization, Pre-Gate blocking, normal STL export or BA.

# CODEX EFFORT

ULTRA

# VALIDATION GATE

- Synthetic two-candidate and rigid-motion tests.
- Exact point-order/unit/convention tests.
- Repeated same-file deterministic replay.
- Replay on the existing physical bad session and comparison of RAW versus candidate-aware modes.
- Existing Apple unit tests and unsigned iphoneos build pass.
- Independent review of the diff before any on-device/live behavior change.
- Ground-truth validation remains required before any accuracy/trueness claim or production promotion.
