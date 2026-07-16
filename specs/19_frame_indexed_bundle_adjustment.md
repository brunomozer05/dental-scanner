# 19 — Frame Indexed Bundle Adjustment

## Status

Spec 19A investigation and design complete. Implementation is pending review.

This document supersedes `19_offline_frame_indexed_optimization.md` as the active design. The earlier document remains a historical roadmap overview.

## 1. Objective

Define an offline, diagnostics-only bundle-adjustment (BA) experiment without unstated assumptions. The first optimizer compares:

```txt
A = current MultiFramePoseAccumulator replay result
B = frame-indexed bundle-adjustment result
```

Optimizer B has one camera pose per selected frame, one shared global pose per marker, fixed intrinsics per frame, persisted ordered 2D/3D correspondences, a 2D reprojection residual, Huber loss, and one explicitly fixed gauge. It is replay-only and does not control live accumulation, readiness, finalization, or normal export.

## 2. Authorization and reference scope

The authorized local external technical reference may inform mathematical conventions, solver trade-offs, and original DentalScanner design.

- `_local_reference/` remains read-only and untracked.
- No credential, private endpoint, authentication material, physical capture, binary, model, asset, or proprietary geometry enters the repository.
- No runtime dependency on the reference is permitted.
- Third-party components must be identified, independently licensed, and independently built.
- Findings use `CONFIRMED BY IMPLEMENTATION`, `CONFIRMED BY SYMBOL`, `STRONG INDICATION`, `INFERENCE`, or `UNCERTAIN`.
- DentalScanner remains self-contained and independently testable.

## 3. Confirmed reference architecture

The reference executable is an unstripped, encrypted arm64 iOS Mach-O. Symbols and packaged configuration are readable, but the relevant instructions cannot be reliably inspected. Symbols establish architecture, not multiplication or call order.

| Finding | Evidence | Classification |
|---|---|---|
| Optimization consumes a frame container | `OptimizeLogic::Run(FrameContainer const&, unsigned long)` | CONFIRMED BY SYMBOL |
| Camera state is indexed by frame | `InitializeVwcByFrameFromBaseMarker`, `InitializeVwcForFrame`, `RecomputeVwcByPnP`, `MarkerSourceFrameIndex` | CONFIRMED BY SYMBOL |
| Marker state is shared by marker ID | `InitializeVwmByIdFromFrames`, `UpdateVwmByIdFromFrame` | CONFIRMED BY SYMBOL |
| Reprojection residuals enter a Ceres problem | `AddReprojectionResiduals(ceres::Problem&, ceres::LossFunction*)`, `ComputeReprojectionResidual` | CONFIRMED BY SYMBOL |
| A residual has two 6-value pose blocks and one 4-value intrinsics block | `AutoDiffCostFunction<ReprojectionErrorSimpleRadial, 2, 6, 6, 4>` | CONFIRMED BY SYMBOL |
| Pose blocks use angle-axis operations | instantiated Ceres angle-axis conversions adjacent to those residuals | STRONG INDICATION |
| Robust Huber loss is present | `ceres::HuberLoss`; configured `kHuberLossDelta = 1.0` | CONFIRMED BY SYMBOL / CONFIG |
| A parameter block is fixed | `ceres::Problem::SetParameterBlockConstant` | CONFIRMED BY SYMBOL |
| Relative marker edges are an additional path | `BuildRelativeEdges`; `AutoDiffCostFunction<MarkerEdgeCost, 6, 6, 6>` | CONFIRMED BY SYMBOL |
| Later rejection/re-estimation exists | `RemoveOutliers`, `RecomputeVwcByPnP`, `RobustAverageVbm` | CONFIRMED BY SYMBOL |
| BA diagnostics include marker reprojection stats | `BAReport`, `MarkerReprojStats`, marker-pose serialization | CONFIRMED BY SYMBOL |
| Reference BA allows a simple radial camera model | 4-value intrinsics block, `ReprojectionErrorSimpleRadial`, focal/radial bounds | STRONG INDICATION |
| BA/graph limits are 150/100 iterations | packaged `BAConfig` | CONFIRMED BY CONFIG |

The app contains Ceres symbols in its main executable but no Ceres dylib, headers, sources, static archive, or build scripts. This strongly indicates static linkage. The encrypted app binary is not a reusable dependency; its exact Ceres version and build options are unknown.

