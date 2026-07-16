# 20 — Offline Capture Maturity Replay

## Status

Diagnostics-only offline replay implemented for schema-1 scan sessions. Physical execution against the existing real session remains pending.

This specification does not authorize changes to live progress, live readiness, Pre-Gate blocking, accumulation, finalization, or export. It establishes an observable capture-maturity model before any live behavior is reconsidered.

## 1. Objective

Determine, from an already persisted frame-indexed session, when the scan acquired enough geometrically distinct support rather than merely accumulating repeated observations.

The replay answers, separately for `ALL` and persisted Pre-Gate `FILTERED` populations:

```txt
how many raw marker observations existed
how many observations were structurally usable
how many viewpoints were geometrically distinct
how many frames contributed selected observations
which marker reached maturity last
whether the expected frame-marker graph was connected
when marker and global maturity were first reached
how early the existing live progress/finalization signals occurred
```

The primary result is `STRICT`. An adapted `REFERENCE_LIKE` result is additional diagnostics and never replaces `STRICT`.

The detailed artifact is:

```txt
<scan-basename>_capture_maturity_replay.json
artifactSchemaVersion = 1
```

It contains no image data and does not modify the source NDJSON, scan, STL, report, or diagnostics files.

Encoding uses `JSONEncoder` with `prettyPrinted` and `sortedKeys`; output is written atomically. The exporter refuses source-artifact collisions and repeated runs over identical input/configuration must produce identical bytes.

## 2. Physical motivation

A real scan observed outside the repository had approximately:

```txt
duration                              44.4 s
frames processed                      1,331
marker observations                   4,619
expected markers                      M0, M1, M2, M3
all markers seen                      0.07 s
all markers exportable                1.93 s
experimental angle diversity ready    false
```

Capture continued for more than 42 seconds after every marker became exportable, while normal finalization reported no focus-accepted frames and eventually exported through its maximum-duration fallback. This is physical motivation, not a tracked test fixture and not proof of a specific cause.

The same session family also showed large differences between current-accumulator `ALL` and persisted Pre-Gate `FILTERED` replay geometry. That evidence does not approve live blocking and does not establish that `FILTERED` is better.

Therefore:

- do not equate "all markers exportable" with geometric maturity;
- do not solve maturity by increasing only a raw frame counter;
- do not activate Pre-Gate blocking from this experiment;
- do not connect the offline metric to live progress until physical validation is complete;
- do not claim that maturity selection replaces bundle adjustment.

## 3. TMarker authorization

The locally available TMarker material was inspected under the previously established owner authorization.

Repository rules still apply:

- `_local_reference/` remains read-only and untracked;
- no reference binary, framework, model, asset, geometry, credential, endpoint, authentication material, or physical capture enters Git;
- DentalScanner has no runtime dependency on the reference;
- third-party libraries remain subject to independent license/build review;
- reusable behavior is reimplemented as an original DentalScanner diagnostic design;
- conclusions retain explicit evidence classifications.

The reference executable is encrypted (`cryptid = 1`). Configuration and symbols can establish values and architecture, but they do not expose the exact formulas or call order of the protected implementation.

## 4. TMarker evidence

### Material inspected

The targeted investigation used:

- `_local_reference/tmarker_new/T-Marker 1.8.4/Payload/TruMarker.app/CommonConfig.json`;
- `_local_reference/tmarker_new/T-Marker 1.8.4/Payload/TruMarker.app/DeviceConfig.json`;
- `_local_reference/tmarker_new/T-Marker 1.8.4/Payload/TruMarker.app/YoloConfig.json`;
- the main `TruMarker` arm64 Mach-O symbol/string tables;
- `en.lproj/Localizable.strings`;
- `_local_reference/analysis/full_reference_analysis.md`;
- `research/reference_scanner_pipeline_findings.md`;
- the existing local IPA inventory/tree reports.

No reference file was modified or copied into the repository.

### Configured values

