AGENT_ROLE: red-team
DATE_UTC: 2026-09-12
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED: 4b223ae57627ee316191e03cddde8fd8a580a097
RELATED_ISSUE: none
REPORT_STATUS: complete

# TARGET

Independent adversarial review of two cross-cutting questions:

1. Which external libraries, tools or techniques could materially improve DentalScanner precision, robustness, debugging or validation?
2. Is a 100 um target technically plausible for the current DentalScanner concept, or is the project over-optimistic?

Directly related Issues inspected: #2, #8, #9, #15, #19, #25 and #26. Issue #4 was also inspected because Ceres/Bundle Adjustment is a concrete candidate discussed in this review.

Recent AI Intelligence Bridge reports were read only as potentially stale inputs, not as evidence of current behavior:

- `ai/inbox/research/2026-09-10_issue-2_ippe-planar-ambiguity.md`
- `ai/synthesized/2026-09-10_issue-2_decision.md`
- `ai/inbox/research/2026-09-10_issue-8_metrology-validation-protocol.md`
- `ai/synthesized/2026-09-10_issue-8_decision.md`
- `ai/inbox/red-team/2026-09-10_issue-8_metrology-protocol.md`

The review deliberately attempted to refute prior conclusions before accepting them.

# CURRENT CODE CHECK

`main` was rechecked immediately before publication and remains:

`4b223ae57627ee316191e03cddde8fd8a580a097` — `Fix capture maturity replay compilation`.

Production/config/test files inspected include:

- `AGENTS.md`
- `Project.swift`
- `.github/workflows/build-opencv-xcframework.yml`
- `DentalScanner/ScannerMVP/OpenCV/OpenCVArucoPoseBridge.mm`
- `DentalScanner/ScannerMVP/Vision/ArUcoDetector.swift`
- `DentalScanner/ScannerMVP/Pose/PoseEstimator.swift`
- `DentalScanner/ScannerMVP/Pose/FinalPoseRefiner.swift`
- `DentalScanner/ScannerMVP/Pose/CameraIntrinsics.swift`
- `DentalScanner/ScannerMVP/Pose/MarkerProfile.swift`
- `DentalScanner/ScannerMVP/Pose/MarkerToImplantTransform.swift`
- `DentalScanner/ScannerMVP/Camera/CameraFrame.swift`
- `DentalScanner/ScannerMVP/Camera/CameraFrameService.swift`
- `DentalScanner/ScannerMVP/Camera/FrameSharpnessAnalyzer.swift`
- `DentalScanner/ScannerMVP/Diagnostics/FrameIndexedObservation.swift`
- `DentalScanner/ScannerMVP/Replay/ScanSessionReplay.swift`
- `DentalScanner/ScannerMVP/Export/STLExporter.swift`
- `DentalScannerTests/ScanSessionReplayTests.swift`
- `DentalScannerTests/ScanSessionCaptureMaturityReplayTests.swift`
- `DentalScannerTests/ScanSessionReplaySTLComparisonTests.swift`
- `specs/13_camera_resolution_focus_intrinsics.md`
- `specs/14_marker_v3_and_robust_pnp.md`
- `specs/15_validation_protocol_and_accuracy.md`
- `research/reference_scanner_pipeline_findings.md`

EVIDENCE: the repository currently builds OpenCV 4.13.0 by default through its XCFramework workflow. `Project.swift` has no Ceres, mrcal, Rerun, external AprilTag or STag dependency.

EVIDENCE: frame-indexed schema-1 replay is already implemented. A complete replay observation contains `frameIndex`, frame dimensions, per-frame `fx/fy/cx/cy`, ordered image corners, ordered object points, persisted `T_cm`, marker identity and quality annotations. Replay tests explicitly preserve physical frame/marker order and use fresh accumulators to verify determinism.

EVIDENCE: raw camera images are not part of schema-1. Therefore PnP/candidate experiments can be rerun from existing NDJSON, but corner-detection/refinement and ROI-sharpness experiments cannot be reconstructed from NDJSON alone.

# CONFIRMED

## 1. Current ArUco corners are refined twice for many markers

`OpenCVArucoPoseBridge.mm` configures:

```cpp
parameters.cornerRefinementMethod = cv::aruco::CORNER_REFINE_SUBPIX;
parameters.cornerRefinementWinSize = 5;
parameters.cornerRefinementMaxIterations = 30;
```

After `ArucoDetector::detectMarkers`, the code then calls its own `RefineMarkerCornersSubpixel`, which invokes:

```cpp
cv::cornerSubPix(... Size(5,5), ..., TermCriteria(..., 30, 0.01));
```

for markers whose four corners are at least a 5-pixel window away from the image border.

This is genuine duplicated use of the SUBPIX family, not merely similar naming.

However, the two passes are not identical. OpenCV's detector refinement can reduce its final window dynamically from `cornerRefinementWinSize` according to marker module size, while the manual second pass uses a fixed 5-pixel window. The detector also has its own refinement stop-accuracy parameter; the bridge does not override it, whereas the manual pass uses `0.01`.

OpenCV documentation explicitly warns that an overly large refinement window may include nearby image corners and move the marker corner to an incorrect location.

INFERENCE: the manual second pass is plausibly redundant and may sometimes be beneficial, neutral or harmful. It is not safe to label it a confirmed accuracy bug or to remove it without an image-ground-truth A/B.

REJECTED CLAIM: `SUBPIX + cornerSubPix` does not by itself prove that current corners are worse.

## 2. The current single-ArUco PnP is a one-solution use of an intrinsically multi-solution planar problem

For `singleArucoV1`, object points are the four square corners in the ordering required by `SOLVEPNP_IPPE_SQUARE`. Production then calls `cv::solvePnP(... SOLVEPNP_IPPE_SQUARE)` and persists one `T_cm`.

OpenCV's official documentation states that `solvePnPGeneric()` can return both solutions for `IPPE_SQUARE`.

Current Issue #2 contains physical-session evidence that this matters for DentalScanner: 3554/3554 tested observations produced two candidates, with large candidate-to-candidate separations and multiple temporal/multi-marker inconsistencies in the persisted sequence. The persisted pose corresponded essentially to the first candidate.

EVIDENCE: planar candidate ambiguity is therefore not merely a literature concern; it is relevant to current DentalScanner data.

EVIDENCE: no current production code uses `solvePnPGeneric` to retain both IPPE candidates.

INFERENCE: candidate-aware offline replay deserves high priority because it addresses a demonstrated failure mode and requires no new third-party dependency.

HYPOTHESIS: temporal/multi-marker candidate selection can reduce catastrophic branch errors. It still does not prove which branch is physically true without synthetic/physical ground truth.

## 3. `solvePnPRefineVVS` is not an obvious replacement for the current v1 path

The OpenCV bridge has `solvePnPRefineLM`, while OpenCV also offers `solvePnPRefineVVS`. Official documentation says LM and VVS use different nonlinear updates; VVS applies the rotation update through an exponential-map formulation on SO(3).