Unknown by implementation: residual multiplication order; order of the four intrinsics values; fixed block identity; solver options; initialization fallback order; exact graph/BA/outlier/PnP/averaging call order; and whether every packaged value is active.

## 4. Coordinate conventions

### Reference assessment

All observed symbols are consistent with:

```txt
Vcm = camera-from-marker
Vwc = world-from-camera
Vwm = world-from-marker
Vcw = camera-from-world = inverse(Vwc)

p_world  = Vwm * p_marker
p_world  = Vwc * p_camera
p_camera = Vcw * p_world
Vcm      = inverse(Vwc) * Vwm
p_camera = inverse(Vwc) * Vwm * p_marker

Vwc_i = Vwm_j * inverse(Vcm_ij)
Vwm_j = Vwc_i * Vcm_ij
```

`Vcm` is passed to a screen-space projection symbol with marker points: `CONFIRMED BY SYMBOL` that it is the direct marker projection transform, with its direction a `STRONG INDICATION`. Paired `ComputeVcw`/`GetVwc`, plus `PredictVcm`, `GetVwm`, and initialization symbols provide a `STRONG INDICATION` for the remaining convention. It is `UNCERTAIN` at implementation level because the instructions are encrypted.

### Confirmed DentalScanner convention

DentalScanner passes marker-local millimetre object points and the returned rotation/translation directly to OpenCV `projectPoints`. Thus persisted `PoseResult` is:

```txt
T_cm,ij = camera-from-marker
p_c = R_cm,ij * p_m + t_cm,ij
```

This is `CONFIRMED BY IMPLEMENTATION` in `OpenCVArucoPoseBridge.mm`.

### DentalScanner BA contract

```txt
T_wc,i = world-from-camera for frame i
T_wm,j = world-from-marker j
T_cw,i = inverse(T_wc,i)
T_cm,ij = T_cw,i * T_wm,j

R_cm,ij = transpose(R_wc,i) * R_wm,j
t_cm,ij = transpose(R_wc,i) * (t_wm,j - t_wc,i)
p_c     = R_cm,ij * p_m + t_cm,ij
```

Object points/translations are millimetres; rotations are radians; image/intrinsics/residuals are pixels. Frame index is identity, timestamp is metadata, and Euler angles are forbidden.

## 5. DentalScanner current inputs

Schema 1 persists frame index/timestamp, frame dimensions, per-frame `fx/fy/cx/cy`, camera/marker profiles, ordered marker observations, ordered 2D/3D points, per-frame PnP vector/matrix/translation, reprojection/distance/area/point count/source/tag identity, quality metadata, and Pre-Gate shadow decisions.

The replay reader currently exposes only frame identity, timestamp, and reconstructed `[PoseResult]`. Spec 19C needs a separate schema-1-to-BA adapter (or immutable decoded-frame callback) for intrinsics and correspondences. It must not infer them from `PoseResult` or alter live replay.

The explicit persisted rotation matrix is authoritative for initialization. Validate it as finite and approximately in SO(3), convert it once to the chosen solver representation, and report disagreement with the persisted rotation vector. Do not run PnP or regenerate the matrix from that vector.

### Entities

#### `BundleAdjustmentCameraIntrinsics`

- identity: owning `frameIndex`;
- constants: `fx`, `fy`, `cx`, `cy`, width, height (pixels);
- lifecycle: decode/validate before problem construction; fixed during solve;
- validation: finite, `fx > 0`, `fy > 0`, and positive dimensions. The first builder does not reject a finite principal point merely for lying outside the image; it records that condition as a calibration-risk diagnostic.

#### `BundleAdjustmentFrameState`

- identity: unique persisted `frameIndex`; metadata: timestamp/file order;
- input: intrinsics and incident observations;
- variable: `T_wc,i`; constants: identity, time, intrinsics, dimensions;
- lifecycle: graph -> initialization -> optimization -> result;
- validation: increasing identity, finite initial pose, at least one retained edge.

#### `BundleAdjustmentMarkerState`

- identity: physical `markerId` plus compatible profile;
- input: incident observations and per-frame `T_cm,ij` estimates;
- variable: shared `T_wm,j`, except fixed gauge marker;
- constants: identity/profile/gauge flag;
- validation: consistent marker-local geometry and sufficient distinct-frame support.