| Configuration | Value | Scope and likely role | Classification |
|---|---:|---|---|
| `MarkerConfig.kProgressMarkerCount` | 3 | Reference progress-marker population; not applicable as a DentalScanner expected-marker count | CONFIRMED BY CONFIGURATION |
| `MarkerConfig.kOptimizationMarkerCount` | 2 | Minimum marker support associated with reference optimization/frame handling | CONFIRMED BY CONFIGURATION |
| `MarkerConfig.kMinValidFramesPerMarker` | 65 | Minimum valid-frame support per marker | CONFIRMED BY CONFIGURATION |
| `AngleDiversityConfig.kMinAngularSeparationDeg` | 1.5 deg | Minimum separation associated with per-marker viewpoint diversity | CONFIRMED BY CONFIGURATION |
| `AngleDiversityConfig.kTargetAngularStdDeg` | 4.5 deg | Desired per-marker angular dispersion target | CONFIRMED BY CONFIGURATION; interpretation supported by symbols |
| `ProgressHoldConfig.kTargetOptFrames` | 300 frames | Session/global optimization-support or progress-hold target | CONFIRMED BY CONFIGURATION |
| `AngleDiversityConfig.kHalfProgressFraction` | 0.5 | Dynamic-progress/relaxation control | CONFIRMED BY CONFIGURATION |
| `AngleDiversityConfig.kDynamicStepUpFactor` | 0.25 | Dynamic-progress step factor | CONFIRMED BY CONFIGURATION |
| `AngleDiversityConfig.kDynamicStepUpMinDeg` | 0.1 deg | Lower angular step bound | CONFIRMED BY CONFIGURATION |
| `AngleDiversityConfig.kStdRelaxMarginDeg` | 0.25 deg | Angular-dispersion relaxation margin | CONFIRMED BY CONFIGURATION |
| `AngleDiversityConfig.kDynamicRelaxFactor` | 0.8 | Dynamic threshold relaxation multiplier | CONFIRMED BY CONFIGURATION |
| `ProgressHoldConfig.kHoldStartPercent` | 1.0 (`Percent`-named unit) | Progress-hold boundary; exact scale and call semantics unavailable | CONFIRMED BY CONFIGURATION; use semantics UNCERTAIN |
| `ProgressHoldConfig.kHoldIntervalPercent` | 1.0 (`Percent`-named unit) | Progress-hold/update interval; exact scale and call semantics unavailable | CONFIRMED BY CONFIGURATION; use semantics UNCERTAIN |

The 65, 1.5-degree, 4.5-degree, and 300-frame values are real configured values, but their exact protected implementation cannot be inferred from the JSON alone.

### Symbols and architectural evidence

| Evidence | Supported conclusion | Classification |
|---|---|---|
| `TM::Record::CountProgress(Frame)` | Progress is computed from a processed frame object, not only elapsed time | CONFIRMED BY SYMBOL |
| `AssessFrameValidity(Frame&, FrameContainer const&)` | A validity assessment exists before retained progress/optimization use | CONFIRMED BY SYMBOL |
| `IsDiversityValid(Frame const&, FrameContainer const&)` | Diversity is an explicit validity dimension | CONFIRMED BY SYMBOL |
| `ComputeAngularStdDeg(FrameContainer const&, markerId)` | Angular dispersion is computed per marker | CONFIRMED BY SYMBOL |
| `GetMarkerCamUnitVectorsHistory(markerId)`-like symbol | Per-marker marker-camera unit-vector history is exposed by the focused symbol set | STRONG INDICATION |
| `FrameContainer::GetFrameCount(markerId)` | Retained frame support can be queried per marker | CONFIRMED BY SYMBOL |
| `Frame::IsProgressValid` | A frame can be valid or invalid for progress independently of raw presence | CONFIRMED BY SYMBOL |
| `UpdateProgressInformation`, `ClearProgressInformation` | Progress has persistent session state | CONFIRMED BY SYMBOL |
| `RelaxProgressThresholdIfFullyConnected` | A bounded relaxation path is conditioned on connectivity | CONFIRMED BY SYMBOL |
| `FindBaseMarkerIDByValidMarkerCount` | Base-marker selection considers valid support | CONFIRMED BY SYMBOL |
| `OptimizeLogic::Run(FrameContainer, baseMarkerId)` | Optimization consumes the frame-indexed retained container | CONFIRMED BY SYMBOL |
| `InitializeVwcByFrameFromBaseMarker`, `InitializeVwcForFrame` | Camera state exists per frame | CONFIRMED BY SYMBOL |
| `InitializeVwmByIdFromFrames` | Shared marker state is initialized from multiple frames | CONFIRMED BY SYMBOL |
| `BuildRelativeEdges`, `MarkerEdgeCost` | Relative marker connectivity/graph constraints exist | CONFIRMED BY SYMBOL |
| `AddReprojectionResiduals`, `ComputeReprojectionResidual` | Frame-indexed reprojection residuals enter optimization | CONFIRMED BY SYMBOL |
| `RemoveOutliers`, `RecomputeVwcByPnP`, `RobustAverageVbm` | A later outlier/re-estimation path exists | CONFIRMED BY SYMBOL |
| `ceres::Problem`, `ceres::Solve`, `ceres::HuberLoss`, `BAReport` | Ceres, robust loss, and BA reporting are present | CONFIRMED BY SYMBOL |