But current `singleArucoV1` production bypasses the legacy final concatenated multi-frame PnP path. The bridge LM refinement is relevant to the multi-point/dual path, not the active four-corner v1 finalization path being investigated in #2.

REJECTED CLAIM: the existence of a more geometrically elegant SO(3) update does not establish better DentalScanner trueness, and VVS-vs-LM is not currently the highest-value v1 experiment.

## 4. Zero `distCoeffs` is real, but it is not a proven bug

Both the current IPPE solve and bridge pose refinement create a five-value zero distortion vector before OpenCV PnP/projection.

At the same time, `CameraFrameService` enables AVFoundation camera-intrinsic delivery when supported and reads `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix` from each actual sample buffer. Apple documents that attachment as the 3x3 camera intrinsic matrix applied to the current sample buffer/current imaging parameters.

Apple also documents `AVCaptureDevice.isGeometricDistortionCorrectionEnabled` and states that, on devices supporting geometric distortion correction, its default is `true`.

DentalScanner does not currently query/persist this GDC state, nor does it consume `AVCameraCalibrationData` lens-distortion lookup tables in this video pipeline. No explicit app-side image undistortion was found.

EVIDENCE: the current production measurement model is therefore: use the delivered video pixel buffer with its delivered per-sample `K`, and assume any remaining distortion is negligible for pose estimation.

EVIDENCE: Apple exposes separate lens-distortion calibration data APIs, proving that an intrinsic matrix by itself is not a full generic lens-distortion model.

INFERENCE: system geometric distortion correction may already remove a large part of the lens warp, so `distCoeffs = 0` cannot be declared incorrect from source inspection alone.

MISSING EVIDENCE: there is no DentalScanner measurement showing that residual spatial distortion after the actual AVFoundation pipeline is below the error budget required for a 100 um claim across field position, zoom/profile and lens position.

REJECTED CLAIM: do not inject OpenCV distortion coefficients into production merely because the vector is currently zero.

RECOMMENDATION: first perform an independent holdout calibration/residual-field experiment using the exact video profile. Promotion of any distortion model should require improvement of physical/ground-truth pose error, not merely calibration-set reprojection.

## 5. Current sharpness is global, not marker-local

`FrameSharpnessAnalyzer` computes a subsampled variance-of-Laplacian-like score over the frame. The sampling is global rather than localized around each marker/corner.

`MarkerFrameObservation` has a `focusVariance` field, but the current `ScannerViewModel` path writes it as `nil`; only a categorical focus state is persisted there.

EVIDENCE: the current pipeline does not have a per-marker/per-corner sharpness metric equivalent to the proposed ROI-local idea.

INFERENCE: a background-rich frame can in principle score acceptably even when a small marker region is blurrier, particularly for a 6.9 mm target at 150-180 mm.

HYPOTHESIS: ROI-local sharpness could be a better predictor of corner/PnP failure than the global score.

It should remain diagnostic until a fixed-image dataset proves predictive value. Higher sharpness alone is not precision evidence.

## 6. The physical scale/datum model is a first-order 100 um risk

Current normal v1 marker size is `6.9 mm`.

Monocular planar pose scale is directly tied to object-point scale. In the simple fronto-parallel approximation:

```text
p ~= f*s/Z
Z ~= f*s/p
```

so to first order:

```text
relative depth scale error ~= relative focal error
                           + relative physical marker-size error
                           - relative measured pixel-size error
```

At `Z = 165 mm`, allocating the full `0.100 mm` depth error budget to physical marker size would require the effective 6.9 mm marker side to be known to roughly:

```text
6.9 * 0.100 / 165 ~= 0.00418 mm ~= 4.2 um
```

This is not claimed as a complete error budget; it demonstrates sensitivity. Print scale, border/corner realization, lamination, cut, mounting and flatness therefore cannot be treated as manufacturing trivia at a 100 um system target.

EVIDENCE: Issue #8 now correctly states that a virtual ArUco origin is not ground truth unless it is physically realized or connected to measurable datums through a characterized transform.

EVIDENCE: the current `MarkerToImplantTransform` configured in `ScannerViewModel` is identity. That is a software convention, not evidence that the physical marker origin equals implant center/axis within 100 um.

## 7. Current STL is not an independent scanned dental surface

`STLExporter` loads a bundled reference marker model and transforms copies according to estimated marker/implant poses. The resulting STL therefore inherits pose, reference-model and marker-to-implant/datum assumptions. It is not an independently reconstructed optical dental surface.

REJECTED CLAIM: a visually better or lower-distance DentalScanner STL cannot independently prove surface-scanner accuracy.

A future `surface/STL <=100 um` claim must first define exactly which physical surface is measured, its reference, datum/registration policy and whether best-fit alignment is allowed.

## 8. Some old repository/reference status descriptions are stale

`research/reference_scanner_pipeline_findings.md` still contains a state table describing frame-indexed observations and deterministic replay as not implemented/partial. Current `FrameIndexedObservation.swift`, `ScanSessionReplay.swift` and replay tests contradict that status.

This does not invalidate the document's conceptual warning about preserving frame identity; it does mean its project-status table must not be used as current evidence.

Likewise, the prior red-team report on Issue #8 is partly superseded: current Issue #8 now contains the stronger requirements on measurands, uncertainty, pilot-vs-confirmatory sample size, remount terminology, failure accounting and separate implant/surface claims that the old report requested.

# CONTRADICTIONS / CLAIMS REJECTED

The following claims should not be carried forward as facts:

1. **`The second cornerSubPix is definitely a bug.`** Rejected. Duplicate SUBPIX is confirmed; effect is unknown until A/B.
2. **`CORNER_REFINE_APRILTAG is automatically more accurate.`** Rejected. It is an OpenCV option worth benchmarking; no DentalScanner evidence yet.
3. **`External AprilTag 3 is the same thing as CORNER_REFINE_APRILTAG.`** Rejected. OpenCV's corner refinement is a refinement mode based on the AprilTag approach; AprilTag 3 is a separate full detector/tag ecosystem.
4. **`Zero distCoeffs means AVFoundation geometry is wrong.`** Rejected. Per-sample K is correctly consumed and system GDC may be active; residual distortion remains an unmeasured hypothesis.
5. **`ChArUco calibration should replace Apple intrinsics.`** Rejected. The immediate use is independent characterization/cross-validation, not blind replacement.
6. **`VVS is superior to LM because it uses SO(3).`** Rejected. Better parameter update mathematics is not physical-accuracy evidence, and LM is not the main current v1 path.
7. **`Ceres covariance would give a trustworthy 100 um confidence bound.`** Rejected. Ceres covariance is conditional on the chosen residual/noise/model and gauge; it does not include unknown marker scale, distortion, branch ambiguity, marker-to-implant transform or other model bias unless those are explicitly modeled.
8. **`Bundle Adjustment can solve calibration/marker-scale bias.`** Rejected. With fixed biased intrinsics/object geometry, BA can converge to a low-residual but metrically biased solution.
9. **`Fisher information proves trueness.`** Rejected. FIM/covariance is a local observability/noise-sensitivity tool; it does not cover discrete IPPE branch errors or unmodeled systematic effects.
10. **`Rerun improves precision.`** Rejected. It can improve human debugging and failure localization, not physical accuracy by itself.
11. **`Smartphone hardware makes 100 um impossible.`** Rejected by current literature: a 2026 controlled in-vitro study using PIC APP on iPhone 16 Pro reported smartphone-photogrammetry CRMS trueness around 54.8 um.
12. **`That smartphone study proves DentalScanner can achieve 100 um.`** Rejected. The detector, physical optical markers, calibration/workflow, device variant, estimator and measurement model are not equivalent to current DentalScanner v1.

