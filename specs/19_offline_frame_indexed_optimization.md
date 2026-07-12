# 19 — Offline Frame Indexed Multi-Frame Optimization

## Status

Future offline experiment after specs 16 and 18.

Not implemented. Optimizer B must not control production export until sufficient controlled validation exists.

## Goal

Create a geometrically correct offline A/B experiment comparing the current pose accumulator with a frame-indexed multi-frame optimizer.

The experiment should determine whether joint optimization improves relative marker geometry and repeatability without reintroducing concatenated multi-frame PnP.

## A/B definition

```txt
A = current MultiFramePoseAccumulator result
B = frame-indexed optimizer result
```

Both A and B must consume the same versioned replay session and the same accepted observation set unless the experiment explicitly tests gate behavior.

## Initial geometric model

Optimizer B starts with:

```txt
one camera pose per accepted frame
one shared/global pose per marker
fixed per-frame intrinsics
2D reprojection residual per usable correspondence
robust Huber loss
```

For frame `i`, marker `j`, object point `Xjk`, and observed image point `uijk`, the predicted point must use:

```txt
frame intrinsics Ki
camera pose Ci
shared marker pose Mj
```

No observation may use another frame's camera pose or silently share one extrinsic across multiple frames.

## Gauge and initialization

The optimizer must remove gauge freedom explicitly, for example by fixing one anchor marker pose or one camera pose. The selected convention must be recorded with the result.

Initial values should come from existing per-frame PnP and current relative marker estimates. Invalid or unavailable initial poses must be reported, not replaced with arbitrary hidden defaults.

The first optimizer must keep frame intrinsics constant. It may reject observations with invalid depth, non-finite projection, or inconsistent point counts before solving.

## Robust residual handling

The first version should provide:

- two-dimensional reprojection residuals;
- Huber or an equivalent documented robust loss;
- explicit residual statistics before and after optimization;
- deterministic outlier classification for reporting;
- no mutation of source replay records.

Outlier removal may be evaluated as a second pass, but its threshold and effect must be reported independently from robust loss.

## Explicit non-goals for the first implementation

Do not implement initially:

```txt
online/runtime optimization
focal optimization
distortion optimization
pose graph
extra circle points
YOLO or other AI inference
marker v3
production export selection
```

Do not alter OpenCV, `PoseEstimator`, `MultiFramePoseAccumulator`, finalization, export gate, or `STLExporter` as part of the first experiment.

## Backend boundary

This spec does not require Ceres.

Optimizer B may use:

- an original small optimizer suitable for the initial problem;
- a future third-party numerical backend approved separately;
- multiple offline backends for cross-checking.

The required property is the geometric model, not library parity with any external reference. Backend choice, version, tolerances, parameterization, and termination reason must be recorded.

## Metrics

Report for A and B:

```txt
known inter-marker distance error
mean reprojection error
P95 reprojection error
outlier ratio
convergence rate
repeatability across sessions
relative marker geometry stability
```

Also record:

```txt
accepted frame count
observation count by marker
residual count
initial cost
final cost
iteration count
termination reason
runtime
non-finite/invalid observation count
```

Known inter-marker distance error requires a measured rig or other ground truth. Without ground truth, the result may claim repeatability or internal consistency only.

## Experiment boundaries

- Offline only.
- Input is a versioned replay session.
- No live-camera dependency.
- No UI/export side effects.
- Results are written as separate experiment artifacts.
- Optimizer B never replaces A silently.
- Every comparison identifies commit, schema, backend, and configuration.
- Feature flags for capture/replay do not imply optimizer promotion.

## Promotion criteria

The first implementation is accepted as an experiment when it is correct and measurable, not merely when B reports lower training residual.

Promotion toward any runtime or export role requires separate evidence that:

- B converges reliably on representative sessions;
- B improves known-geometry error or repeatability across sessions;
- improvement is not caused by discarding difficult markers/sessions;
- failure and non-convergence have safe fallback behavior;
- results remain deterministic within documented tolerance;
- runtime and memory are acceptable for the proposed future environment;
- validation follows spec 15 and does not overstate absolute accuracy.

No production default changes are authorized by this spec.

## Implementation order

1. Define the offline input adapter from spec 18 replay records.
2. Implement projection/residual evaluation and numerical Jacobian/derivative tests as appropriate.
3. Fix gauge and initialize from per-frame PnP.
4. Run optimizer B on synthetic geometry with known truth.
5. Produce A/B metrics on deterministic replay sessions.
6. Evaluate robust loss and outlier reporting.
7. Run repeated controlled sessions following spec 15.
8. Decide whether pose graph, intrinsics optimization, or runtime feasibility deserve separate future specs.

## Acceptance criteria

- Every optimized observation retains its original frame and marker identity.
- Optimizer B uses one camera pose per accepted frame and one shared pose per marker.
- Per-frame intrinsics remain fixed in the initial implementation.
- Gauge freedom is explicitly removed and reported.
- Synthetic known-truth tests validate projection and pose conventions.
- A and B consume the same replay data for a normal comparison.
- Required metrics and termination reason are produced.
- Invalid/non-finite inputs fail safely and are counted.
- Results are deterministic within documented tolerance.
- Optimizer B has no production export, readiness, finalization, or STL effect.
- No external proprietary code, model, asset, or geometry is used.