### TMarker capture-maturity questions

1. **What does the progress bar measure?** It uses frame/progress-validity state with per-marker progress information. The exact aggregation formula is unavailable. `CONFIRMED BY SYMBOL`; exact formula `UNCERTAIN`.
2. **Raw, valid, selected, or optimizable frames?** Symbols distinguish raw frame processing from validity/diversity and retained frame counts. Progress therefore is not a simple raw-detection counter. Whether "valid" and "selected" are the same internal population is `UNCERTAIN`.
3. **How many views per marker?** `kMinValidFramesPerMarker = 65`. `CONFIRMED BY CONFIGURATION`. Whether every count is angularly distinct is `UNCERTAIN`.
4. **How are two views different?** A per-marker unit-vector history and a 1.5-degree minimum angular separation exist. `CONFIRMED BY CONFIGURATION/SYMBOL`; exact comparison and boundary are `UNCERTAIN`.
5. **What represents viewpoint?** The focused symbols strongly indicate retained marker-camera unit vectors per marker. `STRONG INDICATION`; exact direction sign is `UNCERTAIN` and irrelevant to pairwise angles but relevant to bins.
6. **Per marker or anchor?** Angular standard deviation and vector history are keyed by marker ID. `CONFIRMED BY SYMBOL`.
7. **Shared virtual camera/frame pose?** Per-frame camera state exists for optimization. `CONFIRMED BY SYMBOL`. Its direct use in progress is `UNCERTAIN`.
8. **How is angular dispersion calculated?** `ComputeAngularStdDeg` exists per marker and 4.5 degrees is configured. The formula is protected. `CONFIRMED BY SYMBOL/CONFIGURATION`; formula `UNCERTAIN`.
9. **Azimuth/elevation bins?** No supporting config or focused symbol was found. `UNCERTAIN`; DentalScanner bins are an explicit adaptation.
10. **Staged capture?** No confirmed staged/guided-capture architecture was found. `UNCERTAIN`.
11. **Does the slowest marker control global progress?** Per-marker progress values exist, and a complete session must satisfy marker support. Minimum-marker aggregation is a `STRONG INDICATION`, not confirmed implementation.
12. **Can progress reach 100% without diversity?** Diversity validity and progress-valid state are separate explicit concerns, strongly indicating that diversity constrains completion. Exact 100% rule is `UNCERTAIN`.
13. **What prevents early finalization?** Valid-frame support, diversity, optimization target/progress hold, and connectivity-conditioned relaxation all exist. `STRONG INDICATION`; exact conjunction is `UNCERTAIN`.
14. **Minimum capture time?** No explicit minimum-time config or symbol was confirmed. `UNCERTAIN`.
15. **Final stability window?** No exact final-stability window was confirmed. `UNCERTAIN`.
16. **How are thresholds relaxed?** A fully-connected relaxation function and bounded dynamic config values exist. `CONFIRMED BY SYMBOL/CONFIGURATION`; formula/order is `UNCERTAIN`.
17. **Does relaxation affect progress, selection, or BA?** The symbol names place it in progress thresholding, not residual construction. `STRONG INDICATION` that it affects future validity/progress admission, not BA math.
18. **Which frames enter BA?** `OptimizeLogic::Run` consumes `FrameContainer`. `CONFIRMED BY SYMBOL`; exact membership and any later subset are `UNCERTAIN`.
19. **All frames or a diverse subset?** Validity/diversity occurs before container optimization, strongly indicating a retained subset rather than all raw frames. No separate selected-optimization subset symbol was found. `STRONG INDICATION`.
20. **Frames missing some markers?** `kOptimizationMarkerCount = 2` plus pending-invalid-marker symbols strongly indicate partial frames can remain useful. Exact handling is `STRONG INDICATION`.
21. **Disconnected components?** Relative edges, base selection, and fully-connected relaxation exist. `CONFIRMED BY SYMBOL`; exact failure/fallback behavior is `UNCERTAIN`.
22. **Does BA begin only after maturity?** Progress/optimization support are related, but call order is protected. `UNCERTAIN`.
23. **Partial or incremental optimization?** No sufficient evidence confirms incremental BA. `UNCERTAIN`.
24. **How are outliers removed?** Explicit removal, reprojection reporting, camera re-PnP, and robust marker averaging symbols exist. `CONFIRMED BY SYMBOL`; thresholds/order are `UNCERTAIN`.
25. **What should DentalScanner adapt now?** Offline per-marker viewpoint histories, distinct-view selection, explicit connectivity, timeline, slowest-marker diagnostics, and non-premature progress. This is an original DentalScanner adaptation.
26. **What waits for BA?** Optimization membership decisions, joint camera/marker refinement, graph edges, second-pass outliers, and final optimized geometry remain Spec 19 work.
27. **What is not directly applicable?** Reference marker counts, proprietary geometry, extra feature points, AI/model paths, and any protected UI/capture staging are not adopted.

