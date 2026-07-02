# 11 — Device Quality Pipeline, ROI Mask, Useful Observations and Future Pose Optimization

## Status

Phase 1 and Phase 2 implemented as diagnostics/read-only.

Still future:

- Phase 3 - Useful Observation Selection Diagnostics
- Phase 4 - PnP Robustness Diagnostics
- Phase 5 - Future Marker Geometry Upgrade
- Phase 6 - Future Pose Graph / Bundle Adjustment Read-Only

No export, readiness or finalization behavior should be changed by the Phase 1/2 implementation.

This spec documents the next quality upgrades for DentalScanner based on practical iPhone 16 tests and inspection of reference app configuration files.

The goal is not to copy another implementation. The goal is to adopt the same proven architectural pattern:

- device class profiles
- camera/distance/focus thresholds per device class
- frame mask / ROI quality
- useful observation selection
- angle diversity
- stronger diagnostics before changing export
- future robust PnP / pose optimization

## Important Rules

Do not change export behavior in the first implementation phase.

Do not change:

- OpenCV ArUco detection
- current solvePnP behavior
- STLExporter
- export gate
- readiness
- normal finalization
- best final pose candidate export flag
- relative marker geometry logic
- Guided Static Capture
- ARKit Assist
- Python STL comparator

The first implementation must be read-only / diagnostics-first where possible.

Current critical flags must remain:

```swift
normalUseBestFinalPoseCandidateForExport = false
usedBestFinalPoseCandidate = false
forceEmergencyDebugPanel = true
enableRuntimeHeavyDebugSections = false
enableEditableDebugControls = false
```

## Background

Recent iPhone 16 testing showed:

- physical wide camera is preferred
- macro camera should not be used
- ultra-wide should not be used
- 2.0x zoom is currently not useful for our marker/distance setup
- 1.5x zoom appears to be the best candidate
- focus degrades below roughly 120–125 mm
- iPhone 16 should likely operate around 150–180 mm

Reference configuration patterns show:

- broad device categories instead of per-device hardcoded calibration
- separate iPhone / iPhonePro / iPad profiles
- distance limits per device class
- focus variance threshold per device class
- frame mask / border exclusion per device class
- angle diversity requirements
- minimum valid frames per marker
- PnP/RANSAC thresholds
- bundle-adjustment-style optimization settings
- YOLO infrastructure exists, but the inspected config has YOLO disabled

Therefore, DentalScanner should evolve toward a device-aware quality pipeline.

---

# Phase 1 — Device Class Profiles

Implementation status: implemented as diagnostics/read-only.

## Goal

Create a central device quality profile system.

This should not replace the existing `CameraProfile` system. It should complement it.

`CameraProfile` answers:

```txt
Which camera/zoom/focus behavior should be used?
```

`DeviceQualityProfile` answers:

```txt
What distance, ROI, focus, overlay and quality thresholds are appropriate for this device class?
```

## New Type

Add a type similar to:

```swift
enum DeviceQualityClass: String, Codable {
    case iPhone
    case iPhonePro
    case iPad
    case unknown
}
```

Add:

```swift
struct DeviceQualityProfile: Codable, Equatable {
    let qualityClass: DeviceQualityClass

    let minDistanceMm: Double?
    let idealMinDistanceMm: Double?
    let idealMaxDistanceMm: Double?
    let maxDistanceMm: Double?
    let tooCloseFocusRiskDistanceMm: Double?

    let focusVarianceThreshold: Double?
    let overlayScale: Double?

    let frameMaskVerticalBorderPercent: Double?
    let frameMaskHorizontalBorderPercent: Double?

    let minAngularSeparationDeg: Double?
    let targetAngularStdDeg: Double?

    let minValidFramesPerMarker: Int?
    let targetOptimizationFrames: Int?

    let notes: String?
}
```

If existing project naming is different, follow the current style.

## Initial Profile Values

Use these as starting points, not as final medical calibration.

### iPhone

```txt
qualityClass = iPhone
minDistanceMm = 100
maxDistanceMm = 220
focusVarianceThreshold = 70
overlayScale = 1.4
frameMaskVerticalBorderPercent = 0.275
frameMaskHorizontalBorderPercent = 0.225
minAngularSeparationDeg = 1.5
targetAngularStdDeg = 4.5
minValidFramesPerMarker = 65
targetOptimizationFrames = 300
```