# MATHEMATICAL / GEOMETRIC REVIEW

## Coordinate convention

Current project tests explicitly validate:

```text
T_cm = camera-from-marker
p_c = R_cm * p_m + t_cm
C_m = -R_cm^T * t_cm
```

No Euler-angle reasoning is needed or recommended. Internal rotations remain radians; reported angular metrics may be degrees. Translation/object geometry are millimetres; image residuals/corners/intrinsics are pixels.

## Frame identity

`frameIndex` is persisted and replay reader tests verify increasing frame identity and original marker order. This is sufficient foundation for offline multi-candidate PnP, information analysis and later frame-indexed BA. Timestamp remains metadata, not identity.

## Gauge/connectivity

Pairwise marker geometry is naturally invariant to a global rigid gauge. No M0 special case is justified. Future BA must fix exactly one gauge or otherwise handle the null space explicitly; disconnected states must never receive identity as a fake initializer.

## Apparent marker size and subpixel requirement

The repository does not contain the physical session NDJSON used in Issue #2, so the current empirical marker-side distribution in pixels cannot be independently recomputed from Git history alone. The schema already persists corners, area and K, so this question can be answered offline from the existing external session artifacts without taking new scans.

For a sensitivity illustration at `Z=165 mm`, if the marker side appears as `p` pixels, keeping only the effective pixel-size contribution below 0.100 mm requires approximately:

```text
|delta p| <= p * 0.100 / 165
```

Examples:

| apparent side p | approximate effective side error for 0.100 mm depth contribution |
|---:|---:|
| 50 px | 0.030 px |
| 60 px | 0.036 px |
| 80 px | 0.048 px |
| 100 px | 0.061 px |
| 150 px | 0.091 px |

These are first-order sensitivity values, not requirements on each individual corner. Multi-corner/multi-frame estimation can reduce random noise. Systematic corner bias, marker-size error and calibration bias do not average away in the same way.

INFERENCE: merely saying `subpixel corners` is not enough for a 100 um argument. Depending on actual apparent size and geometry, the effective corner/edge localization regime may need to be on the order of a few hundredths of a pixel for one error component to remain comfortably below 100 um.

The first action should be to compute the real `p`, K and Jacobian/sensitivity distributions from already captured schema-1 data.

## Calibration bias sensitivity

In the same simple scale approximation, `delta Z / Z ~= delta f / f`. At `Z=165 mm`, a 0.100 mm total depth error corresponds to only about `0.0606%` relative scale. Per-frame Apple K is valuable because it follows current imaging parameters, but no current evidence demonstrates residual projection-model bias below this level over the field of view.

## Planar ambiguity

The Issue #2 evidence includes candidate separations of tens of degrees and large camera-center differences while reprojection differences can be small. This is a discrete failure mode, not a small Gaussian perturbation.

INFERENCE: no amount of reporting a smaller single-solution reprojection RMS can establish that the correct planar branch was selected.

## BA: what it can and cannot fix

A geometrically correct frame-indexed BA can potentially improve:

- joint consistency across frames;
- random corner noise aggregation;
- shared-marker pose estimation;
- camera/marker state consistency;
- diagnostics of residual distribution;
- robustness when paired later with validated selection/outlier handling.

It cannot automatically fix:

- wrong physical marker scale;
- unknown marker-to-implant transform;
- systematic corner bias shared across frames;
- unmodeled residual lens distortion;
- biased intrinsics/object geometry;
- a wrong/discrete branch initialization in every relevant observation;
- poor physical datum realization;
- lack of ground truth.

A BA that lowers reprojection while worsening ground-truth geometry must be classified as worse.

## Orientation and the meaning of 100 um

A linear threshold does not define an angular threshold. A small-angle orientation error produces approximately `L*theta` lateral displacement at lever arm `L`.

For a 0.100 mm displacement budget:

| lever arm | corresponding small-angle error |
|---:|---:|
| 10 mm | ~0.573 deg |
| 20 mm | ~0.286 deg |
| 30 mm | ~0.191 deg |

The 2026 iPhone 16 Pro smartphone-photogrammetry study reported about `0.54 deg` angular deviation despite good linear CRMS/BRMS results. This is a concrete warning that excellent centroid/linear metrics do not imply an implant-axis endpoint error below 100 um for realistic lever arms.

# EXTERNAL TOOLS / TECHNIQUES REVIEW

## A. OpenCV corner-refinement modes: NONE / SUBPIX / CONTOUR / APRILTAG

**Concrete problem:** corner localization is a high-leverage input to 4-corner planar PnP; current code also performs a second fixed-window SUBPIX pass.

**Problem exists?** Yes: duplicated SUBPIX is confirmed and there is no comparative ground-truth test.

**Equivalent already present?** All four refinement modes are available inside the current OpenCV dependency; no new library is required.

**Simpler solution:** benchmark exact current behavior against detector-only SUBPIX before changing libraries.

**Maturity/license/iOS:** OpenCV is mature, already integrated as Objective-C++, current project version 4.13.0, Apache-2.0. No new app dependency or material app-size change for switching an existing enum.

**Determinism:** fixed image/config/version should be deterministic enough for test purposes; verify byte/numeric repeatability explicitly.

**Parallel-geometry risk:** low if used only to produce alternative corners for the same existing PnP model; high if promoted live without benchmark.

**Precision vs diagnostic:** could improve physical precision if it reduces true corner error; could also worsen it. Lower reprojection alone is insufficient.

**Decision:** BENCHMARK NOW, offline/synthetic/fixed-image first. Do not switch production yet.

## B. `solvePnPGeneric` + both IPPE solutions

**Concrete problem:** demonstrated planar branch ambiguity/discontinuity in current physical session.

**Problem exists?** Yes, with direct project evidence.

**Equivalent already present?** OpenCV already provides the function; schema-1 has K, corners and object points needed to reconstruct candidates offline.

**Simpler solution:** diagnostic wrapper/replay; no new solver dependency.

**Maturity/license/iOS:** same existing OpenCV integration/license/app size.