The focused evidence did not establish exact timeout/fallback behavior, operator guidance strings, a minimum capture duration, a final stability window, or the precise role of focus/motion/reprojection in progress admission. Reprojection is confirmed in optimization/outlier symbols, but that is not proof of the capture-progress criterion. These items remain `UNCERTAIN`.

## 5. Evidence classifications

Every artifact entry and policy parameter uses one of:

```txt
CONFIRMED BY IMPLEMENTATION
CONFIRMED BY CONFIGURATION
CONFIRMED BY SYMBOL
STRONG INDICATION
INFERENCE
UNCERTAIN
```

Rules:

- A config proves the value and key, not the protected call site.
- A symbol proves component presence/signature, not formula or call order.
- Multiple aligned config and symbol observations may support `STRONG INDICATION`.
- A DentalScanner design choice inspired by the reference is labeled adaptation or inference.
- No threshold is represented as a precision guarantee.

Important semantic conclusions:

- `65` is a configured minimum of valid frames per marker. Treating it as exactly 65 distinct viewpoints is a conservative DentalScanner adaptation, not confirmed reference implementation.
- `1.5 deg` is a configured minimum angular separation associated with per-marker diversity.
- `4.5 deg` is a configured target angular standard deviation. The presence of `IsDiversityValid` and `ComputeAngularStdDeg` supports interpreting it as desired spread rather than undesired instability, but the exact formula is unavailable.
- `300` is a global optimization/progress-hold target. It is not evidence that BA consumes exactly 300 frames and never independently produces maturity.
- Reference relaxation is confirmed to exist, but the replay's arithmetic schedule is explicitly `REFERENCE_LIKE`, not an implementation claim.

## 6. DentalScanner current behavior

Current live progress primarily reports marker availability/exportability and can reach 100% before offline geometric maturity. Existing diagnostics expose useful milestones, but they are not all semantically exact:

- `timeToAllMarkersSeenSeconds`: first time all expected marker IDs are present in raw per-frame pose results;
- `timeToAllMarkersExportableSeconds`: first throttled sample where every expected marker satisfies current exportable validation;
- `normalFinalizationStartedAtSeconds`: latest uninterrupted normal-finalization start, used only as an available proxy for UI-100 timing;
- `normal_finalization_export_triggered`: export-trigger event, not proof that asynchronous STL writing completed;
- an exact first-UI-100 timestamp and exact STL-write completion timestamp are not currently persisted.

The maturity replay consumes associated diagnostics/report data only when available and labels unavailable or proxy comparisons. It does not hardcode the physical-session values.

