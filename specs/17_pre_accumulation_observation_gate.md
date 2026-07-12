# 17 — Pre-Accumulation Observation Quality Gate

## Status

Planned after spec 16.

Not implemented. The first version must be experimental, measurable, and disabled by default.

## Goal

Prevent observations that fail explicit quality checks from entering `MultiFramePoseAccumulator`, while preserving an A/B control path and leaving export/finalization unchanged.

## Current problem

The current processing order allows this condition:

```txt
an observation may reach the primary accumulator before the experimental quality gate classifies it as rejected
```

As a result, a frame later rejected for focus, frame-mask, distance, or other quality reasons may already influence the primary fused pose.

## Dependency

Spec 16 must exist first so the gate evaluates a complete frame-owned observation rather than disconnected pose values.

The gate must receive immutable observation data and return a classification. It must not mutate the observation or recompute PnP.

## Feature flag

The first implementation must use:

```swift
enablePreAccumulationObservationGate = false
```

Rules:

- `false` preserves current accumulator behavior exactly;
- `true` inserts only accepted observations into the experimental gated path;
- the active flag value must be recorded in diagnostics and replay metadata;
- changing the default requires a separate validated decision.

## Candidate checks

Evaluate candidates in an explicit, deterministic order:

```txt
expected marker
finite pose
finite intrinsics
frame mask
too close
too far
focus risk
reprojection
motion
```

The implementation spec for each check must define:

- required inputs;
- behavior when metadata is unavailable;
- rejection reason;
- threshold source;
- whether the result is hard reject or diagnostic warning.

Unknown optional metadata must not silently become a hard rejection. For example, unavailable motion support should be reported separately from known bad motion.

## Explicit first-commit exclusion

Angle diversity must not enter the first commit of this spec.

Angle diversity is history-dependent, while the initial gate should validate local observation quality. It can be added later as a separate, measured selection layer after deterministic replay exists.

## Observation flow and counters

The pipeline must distinguish:

```txt
raw observations
pre-gate accepted
pre-gate rejected
accumulator inserted
```

Required global counters:

```txt
preAccumulationGateEnabled
preAccumulationRawObservationCount
preAccumulationAcceptedCount
preAccumulationRejectedCount
preAccumulationInsertedCount
```

Required per-marker counters:

```txt
perMarkerPreGateRawCount
perMarkerPreGateAcceptedCount
perMarkerPreGateRejectedCount
perMarkerAccumulatorInsertedCount
```

Required rejection counts:

```txt
rejectedUnexpectedMarkerCount
rejectedNonFinitePoseCount
rejectedMissingOrInvalidIntrinsicsCount
rejectedFrameMaskCount
rejectedTooCloseCount
rejectedTooFarCount
rejectedFocusRiskCount
rejectedReprojectionCount
rejectedMotionCount
rejectedUnknownQualityCount
```

The sum of accepted and rejected observations must be reconcilable with the raw count. Inserted count may be lower only for a separately recorded downstream reason.

## A/B requirement

Every validation batch must compare:

```txt
gate OFF
gate ON
```

Use the same device, camera profile, marker setup, distance, lighting, and operator path. After spec 18, both modes should also be evaluated against the same deterministic replay session.

Compare at least:

- accepted/rejected counts and reasons;
- marker coverage;
- time to readiness;
- fused-pose repeatability;
- relative marker geometry stability;
- scan completion/failure rate;
- final STL repeatability when normal export is run independently.

Do not claim absolute accuracy without ground truth.

## Non-goals

The first implementation must not:

- change OpenCV or PnP;
- change the accumulator algorithm itself;
- change readiness thresholds;
- change finalization;
- change best final pose candidate selection;
- change export gate or `STLExporter`;
- add angle diversity;
- add bundle adjustment or pose graph;
- auto-enable the gate.

## Implementation order

1. Add the disabled flag and classification result types.
2. Run the gate in shadow mode and record counters without changing accumulator input.
3. Verify counter reconciliation and missing-metadata behavior.
4. Add an experimental gated accumulator input path behind the same disabled-by-default flag.
5. Run gate-OFF/gate-ON validation and deterministic replay when available.
6. Consider a default change only in a separate task with evidence.

## Acceptance criteria

- Gate OFF produces current accumulator behavior.
- Shadow mode has no behavioral effect.
- Gate ON inserts no explicitly rejected observation.
- Every rejection has one stable primary reason.
- Raw, accepted, rejected, and inserted counters reconcile.
- Missing optional metadata follows documented behavior.
- Angle diversity is absent from the first implementation.
- Export, readiness, finalization, and STL generation remain unchanged.
- A/B reports identify flag state and rejection breakdown.
- No precision claim is made without ground truth.
