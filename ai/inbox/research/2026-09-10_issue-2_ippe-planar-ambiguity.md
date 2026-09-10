AGENT_ROLE: research
DATE_UTC: 2026-09-10
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED: 4b223ae57627ee316191e03cddde8fd8a580a097
RELATED_ISSUE: #2
REPORT_STATUS: complete

# RESEARCH QUESTION

Can the current `singleArucoV1` use of planar `SOLVEPNP_IPPE_SQUARE` collapse a genuinely ambiguous two-solution pose problem into a single persisted pose in a way that can inflate DentalScanner's offline viewpoint-diversity / capture-maturity metrics, and can this be tested deterministically from the schema-1 session data already persisted without changing the live pipeline?

# CURRENT DENTALSCANNER BEHAVIOR

## Production pose path

At `main` commit `4b223ae57627ee316191e03cddde8fd8a580a097`, the production `singleArucoV1` path is:

```text
ArucoDetector
  -> four detected ArUco corners in detector order
PoseEstimator.estimateSingleArucoV1Pose
  -> OpenCVArucoPoseBridge.estimatePose
OpenCVArucoPoseBridge.mm
  -> BuildMarkerObjectPoints(markerSizeMillimeters)
  -> cv::solvePnP(..., SOLVEPNP_IPPE_SQUARE)
  -> one rvec/tvec returned to Swift
PoseResult
  -> one rotation matrix + one translation persisted
```

Relevant files:

- `DentalScanner/ScannerMVP/Vision/ArUcoDetector.swift`
- `DentalScanner/ScannerMVP/Pose/PoseEstimator.swift`
- `DentalScanner/ScannerMVP/OpenCV/OpenCVArucoPoseBridge.mm`
- `DentalScanner/ScannerMVP/Pose/PoseResult.swift`

`OpenCVArucoPoseBridge.mm::BuildMarkerObjectPoints` uses, in order:

```text
(-s/2, +s/2, 0)
(+s/2, +s/2, 0)
(+s/2, -s/2, 0)
(-s/2, -s/2, 0)
```

and `estimatePoseForCorners` calls `cv::solvePnP` with `SOLVEPNP_IPPE_SQUARE`. The bridge constructs `distCoeffs = zeros(1, 5)` for this path. The returned single pose is then used to compute the DentalScanner reprojection RMS and is stored as the `PoseResult`.

Targeted repository search found no current `solvePnPGeneric` use in `main`.

## Corner ordering

No corner-ordering defect was found in the inspected path.

`ArucoDetector.swift` preserves the corner array returned by OpenCV. Current OpenCV ArUco documentation states that detected corners are returned clockwise starting with the marker's top-left corner: top-left, top-right, bottom-right, bottom-left. The DentalScanner object-point order above is exactly the order documented for `SOLVEPNP_IPPE_SQUARE`.

Therefore, on the inspected code, point ordering is compatible with the documented `IPPE_SQUARE` contract.

## Persisted frame data

`ScannerViewModel.makeFrameObservation` and `FrameIndexedObservation.swift` persist, per marker observation:

- ordered image corners;
- ordered object points;
- rotation vector;
- explicit rotation matrix;
- translation vector;
- reprojection error;
- marker metadata.

Per frame they also persist:

- `frameIndex`;
- timestamp;
- image width/height;
- `fx`, `fy`, `cx`, `cy` when intrinsics are available.

This is sufficient to rerun the current planar PnP model offline for schema-1 `singleArucoV1` observations without rerunning detection or requiring camera images.

## Capture-maturity viewpoint path

`ScanSessionCaptureMaturityReplay.swift::CaptureMaturityViewpointMath.viewpoint` consumes the already selected/persisted `PoseResult` and defines:

```text
T_cm = camera-from-marker
p_c = R_cm * p_m + t_cm

C_m = -transpose(R_cm) * t_cm
viewDirection = normalize(C_m)
```

Distinct views are then selected from the angular distance between these per-marker directions. The current STRICT model uses a 1.5 degree distinct-view threshold and separately evaluates angular spread. The replay validates that rotations are finite, orthonormal and determinant +1, but it does not recover or inspect a second planar IPPE candidate.