For iPhone 16 / `iPhone17,*`, preserve the existing tested override:

```txt
recommendedCameraProfile = Wide 1.5x
tooCloseFocusRiskDistanceMm = 125
idealMinDistanceMm = 150
idealMaxDistanceMm = 180
maxDistanceMm = 220
```

### iPhonePro

```txt
qualityClass = iPhonePro
minDistanceMm = 80
maxDistanceMm = 150
focusVarianceThreshold = 150
overlayScale = 1.65
frameMaskVerticalBorderPercent = 0.275
frameMaskHorizontalBorderPercent = 0.3
minAngularSeparationDeg = 1.5
targetAngularStdDeg = 4.5
minValidFramesPerMarker = 65
targetOptimizationFrames = 300
```

Do not assume iPhone 16 Pro behaves like iPhone 16 normal. Keep it separately testable.

### iPad

```txt
qualityClass = iPad
minDistanceMm = 85
maxDistanceMm = 185
focusVarianceThreshold = 70
overlayScale = 1.0
frameMaskVerticalBorderPercent = 0.125
frameMaskHorizontalBorderPercent = 0.2
minAngularSeparationDeg = 1.5
targetAngularStdDeg = 4.5
minValidFramesPerMarker = 65
targetOptimizationFrames = 300
```

### Unknown

Use conservative values.

```txt
qualityClass = unknown
minDistanceMm = nil
maxDistanceMm = nil
frameMaskVerticalBorderPercent = 0.25
frameMaskHorizontalBorderPercent = 0.25
minAngularSeparationDeg = 1.5
targetAngularStdDeg = 4.5
```

Unknown devices should not be blocked. They should show a warning:

```txt
Dispositivo não calibrado — resultados podem variar
```

## Device Classification

Add a central resolver:

```swift
DeviceQualityProfileResolver.profile(
    deviceModelIdentifier: String,
    deviceMarketingName: String?
) -> DeviceQualityProfile
```

Suggested logic:

```txt
if identifier starts with iPad -> iPad
else if marketing name contains "Pro" -> iPhonePro
else if identifier starts with iPhone -> iPhone
else -> unknown
```

For known tested devices, allow overrides:

```txt
iPhone17,3 / iPhone 16 -> iPhone + Wide 1.5x recommendation
```

Do not hardcode a full profile per every iPhone model yet.

---

# Phase 2 — Frame Mask / ROI Quality Diagnostics

Implementation status: implemented as diagnostics/read-only.

The current implementation computes a safe ROI from the active `DeviceQualityProfile`, records per-marker bounding box diagnostics when marker overlay corners are available, and saves only warnings/diagnostic fields. It does not block export.

## Goal

Add a mask/ROI quality layer so the app can detect when markers are too close to the border.

This is one of the most important next steps.

Markers near the image edge should be considered lower quality because they are more likely to suffer from:

- lens distortion
- blur
- corner detection error
- unstable pose
- bad reprojection
- bad final geometry

## Definition

For the current camera frame:

```txt
safeMinX = frameWidth * horizontalBorderPercent
safeMaxX = frameWidth * (1 - horizontalBorderPercent)
safeMinY = frameHeight * verticalBorderPercent
safeMaxY = frameHeight * (1 - verticalBorderPercent)
```

A marker is inside the frame mask only if all marker corners or the marker bounding box are inside this safe rectangle.

If using all corners is risky, start with marker center + bounding box.

## New Per-Marker Diagnostics

Add per marker:

```txt
markerFrameCenterX
markerFrameCenterY
markerFrameNormalizedCenterX
markerFrameNormalizedCenterY
markerFrameMinX
markerFrameMinY
markerFrameMaxX
markerFrameMaxY

markerInsideFrameMask
markerFrameMaskViolation
markerDistanceToFrameMaskEdgePx
markerDistanceToFrameMaskEdgeNormalized

markerNearFrameEdgeWarning
```

For global scan diagnostics:

```txt
frameMaskVerticalBorderPercent
frameMaskHorizontalBorderPercent
frameMaskSafeRectMinX
frameMaskSafeRectMinY
frameMaskSafeRectMaxX
frameMaskSafeRectMaxY

visibleMarkersInsideFrameMaskCount
visibleMarkersViolatingFrameMaskCount
anyMarkerNearFrameEdge
frameMaskQualityState
frameMaskQualityMessage
```