#### `BundleAdjustmentFrameMarkerObservation`

- identity: `(frameIndex, markerObservationPosition)`, preserving marker multiplicity;
- relation: exactly one frame and one marker;
- constants: ordered observed 2D points, marker-local 3D points, persisted `T_cm,ij`, source/profile, quality/gate metadata;
- validation: equal non-empty point counts, at least four pairs initially, finite values, valid intrinsics/pose, compatible geometry.

#### `FrameIndexedBundleAdjustmentProblem`

- provenance: session/schema/app/solver/config/policy;
- immutable ordered frames, markers, observations, components, gauge, solver options;
- variables: only frame and marker poses;
- constants: intrinsics, object/image points, metadata.

#### `FrameIndexedBundleAdjustmentResult`

- optimized frame/marker poses, solver status, termination reason, diagnostics, residuals, exclusions, provenance;
- separate diagnostic artifact, never written into source NDJSON;
- validation: finite poses, gauge consistency, complete metrics, deterministic ordering.

## 6. Mathematical problem

For frame `i`, marker `j`, point `k`:

```txt
p_m,jk = [X, Y, Z]^T                       marker-local mm
u_ijk  = [u, v]^T                          observed px
T_wc,i = (R_wc,i, t_wc,i)                  variable
T_wm,j = (R_wm,j, t_wm,j)                  variable/fixed gauge
K_i    = (fx_i, fy_i, cx_i, cy_i)          fixed

p_c,ijk = transpose(R_wc,i) *
           (R_wm,j * p_m,jk + t_wm,j - t_wc,i)
         = [x, y, z]^T

u_hat = fx_i * x / z + cx_i
v_hat = fy_i * y / z + cy_i
r_ijk = [u_hat - u, v_hat - v]^T

min sum rho_Huber(||r_ijk||^2; delta)
```

The residual sign is predicted minus observed. There is one 2D block per point: four corners yield four blocks/eight scalar residuals. Frame, marker, observation, point order, and multiplicity remain persisted order.

No distortion is applied or optimized initially, matching current PnP's zero distortion. Intrinsics, object points, marker size, and scale remain fixed.

### Domain handling

- Reject before solving any observation with non-finite data, mismatched counts, invalid intrinsics, or initial `z <= depthEpsilonMm`.
- Start `depthEpsilonMm` at `1e-6` mm as only a numerical positivity guard.
- If an iterate gives non-finite projection or invalid depth, residual evaluation fails; do not clamp depth or fabricate a penalty.
- Report evaluation failure separately from non-convergence.

### Huber loss

Start with Huber `delta = 2.0 px` per 2D point block. This is tied to the current scanner's 2 px per-frame reprojection threshold, not copied from the reference's 1 px configuration. Persist delta and residual granularity. Huber changes influence, not membership; a second outlier pass is out of scope.

## 7. Parameterization

| Option | Benefits | Costs | Decision |
|---|---|---|---|
| Angle-axis + translation (6) | Minimal; compatible with persisted Rodrigues and reference 6-value blocks; simple AutoDiff/bridge | Conditioning near pi; matrix conversion required | Recommended for 19B–19E |
| Quaternion + translation (7 ambient/6 tangent) | Stable composition; natural matrix initialization | Requires manifold, normalization, sign canonicalization | Fallback if angle-axis tests expose conditioning issues |
| SE(3) local parameterization | Explicit tangent-space updates | Custom manifold/Jacobians and highest maintenance | Deferred |

Initialize angle-axis from the authoritative explicit matrix. Matrix-to-angle-axis is representation conversion, not pose estimation. Retain the persisted vector for diagnostics. Validate finiteness, determinant near 1, and orthonormality before conversion. Mixed rotation-radian/translation-mm scaling must be tested. Euler angles are not allowed.

## 8. Gauge

Known object points fix scale, but a common world rigid transform leaves all projections invariant: a 6-DOF SE(3) gauge.

- Fixing a marker produces a marker-relative world suitable for relative geometry.
- Fixing the first camera is valid but less aligned with current outputs.
- Fixing both generally over-constrains the problem unless their relation is an exact measurement.

The first experiment fixes exactly one marker:

```txt
T_wm,base = identity
```

This identity defines the coordinate frame; it is not a fallback initializer.