**Determinism:** deterministic fixed-input candidate generation should be verified numerically and by persisted candidate ordering, but selection policy must not rely on undocumented incidental ordering.

**Parallel-geometry risk:** moderate. Candidate selection can become a second PnP policy; keep it replay-only until synthetic/ground-truth tests.

**Precision vs diagnostic:** high potential robustness value; not proof of trueness.

**Decision:** HIGHEST-PRIORITY GEOMETRIC BENCHMARK; aligns with Issue #2.

## C. `solvePnPRefineVVS` vs `solvePnPRefineLM`

**Concrete problem:** local nonlinear pose refinement formulation.

**Problem exists?** No evidence that LM is the limiting error source for current single-v1 production; that path is bypassed there.

**Equivalent present?** LM exists in the bridge; VVS exists in OpenCV.

**Simpler solution:** resolve branch ambiguity/corner/calibration first.

**Maturity/license/iOS:** existing OpenCV; no dependency cost.

**Determinism:** straightforward fixed input.

**Parallel-geometry risk:** low offline, but poor priority can distract from larger failure modes.

**Precision vs diagnostic:** possible small local optimization difference; unlikely to solve discrete branch/model bias.

**Decision:** DEFER for v1; later benchmark for multi-point/v2 if residual GT error remains after higher-priority work.

## D. ChArUco for independent camera calibration

**Concrete problem:** determine whether Apple per-sample K + zero distortion leaves systematic projection bias under the exact DentalScanner video pipeline.

**Problem exists?** Residual distortion/calibration bias is unmeasured, not proven.

**Equivalent present?** Apple per-sample K is already used. ChArUco would be an independent characterization route, not a replacement by default.

**Simpler solution:** use current OpenCV ChArUco support on an accurately fabricated target and holdout frames; no new library.

**Maturity/license/iOS:** OpenCV documents ChArUco as a high-precision calibration option and recommends ChArUco corners over standard ArUco corners for camera calibration. Same Apache-2.0 dependency already in app/toolchain.

**Determinism:** calibration dataset/order/profile/version must be frozen; use holdout/cross-session evaluation.

**Parallel-geometry risk:** moderate if a new K/D silently replaces Apple K; low if strictly offline characterization.

**Precision vs diagnostic:** potentially identifies a real systematic limit; by itself does not prove production improvement.

**Decision:** BENCHMARK NOW as offline calibration characterization, especially before blaming PnP or adding rich camera models.

## E. mrcal

**Concrete problem:** more rigorous camera-model cross-validation and projection-uncertainty analysis if simple OpenCV calibration reveals spatial residuals/model inadequacy.

**Problem exists?** Unknown until the simpler ChArUco/holdout experiment is run.

**Equivalent present?** OpenCV already calibrates and reports residual/error; mrcal adds richer model/uncertainty/cross-validation tooling.

**Simpler solution:** OpenCV ChArUco first.

**Maturity/license:** established calibration/SfM toolkit from the Caltech/JPL ecosystem; Apache-2.0. Current distribution strongly favors Linux; macOS arm64 support exists, but it is not a natural iOS runtime dependency.

**Compatibility/build:** C/Python tooling with nontrivial native dependencies. Best used as desktop/offline analysis, not linked into the iOS app.

**Determinism:** pin version/config/data/order and verify; optimization/cross-validation outputs are analysis artifacts, not live state.

**App size:** zero if used offline; undesirable/unknown increase if forced into iOS.

**Parallel-geometry risk:** high if adopted as a second live camera model; low as independent calibration oracle.

**Precision vs diagnostic:** valuable for diagnosing calibration uncertainty/model inadequacy; its projection uncertainty is conditional and does not cover every source of blur, synchronization or model error.

**Decision:** CONDITIONAL BENCHMARK LATER. Use only if OpenCV/Apple-vs-holdout results show a calibration-model problem that simpler tools cannot explain.

## F. Ceres Solver + covariance

