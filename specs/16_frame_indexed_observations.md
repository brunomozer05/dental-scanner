# 16 — Frame Indexed Observation Model

## Status

Next architecture foundation.

Not implemented. This spec defines a diagnostics-first data foundation and does not authorize changes to the primary scan or export pipeline.

## Goal

Introduce an explicit observation entity for each processed camera frame while preserving all current production behavior.

The first implementation must make frame ownership unambiguous so future replay, quality gating, angular analysis, and offline optimization can operate on geometrically valid data.

## Current limitation

DentalScanner has per-frame camera data and per-marker pose results, but it does not retain a single first-class record that keeps together:

- frame identity;
- frame intrinsics;
- the marker observations produced by that frame;
- their 2D/3D correspondences;
- the quality state that existed when the frame was processed.

Without this relationship, future multi-frame optimization can accidentally lose which camera pose and intrinsics generated an image point.

## Proposed conceptual types

The exact Swift layout must follow project conventions when implemented. The conceptual contracts are:

```swift
FrameObservation
MarkerFrameObservation
```

### `FrameObservation`

Represents one processed frame:

```txt
frameIndex
timestamp
intrinsics
frameWidth
frameHeight
cameraProfileMetadata
markerObservations
```

Recommended camera-profile metadata:

```txt
cameraProfileId
cameraDeviceType
requestedZoomFactor
appliedZoomFactor
activeFormatDescription
pixelFormat
```

Values unavailable on older devices must remain optional. Missing metadata must not invalidate otherwise usable diagnostic records.

### `MarkerFrameObservation`

Represents one marker as observed in one frame:

```txt
markerId
markerProfile
poseSource
imageCorners
objectPoints
perFramePose
reprojectionError
distanceMm
frameMaskState
focusQuality
motionQuality
isFinite
isValid
invalidReason
```

`perFramePose` is the pose estimated from only that frame's correspondences. It must not be a pose produced by concatenating points from other frames.

## Geometry invariants

- Every `MarkerFrameObservation` belongs to exactly one `FrameObservation`.
- Every image point is interpreted using the intrinsics and dimensions of its owning frame.
- Image-point count and object-point count must match.
- All stored numeric geometry must be checked for finite values.
- A marker observation may be retained for diagnostics even when invalid, but its invalid state and reason must be explicit.
- Observations from different frames must never be concatenated into one `solvePnP` under a single extrinsic.
- Resizing must preserve coordinate-system consistency between image points and intrinsics.

## First implementation boundaries

The first implementation is diagnostics/read-only.

It must not:

- feed export;
- change `MultiFramePoseAccumulator` input or output;
- change readiness;
- change finalization;
- change best final pose candidate selection;
- change `STLExporter`;
- change OpenCV or `PoseEstimator`;
- persist full camera images.

The existing `singleArucoV1` bypass of legacy concatenated multi-frame PnP must remain unchanged.

## Buffer behavior

Use a bounded in-memory buffer.

Requirements:

- explicit configurable limit;
- deterministic oldest-first eviction;
- dropped-record counter;
- reset at scan/session reset;
- no unbounded image, `CVPixelBuffer`, or `CMSampleBuffer` retention;
- no reference cycles or hidden ownership of camera buffers;
- safe behavior when a frame contains no expected markers.

The first version should retain numeric observation data only.

## Diagnostics

Add when this spec is implemented:

```txt
frameObservationCount
frameObservationDroppedCount
frameObservationBufferLimit
frameObservationOldestTimestamp
frameObservationNewestTimestamp
framesWithExpectedMarkersCount
perMarkerFrameObservationCount
```

Useful additional diagnostics:

```txt
framesWithoutIntrinsicsCount
invalidMarkerFrameObservationCount
nonFiniteMarkerFrameObservationCount
observationPointCountMismatchCount
```

Diagnostics must be safe for empty buffers and missing values.

## Implementation order

1. Define value-only observation types with no pipeline consumers.
2. Build a bounded recorder from data already produced by the current frame path.
3. Add reset/eviction behavior and unit tests for ownership and limits.
4. Expose aggregate diagnostics in the existing diagnostic/report path.
5. Validate that current pose accumulation, readiness, finalization, and export outputs are unchanged.
6. Only after validation, allow specs 17 and 18 to consume the records.

Each step should be isolated and reversible. Do not implement specs 17–19 in the same commit.

## Acceptance criteria

- Every retained marker observation has one frame index and timestamp.
- Intrinsics and frame dimensions remain associated with their source frame.
- Per-frame PnP remains the source of the stored initial pose.
- The buffer is bounded and eviction diagnostics are correct.
- No camera frame buffers or images are retained.
- Empty, nil, NaN, and infinity inputs do not crash diagnostics.
- `MultiFramePoseAccumulator` behavior is unchanged.
- Readiness, finalization, best-candidate selection, export gate, and STL output are unchanged.
- Legacy concatenated multi-frame PnP remains bypassed for `singleArucoV1`.
- Reports can expose counts without exposing private data or local paths.

## Out of scope

- Pre-accumulation filtering — spec 17.
- Session persistence/replay — spec 18.
- Joint multi-frame optimization — spec 19.
- Primary angle-diversity integration.
- Pose graph.
- Marker v3 or extra geometric points.