Base policy: build selected bipartite components; choose the eligible component with most retained observations (deterministic ties); among its markers meeting minimum distinct-frame support, choose the smallest marker ID; persist the policy and ID. M0 may be selected but is never special-cased. If the lowest expected ID is unavailable, choose the next eligible ID. If none exists, fail explicitly.

## 9. Initialization

Reference symbols confirm base-marker, per-frame, processing-order, marker-from-frame, PnP recomputation, and robust-average initialization concepts. Exact formulas/order are unknown.

DentalScanner builds a bipartite graph with frame nodes, marker nodes, and observation edges carrying persisted `T_cm,ij`. Starting at `T_wm,base = I`:

```txt
known T_wm,j + T_cm,ij => T_wc,i = T_wm,j * inverse(T_cm,ij)
known T_wc,i + T_cm,ij => T_wm,j = T_wc,i * T_cm,ij
```

Traverse deterministically by frame index then persisted observation position. A spanning-tree edge first initializes a reached state. Recompute states with all reachable finite candidates using:

- translation: component-wise median;
- rotation: quaternion medoid under geodesic distance, deterministic sign and input-order tie-break;
- conversion to solver parameterization only after aggregation.

This aggregate initializes but does not filter residuals. Accumulator A is a comparison and optional cross-check, not the primary initializer: it lacks per-frame cameras, bounds history, and selects a runtime anchor.

Minimum eligibility:

- at least two frames and two markers in a connected component;
- at least four ordered pairs per observation;
- valid fixed intrinsics and persisted `T_cm` for every retained edge;
- each optimized marker in at least two distinct frames;
- every optimized frame has a retained edge;
- one eligible base marker.

A frame may initialize without observing the base directly if a graph path reaches it. Disconnected states never receive identity. Initially optimize only the selected eligible component and report excluded component/frame/marker IDs and counts. If expected markers lie outside, mark the result partial and non-promotable. Under-connected exclusions are explicit; if they make the problem ineligible, fail before solve.

## 10. Observation policies

```txt
ALL      = every structurally valid persisted observation
FILTERED = only persisted preAccumulationGateEvaluated == true
           and preAccumulationGateWouldAccept == true
```

Default: `ALL`. It reproduces the complete pre-accumulator population; the experimental Pre-Gate was aggressive; BA and gate effects must remain separate. FILTERED uses persisted decisions and never reruns thresholds. Both preserve file/frame/marker/point order and frame-local intrinsics.

ALL and FILTERED are separate experiments. Report population and connectivity changes so removal of difficult data is not described as optimizer improvement.

## 11. Residual and robust loss

Implementation requirements:

- one frame pose and one shared marker pose per point residual;
- exact frame intrinsics remain constant;
- no cross-frame correspondence concatenation under one extrinsic;
- residual identity includes frame, marker, observation position, and point index;
- raw pixel residual and robust cost both remain diagnostic;
- initial/final statistics use the same membership;
- Huber neither mutates records nor hides selection.

The reference's variable 4-value simple-radial path is not adopted. Focal, principal point, distortion, object points, and scale stay fixed.

## 12. Solver decision

| Option | Integration/maintenance | Capability and scale | Risk |
|---|---|---|---|
| Ceres | New C++/CMake dependency; static/XCFramework packaging and notices needed | AutoDiff, Huber, manifolds, sparse Schur; appropriate for ~6,024 pose DOF and ~28,000 scalar residuals at 1,000 frames/3,500 four-corner observations | Medium integration risk |
| Original GN/LM | No runtime dependency but substantial numerical code | Must implement Jacobians, damping, block sparsity, robust weighting, convergence; dense normal matrix is inappropriate | Highest correctness/maintenance risk |
| Current libraries | OpenCV/Accelerate already exist | PnP is not BA; Accelerate is linear algebra, not the nonlinear solver | No suitable existing BA backend found |
| External macOS tool | Keeps experiment out of the iOS app | Full Ceres on physical datasets without device runtime pressure | Best initial isolation; schema/math must be shared or cross-validated |

### Primary recommendation

Implement the first executable BA as a self-contained macOS/offline diagnostic tool using project-built, version-pinned Ceres. Keep its model/fixtures independent of live UI. Only after 19E decide separately whether an iOS diagnostic static library/XCFramework is justified.