`DentalScannerTests/ScanSessionCaptureMaturityReplayTests.swift` has direct tests for the `T_cm` convention, camera-center inversion, normalized view direction, angular distances, independent per-marker histories and distinct/redundant selection. Targeted inspection found no test of IPPE two-candidate ambiguity or candidate alternation.

# EVIDENCE FROM LITERATURE / DOCUMENTATION

## OpenCV 4.13.0 — Perspective-n-Point documentation

Source: OpenCV 4.13.0, `Perspective-n-Point (PnP) pose computation`.

URL: https://docs.opencv.org/4.13.0/d5/d1f/calib3d_solvePnP.html

Relevant findings:

- `solvePnP` estimates the object-to-camera transformation.
- OpenCV camera coordinates use +X right, +Y down, +Z forward.
- `SOLVEPNP_IPPE_SQUARE` is specifically intended for square marker pose and requires the same four object-point order used by DentalScanner.
- `solvePnPGeneric` can retrieve all possible solutions.
- `IPPE` and `IPPE_SQUARE` are among the methods that can return multiple solutions.

Applicability: direct. DentalScanner uses the documented `IPPE_SQUARE` method with the documented square point order.

## OpenCV 4.13.0 source — `modules/calib3d/src/solvepnp.cpp`

Source: OpenCV tag `4.13.0`.

URL: https://raw.githubusercontent.com/opencv/opencv/4.13.0/modules/calib3d/src/solvepnp.cpp

Relevant findings:

1. `cv::solvePnP` internally calls `solvePnPGeneric` and, when at least one solution exists, copies only `rvecs[0]` / `tvecs[0]` to its output.
2. In the `SOLVEPNP_IPPE_SQUARE` branch, OpenCV calls `IPPE::PoseSolver::solveSquare`, obtains two pose candidates and two reprojection errors, then pushes the lower-error candidate first and the other second.
3. Therefore the DentalScanner live call to `solvePnP(...IPPE_SQUARE)` receives only the first of the two sorted IPPE candidates.
4. The optional `solvePnPGeneric` `reprojectionError` output is computed as:

```text
L2_pixel_error / sqrt(2 * N)
```

whereas DentalScanner's current `ComputeRMSReprojectionError` is:

```text
sqrt(sum_i ||u_i - uhat_i||^2 / N)
```

For the same projections these differ by a factor of `sqrt(2)`. This distinction matters if a future diagnostic wrapper exposes `solvePnPGeneric` errors: the generic output must not be compared directly with DentalScanner's existing pixel-RMS thresholds as if it used the same definition.

Applicability: direct to the default OpenCV version targeted by the repository's OpenCV XCFramework workflow (`.github/workflows/build-opencv-xcframework.yml` defaults to `4.13.0`). The exact provenance of a particular already-built runtime XCFramework was not independently established in this investigation, so a future experiment should record the linked OpenCV version.

## OpenCV 4.13.0 — ArUco detection documentation

Source: OpenCV 4.13.0, `Detection of ArUco Markers`.

URL: https://docs.opencv.org/4.13.0/d5/dae/tutorial_aruco_detection.html

Relevant finding: for each detected marker, `markerCorners` are returned in original order, clockwise starting with top-left. The same documentation shows the square object coordinates used by the pose example.

Applicability: direct to the detector API used by DentalScanner and supports the conclusion that the current corner/object-point ordering is not the identified problem.

## Collins & Bartoli — Infinitesimal Plane-Based Pose Estimation

Source: Toby Collins and Adrien Bartoli, *International Journal of Computer Vision*, 109(3), 252-286, 2014, DOI `10.1007/s11263-014-0725-5`.

Peer-reviewed paper metadata / manuscript source:

- DOI: https://doi.org/10.1007/s11263-014-0725-5
- Author implementation: https://github.com/tobycollins/IPPE

Relevant finding from the algorithm/authors' implementation documentation: planar IPPE explicitly returns two candidate poses. Ambiguity becomes important when the projection approaches an affine/weak-perspective case, for example when a planar target is relatively small in the image or sufficiently distant. In that regime the two candidate projections can both agree with the image correspondences within noise, so reprojection error alone may not reliably identify the physical branch.