No live property is changed:

```txt
scanProgress
captureProgressPercent
expectedMarkerProgressById
normal finalization maturity
```

## 7. Pose/viewpoint convention

DentalScanner's persisted per-frame pose is:

```txt
T_cm = camera-from-marker
p_c  = R_cm * p_m + t_cm
```

This is `CONFIRMED BY IMPLEMENTATION`: OpenCV `solvePnP` output is stored and later passed directly to `projectPoints`.

For viewpoint diagnostics:

```txt
C_m = -transpose(R_cm) * t_cm
d_m = C_m / ||C_m||
```

`C_m` is the camera center in marker-local coordinates, and `d_m` is the unit marker-to-camera direction.

Angular distance:

```txt
theta(a, b) = acos(clamp(dot(a, b), -1, 1))
```

- internal unit: radians;
- public artifact unit: degrees;
- no Euler-angle comparison;
- no use of Rodrigues vector as a viewpoint substitute;
- no special anchor or logic for M0;
- sign reversal would preserve pairwise angular distance but would change azimuth/elevation bin identity, so the confirmed `C_m` direction is used.

Before use, require finite translation, finite 3x3 rotation, approximate orthonormality, determinant approximately `+1`, and camera-center norm above epsilon. Invalid observations are diagnosed, not repaired.

Default numerical checks:

```txt
orthogonality tolerance   1e-5
determinant tolerance     1e-5
vector norm epsilon       1e-9
```

These are DentalScanner numerical guards, not reference thresholds.

## 8. Frame/observation selection

The schema-1 reader remains the integrity and reconstruction authority. The maturity consumer uses an immutable complete-observation callback rather than introducing a second NDJSON parser.

Counts remain distinct:

```txt
sourceObservationCount
policyInputObservationCount
validObservationCount
selectedObservationCount
frameSupportExcludedObservationCount
selectedDistinctViewCount
selectedFrameCount
framesWithOneSelectedMarker
framesWithAllExpectedMarkersSelected
framesWithAllExpectedMarkersObserved
```

Selection preserves:

- physical frame order;
- marker observation order and multiplicity;
- original frame index and capture timestamp;
- persisted explicit rotation matrix and translation;
- marker-local independent histories.

Strategies:

1. `perMarkerObservation` — default `STRICT` strategy. Each marker observation independently adds a distinct view only when sufficiently separated from that marker's selected history.
2. `wholeFrameWhenAnyMarkerHasDistinctView` — adapted `REFERENCE_LIKE` strategy. When a structurally valid frame contains at least one new distinct marker view, all structurally valid policy observations in that frame are retained as selected frame support, while distinct-direction histories remain per marker.

The second strategy is not asserted to be the exact protected reference implementation.

`minimumObservationsPerFrame` defaults to `1`; the reference count of two optimization markers is not transplanted. If an experimental configuration raises this value, otherwise valid observations in a frame with insufficient support are counted as `frameSupportExcluded`, not falsely labeled as angularly redundant.

## 9. Angular diversity

### Distinct-view admission

The first valid view for each marker is selected. A later candidate is compared with every selected direction for the same marker:

```txt
nearestAngle = min(theta(candidate, selectedDirection))
```

It is distinct when it meets the active minimum-separation threshold within the configured numerical tolerance; otherwise it is redundant. A selected view for one marker does not select a distinct view for another marker.

### Angular spread

The DentalScanner adapted spread metric is:

```txt
s          = sum(d_i)
mean       = normalize(s), when ||s|| > epsilon
deviation_i = theta(d_i, mean)
spreadRMS   = sqrt(mean(deviation_i^2))
```

This is persisted as `angularSpreadDegrees`. It is an original stable diagnostic consistent with the reference concept of a per-marker angular standard-deviation target, but it is not claimed to be the protected `ComputeAngularStdDeg` formula.

If the mean direction is numerically undefined because selected directions cancel, `angularSpreadDegrees` is unavailable (`nil` in the Codable model), `angularMeanDirectionDefined` is `false`, angular-spread progress is zero, and the marker cannot satisfy angular-spread maturity. The replay never substitutes a constant preferred direction or a synthetic spread.