## UI Behavior

If any required marker is outside the safe mask:

```txt
Centralize os markers
```

If a marker is near edge but still acceptable:

```txt
Evite as bordas da câmera
```

If all required markers are inside the safe region:

```txt
Markers centralizados
```

Do not block export in Phase 2.

Only show warning and save diagnostics.

## Debug Emergency Panel

Add a compact section:

```txt
Device quality class
Frame mask V/H
Safe ROI: ok/warn
Markers inside mask: X/Y
Near edge: yes/no
Frame mask message
```

Keep formatting safe:

- nil -> —
- NaN/infinity -> —
- no force unwrap
- no heavy calculations inside SwiftUI body

---

# Phase 3 — Useful Observation Selection Diagnostics

## Goal

Separate raw observations from useful observations.

Today the app can collect many observations, but many may be redundant or low quality.

A useful observation should be:

- in focus
- not too close
- not too far
- inside frame mask
- low reprojection error
- low jitter
- acceptable normal/pose quality
- not angularly redundant

## Observation Categories

For each marker, track:

```txt
rawObservationCount
validObservationCount
usefulObservationCount
optimizationObservationCount
rejectedObservationCount
```

Add rejection reasons:

```txt
tooClose
tooFar
focusRisk
nearFrameEdge
highReprojection
highJitter
invalidPose
duplicateAngle
notFinite
missingIntrinsics
```

## Angle Diversity

Use initial thresholds:

```txt
minAngularSeparationDeg = 1.5
targetAngularStdDeg = 4.5
```

For each marker, track:

```txt
angularSamplesCount
angularUsefulSamplesCount
angularStdDeg
angularMinSeparationDeg
angularCoverageScore
angleDiversityReady
```

Suggested read-only score:

```txt
angleDiversityScore = clamp(
    (angularStdDeg / targetAngularStdDeg) * 100,
    0,
    100
)
```

If angularStdDeg is unavailable:

```txt
angleDiversityScore = nil
```

Do not use this score to block export in the first implementation.

## Progress Separation

Keep current marker visual progress working.

Add a second diagnostic-only progress:

```txt
markerUsefulProgress
markerOptimizationProgress
```

Suggested initial logic:

```txt
markerUsefulProgress = usefulObservationCount / minValidFramesPerMarker
markerOptimizationProgress = optimizationObservationCount / targetOptimizationFrames
```

Clamp to 0...1.

Do not replace current visual progress yet.

## UI

Do not overload the main UI.

Only add simple warnings:

```txt
Mova em ângulos diferentes
Mantenha dentro da área central
Mantenha distância ideal
```

Emergency debug should show detailed numbers.

---

# Phase 4 — PnP Robustness Diagnostics

## Goal

Understand how stable each marker pose is before changing solvePnP.

Do not replace the current solvePnP in this phase.

## Add Diagnostics

Per marker:

```txt
pnpInputPointCount
pnpFinitePointCount
pnpReprojectionMean
pnpReprojectionMax
pnpReprojectionStd
pnpCornerWorstIndex
pnpCornerWorstError
pnpPoseAmbiguityScore
pnpQualityState
```

If available, track per-corner reprojection:

```txt
corner0ReprojectionError
corner1ReprojectionError
corner2ReprojectionError
corner3ReprojectionError
```

## Optional Read-Only Experiment

If safe and isolated, add a read-only alternative estimate:

```txt
alternativePnPMethod
alternativePnPReprojectionMean
alternativePnPTranslationDelta
alternativePnPRotationDelta
```

Possible future candidates:

```txt
IPPE
IPPE_SQUARE
RANSAC solvePnP
```

Important:

- do not feed alternative result into export
- do not affect readiness
- do not affect finalization
- diagnostics only

---

# Phase 5 — Future Marker Geometry Upgrade

## Goal

Evaluate whether ArUco-only marker pose is limiting precision.

Reference configs suggest a marker with more observed points can support stronger PnP/RANSAC/BA behavior.

Our current single ArUco v1 may be limited because it relies heavily on four square corners.

## Future Marker v3 Concept

Possible physical marker improvement:

```txt
ArUco ID for identity
extra printed dots/circles around marker
known 3D/2D coordinates
matte/anti-reflective finish
rigid printed body
no manually glued crooked sticker
```

This would allow:

```txt
more than 4 image points
RANSAC inlier filtering
better pose stability
less sensitivity to one bad ArUco corner
better final optimization
```

This phase is not for immediate implementation.

Do not start this until:

- iPhone 16 camera/focus is stable
- frame mask diagnostics are implemented
- useful observation diagnostics are implemented
- current ArUco-only limits are measured

---

# Phase 6 — Future Pose Graph / Bundle Adjustment Read-Only

## Goal

Create a read-only final pose optimizer that uses the best observations collected during finalization.

Do not use it for export initially.

## Inputs

Possible inputs:

```txt
useful observations per marker
camera intrinsics
marker IDs
marker corner observations
marker pose observations
relative marker geometry samples
frame mask quality
reprojection errors
angle diversity scores
```

## Robust Loss

Future optimizer should use robust loss behavior similar in spirit to Huber loss.

Initial diagnostic fields:

```txt
poseGraphCandidateAvailable
poseGraphObservationCount
poseGraphMarkerCount
poseGraphIterationCount
poseGraphInitialError
poseGraphFinalError
poseGraphErrorReduction
poseGraphWorstMarkerId
poseGraphWorstResidual
poseGraphAccepted
poseGraphRejectReason
```

Compare against current export pose:

```txt
poseGraphVsCurrentTranslationDeltaMean
poseGraphVsCurrentRotationDeltaMean
poseGraphVsCurrentRelativeGeometryDelta
```

Do not set:

```swift
normalUseBestFinalPoseCandidateForExport = true
```

Do not use pose graph result for export until multiple scan comparisons prove it is better.

---

# Diagnostics / Report Fields

Add these fields to `_diagnostics.json` and `_report.json` as implementation phases land.

## Device Quality

```txt
deviceQualityClass
deviceQualityProfileName
deviceQualityIsKnown
deviceQualityWarning

deviceQualityMinDistanceMm
deviceQualityIdealMinDistanceMm
deviceQualityIdealMaxDistanceMm
deviceQualityMaxDistanceMm
deviceQualityTooCloseFocusRiskDistanceMm
deviceQualityFocusVarianceThreshold
deviceQualityOverlayScale

deviceQualityFrameMaskVerticalBorderPercent
deviceQualityFrameMaskHorizontalBorderPercent
```

## Frame Mask

```txt
frameMaskSafeRectMinX
frameMaskSafeRectMinY
frameMaskSafeRectMaxX
frameMaskSafeRectMaxY
visibleMarkersInsideFrameMaskCount
visibleMarkersViolatingFrameMaskCount
anyMarkerNearFrameEdge
frameMaskQualityState
frameMaskQualityMessage
```

## Useful Observations

```txt
rawObservationCount
validObservationCount
usefulObservationCount
optimizationObservationCount
rejectedObservationCount

rejectedTooCloseCount
rejectedTooFarCount
rejectedFocusRiskCount
rejectedNearFrameEdgeCount
rejectedHighReprojectionCount
rejectedHighJitterCount
rejectedInvalidPoseCount
rejectedDuplicateAngleCount
rejectedNotFiniteCount
```

## Angle Diversity

```txt
angularSamplesCount
angularUsefulSamplesCount
angularStdDeg
angularMinSeparationDeg
angleDiversityScore
angleDiversityReady
```

## PnP Diagnostics

```txt
pnpInputPointCount
pnpFinitePointCount
pnpReprojectionMean
pnpReprojectionMax
pnpReprojectionStd
pnpCornerWorstIndex
pnpCornerWorstError
pnpPoseAmbiguityScore
pnpQualityState
```

## Future Pose Graph

```txt
poseGraphCandidateAvailable
poseGraphObservationCount
poseGraphMarkerCount
poseGraphIterationCount
poseGraphInitialError
poseGraphFinalError
poseGraphErrorReduction
poseGraphWorstMarkerId
poseGraphWorstResidual
poseGraphAccepted
poseGraphRejectReason
poseGraphVsCurrentTranslationDeltaMean
poseGraphVsCurrentRotationDeltaMean
poseGraphVsCurrentRelativeGeometryDelta
```

---

# Emergency Debug Panel

Add compact sections only.

Do not re-enable the old full debug panel.

