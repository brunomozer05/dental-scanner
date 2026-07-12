# 12 — Observation Quality and Angle Diversity

## Status

Draft / next implementation phase.

This spec defines how DentalScanner should separate raw marker observations from useful observations and how it should measure angle diversity.

This spec must not mention external app names or product names.

## Goal

Improve scan repeatability by ensuring that marker progress and final refinement are based on useful observations, not just raw frame count.

A useful observation should be:

- inside the safe ROI / frame mask
- within the device/profile distance range
- not too close for focus
- finite
- stable enough
- not near the image border
- not angularly redundant
- low reprojection / low pose error when available

## Non-goals

Do not implement in this phase:

- YOLO
- circle detector
- new physical marker
- new solvePnP method
- RANSAC PnP as primary path
- bundle adjustment
- pose graph export
- STL export changes

Do not change:

- OpenCV ArUco detection
- STLExporter
- export gate
- normal finalization
- best final pose candidate export flag
- relative marker geometry
- Guided Static Capture
- ARKit Assist

Keep:

```swift
normalUseBestFinalPoseCandidateForExport = false
usedBestFinalPoseCandidate = false
forceEmergencyDebugPanel = true
enableRuntimeHeavyDebugSections = false
enableEditableDebugControls = false
```

---

# Concepts

## Raw Observation

A marker was detected in a frame.

This does not mean the observation is good enough for progress or final optimization.

## Valid Observation

A detected marker with finite pose/corners and enough basic data to evaluate quality.

## Useful Observation

A valid observation that passes the experimental quality gate.

Initial criteria:

```txt
inside frame mask / safe ROI
not too close
not too far
not in focus-risk distance
finite translation/rotation
valid marker ID
quality gates currently used by the project pass
```

## Optimization Observation

A useful observation that is also selected for final refinement or future pose optimization.

This selection should prefer:

```txt
low reprojection
good focus
good distance
inside ROI
angle diversity
low motion
low jitter
```

---

# Initial Constants

Use values from `DeviceQualityProfile` when available.

Fallback values:

```txt
minValidFramesPerMarker = 65
targetOptimizationFrames = 300
minAngularSeparationDeg = 1.5
targetAngularStdDeg = 4.5
```

---

# Per-marker Counters

Add per-marker diagnostics:

```txt
rawObservationCount
validObservationCount
usefulObservationCount
optimizationObservationCount
rejectedObservationCount

rejectedByFrameMaskCount
rejectedByTooCloseCount
rejectedByTooFarCount
rejectedByFocusRiskCount
rejectedByInvalidPoseCount
rejectedByNotFiniteCount
rejectedByDuplicateAngleCount
rejectedByHighReprojectionCount
rejectedByHighJitterCount
rejectedByUnknownReasonCount
```

Progress fields:

```txt
markerUsefulProgress
markerUsefulReady
markerOptimizationProgress
markerOptimizationReady
```

Suggested formulas:

```txt
markerUsefulProgress = clamp(usefulObservationCount / minValidFramesPerMarker, 0, 1)
markerUsefulReady = usefulObservationCount >= minValidFramesPerMarker
markerOptimizationProgress = clamp(optimizationObservationCount / targetOptimizationFrames, 0, 1)
```

Do not replace the current visual marker progress in the first implementation unless a separate feature flag clearly controls it.

---

# Global Counters

Add global diagnostics:

```txt
totalRawObservationCount
totalValidObservationCount
totalUsefulObservationCount
totalOptimizationObservationCount
totalRejectedObservationCount

usefulMarkersReadyCount
usefulAllMarkersReady
overallUsefulProgress
overallOptimizationProgress
topObservationRejectReason
```

Suggested:

```txt
overallUsefulProgress = minimum useful progress across required markers
usefulAllMarkersReady = all required markers have usefulObservationCount >= minValidFramesPerMarker
```

---

# Angle Diversity

## Goal

Avoid accepting many nearly identical frames as if they were useful.

A scan should contain observations from slightly different viewpoints.

## Initial Fields

Per marker:

```txt
angularSamplesCount
angularUsefulSamplesCount
angularStdDeg
angularMinSeparationDeg
angularMaxSeparationDeg
angleDiversityScore
angleDiversityReady
angleDiversityWarning
```

Global:

```txt
globalAngularStdDeg
globalAngleDiversityScore
globalAngleDiversityReady
```

## Initial Rules

```txt
minAngularSeparationDeg = 1.5
targetAngularStdDeg = 4.5
```

Suggested score:

```txt
angleDiversityScore = clamp((angularStdDeg / targetAngularStdDeg) * 100, 0, 100)
```

Suggested ready rule:

```txt
angleDiversityReady = angularStdDeg >= targetAngularStdDeg
```

Do not use this to block export initially.

## Duplicate Angle Rejection

A new observation may be marked as angularly redundant if its angle is too close to recently accepted useful observations.

Initial rule:

```txt
if angular separation < minAngularSeparationDeg:
    count as duplicateAngle
```

Do not discard it from raw/valid counters. Only prevent it from becoming useful/optimization observation if the experimental gate is active.

---

# UI

Do not overload the main scanner UI.

Allowed short messages:

```txt
Mova em ângulos diferentes
Centralize os markers
Mantenha a distância ideal
Continue devagar
```

Debug emergency panel should contain detailed numbers.

---

# Emergency Debug

Add compact section:

```txt
Useful observations
Raw / valid / useful / optimization
Rejected total
Top reject reason
Useful progress
Useful ready
Angle samples
Angle std
Angle diversity score
Angle ready
```

No force unwrap.

No heavy calculations inside SwiftUI body.

---

# Reports

Add fields to:

```txt
_diagnostics.json
_report.json
```

Fields:

```txt
rawObservationCount
validObservationCount
usefulObservationCount
optimizationObservationCount
rejectedObservationCount
topObservationRejectReason

markerUsefulProgress
markerUsefulReady
markerOptimizationProgress
markerOptimizationReady

angularSamplesCount
angularUsefulSamplesCount
angularStdDeg
angularMinSeparationDeg
angularMaxSeparationDeg
angleDiversityScore
angleDiversityReady
angleDiversityWarning
```

Keep compatibility with old scans.

Missing fields should be nil/blank.

---

# Comparator Follow-up

After app scans exist, update the Python comparator to export these fields.

Do not change:

```txt
STL loading
ICP
alignment
distance metrics
rotation metrics
anchor comparison
current qualityScore formula
```

Only add columns first.

Possible future warnings:

```txt
LOW_USEFUL_OBSERVATIONS
LOW_ANGLE_DIVERSITY
HIGH_REJECTED_OBSERVATIONS
HIGH_DUPLICATE_ANGLE_REJECTIONS
```

---

# Implementation Order

## Commit 1

Add counters and reports only.

```bash
git commit -m "Add observation quality diagnostics"
```

## Commit 2

Add angle diversity read-only diagnostics.

```bash
git commit -m "Add angle diversity diagnostics"
```

## Commit 3

Optionally let experimental useful progress influence UI progress behind a feature flag.

```bash
git commit -m "Use experimental useful observation progress"
```

Do not do Commit 3 until enough test scans exist.

---

# Acceptance Criteria

- app builds
- current export behavior unchanged
- current finalization behavior unchanged
- current marker overlay still works
- useful observations are counted separately from raw observations
- rejection reasons are visible in debug
- angle diversity fields are recorded
- no external app/product names are used
- old scans remain compatible