Many views concentrated in one small region can satisfy raw count while failing distinct-view count, spread, or coverage.

## 10. Coverage

Coverage is a DentalScanner diagnostic adaptation. No azimuth/elevation-bin mechanism was confirmed in the reference.

Per-marker convention:

```txt
azimuth   = atan2(y, x), range [-180, 180) degrees
elevation = asin(z),     range [-90, 90] degrees
```

Default diagnostic grid:

```txt
azimuth bins    12
elevation bins   6
```

At a pole where horizontal norm is at most epsilon, azimuth is deterministically assigned to `0 deg`. Bin order is elevation index then azimuth index.

The artifact persists:

```txt
coveredBinCount
totalBinCount
coveragePercent
coveredBins
missingBins
```

Default `requiredCoveragePercent = 0`, so coverage is reported but does not gate maturity until physical evidence defines a justified requirement.

## 11. Relaxation

### `STRICT`

- primary result;
- fixed 1.5-degree distinct-view threshold;
- fixed 4.5-degree spread target;
- no threshold relaxation;
- no adaptive promotion to maturity.

### `REFERENCE_LIKE`

This mode demonstrates bounded relaxation using confirmed config values and the confirmed connectivity-conditioned relaxation concept, but its exact schedule is an adaptation.

Initial adapted schedule:

```txt
first threshold                 targetSelectedFrameCount * 0.5
later interval                  targetSelectedFrameCount * 0.25
angular separation update       current * 0.8
angular separation floor        0.1 deg
spread target update            current - 0.25 deg
spread target floor             0.25 deg
precondition                    expected selected graph connected
```

Each event persists:

```txt
previous/current separation
previous/current spread target
frame index
timestamp
selected-frame count
next threshold
reason
reason further relaxation stopped
```

`REFERENCE_LIKE` never mutates or replaces the `STRICT` result.

## 12. Marker maturity

Each expected marker has an independent history and one state:

```txt
notObserved
insufficientValidObservations
insufficientDistinctViews
insufficientAngularSpread
insufficientCoverage
mature
```

Default experimental criteria:

```txt
valid observations             >= 65
distinct selected views        >= 65
angular spread                 >= 4.5 deg in STRICT
coverage                       diagnostic only by default
```

The first condition is based on confirmed valid-frame config. Requiring 65 distinct views is deliberately conservative and classified as an adaptation pending physical validation.

For every marker, persist:

```txt
raw/policy-input/valid/selected/redundant/frame-support-excluded/rejected counts
rejection counts by structural reason
selected direction history
nearest-angle statistics
angular spread
coverage
first observed/distinct/mature timestamps
maturity frame index and state
blocking reason
progress components
confirmed/adapted/uncertain criterion lists
```

Unexpected marker IDs are diagnosed and do not satisfy expected-marker maturity.

## 13. Global maturity

Global maturity requires all of:

```txt
every configured expected marker is mature
expected marker IDs are connected through the selected frame-marker graph
selected support satisfies configured structural requirements
no confirmed global requirement is missing
```

`targetSelectedFrameCount = 300` is reported as optimization-target progress, but reaching it cannot independently make the session mature.

The slowest marker is selected deterministically:

- before maturity: lowest marker progress, with marker ID as tie-breaker;
- after all marker criteria pass: latest maturity timestamp, with marker ID as tie-breaker.

Persist:

```txt
firstTimestampAllMarkersMature
frameIndexAllMarkersMature
firstTimestampGlobalMature
frameIndexGlobalMature
slowestMarkerId
slowestMarkerBlockingReason
matureMarkerCount
selectedFrameCount
selectedObservationCount
optimizationTargetReachedTimestamp
expectedMarkersConnected
globalMaturityState
globalBlockingReason
```

`requireSelectedFrameTargetForGlobalMaturity = true` makes the configured 300-frame target an explicit DentalScanner support gate in the initial experiment. This use is an adaptation, not a confirmed reference formula, and is persisted in the global adapted/uncertain criterion lists. The flag can be disabled in a controlled offline configuration without changing the live app.

No marker, including M0, is a preferred maturity anchor.

## 14. Connectivity

The replay maintains bipartite graphs:

```txt
frame node <-> marker node
```