The authors also note that temporal filtering can reduce random switching but is not guaranteed to resolve the ambiguity, while additional geometric information/marker consensus can provide stronger constraints.

Applicability: direct at the mathematical problem level because DentalScanner estimates pose from four points on one square plane. It does **not** prove that the DentalScanner physical session actually experienced branch switching; that requires replay evidence.

# MATHEMATICAL IMPLICATION

## Coordinate systems and transform direction

For frame `i` and physical marker `j`:

- `M_j`: local coordinate frame of marker `j`.
- `C_i`: OpenCV optical camera frame for image `i`.
- camera axes: +X right, +Y down, +Z forward.
- marker object coordinates: millimeters.
- image coordinates: pixels.

The persisted PnP pose is:

```text
T_Ci_Mj = [ R_Ci_Mj  t_Ci_Mj ]
           [    0         1    ]
```

with:

```text
p_Ci = R_Ci_Mj * p_Mj + t_Ci_Mj
```

`R` is a proper rotation in SO(3). OpenCV exposes Rodrigues axis-angle as `rvec`; DentalScanner also stores the explicit 3x3 rotation matrix. Euler angles are not needed for the geometric reasoning.

Because marker coordinates are in millimeters, `t_Ci_Mj` is in millimeters.

The inverse pose is:

```text
T_Mj_Ci = inverse(T_Ci_Mj)
        = [ R_Ci_Mj^T   -R_Ci_Mj^T * t_Ci_Mj ]
          [     0                    1          ]
```

so the camera center expressed in marker coordinates is:

```text
C_Mj = -R_Ci_Mj^T * t_Ci_Mj
```

and the capture-maturity view direction is:

```text
d_Mj = C_Mj / ||C_Mj||
```

## Two planar candidates

For a schema-1 single-marker observation, diagnostic `solvePnPGeneric(..., SOLVEPNP_IPPE_SQUARE)` can return two candidates:

```text
T_Ci_Mj^(0)
T_Ci_Mj^(1)
```

Each candidate has its own camera center and view direction:

```text
C_Mj^(k) = -(R_Ci_Mj^(k))^T * t_Ci_Mj^(k)
d_Mj^(k) = normalize(C_Mj^(k))
```

The rotation separation between two candidate or temporal poses should be measured on SO(3), for example:

```text
DeltaR = R_a^T * R_b
angle_R = acos(clamp((trace(DeltaR) - 1) / 2, -1, 1))
```

reported in degrees only for diagnostics.

## Same-marker temporal camera motion

Under the rigid-fixture assumption, a marker can independently imply camera motion between adjacent frames:

```text
T_Ci_Cprev^(j) = T_Ci_Mj * inverse(T_Cprev_Mj)
```

If multiple rigid markers are observed in both frames, their implied `T_Ci_Cprev^(j)` should agree within measurement noise. A large motion that is coherent across markers is evidence of real camera motion and should **not** automatically be labeled a pose flip.

## Same-frame relative marker geometry

For markers `a` and `b` observed in the same frame:

```text
T_Ma_Mb^(i) = inverse(T_Ci_Ma) * T_Ci_Mb
```

For a rigid physical fixture this relative transform should be approximately constant across frames. Candidate assignments that cause isolated discontinuities in this relation are less consistent with the rigid-scene model.

This is an internal rigidity constraint, not ground truth of absolute trueness.

## Observability and ambiguity

A single planar square observed in one frame does not always provide enough information to distinguish two physically plausible branches robustly when perspective cues are weak relative to corner noise. A lower reprojection residual is therefore not sufficient proof that candidate 0 is the physically correct branch.

Additional information that can improve branch observability includes temporal continuity, simultaneously observed rigid markers, known relative geometry, non-coplanar features, or multi-view optimization. Each introduces assumptions that must be made explicit rather than treated as automatic truth.

# EVIDENCE

