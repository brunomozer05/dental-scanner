# 18 — Scan Session Capture and Deterministic Replay

## Status

Planned after the frame-indexed observation foundation.

Not implemented. This spec defines an offline diagnostic artifact, not a new production scan pipeline.

## Goal

Persist enough geometric and quality information to reproduce a scan session deterministically without saving full camera frames by default.

The same captured session should be usable to compare the current accumulator, the new quality gate, future angle-diversity selection, and an offline optimizer without asking the operator to repeat the physical scan.

## Dependencies

- Spec 16 provides the frame-indexed observation model.
- Spec 17 defines optional gate classifications and counters.
- Spec 19 consumes replay data for offline A/B optimization.

Replay capture must not require specs 17 or 19 to be enabled.

## Versioned session schema

The top-level session record must include:

```txt
sessionSchemaVersion
appCommitHash
appBuildIdentifier
captureStartedTimestamp
captureEndedTimestamp
device
cameraProfile
featureFlags
frameObservations
```

Each frame record must include, when available:

```txt
frameIndex
timestamp
frameWidth
frameHeight
intrinsics
camera profile metadata
marker observations
frame quality metadata
```

Each marker record must include:

```txt
markerId
markerProfile
poseSource
2D image correspondences
3D object correspondences
per-frame pose
reprojection error
distance
frame-mask state
focus quality
motion quality
finite/valid state
gate classification and reason
```

The schema must not contain credentials, tokens, passwords, private endpoints, local filesystem paths, or unrelated user/account information.

## Storage decision

The first implementation should use versioned JSON because it is inspectable, easy to diff, and straightforward for comparator integration.

Requirements:

- stable field names;
- explicit schema version;
- deterministic ordering by frame index and marker ID;
- finite-number sanitization;
- optional fields for unavailable metadata;
- documented units and coordinate conventions.

If real sessions prove JSON too large or slow, a future binary encoding may be added behind a new schema/container version. The semantic schema and compatibility rules must remain independent of the encoding.

## Bounded file size

Control size through data selection, not by silently dropping arbitrary fields.

The current 600-frame `FrameObservationRecorder` buffer from spec 16 is a rolling diagnostics buffer only. It is not the authoritative full-session replay store. Spec 18 must introduce an explicit progressive or dedicated session-persistence path so replay completeness does not depend on the rolling buffer.

- No full camera images by default.
- No `CVPixelBuffer`, video, thumbnails, or external assets.
- Reuse the numeric-only observation model and explicit bounds from spec 16 without treating its rolling buffer as complete session history.
- Record whether observations were evicted before serialization.
- Define a maximum serialized session size and report truncation explicitly.
- Optional compression may be evaluated later without changing replay semantics.

## Deterministic replay

Given the same session file, app commit, replay configuration, and algorithm version, replay must produce the same ordered inputs and deterministic outputs within documented floating-point tolerance.

Replay must control or record:

```txt
algorithm configuration
feature flags
marker ordering
frame ordering
threshold sources
random seeds, if any
floating-point/backend identifier when relevant
```

The replay runner must not access the live camera, current device intrinsics, wall-clock timing, or mutable UI state as hidden inputs.

## Compatibility

- New readers must reject unknown major schema versions clearly.
- New readers should accept older supported versions using defaults for missing optional fields.
- Existing fields must not change meaning in place.
- Units and coordinate frames must be versioned if they change.
- Migration must be deterministic and tested with committed synthetic fixtures, not private scan data.
- Unsupported records must fail with diagnostics rather than partial silent replay.

## Security and privacy

Replay files must contain only technical scan geometry and quality metadata needed for experiments.

Do not store:

- credentials or authentication material;
- private URLs;
- proprietary external models/assets/geometries;
- full images by default;
- local reference paths;
- account metadata.

Any future optional image capture requires a separate explicit privacy/storage design.

## Comparison targets

The same replay should be able to evaluate:

```txt
current MultiFramePoseAccumulator
pre-accumulation gate OFF/ON
future per-marker angle diversity
offline frame-indexed optimizer
```

Each result must identify the algorithm/configuration version that produced it.

## CLI and comparator follow-up

A future CLI may:

- validate session schema;
- replay an algorithm configuration;
- export metrics in machine-readable form;
- compare A/B results;
- integrate with the existing comparator.

CLI and comparator implementation are follow-up work. This spec does not authorize changing the current Python comparator.

## Implementation order

1. Finalize schema names, units, coordinate frames, and versioning rules.
2. Serialize bounded synthetic `FrameObservation` fixtures.
3. Add reader validation and old-schema compatibility tests.
4. Capture diagnostic-only session files behind a disabled feature flag.
5. Replay the current accumulator and verify deterministic input ordering/output.
6. Add gate and optimizer consumers only in their own phases.

## Acceptance criteria

- Session files include schema, commit, build, device, profile, and feature-flag identity.
- Frame and marker observations preserve ownership and coordinate conventions.
- Full camera images are absent by default.
- File size is bounded and truncation/eviction is reported.
- The same session produces deterministic replay results within documented tolerance.
- Older supported schemas remain readable.
- Unknown schemas fail clearly.
- No credentials, private URLs, local paths, or external proprietary material are stored.
- Live scan, readiness, finalization, export, and comparator behavior remain unchanged.