Graph populations are separated by:

- `ALL` versus `FILTERED`;
- structurally valid observations versus selected observations.

Each observation edge preserves multiplicity for counts while connectivity uses node incidence.

Persist:

```txt
componentCount
largestComponentFrameCount
largestComponentObservationCount
largestComponentMarkerIds
expectedMarkersConnected
disconnectedMarkerIds
isolatedFrameCount
```

A disconnected expected marker blocks global maturity. The replay never assigns an identity or inferred relation to a disconnected component.

## 15. Progress model

Marker progress exposes its components:

```txt
validObservationProgress = min(valid / requiredValid, 1)
distinctViewProgress     = min(distinct / requiredDistinct, 1)
angularSpreadProgress    = min(spread / requiredSpread, 1)
coverageProgress         = min(coverage / requiredCoverage, 1)
markerProgress           = minimum of enabled required components
```

When coverage is disabled, it is reported but contributes a neutral `1.0`.

Global progress is the minimum expected-marker progress plus global connectivity/maturity rules:

```txt
globalProgress <= 0.99 while global state is not mature
globalProgress == 1.0 only when global state is mature
```

`firstTimestampAllMarkersMature` records completion of the per-marker criteria. `firstTimestampGlobalMature` additionally requires connectivity and configured global support and is the milestone used for UI-versus-offline maturity comparison.

This diagnostic is intentionally not wired to the live UI.

## 16. Timeline

Snapshots are emitted deterministically at a configurable interval, default `0.5 s`, using persisted frame timestamps and physical file order. Each interval is represented by the first physical frame that reaches or crosses its elapsed-time boundary; a terminal snapshot is appended when the last frame is not already represented. Timestamp regressions are diagnosed; frames are never sorted or interpolated.

Each snapshot contains:

```txt
timestamp
frameIndex
policy
mode

per marker:
  raw/valid/distinct/redundant counts
  angular spread
  coverage
  maturity state
  progress
  blocking reason

global:
  mature/expected marker counts
  all-markers-mature
  selected frames/observations
  connectivity
  optimization target progress
  global progress
  blocking reason
```

Marker IDs, bin IDs, rejection reasons, and timeline records use stable deterministic ordering. Repeated replay with the same input/configuration must produce byte-identical JSON.

## 17. ALL versus FILTERED

`ALL` includes every persisted marker observation that passes schema reconstruction and maturity structural validation.

`FILTERED` includes only observations whose persisted annotations satisfy:

```txt
preAccumulationGateEvaluated == true
preAccumulationGateWouldAccept == true
```

The gate is not re-executed. Current thresholds are not applied retrospectively. Missing evaluation or decision annotations are counted and excluded from `FILTERED` maturity rather than inferred.

Both policies run `STRICT` and `REFERENCE_LIKE` independently and report:

- source and retained populations;
- selected frames and observations;
- per-marker maturity;
- connectivity;
- timeline;
- slowest marker;
- maturity-time differences.

No result declares `ALL` or `FILTERED` better. In particular, a lower `FILTERED` maturity can mean the persisted gate removed useful coverage; a higher result can mean it removed redundancy. Only physical/ground-truth validation can interpret the change.

## 18. Physical validation

The existing physical session must remain outside Git:

```txt
Scan_2026-07-16_12-30_session.ndjson
```

On device:

```txt
saved scan
-> associated sessionCaptureURL
-> "Executar replay de maturidade da captura"
-> background schema-1 replay
-> ALL/FILTERED, STRICT/REFERENCE_LIKE summaries
-> <scan>_capture_maturity_replay.json
-> share sheet
```

Expected UI states:

```txt
Analisando maturidade da captura...
Replay de maturidade concluído
Falha no replay de maturidade: <actual error>
```

Physical questions:

- Were most of the 1,331 frames redundant?
- Which marker matured last?
- Did M3 actually limit the session?
- Did the UI reach 100% before `STRICT` maturity?
- Did `ALL` and `FILTERED` change maturity and connectivity differently?
- Did persisted `highMotion` rejection reduce useful angular coverage?

Do not report answers until the actual artifact has been executed and inspected.