1. **EVIDENCE:** production `singleArucoV1` calls `cv::solvePnP(...SOLVEPNP_IPPE_SQUARE)` and receives one pose.
2. **EVIDENCE:** OpenCV 4.13.0's implementation computes two `IPPE_SQUARE` candidates in `solvePnPGeneric`, sorts them by IPPE reprojection error, and `solvePnP` returns only the first.
3. **EVIDENCE:** DentalScanner's current corner/object-point order matches the documented `IPPE_SQUARE` order. No ordering bug was found.
4. **EVIDENCE:** current capture maturity computes viewpoint from the one persisted `T_cm`; it does not model alternative planar candidates.
5. **EVIDENCE:** schema-1 observations already preserve the ordered 2D points, ordered 3D points and per-frame intrinsics required to reconstruct the same PnP problem offline.
6. **EVIDENCE:** current maturity tests cover transform/viewpoint math and view selection, but targeted inspection found no planar-candidate ambiguity/alternation test.
7. **EVIDENCE:** DentalScanner's reprojection RMS convention and OpenCV 4.13.0 `solvePnPGeneric` optional reprojection-error convention are not numerically identical; direct threshold reuse would be incorrect.

# INFERENCE

1. **INFERENCE:** capture maturity currently treats whatever branch `solvePnP` selected as an observed camera viewpoint. If the preferred IPPE branch changes because two candidate errors are nearly indistinguishable, the resulting change in `d_Mj` can be counted as geometric diversity even when part of that change is solver ambiguity rather than physical camera motion.
2. **INFERENCE:** the current schema is unusually well suited to falsifying this concern because it retains the exact point correspondences and intrinsics without requiring a new physical capture or any live-PnP modification.
3. **INFERENCE:** multi-marker temporal consensus is stronger than a single-marker smoothness prior for this investigation because it can preserve genuinely large coherent camera movements while penalizing isolated marker branch changes.
4. **INFERENCE:** the safest first experiment is diagnostic multi-candidate replay, not replacement of `PoseEstimator` or insertion of smoothing into production.

# HYPOTHESIS

1. **HYPOTHESIS:** some of the distinct viewpoints measured in the problematic physical session motivating Issue #2 are caused by alternation or near-alternation between the two `IPPE_SQUARE` pose branches.
2. **HYPOTHESIS:** selecting candidates with temporal + multi-marker rigid-motion consistency will reduce isolated pose reversals and may materially change the STRICT capture-maturity timeline and/or current-accumulator output for that same session.
3. **HYPOTHESIS:** the effect will be strongest in frames where the two candidates have similar pixel fit while their SE(3) separation is materially larger than ordinary adjacent-frame motion.

None of these hypotheses is established by the present code inspection.

# POTENTIAL BENEFIT

The proposed experiment could distinguish **real angular diversity** from diversity partially created by an ambiguous planar pose solver. If the hypothesis is supported, it would improve the semantic reliability of capture-maturity diagnostics and could prevent a future live maturity gate from rewarding solver branch changes as useful camera motion.

The experiment could also produce a reusable ambiguity diagnostic for future BA initialization: both candidate states could be retained until temporal/multi-marker evidence resolves them instead of irreversibly collapsing the ambiguity at the first per-frame solve.

This would not by itself demonstrate better trueness or 100 micrometer accuracy. Trueness still requires the ground-truth metrology program in Issue #8.

# RISKS / FAILURE MODES

- **Real motion mistaken for a flip:** a camera can genuinely move rapidly. Temporal smoothness alone must not reject a large jump when multiple markers imply the same camera motion.
- **Candidate labels are not identities:** candidate index 0 means lower IPPE reprojection error for that frame, not a persistent physical branch identity across time.
- **Reprojection is insufficient:** near-equal residuals are a sign of poor branch observability, not permission to choose either pose by a fixed residual rule.
- **Reprojection-unit mismatch:** OpenCV's `solvePnPGeneric` optional error output in 4.13.0 uses per-coordinate RMSE (`sqrt(2N)` denominator), while DentalScanner uses per-point Euclidean RMS (`sqrt(N)` denominator). Diagnostic code must recompute the existing DentalScanner metric for each candidate if values are compared with current reports/thresholds.
- **Positive depth is necessary but may not be sufficient:** candidate feasibility should record whether transformed object points satisfy positive camera-space depth, but positive depth alone may not disambiguate both plausible planar solutions.
- **No raw image in schema-1:** the experiment cannot re-evaluate corner localization, blur, rolling shutter or detection errors. This is a limitation but also isolates the PnP-branch question.
- **Distortion model is fixed by current behavior:** the live bridge passes zero distortion coefficients. The ambiguity experiment should reproduce that model to isolate branch selection. Whether zero residual distortion is itself optimal is a separate research question.
- **Unknown exact runtime OpenCV provenance:** the repository's XCFramework build workflow defaults to 4.13.0, but a captured session does not currently prove which binary version produced it. The experiment should record the runtime/build provenance when available.
- **Internal consistency is not trueness:** reduced temporal jumps or more constant marker-marker transforms can identify a more self-consistent branch sequence but cannot prove absolute geometric correctness without ground truth.