Official Ceres documentation describes static iOS arm64 builds, current C++17 requirements, an Eigen-only configuration for small/moderate problems, and optional Accelerate BLAS/LAPACK: <https://ceres-solver.readthedocs.io/latest/installation.html>.

Avoid SuiteSparse initially. Ceres uses a BSD-style main license and lists additional bundled-component notices; audit every selected dependency and artifact: <https://github.com/ceres-solver/ceres-solver/blob/master/LICENSE>.

Controls: pin source/checksum; build required architectures; never reuse reference binaries; record Ceres/Eigen/Abseil/compiler/architecture/linear solver/thread count/tolerances/iterations; generate notices; measure app size only if iOS is authorized; add macOS CI before iOS packaging.

Initial deterministic solver profile for 19B:

```txt
trust-region strategy: Levenberg-Marquardt
linear solver: SPARSE_SCHUR with EIGEN_SPARSE
elimination group 0: per-frame camera pose blocks
remaining group 1: shared marker pose blocks
threads: 1
maximum iterations: 100
function tolerance: 1e-6
gradient tolerance: 1e-10
parameter tolerance: 1e-8
```

Eliminating the many camera blocks leaves the small shared-marker system. `DENSE_SCHUR` is permitted only for tiny synthetic fixtures. These are versioned starting values, not backend defaults: 19B must validate or explicitly revise them before 19C. A result is `converged` only when Ceres reports its convergence termination and all output/domain checks pass. Iteration/time limits are non-converged outcomes even if cost decreased; `usableButNotConverged` remains diagnostic and non-promotable.

### Fallback

If Ceres blocks 19B, use a small deterministic LM kernel only as a synthetic oracle with finite-difference Jacobian checks. Do not scale a dense prototype to physical sessions. A custom physical-scale backend requires separate block-sparse Schur review.

## 13. Failure handling

Fail before solving for unsupported/incomplete schema, invalid integrity, missing/invalid intrinsics, non-finite/malformed poses or points, inconsistent geometry, no base, insufficient connectivity/support, invalid initial depth, or uninitialized selected states.

Distinct outcomes:

```txt
notRun
converged
usableButNotConverged
evaluationFailure
numericalFailure
iterationLimit
cancelled
```

Emit only finite, gauge-consistent results with termination reason. Failure never modifies NDJSON, accumulator, scan, STL, reports, or live state. A failed/partial B never replaces A or claims improvement.

## 14. Diagnostics schema

Future output reports:

```txt
capture and schema provenance
algorithm/config/backend/version/architecture
observation and gauge policies; base marker/component
solver status; converged; termination; iterations; runtime
initial/final cost and reduction
frames/markers/observations/corners considered and optimized
residual count
initial/final RMS
per-frame and per-marker RMS
maximum and P50/P90/P95/P99 residual
invalid depth and exclusions by reason
disconnected components and excluded IDs
initialization disagreement
rotation matrix/vector consistency
determinism tolerances and repeated-run deltas
```

A versus B reports marker sets, missing markers, pairwise distances/deltas, pairwise relative-rotation deltas, and population/connectivity differences. Ground-truth error is reported only with measured truth. Lower training residual alone is not “BA better.”

## 15. Synthetic validation plan

Use deterministic truth with at least three cameras, four markers, non-trivial rotations/translations, known per-frame intrinsics, mathematical projections, seeded noise, and controlled initial perturbation. Identity-only fixtures are prohibited.

Required cases:

1. transform composition/inversion;
2. hand-computed projection and residual sign;
3. AutoDiff/analytic Jacobian against central finite differences;
4. exact noiseless recovery;
5. approximate seeded-noise recovery;
6. global-frame invariance and canonical fixed gauge;
7. gauge removal/no unexpected rank deficiency;
8. frame not seeing base but connected through another marker;
9. disconnected component diagnosed, never identity-initialized;
10. invalid intrinsics;
11. negative/near-zero depth;
12. non-finite 2D/3D corner;
13. mismatched point arrays;
14. bad finite initialization and defined convergence/failure;
15. large outlier with and without Huber, without deletion;
16. canonical persisted traversal despite container ordering;
17. repeated-run determinism;
18. exact ALL/FILTERED populations and connectivity reporting;
19. marker multiplicity and corner order through schema adapter;
20. explicit matrix initialization not replaced by persisted Rodrigues vector.