Associated diagnostics comparison is `availableWithCaveats` or `unavailable`. It must distinguish all-markers-seen, exportable, finalization-start/UI proxy, export-trigger, and unavailable true export-completion time.

When source data exists, persist:

```txt
actualAllMarkersSeenTimestamp
actualAllMarkersExportableTimestamp
actualUI100PercentTimestamp
actualFinalizationStartedTimestamp
actualExportTriggeredTimestamp
actualExportTimestamp
offlineStrictMaturityTimestamp
offlineReferenceLikeMaturityTimestamp
filteredOfflineStrictMaturityTimestamp
ui100ToStrictMaturityDeltaSeconds
exportableToStrictMaturityDeltaSeconds
strictMaturityReachedBeforeExport
```

The source diagnostics timestamps are session-relative while `FrameObservation.timestampSeconds` is a capture clock. The comparison layer must verify/describe its alignment and never subtract incompatible clocks silently.

An external-path macOS CLI is deferred because the current project has no suitable shared macOS target. Do not add an unsafe importer or duplicate the reader. An opt-in XCTest path may consume an externally supplied file without tracking it.

## 19. Explicit non-goals

```txt
live ScannerViewModel progress changes
live scanProgress/captureProgressPercent/expectedMarkerProgressById
live accumulator inputs or MultiFramePoseAccumulator changes
maxSamplesPerMarker or live minimumAngularDiversityRadians changes
Pre-Gate criteria/order or blocking
Experimental Observation Gate changes
PoseEstimator/OpenCV/solvePnP/projectPoints changes
FinalPoseRefiner or legacy concatenated PnP changes
readiness or normal finalization changes
Best Final Pose Candidate behavior
ExportGate or normal STLExporter changes
camera/focus/profiles/4K changes
Python comparator changes
bundle adjustment, Ceres, pose graph, second-pass outliers
intrinsics optimization
guided capture or live staged capture
```

Capture maturity, frame selection, and geometric optimization remain separate concerns.

## 20. Acceptance criteria

- Actual reference config and focused symbols are listed with classifications.
- Protected formulas/call order remain explicitly uncertain.
- The configured 65/1.5/4.5/300 values have documented units, scope, semantics, and caveats.
- `T_cm`, camera center, viewpoint direction, and angular distance are implemented/tested without Euler angles.
- Invalid/non-SO(3) pose data is diagnosed rather than repaired.
- ALL and persisted-decision FILTERED populations are separate.
- Missing gate annotations are diagnosed and never inferred.
- STRICT is primary and never relaxes.
- REFERENCE_LIKE relaxation history is bounded, explicit, and secondary.
- Frames and observations are counted separately.
- Maturity exists independently per expected marker.
- Slowest-marker and global connectivity diagnostics are deterministic.
- Coverage bins are explicitly marked as a DentalScanner adaptation.
- Global progress cannot reach 100% before global maturity.
- Timeline and JSON ordering are deterministic.
- Associated live milestones use exact values or explicit proxies/unavailable states.
- On-device execution is off the main thread and produces one shareable JSON artifact.
- No source/runtime artifact is overwritten.
- No live progress or scan/export behavior changes.
- No reference or physical artifact is committed.
- Bundle adjustment is not implemented; Spec 19B remains pending.

## 21. Open questions

1. Does physical evidence support requiring 65 distinct views, or should valid-frame and distinct-view targets differ?
2. What exact spread metric best correlates with relative marker stability?
3. Should coverage become a maturity gate, and with what sphere partition/threshold?
4. Does per-observation or whole-frame selection better preserve future BA connectivity?
5. How often and under what stall condition should any relaxation occur?
6. Is the first normal-finalization start an adequate UI-100 proxy, or should a future schema persist the exact transition?
7. Should export completion receive a dedicated persisted timestamp?
8. How does ALL/FILTERED maturity correlate with physical ground truth and replay STL geometry?
9. Which selected observation population should feed Spec 19C after offline validation?
10. Should a shared macOS diagnostic target be introduced before physical BA evaluation?
11. Is on-device runtime acceptable for a multi-thousand-observation session, or should repeated per-frame maturity metrics be cached after physical profiling?

No open question authorizes live integration. The next decision follows execution and review of the physical maturity artifact.