# PROPOSED OFFLINE EXPERIMENT

Implement only if the Orchestrator approves Issue #2 work. No live geometry should change.

## 1. Input population

Use one or more existing schema-1 `*_session.ndjson` files, beginning with the physical session that motivated Issue #2 if available.

For each `singleArucoV1` observation require:

- exactly four ordered image corners;
- exactly four ordered square object points;
- finite `fx`, `fy`, `cx`, `cy`;
- finite persisted pose;
- supported marker profile.

Preserve physical file/frame order. Do not sort observations into a new temporal order.

## 2. Reconstruct both IPPE candidates

For each eligible observation call diagnostic-only `solvePnPGeneric(..., SOLVEPNP_IPPE_SQUARE)` using the persisted points and intrinsics, with the same zero-distortion assumption as production.

Persist separately for each candidate:

- `R_cm`, Rodrigues `rvec`, `t_cm` in mm;
- camera center in marker coordinates;
- marker-to-camera view direction;
- positive-depth result for every object point;
- DentalScanner-style per-point pixel RMS recomputed with `projectPoints`;
- OpenCV generic error only as a separately named value if useful;
- rotation/translation difference between the two candidates;
- difference/ratio between candidate residuals without treating it as ground truth.

Also compare the persisted live pose with the reconstructed candidate set to establish which candidate it corresponds to within numerical tolerance.

## 3. Build deterministic selection modes

At minimum compare:

```text
RAW_PERSISTED
LOWEST_REPROJECTION_CANDIDATE
TEMPORAL_CONTINUITY
MULTI_MARKER_CONSENSUS
```

`RAW_PERSISTED` is the control and must use the original persisted pose exactly.

`LOWEST_REPROJECTION_CANDIDATE` is diagnostic only; it should reproduce the conceptual current OpenCV first-solution policy and must not be interpreted as physically correct.

`TEMPORAL_CONTINUITY` should use SE(3) continuity with `deltaTime`; it must record costs rather than silently rejecting observations.

`MULTI_MARKER_CONSENSUS` should compare the camera motion implied independently by all markers shared between adjacent frames. Do not give M0 special status. Large motions agreed upon by several markers should remain allowable.

If candidate evidence is insufficient, output `unavailable` rather than inventing a branch.

## 4. Re-run existing consumers

For each available mode:

1. re-run the existing Spec 20 capture-maturity core;
2. feed a fresh `MultiFramePoseAccumulator` with the selected per-frame observations;
3. verify same-file determinism;
4. generate diagnostic geometry/STL only if Issue #2's existing acceptance criteria require it.

Do not alter live progress, readiness, finalization, Pre-Gate blocking or normal export.

## 5. Analyze reversal patterns

A useful diagnostic event is not merely a large frame-to-frame delta. Classify separately:

- isolated large pose jump for one marker;
- immediate reversal toward the prior state;
- simultaneous coherent motion across multiple markers;
- frames where candidate residuals are close but candidate poses are far apart;
- periods where the persisted branch differs from the continuity/consensus branch.

Do not hard-code an ambiguity threshold from literature before inspecting the empirical distributions. Report continuous values first.

# SUCCESS METRIC

## For this Issue #2 experiment

Define success as obtaining deterministic evidence that can answer whether hidden planar candidates materially affect DentalScanner behavior.

Primary diagnostic measurements:

- fraction/count of eligible observations returning two finite IPPE candidates;
- fraction satisfying positive depth for candidate 0, candidate 1, both, neither;
- distribution of candidate-to-candidate SO(3) rotation separation;
- distribution of candidate-to-candidate translation/camera-center separation in mm;
- distribution of DentalScanner-style reprojection residual difference and ratio;
- rate at which continuity/consensus selects a different branch than `RAW_PERSISTED` / lowest reprojection;
- isolated-jump and immediate-reversal rates per marker;
- cross-marker disagreement of inferred `T_Ci_Cprev` before and after selection;
- same-frame relative marker transform variability before and after selection;
- change in Spec 20 selected-distinct-view count, angular spread and maturity timestamp/state;
- change in fresh-accumulator relative marker geometry;
- byte/delta-level determinism of repeated same-file runs where applicable.

A result is **experimentally important** if branch-aware modes materially change maturity or relative-geometry behavior while reducing isolated/multi-marker-incoherent discontinuities on the identical source frames. This is evidence that planar ambiguity is relevant to the pipeline, not proof that the selected branch is metrically true.

## Repeatability / reproducibility / trueness

- **Internal stability:** temporal and same-frame rigid-consistency metrics above.
- **Repeatability:** must later compare multiple physical sessions with an unchanged fixture.
- **Reproducibility:** must later include controlled remount/operator/device-condition variation as defined by the metrology plan.
- **Trueness:** requires Issue #8 ground truth with independently characterized uncertainty substantially below the target error. Neither lower reprojection nor a smoother trajectory is a trueness metric.

No 100 micrometer claim should be made from this replay alone.

# REPOSITORY IMPACT

If the experiment is approved later, likely diagnostic-only areas are:

- `DentalScanner/ScannerMVP/OpenCV/` — a separate diagnostic wrapper exposing all `IPPE_SQUARE` candidates; do not change the live estimator call path.
- `DentalScanner/ScannerMVP/Replay/` — candidate reconstruction, continuity/consensus replay and artifact generation.
- `DentalScannerTests/` — synthetic two-candidate, continuity, coherent-motion, reversal and deterministic replay tests.

Potentially reusable existing components:

- `ScanSessionSchemaV1Reader`;
- `ScanSessionCaptureMaturityReplay` core;
- `MultiFramePoseAccumulator` instantiated fresh for each replay mode.

No production `PoseEstimator`, live OpenCV behavior, readiness, finalization, ExportGate or STL export change is justified by this investigation.

# OPEN QUESTIONS

1. Does the physical session motivating Issue #2 actually contain frequent frames where the two IPPE candidates have similar image fit but materially different SE(3) poses?
2. Does the persisted production pose numerically match candidate 0 from the exact linked OpenCV build for essentially all eligible observations?
3. Are suspect jumps isolated to one marker or coherent across several simultaneously visible markers?
4. How much of the current 1.5 degree distinct-view population disappears when branch continuity/consensus is applied?
5. Does branch-aware selection improve same-frame rigid marker geometry without merely over-smoothing genuine camera motion?
6. What exact OpenCV build/version generated each historical physical session? Current session metadata may not make this fully auditable.
7. Separately from Issue #2, does the live zero-distortion assumption leave measurable residual systematic error on the iPhone camera stream? This should be a distinct investigation so it does not confound planar-candidate analysis.

# RECOMMENDATION

EXPERIMENT

The code and OpenCV implementation establish a real observability gap: a mathematically two-candidate `IPPE_SQUARE` result is collapsed to one pose before DentalScanner computes viewpoint diversity. The existing schema already contains enough information for a small deterministic offline test, so there is no justification for changing live PnP first. Whether this gap actually caused the problematic physical behavior remains a hypothesis until the two candidates are replayed on the recorded session.

# PROPOSED ISSUE CHANGE

Issue #2 already covers the correct experiment and does not need a new Issue. Suggested clarification for its acceptance criteria, if the Orchestrator later chooses to edit it:

```text
- Recompute candidate reprojection using the existing DentalScanner per-point pixel RMS convention; do not compare OpenCV solvePnPGeneric's optional per-coordinate RMSE directly with current DentalScanner thresholds.
- Persist both candidate SE(3) poses, positive-depth status, candidate separation, and all continuity/consensus costs before selection.
- Verify current ArUco/IPPE point ordering in a test and verify the persisted live pose against the reconstructed candidate set.
```
