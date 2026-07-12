# 18 — Scan Session Capture and Deterministic Replay

## Status

Phase 18A full-session progressive observation capture implemented on 2026-07-12.

The deterministic replay reader, accumulator replay, gate A/B replay, comparator integration, and offline optimizer integration remain pending. The capture artifact is diagnostic and does not create a new production scan pipeline.

## Goal

Persist enough geometric and quality information to reproduce a scan session deterministically without saving full camera frames by default.

The same captured session should be usable to compare the current accumulator, the new quality gate, future angle-diversity selection, and an offline optimizer without asking the operator to repeat the physical scan.

## Dependencies

- Spec 16 provides the frame-indexed observation model.
- Spec 17 defines optional gate classifications and counters.
- Spec 19 consumes replay data for offline A/B optimization.

Replay capture must not require specs 17 or 19 to be enabled.

## Versioned session schema — Phase 18A

Phase 18A uses NDJSON / JSON Lines with one independently encoded object per line. Every record has `recordType` and `schemaVersion`; schema version 1 defines these record types:

```txt
sessionHeader
frameObservation
sessionFooter
```

The header records a session identifier, capture-start timestamp, device model identifier, OS version, camera profile identifier/name, marker profile, expected physical marker IDs, relevant capture/gate feature flags, app version, app build identifier, and an optional app Git commit hash. The commit hash is populated only when reliable build provenance is injected into `AppGitCommitHash`; the current project does not inject it, so this field is normally absent rather than inferred from a development machine.

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
stable pose-source identifier and associated fallback tag ID when applicable
2D image correspondences
3D object correspondences
per-frame pose
explicit rotation-matrix rows used by the current accumulator
reprojection error
distance
marker area in pixels
used point count
detected top/bottom tag IDs when applicable
frame-mask state
focus quality
motion quality
finite/valid state
gate classification and reason
```

The schema must not contain credentials, tokens, passwords, private endpoints, local filesystem paths, or unrelated user/account information.

## Storage decision

Phase 18A uses progressive NDJSON rather than a single JSON array. This keeps the artifact inspectable while avoiding full-session retention in memory. Header, frame, and footer lines are written in enqueue order by a private serial writer queue.

Requirements:

- stable field names;
- explicit schema version;
- persisted frame ordering is enqueue ordering; marker and 2D/3D point order are preserved exactly from the authoritative `FrameObservation`;
- non-finite numeric values are encoded using explicit `NaN`, `Infinity`, and `-Infinity` strings where a non-optional diagnostic field can contain them;
- optional fields for unavailable metadata;
- documented units and coordinate conventions.

If real sessions prove JSON too large or slow, a future binary encoding may be added behind a new schema/container version. The semantic schema and compatibility rules must remain independent of the encoding.

## Bounded file size

Control size through data selection, not by silently dropping arbitrary fields.

The current 600-frame `FrameObservationRecorder` buffer from spec 16 remains a rolling diagnostics buffer only. It is not the authoritative full-session replay store. Phase 18A adds a separate progressive writer that receives the same authoritative immutable observation before the unchanged accumulator update.

- No full camera images by default.
- No `CVPixelBuffer`, video, thumbnails, or external assets.
- Reuse the numeric-only observation model and explicit bounds from spec 16 without treating its rolling buffer as complete session history.
- The progressive writer does not evict persisted frames.
- The schema-1 hard limit is 128 MiB, with footer space reserved. A numeric observation is expected to be roughly 2–8 KiB; at up to approximately 9,000 processed frames in a five-minute 30 FPS session this is approximately 18–72 MiB, leaving conservative headroom without allowing unbounded storage.
- If the limit or bounded writer backlog is exceeded, capture stops accepting frames, remains incomplete, and reports an integrity failure without affecting the primary scan.
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

Phase 18A records the complete numeric `PoseResult` inputs currently consumed by `MultiFramePoseAccumulator`: marker/profile/source identity, rotation vector, the exact rotation-matrix rows supplied to the accumulator, translation vector, reprojection error, distance, marker area, used point count, and detected tag IDs. The future reader must validate the matrix shape and use the explicit matrix rather than silently recomputing a potentially numerically different value from Rodrigues data.

The remaining provenance caveat is that `appGitCommitHash` is optional until build tooling injects reliable commit metadata. A replay reader must report that gap and must not substitute the Git HEAD of the machine running the reader.

## Capture lifecycle — Phase 18A

```txt
new scan
  -> create a unique *_session.ndjson file in the existing scan Documents storage
  -> enqueue sessionHeader

authoritative FrameObservation
  -> rolling diagnostics recorder
  -> progressive session writer enqueue
  -> unchanged MultiFramePoseAccumulator.update input

successful completion
  -> drain previously queued frame records
  -> write sessionFooter
  -> synchronize and close
  -> mark capture completed

reset, cancel, camera stop, or camera error
  -> drain previously queued frame records
  -> write sessionFooter with completed = false when possible
  -> synchronize and close
```

The writer tracks enqueued/written frame indices and treats a non-increasing enqueue index as an integrity violation. It never silently sorts observations. Capture failures remain non-fatal to readiness, finalization geometry, STL generation, and export.

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

1. **Implemented:** schema-1 progressive NDJSON capture behind `enableScanSessionObservationCapture = true` for the experimental development phase.
2. Add committed synthetic schema fixtures and reader validation.
3. Add old-schema compatibility and unknown-schema rejection tests.
4. Replay the current accumulator and verify deterministic input ordering/output.
5. Add gate A/B replay only in its follow-up phase.
6. Add comparator and offline optimizer consumers only in their own phases.

## Acceptance criteria

- Phase 18A session files include schema, session, build, device, camera-profile, marker-profile, and expected-marker identity; commit provenance is optional until reliably injected.
- Frame and marker observations preserve ownership and coordinate conventions.
- Full camera images are absent by default.
- File size is bounded and truncation/eviction is reported.
- Pending reader phase: the same session produces deterministic replay results within documented tolerance.
- Older supported schemas remain readable.
- Unknown schemas fail clearly.
- No credentials, private URLs, local paths, or external proprietary material are stored.
- Live scan, readiness, finalization, export, and comparator behavior remain unchanged.