**Concrete problem:** future frame-indexed joint optimization (#4) and model-conditional covariance/observability diagnostics.

**Problem exists?** Joint optimization is not yet implemented; the current architectural gap is real but not proven to be the dominant accuracy limit.

**Equivalent present?** No BA backend in current production. The project already has deterministic frame-indexed data/replay and a mathematically specified BA experiment.

**Simpler solution:** synthetic residual/Jacobian/FIM tests and Issue #2 first; do not add Ceres just to get a covariance number.

**Maturity/license/iOS:** Ceres is mature, BSD-licensed, officially portable to iOS, and built for nonlinear least squares/BA. Current releases require C++17 plus Eigen/Abseil; optional sparse dependencies increase packaging complexity.

**Build/maintenance/app size:** materially higher than current project. Exact binary-size impact must be measured on a pinned minimal build; do not assume it is negligible.

**Determinism:** configure/pin solver and ordering; multi-thread floating reductions may need tolerance-based rather than byte-exact assertions. Current Issue #4 appropriately requires deterministic behavior.

**Parallel-geometry risk:** high if it becomes a new production truth before adapter/gauge/GT validation.

**Covariance caveat:** official Ceres covariance assumes the residual covariance model supplied by the user and requires correct handling of rank deficiency/gauge. It is not a physical trueness certificate.

**Decision:** APPROPRIATE FOR ISSUE #4 SYNTHETIC/OFFLINE WORK, but not justified as a shortcut around #2/#8/calibration. Covariance should come after the residual/noise/gauge model is validated.

## G. Rerun

**Concrete problem:** visualize replay over time: marker/camera transforms, candidate branches, residuals, frame identity and quality signals.

**Problem exists?** Current JSON/debug-panel artifacts are rich but difficult to inspect spatiotemporally.

**Equivalent present?** Existing replay JSON/STLs and debug panel provide data, not an equivalent interactive timeline/3D visualizer.

**Simpler solution:** CSV/JSON + small plotting scripts may answer many scalar questions first.

**Maturity/license:** active open-source project, SDK/viewer dual MIT/Apache-2.0. Official SDKs are Python, C++ and Rust; no first-class Swift SDK was identified.

**Compatibility/build/app size:** do not link it into the iOS app. A desktop Python converter from DentalScanner NDJSON to Rerun recording keeps app size/geometry unchanged.

**Determinism:** viewer is not an oracle; persist deterministic source artifacts and treat visualization as derived.

**Parallel-geometry risk:** very low if read-only/offline.

**Precision vs diagnostic:** diagnostic only, but could materially shorten debugging of branch/continuity/connectivity failures.

**Decision:** OPTIONAL/HIGH-VALUE DEBUG TOOL if current plots become a bottleneck; not a precision dependency and not required before Issue #2 core metrics.

## H. Xcode ASan / TSan / UBSan / Main Thread Checker

**Concrete problem:** memory corruption, Objective-C++/C++ UB, races and thread misuse can create intermittent wrong/crashing behavior in camera/replay code.

**Problem exists?** No specific memory/race bug is confirmed by this review, but the project mixes Swift, Objective-C++, OpenCV, camera queues and shared diagnostics.

**Equivalent present?** No equivalent checks were found in the current CI files inspected.

**Simpler solution:** use Apple's built-in sanitizers rather than adding a third-party dependency.

**Maturity/license/iOS:** first-party Xcode/LLVM diagnostics. Apple documents ASan, TSan, UBSan and Main Thread Checker; UBSan is C-based-language only. Sanitizers add substantial runtime overhead and are testing tools, not production configuration.

**Determinism:** sanitizers perturb memory/timing and therefore must not be used as performance baselines; a clean sanitizer run is a robustness check.

**App size:** no release-app dependency when confined to test configurations.

**Precision vs diagnostic:** robustness only; they do not make geometry more accurate.

**Decision:** WORTH ADDING TO DEV/CI STRATEGY where compatible, especially Objective-C++ bridge tests; separate from precision experiments.

## I. Instruments / `OSSignposter` / MetricKit

**Concrete problem:** dropped frames, processing latency, thermal/performance pressure and focus/camera timing may indirectly change which observations survive.

**Problem exists?** The app already records processing/drop diagnostics but does not expose every stage as Instruments signpost intervals.

**Equivalent present?** Partial internal timing/diagnostics exist.

**Simpler solution:** add targeted signposts around detect/PnP/replay stages if a performance question requires them.

**Maturity/compatibility:** first-party Apple. `OSSignposter` integrates directly with Instruments. MetricKit/MetricManager provides aggregated real-device performance/diagnostic reports.

**Determinism/app size:** signposts/MetricKit are observational; minimal dependency risk. Field metrics are not deterministic geometry inputs.

**Precision vs diagnostic:** diagnostic/performance only. MetricKit is especially low priority before there is deployed field usage that cannot be characterized with controlled captures.

**Decision:** Instruments/signposts are useful now when performance/FPS is under test; MetricKit is DEFERRED as a precision initiative.

## J. External AprilTag 3

**Concrete problem:** potentially improve small-tag detection/corner robustness or enable a different fiducial design.

**Problem exists?** Small planar marker/corner quality is a plausible limitation, but there is no evidence that ArUco decoding itself is the dominant failure. Current demonstrated failure is planar pose ambiguity, which a different decoder alone does not guarantee to solve.

**Equivalent present?** OpenCV already offers `CORNER_REFINE_APRILTAG` without replacing the ArUco marker family/detector.

**Simpler solution:** benchmark OpenCV refinement modes first and complete #15 v1-vs-v2 evidence.

**Maturity/license:** AprilTag 3 is active, mature in robotics, BSD-2-Clause, C library with minimal dependencies; current package metadata is 3.4.5.

**iOS/build/app size:** technically portable C, but the project would own another native detector build, marker family and validation path. Exact binary impact is unmeasured.

**Determinism:** likely stable for fixed pixels/config/version, but must be benchmarked/pinned.

**Parallel-geometry risk:** high. It could create a second detector/pose stack and require new physical assets/calibration without proving the current bottleneck.

**Precision vs diagnostic:** could eventually improve detection/corner quality; currently unproven.

**Decision:** DEFER. Do not add to iOS until OpenCV-only corner/PnP/calibration experiments identify a gap it specifically addresses.

## K. STag

**Concrete problem:** alternative stable fiducial/ellipse-based marker design may improve pose robustness in some regimes.

**Problem exists?** No DentalScanner evidence points specifically to STag's design as the required solution.

**Equivalent present?** No, but #15 intentionally requires benchmarking current marker v1/v2 before a new marker system.

**Simpler solution:** complete current marker/corner/calibration benchmarks and synthetic #26 first.

**Maturity/license:** original STag code is MIT-licensed, but its own repository states that it is no longer actively maintained and points to a newer fork/package.

**iOS/build/app size:** another C++/OpenCV-based detector and physical marker ecosystem; integration and long-term maintenance are project-owned.

**Parallel-geometry risk:** high.

**Precision vs diagnostic:** may improve a future marker design, but there is no basis today to expect it to beat a properly characterized existing system on the relevant measurands.

**Decision:** DEFER/REJECT FOR CURRENT ROADMAP. If ever tested, begin desktop/synthetic and only after #15 justifies leaving current marker families.

## L. ROI-local sharpness

**Concrete problem:** global sharpness may not describe the small image region that controls marker corners.

**Problem exists?** Yes: current metric is global and no numeric per-marker focus variance is persisted.

**Equivalent present?** Frame mask/area/focus-state diagnostics exist but are not equivalent to local image-frequency/edge quality around marker corners.

**Simpler solution:** implement/benchmark a local metric with existing image data before any external blur-quality library.

**Maturity/license/build:** no new dependency needed; existing OpenCV/Accelerate operations are sufficient.

**Determinism/app size:** deterministic fixed pixels; negligible incremental app size if eventually used.

**Parallel-geometry risk:** low while diagnostic; high if it becomes a hard gate without evidence because it can destroy viewpoint/connectivity.

**Precision vs diagnostic:** initially diagnostic. It can improve precision only indirectly if validated selection/weighting removes truly bad corner observations without losing needed geometry.

**Decision:** BENCHMARK NOW under Issue #9, shadow only.

# 100 UM VIABILITY ASSESSMENT

The single phrase `100 um accuracy` is too ambiguous. The following must remain separate.

## Repeatability

**Classification:** PLAUSIBLE BUT NOT DEMONSTRATED for marker-pair geometry under controlled bench conditions.

Why: deterministic replay and multi-frame aggregation exist, and dedicated dental photogrammetry systems routinely report tens-of-micrometre repeatability/trueness in controlled studies. But current DentalScanner has not yet run the calibrated #8 benchmark and the known IPPE branch discontinuities can dominate some sessions.

## Mean dimensional bias / trueness

**Classification:** IMPOSSIBLE TO ASSESS UNTIL #8 GROUND TRUTH, despite physical plausibility.

Current repeatability/reprojection cannot reveal systematic marker-size, camera-model, datum or physical-holder bias. Current Issue #8 correctly requires reference value + uncertainty + datum realization.

## Individual-scan error

**Classification:** UNLIKELY TO BE DEFENSIBLE AT <=100 UM WITH CURRENT V1 PIPELINE AS-IS, but not shown to be physically impossible.

Reason: at least one physical session contains large planar-pose discontinuities; marker-size realization, residual distortion and marker-to-implant transform are not characterized at the required scale. A single catastrophic branch error violates an individual-scan claim regardless of average good behavior.

## P95 <=100 um

**Classification:** IMPOSSIBLE TO ASSESS CURRENTLY.

No confirmatory metrology sample, failure accounting and predeclared P95 inference/tolerance method exist yet. Current Issue #8 now explicitly recognizes this.

## Marker-pair geometry

**Classification:** BEST FIRST 100 UM MEASURAND; PLAUSIBLE BUT NOT DEMONSTRATED.

It is gauge-independent and can be tied to CMM/optical metrology. It still depends on the physical realization of each marker frame and scale.

## Marker-to-implant geometry

**Classification:** IMPOSSIBLE TO ASSESS CURRENTLY.

Code applies an identity marker-to-implant transform. That does not establish a physical identity at 100 um. The holder/implant datum transform needs independent measurement and uncertainty.

## Implant center error

**Classification:** IMPOSSIBLE TO ASSESS until marker-to-implant ground truth exists. It may eventually be plausible under controlled conditions; current marker-pair data cannot substitute for it.

## Implant axis/orientation

**Classification:** CURRENT EVIDENCE IS WORSE THAN FOR LINEAR CENTER METRICS.

Issue #2 shows occasional tens-of-degrees pose discontinuities. Even successful smartphone dental photogrammetry literature can report angular errors around half a degree while achieving tens-of-micrometre centroid errors. A clinically meaningful endpoint/tip displacement criterion must specify a lever arm.

## Surface/STL error

**Classification:** NOT YET A WELL-DEFINED INDEPENDENT 100 UM CLAIM FOR THE CURRENT PRODUCT ARTIFACT.

The current STL is generated by rigidly transforming a reference model, not by reconstructing a dental surface from image texture/depth. A surface metric is therefore downstream of pose/model/datum/registration choices and should remain secondary.

## Overall classification

- **Smartphone dental photogrammetry as a technology class:** `plausible under controlled bench conditions` for sub-100-um linear metrics.
- **DentalScanner current v1 marker-pair target:** `plausible but not demonstrated`.
- **Current v1 production individual-scan <=100 um:** `unlikely with current pipeline as-is / not defensible yet`, due to demonstrated branch failures plus uncharacterized physical/calibration systematics.
- **Clinical implant center/axis and P95 claims:** `impossible to assess until specific metrology experiments`.

Therefore 100 um should remain an engineering research target, not a product precision claim.

# COMPARABILITY OF DENTAL PHOTOGRAMMETRY LITERATURE

External literature prevents an overly pessimistic conclusion but does not validate the current architecture.

A 2026 controlled in-vitro Journal of Dentistry study used PIC APP on an **iPhone 16 Pro**, four implant replicas, 20 repetitions and a high-accuracy industrial reference scanner. Reported smartphone-photogrammetry results included approximately:

- CRMS trueness: `54.8 +/- 6.57 um`
- BRMS: `31.70 +/- 14.15 um`
- angular deviation: `0.54 +/- 0.03 deg`

A 2026 systematic review/meta-analysis of extraoral implant photogrammetry reported mean values in the tens of micrometres, while also documenting study heterogeneity/publication-bias concerns.

These results show that consumer-phone imaging hardware does not impose a universal >100 um floor under controlled setups.

They are not directly transferable because DentalScanner currently differs in important ways:

- 6.9 mm ArUco v1 square rather than the studied proprietary optical transfer system;
- four coplanar critical corners per v1 marker;
- current one-solution IPPE persistence;
- uncharacterized physical marker print/datum scale at the micrometre level;
- Apple per-frame K + zero residual-distortion model not yet independently characterized;
- different device (`iPhone 16` baseline vs `iPhone 16 Pro` in the cited study);
- different target geometry, calibration and acquisition workflow;
- current identity marker-to-implant transform;
- no CMM/industrial ground-truth study for DentalScanner.

The correct interpretation is: **hardware feasibility is supported; current-system feasibility is not established**.

# RISKS

1. **Optimizing the wrong bottleneck.** Adding Ceres/AprilTag/STag before resolving corner/calibration/branch evidence can add complexity without changing physical error.
2. **Parallel geometry systems.** External detector/calibration/optimizer stacks can create inconsistent coordinate conventions, distortion models and provenance.
3. **Model-consistent false confidence.** Reprojection and covariance can look excellent while physical marker scale or calibration is biased.
4. **Branch ambiguity hidden by averaging.** IPPE wrong-branch events are discrete and can make Gaussian repeatability metrics misleading.
5. **Physical marker uncertainty.** A 6.9 mm printed marker is a scale standard in the PnP model. Micrometre-level claims require measurement of the actual physical realization.
6. **Marker-to-implant datum uncertainty.** Identity in software is not metrology.
7. **Field-dependent calibration.** A good central reprojection result can coexist with edge bias. Current focus/frame-mask sensitivity makes spatial residual analysis important.
8. **Focus/zoom coupling.** Per-sample K tracks imaging parameters, but residual distortion/model stability versus lens position and zoom is unmeasured.
9. **Synthetic overconfidence.** #26 can reveal algorithmic floors and failure modes but cannot establish iPhone/print/holder trueness.
10. **Metric mismatch.** Centroid, pairwise distance, axis angle, tip displacement and STL RMS are not interchangeable 100 um claims.
11. **Failure exclusion.** A precision study that drops branch-failed/missing/export-failed sessions will be optimistically biased.
12. **Library maintenance/app growth.** Ceres/external detectors create build and binary obligations that must be justified by measured gain.

# MISSING EVIDENCE

- Real apparent marker-side distribution in pixels from existing physical schema-1 sessions.
- Ground-truth corner localization error under DentalScanner-like blur, scale, perspective and FOV position.
- A/B evidence for the current second manual `cornerSubPix` pass.
- Holdout calibration residual field under the actual AVFoundation video pipeline.
- Persisted/verified GDC support+enabled state for tested devices/profiles.
- Stability of projection residuals versus lens position/focus/zoom/profile.
- Metrology of actual 6.9 mm printed marker edges/corners, flatness and mount.
- Characterized physical marker-origin to implant-center/axis transform.
- Synthetic branch-ground-truth test for candidate-aware IPPE selection.
- Issue #8 physical reference/uncertainty data.
- Failure-inclusive repeatability/trueness study.

# MISSING TESTS

1. Fixed-image/synthetic comparison of exact current `double SUBPIX` against `detector-only SUBPIX`, `CONTOUR`, `APRILTAG`, `NONE`.
2. Synthetic square pose cases with known `T_cm`, both IPPE candidates and explicit branch-correctness scoring.
3. PnP tests that persist candidate reprojection/positive-depth/continuity costs separately from chosen candidate.
4. Calibration holdout tests that evaluate spatial residual by normalized image radius/quadrant, not only global reprojection RMS.
5. Sensitivity/Jacobian tests mapping corner perturbation in pixels to translation mm and geodesic rotation for representative K/Z/pose.
6. Marker-scale perturbation test confirming expected scale sensitivity.
7. ROI-local sharpness correlation test against true/synthetic corner error.
8. Marker-to-implant datum-transform tests once physical calibration exists.
9. Future BA synthetic tests must compare against ground truth after applying the same gauge, not arbitrary absolute world frames.
10. Sanitizer-enabled Objective-C++ bridge/replay tests where platform support permits.

# SIMPLER ALTERNATIVE / MINIMUM EXPERIMENT SEQUENCE

The smallest defensible sequence is deliberately offline-first.

## E0 — Existing-NDJSON information and sensitivity audit

**INPUT**
Existing schema-1 physical sessions already captured outside Git: per-frame K, dimensions, image corners, object points, pose, marker area, frame identity.

**BASELINE**
Current persisted geometry and actual observed marker sizes/viewpoints.

**CANDIDATE**
No new estimator: compute exact/finite-difference projection Jacobians, simple Fisher/condition metrics and pixel-to-mm sensitivity using current frames.

**METRICS**
Apparent marker side/area distribution, `fx/fy`, condition number/eigenvalue diagnostics, predicted local pose sensitivity for assumed 0.02/0.05/0.10 px corner noise, viewpoint dependence.

**SUCCESS CONDITION**
A meaningful portion of real observations has a local noise floor comfortably below 0.100 mm with margin, and the result identifies which viewpoints are weak.

**FAIL CONDITION**
Achieving 0.100 mm would require corner noise materially below what synthetic/real images can support, or the geometry remains poorly conditioned across normal viewpoints.

This is a smaller first step than integrating a new library and directly advances #25.

## E1 — IPPE candidate replay (#2)

**INPUT**
Existing NDJSON; no new scans.

**BASELINE**
Persisted current `solvePnP` IPPE_SQUARE pose.

**CANDIDATE**
`solvePnPGeneric` returning all valid IPPE_SQUARE candidates; offline candidate-aware policies only.

**METRICS**
Candidate separation, reprojection per candidate using DentalScanner RMS convention, positive depth, temporal delta, multi-marker camera-motion disagreement, synthetic branch correctness, accumulator output change, determinism.

**SUCCESS CONDITION**
Candidate-aware modes reduce known synthetic branch error and physical continuity contradictions without relying on M0 or reprojection-only ranking.

**FAIL CONDITION**
No reproducible reduction, or candidate policy introduces comparable/new discontinuities.

## E2 — Corner-refinement benchmark

**INPUT**
Deterministic synthetic images matched to actual E0 marker-size/K distributions, including blur/noise/perspective/FOV position; add a frozen real-image corpus when available.

**BASELINE**
Exact current detector SUBPIX + manual fixed-window `cornerSubPix`.

**CANDIDATES**
Detector-only SUBPIX, CONTOUR, APRILTAG, NONE. External AprilTag 3 is explicitly excluded from the first experiment.

**METRICS**
Corner GT error px, translation error mm, geodesic rotation error, IPPE branch-error rate, detection failure, tail errors, center-vs-edge, runtime.

**SUCCESS CONDITION**
A candidate improves true corner and pose error including tails across realistic conditions without increasing branch/failure rate.

**FAIL CONDITION**
Only reprojection improves, gain disappears outside easy images, or detection/branch tails worsen.

## E3 — Calibration / residual distortion characterization

**INPUT**
Accurately fabricated ChArUco/calibration target, exact Wide 1.5x video path, multiple FOV positions/viewpoints and controlled lens-position/profile bins; independent holdout images.

**BASELINE**
Apple per-sample K + zero OpenCV distortion, as production does now.

**CANDIDATE**
Offline OpenCV ChArUco calibration/distortion model. mrcal is only a second-stage candidate if the simple model reveals unresolved structured residuals.

**METRICS**
Holdout vector residual field, physical board/datum pose error, spatial bias versus normalized radius/quadrant, session repeatability, lens-position/zoom dependence, model complexity.

**SUCCESS CONDITION**
A repeatable systematic bias is demonstrated and a candidate model reduces independent holdout physical error, not merely training reprojection.

**FAIL CONDITION**
Residual field is negligible relative to target budget, candidate overfits, or model is not stable across capture conditions.

## E4 — ROI-local sharpness benchmark

**INPUT**
Same frozen/synthetic image corpus with marker ROIs and corner/pose truth/proxy.

**BASELINE**
Current global sharpness/focus state.

**CANDIDATE**
Per-marker/per-corner ROI-local sharpness diagnostic.

**METRICS**
Correlation/ROC or other predeclared predictive score versus corner/pose error, false reject rate, coverage/connectivity loss.

**SUCCESS CONDITION**
Local metric materially predicts bad corner/pose observations better than global metric without destroying useful viewpoint support.

**FAIL CONDITION**
No predictive improvement, or selection would remove geometrically valuable observations.

## E5 — Physical marker/datum metrology

Before asking an optimizer to deliver 100 um, independently measure:

- actual ArUco side/edge/corner realization;
- print scale and anisotropy;
- flatness;
- mounting/remount stability;
- marker-frame datum realization;
- marker-to-implant center/axis transform and uncertainty.

If this physical uncertainty already consumes most of the 100 um budget, software refinement alone cannot rescue the claim.

## E6 — Issue #8 pilot then confirmatory study

Run the current Issue #8 sequence only after the measurement contract/fixture exists. Start with gauge-independent marker-pair dimensions; later promote implant center/axis. Keep failed scans in the denominator. Compare algorithms only on identical raw inputs where possible.

## E7 — Frame-indexed BA/Ceres

Only after E0/E1 and calibration/physical-scale risks are understood, execute Issue #4 synthetic BA. Compare ground-truth pose/relative geometry as primary; reprojection is secondary. Add covariance only after observation-noise scaling and gauge handling are validated.

# TOOLS THAT MERIT BENCHMARK

High priority:

- existing OpenCV `solvePnPGeneric` / dual IPPE candidate diagnostics;
- existing OpenCV corner refinement modes including `CORNER_REFINE_APRILTAG`;
- existing OpenCV ChArUco for independent calibration characterization;
- no-dependency ROI-local sharpness diagnostic;
- sensitivity/Fisher/Jacobian analysis from existing schema-1 NDJSON;
- Apple sanitizers and targeted Instruments/signposts for robustness/performance.

Conditional/later:

- Ceres Solver for Issue #4 synthetic frame-indexed BA, then schema/replay A/B;
- Ceres covariance after gauge/noise-model validation;
- mrcal as an independent offline calibration/uncertainty oracle if simpler calibration exposes a model problem;
- Rerun as an offline visual debugger if branch/replay inspection becomes a human-debug bottleneck.

# TOOLS TO DEFER / DISCARD FOR NOW

- external AprilTag 3 in the iOS production detector;
- STag in the iOS production detector;
- VVS-vs-LM as a current v1 priority;
- MetricKit as a precision initiative before controlled local performance questions are exhausted;
- any live distortion model replacement;
- any live BA/export promotion;
- marker v3/new marker ecosystem before #15 and the current calibration/corner benchmarks;
- any corner-refinement production change justified only by smaller reprojection.

# EXTERNAL SOURCES REVIEWED

Official / primary documentation:

- OpenCV 4.13 ArUco detection/corner refinement: `https://docs.opencv.org/4.13.0/d5/dae/tutorial_aruco_detection.html`
- OpenCV 4.13 PnP/IPPE/refinement: `https://docs.opencv.org/4.13.0/d5/d1f/calib3d_solvePnP.html`
- OpenCV 4.13 ChArUco calibration: `https://docs.opencv.org/4.13.0/da/d13/tutorial_aruco_calibration.html`
- OpenCV license: `https://opencv.org/license/`
- Apple camera intrinsic sample attachment: `https://developer.apple.com/documentation/coremedia/kcmsamplebufferattachmentkey_cameraintrinsicmatrix`
- Apple camera calibration/lens distortion: `https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata`
- Apple geometric distortion correction: `https://developer.apple.com/documentation/avfoundation/avcapturedevice/isgeometricdistortioncorrectionenabled`
- Apple sanitizer guidance: `https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early`
- Apple OSSignposter: `https://developer.apple.com/documentation/os/ossignposter`
- Apple MetricKit: `https://developer.apple.com/documentation/metrickit`
- Ceres covariance: `https://ceres-solver.readthedocs.io/latest/nnls_covariance.html`
- Ceres installation/features: `https://ceres-solver.readthedocs.io/latest/installation.html`, `https://ceres-solver.readthedocs.io/latest/features.html`
- mrcal overview/projection uncertainty/install: `https://mrcal.secretsauce.net/`, `https://mrcal.secretsauce.net/docs-default/install.html`
- Rerun code/license: `https://rerun.io/docs/reference/about`
- AprilTag 3 official repository: `https://github.com/AprilRobotics/apriltag`
- STag original repository: `https://github.com/bbenligiray/stag`

Dental accuracy literature:

- Gianfreda et al., 2026, Journal of Dentistry, smartphone-based photogrammetry on iPhone 16 Pro, PMID 42031357, DOI `10.1016/j.jdent.2026.106716`.
- Prasad et al., 2026, systematic review/meta-analysis of extraoral implant scanning/photogrammetry, PMID 41723014, DOI `10.1016/j.prosdent.2026.01.018`.
- Additional systematic-review context: PMID 40481748 and PMID 41241558.

No external result was treated as proof that DentalScanner currently achieves the same performance.

# REQUIRED CHANGES / PRIORITY RECOMMENDATION

1. Keep Issue #2 ahead of any live precision change. Implement only the replay experiment after independent plan review; do not promote candidate selection live from one physical session.
2. Run E0 sensitivity on existing physical NDJSON before requesting new captures. It can show whether the current image geometry is even compatible with the desired error budget under plausible corner noise.
3. Run the corner-refinement A/B before adding AprilTag 3/STag or removing the manual second pass.
4. Run independent camera-model characterization before changing `distCoeffs` or replacing Apple intrinsics.
5. Measure the physical v1 marker/datum and marker-to-implant transform before interpreting algorithmic improvement as a 100 um clinical result.
6. Keep #8 as the promotion oracle for trueness; current Issue #8 is substantially stronger than the older specs/reports and should take precedence over them.
7. Keep #25 and #26 as falsification tools, not production justification.
8. Proceed to Ceres/BA only through the staged synthetic/replay plan. Do not use covariance as a substitute for metrology.
9. Treat Rerun, sanitizers and Instruments as engineering quality tools; they are useful but do not belong in the physical precision claim.
10. Do not create a new fiducial ecosystem until #15 plus current corner/calibration experiments demonstrate that the physical marker design itself is the limiting factor.

# WHAT MUST NOT BE SENT TO CODEX YET

Do not send any implementation brief that asks Codex to:

- switch production refinement to `CORNER_REFINE_APRILTAG`;
- remove the manual `cornerSubPix` pass outright;
- add external AprilTag 3 or STag to the iOS app;
- change production `distCoeffs` from zero based only on generic lens-distortion theory;
- replace Apple per-frame intrinsics with ChArUco/mrcal calibration;
- switch current v1 to VVS;
- select IPPE candidates live;
- enable candidate-aware maturity/progress/readiness/export;
- add or promote live Bundle Adjustment;
- use Ceres covariance as a precision/confidence claim;
- make ROI sharpness a blocking gate;
- encode a `100 um` pass/fail product threshold before the #8 fixture/reference/uncertainty contract exists.

# FUTURE CODEX ENVELOPES — NOT AUTHORIZED YET

These are possible future task shapes only after the corresponding review/promotion gate.

## Candidate A — corner-refinement benchmark

**OBJECTIVE**
Compare the exact current double-SUBPIX behavior against existing OpenCV refinement alternatives on deterministic ground-truth images.

**EVIDENCE**
Current code performs detector SUBPIX plus a second fixed-window `cornerSubPix`; physical impact is unknown.

**GUARDRAILS**
Diagnostics/offline only; no production mode change; same images/K/object geometry; no reprojection-only success claim.

**VALIDATION**
Synthetic/frozen-image corner GT, translation mm, geodesic rotation, IPPE branch-error rate, tails, runtime and determinism.

## Candidate B — residual camera-model characterization

**OBJECTIVE**
Quantify whether the exact Wide 1.5x AVFoundation video path has repeatable spatial projection bias not explained by Apple per-sample K.

**EVIDENCE**
Production uses current sample K and zero OpenCV distortion; GDC state/residual field is not characterized.

**GUARDRAILS**
Offline; no live K/distortion replacement; accurately measured target; train/holdout separation; stratify relevant capture state.

**VALIDATION**
Independent holdout physical/vector residual field and pose/datum error across FOV/lens position/profile.

## Candidate C — ROI-local sharpness diagnostic

**OBJECTIVE**
Test whether marker-local image sharpness predicts corner/pose failures better than current global sharpness.

**EVIDENCE**
Current sharpness is global and `focusVariance` is not numerically persisted per marker.

**GUARDRAILS**
Shadow/diagnostic only; no frame blocking or accumulator change.

**VALIDATION**
Prediction of ground-truth/proxy corner and pose error, false-rejection rate and effect on marker/viewpoint connectivity.

# VERDICT

The project should not adopt a new detector, live distortion model, BA promotion or 100 um claim yet. The strongest near-term opportunities use capabilities already present in OpenCV and schema-1 replay, plus independent physical/calibration validation. External AprilTag/STag are currently more likely to add a parallel geometry stack than to solve the demonstrated bottleneck. Ceres is justified only for the already-staged offline BA experiment; mrcal and Rerun are useful conditional desktop tools.

The 100 um target is **not physically absurd**: controlled dental photogrammetry, including a recent iPhone 16 Pro study, demonstrates sub-100-um linear performance is possible for the technology class. But the current DentalScanner v1 production pipeline has neither the ground-truth evidence nor the characterized physical/calibration model needed to support that claim, and a demonstrated planar branch failure makes an individual-scan <=100 um claim particularly premature.

VERDICT: REVISE