Fixtures record seed, distribution, perturbation, truth, and tolerance. Rotation error is a relative-rotation geodesic angle, not Euler differences.

## 16. Physical A/B plan

After synthetic acceptance, use the external physical session without tracking it:

1. validate schema/integrity/provenance;
2. run A and B on identical ALL input;
3. run B twice fresh and verify determinism;
4. report convergence, residuals, exclusions, connectivity, and runtime;
5. compare pairwise relative geometry;
6. run FILTERED separately and report membership/connectivity changes;
7. use absolute-error claims only with measured ground truth;
8. retain known visual marker issues as operator context, not causal labels.

No automatic “BA better” verdict is produced.

## 17. Incremental implementation phases

### 19A — Investigation and specification

This document. Acceptance: conventions, model, solver, failures, diagnostics, tests, and open questions are explicit; no production code changes.

### 19B — Synthetic mathematical core

Deliver isolated transform/projection/residual/Huber/gauge code and non-trivial ground-truth tests. Accept when exact/noisy recovery, Jacobian, gauge, depth, outlier, connectivity, and determinism tests pass without app/NDJSON integration.

### 19C — Schema-1 NDJSON to BA problem

Deliver a streaming adapter preserving identities, order, intrinsics, points, pose, policy, and provenance. Accept when fixtures prove explicit-matrix initialization, ALL/FILTERED membership, validation, and components.

### 19D — Synthetic accumulator A versus BA B

Deliver deterministic A/B runner and machine-readable result. Accept when A/B start fresh, consume declared data, expose metrics, and B has no export effect.

### 19E — Offline physical-session execution

Run external physical ALL first, FILTERED second. Accept with complete integrity, convergence/failure, runtime, determinism, residual, connectivity, and relative-geometry reports; commit no artifact.

### 19F — Diagnostic accumulator-versus-BA STL export

Produce separately named/provenanced offline diagnostic STLs from semantically comparable A/B states. Accept only with tested transforms and unchanged normal export.

### 19G — Outlier and pose-graph evaluation

Evaluate second-pass outliers and/or relative graph separately. Each needs independent membership, thresholds, metrics, failure behavior, and review.

## 18. Explicit non-goals

```txt
online/runtime optimization or ScannerViewModel changes
live accumulator inputs/algorithm
Pre-Gate criteria/order/blocking or Experimental Gate
PoseEstimator/OpenCV/per-frame PnP
legacy concatenated PnP bypass
readiness/finalization/Best Final Pose Candidate
ExportGate/normal STLExporter
camera/focus/profiles/4K
focal/principal-point/distortion optimization
marker scale/object-point optimization
pose graph or second outlier pass in the first BA
extra circles, YOLO/AI, four-corner RANSAC
Python comparator integration
```

## 19. Acceptance criteria

- Transform conventions/compositions and residual equation are explicit.
- Reference claims retain evidence classifications and uncertainty.
- Units, sign, depth, parameterization, gauge, initialization, and disconnected behavior are defined.
- Exactly one marker is fixed by deterministic policy; no hidden identities or M0 special case exist.
- ALL/FILTERED are offline policies with ALL default.
- Huber pixel delta is justified; no second outlier pass is implied.
- Ceres offline and the fallback are evaluated with dependency controls.
- Non-trivial truth tests cover required success/failure modes.
- 19B–19G have independent acceptance gates.
- Live pipeline and normal export remain unchanged.
- No local reference or physical/runtime artifact is tracked.

Implementation starts only after review.

## 20. Open questions

1. Which pinned Ceres release/dependency set fits macOS CI? (19B)
2. Direct AutoDiff blocks or a project pose abstraction above Ceres? (19B)
3. Real-data SO(3) and matrix/vector consistency tolerances? (19C)
4. Keep single-planar-marker frames as weak or exclude configurably? (19C/19E)
5. Physical-session iteration/time limits after profiling? (19E)
6. Does 2 px Huber generalize against held-out geometry? (19D/19E)
7. Solve disconnected components independently for diagnostics? (after 19E)
8. Is iOS packaging justified after offline evidence? (after 19E)
9. Which exactly comparable state drives diagnostic STL B? (19F)
10. Do graph edges or second-pass outliers help after pure BA baseline? (19G)