## Device Quality Section

```txt
Device class
Recommended camera profile
Distance min/ideal/max
Too close focus risk
Frame mask V/H
Focus threshold
Overlay scale
```

## Frame Mask Section

```txt
Safe ROI
Markers inside ROI
Markers near edge
ROI message
```

## Useful Observations Section

```txt
Raw/valid/useful observations
Optimization observations
Rejected observations
Top reject reason
Angle std
Angle diversity score
```

## PnP Section

```txt
Reprojection mean/max
Worst corner
PnP quality
```

Everything must use safe formatting helpers.

---

# Python Comparator Follow-up

After app fields are implemented and scans are generated, update the Python comparator to export the new fields.

Add to:

```txt
scan_quality_ranking.csv
stl_comparison.csv
report_diagnostics.csv
scan_diagnostics_summary.csv
marker_report_diagnostics.csv
```

Do not alter:

```txt
STL loading
ICP
alignment
distance metrics
rotation metrics
anchor/component comparison
quality score formula
```

Only add columns at first.

Possible future comparator changes:

```txt
qualityScore penalty for frame mask violation
qualityScore penalty for poor angle diversity
qualityScore penalty for high PnP reprojection
qualityScore warning for unknown device quality class
```

Do not change scoring until enough scans exist.

---

# Implementation Order

## Commit 1 — Spec Only

Create this spec.

```bash
git add specs/11_device_quality_pipeline.md
git commit -m "Add device quality pipeline spec"
git push origin main
```

## Commit 2 — DeviceQualityProfile + Debug/Diagnostics

Implement:

- device quality class resolver
- initial profiles
- diagnostics/report fields
- emergency debug fields

Do not change scan behavior.

Suggested commit:

```bash
git commit -m "Add device quality profile diagnostics"
```

Status: implemented together with Phase 2 in `Add device quality and frame mask diagnostics`.

## Commit 3 — Frame Mask / ROI Diagnostics

Implement:

- safe ROI calculation
- marker inside/outside mask diagnostics
- UI warning
- report fields

Do not block export yet.

Suggested commit:

```bash
git commit -m "Add frame mask quality diagnostics"
```

Status: implemented together with Phase 1 in `Add device quality and frame mask diagnostics`.

## Commit 4 — Useful Observation Diagnostics

Implement:

- raw/valid/useful/optimization observation counters
- rejection reasons
- angle diversity read-only fields
- emergency debug fields

Do not change export yet.

Suggested commit:

```bash
git commit -m "Add useful observation diagnostics"
```

## Commit 5 — Comparator Columns

Update comparator to read/export new diagnostics.

Suggested commit:

```bash
git commit -m "Export device quality diagnostics"
```

## Future Commits

Only after test data:

- use frame mask as soft gate
- use useful observations for progress
- add alternative PnP read-only
- add pose graph read-only
- consider marker v3 with extra points

---

# Acceptance Criteria

## Spec Commit

- spec added
- no Swift code changed
- build not required

## Device Quality Diagnostics

- app builds
- default behavior preserved
- iPhone 16 still recommends Wide 1.5x
- unknown devices do not crash
- emergency debug shows device quality class
- diagnostics/report include device quality profile fields
- export/readiness/finalization unchanged

## Frame Mask Diagnostics

- app builds
- safe ROI is visible in debug
- marker near border produces warning
- no export blocking yet
- report contains frame mask fields
- debug does not crash

## Useful Observation Diagnostics

- app builds
- raw observations and useful observations are separated
- rejection reasons are counted
- angle diversity is reported
- no export blocking yet
- current visual progress remains unchanged

## Comparator

- old scans still work
- new fields appear as columns
- missing fields stay blank/NaN
- STL/ICP/alignment logic unchanged

---

# Notes

Do not blindly copy hardcoded camera matrices from external configs.

DentalScanner should prefer actual AVFoundation intrinsics when available:

```txt
cameraIntrinsicMatrixAvailable
cameraIntrinsicFx
cameraIntrinsicFy
cameraIntrinsicCx
cameraIntrinsicCy
activeVideoDimensions
activeFormatDescription
```

External config values are architectural references, not final calibration.

The project still needs a professional reference STL to measure true accuracy.

Current comparisons measure repeatability between app-generated STLs, not absolute clinical precision.
