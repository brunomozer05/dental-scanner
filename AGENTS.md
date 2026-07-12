# DentalScanner project rules

## Architecture and safety

- Before architectural changes, read `specs/README.md` and only the specs relevant to the task.
- Confirm behavior against production code. Specs describe intent and are not proof of implementation.
- Do not change OpenCV, `PoseEstimator`, `ExportGate`, `STLExporter`, or finalization outside explicit scope.
- Keep these defaults unless the task explicitly changes them:

```swift
normalUseBestFinalPoseCandidateForExport = false
usedBestFinalPoseCandidate = false
forceEmergencyDebugPanel = true
enableRuntimeHeavyDebugSections = false
enableEditableDebugControls = false
```

- Legacy concatenated multi-frame PnP remains bypassed for `singleArucoV1`. Do not reactivate it without explicit instruction and a controlled experiment.

## Technical reference workflow

- For work involving frame observations, multi-frame geometry, camera/marker pose, intrinsics, frame/focus quality, frame mask, angle diversity, PnP/RANSAC, reprojection, pose graph, bundle adjustment, global optimization, or extra marker points, first read `research/reference_scanner_pipeline_findings.md`.
- If a specific question remains and the local folders exist, consult `_local_reference/tmarker_new/` and `_local_reference/analysis/` only in a targeted, read-only, conceptual way. Do not repeat a full audit for each task.
- Never copy proprietary code, decompiled code, assets, models, geometries, credentials, tokens, passwords, private URLs, or authentication material.
- Distinguish `EVIDENCE`, `INFERENCE`, and `HYPOTHESIS`.
- When a reference concept inspires a change: identify the concept, compare it with DentalScanner code, design an original implementation, keep a feature flag for risky behavior, add diagnostics, and validate experimentally.

## Development discipline

- Prefer small, isolated commits and one architectural change per commit.
- Do not use `git add .` when local artifacts exist. Never add `_local_reference/`, scans, STLs, or test CSVs.
- Run `git diff --check` and `git diff --cached --check`.
- If Xcode, Tuist, or mise is unavailable, state that a local build was not run.
- Do not claim absolute precision improvement without a reference STL or other ground truth.
