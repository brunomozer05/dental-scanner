# 13 — Camera Resolution, Focus, Exposure and Intrinsics Diagnostics

## Status

Draft / experimental camera quality plan.

This spec defines experimental camera improvements for DentalScanner.

Do not mention external app names or product names.

## Goal

Improve marker detection and pose stability by testing:

- physical wide camera
- 1.5x zoom
- higher camera resolution when available
- safer focus behavior
- focus/exposure diagnostics relative to the safe ROI
- active AVFoundation intrinsics
- reference camera matrix diagnostics in read-only mode

## Non-goals

Do not change:

- OpenCV ArUco detection
- solvePnP primary behavior
- STLExporter
- export gate
- finalization
- best final pose candidate export behavior
- Guided Static Capture
- ARKit Assist

Do not use hardcoded reference camera matrices in the primary solvePnP path.

The primary path should keep using AVFoundation intrinsics when available.

---

# Camera Profile Strategy

Existing profiles:

```txt
Default
Wide 1.0x
Wide 1.5x
Wide 2.0x
Wide 1.5x Conservative Focus
Wide 2.0x Conservative Focus
```

Current observation:

```txt
iPhone 16 normal appears best with physical wide camera + 1.5x zoom + longer distance.
2.0x is experimental / not recommended for iPhone 16.
```

Keep:

```txt
iPhone17,* / iPhone 16 normal -> recommended Wide 1.5x
```

Do not auto-switch without a clear feature flag.

---

# High Resolution Camera Profile

Add an experimental camera profile:

```txt
Wide 1.5x High Resolution Experimental
```

Rules:

```txt
use physical wide camera
requested zoom = 1.5x
do not use macro
do not use ultra-wide
do not prefer virtual / multi-camera
try high-resolution video format if available
fallback safely to current format
do not select automatically by default
```

Possible target:

```txt
3840x2160
```

But do not assume it exists on all devices.

Current implementation note:

```txt
When Wide 1.5x High Resolution Experimental is selected manually, the camera service should try to apply 3840x2160.
Normal profiles must keep the existing format behavior.
If 3840x2160 is unavailable or cannot be applied, the app must keep a safe fallback format and record the fallback reason.
```

## Diagnostics

Add:

```txt
cameraHighResolutionProfileAvailable
cameraHighResolutionProfileSelected
cameraRequestedHighResolutionDimensions
cameraAppliedHighResolutionDimensions
cameraHighResolutionFallbackReason
cameraAvailableFormatCount
cameraAvailableMaxResolutionWidth
cameraAvailableMaxResolutionHeight
```

If high resolution is not implemented yet, add diagnostics to list whether a high-resolution format is available.

---

# Active Intrinsics

Continue recording:

```txt
cameraIntrinsicMatrixAvailable
cameraIntrinsicFx
cameraIntrinsicFy
cameraIntrinsicCx
cameraIntrinsicCy
activeVideoDimensions
activeFormatDescription
currentVideoZoomFactor
appliedZoomFactor
requestedZoomFactor
selectedCameraDeviceType
selectedCameraLocalizedName
```

## Intrinsics Consistency

Add diagnostics:

```txt
intrinsicsFrameWidth
intrinsicsFrameHeight
intrinsicsLikelyMatchesActiveFormat
intrinsicsFormatWarning
```

Suggested warning:

```txt
Active intrinsics may not match processed frame dimensions
```

Only set warning when there is strong evidence.

---

# Reference Camera Matrix Diagnostics

Add read-only reference camera matrix diagnostics.

Important:

```txt
Never use this matrix in primary solvePnP.
Never change export based on this matrix.
Never replace AVFoundation intrinsics with this matrix.
```

Reference values can be stored by device quality class.

## Fields

```txt
referenceCameraMatrixDiagnosticsEnabled
referenceCameraMatrixSource
referenceCameraMatrixFx
referenceCameraMatrixFy
referenceCameraMatrixCx
referenceCameraMatrixCy

activeCameraIntrinsicFx
activeCameraIntrinsicFy
activeCameraIntrinsicCx
activeCameraIntrinsicCy

referenceVsActiveFxDelta
referenceVsActiveFyDelta
referenceVsActiveCxDelta
referenceVsActiveCyDelta

referenceVsActiveFxRatio
referenceVsActiveFyRatio

referenceCameraMatrixResolutionMismatchWarning
```

If active video dimensions are 1920x1080 and reference center appears closer to 3840x2160, warn:

```txt
Reference matrix may not match active video dimensions
```

---

# Focus and Exposure Diagnostics

## ROI Center

Compute normalized center of the current safe ROI:

```txt
roiCenterNormalizedX
roiCenterNormalizedY
```

## Focus Point

Record when available:

```txt
lastFocusPointNormalizedX
lastFocusPointNormalizedY
lastExposurePointNormalizedX
lastExposurePointNormalizedY
focusPointInsideROI
focusPointDistanceToROICenter
exposurePointInsideROI
exposurePointDistanceToROICenter
```

## Future Focus Behavior

Future optional behavior:

```txt
focus toward ROI center
focus toward best marker center
set exposure point near ROI center
avoid aggressive focus recovery when too close
```

Do not enable manual fixed focus in this phase.

Do not permanently lock focus.

If adding focus movement, keep it behind a feature flag:

```swift
enableExperimentalROICenterFocus = false
```

---

# Distance Behavior

For iPhone 16 normal:

```txt
tooCloseFocusRiskDistanceMm = 125
idealMinDistanceMm = 150
idealMaxDistanceMm = 180
maxDistanceMm = 220
```

Guide messages:

```txt
< 125 mm -> Muito perto - afaste para focar
125–150 mm -> Afaste um pouco
150–180 mm -> Distância ideal
180–220 mm -> Aproxime um pouco
> 220 mm -> Muito distante
```

The side distance guide must use dynamic thresholds from the selected `CameraProfile` first and `DeviceQualityProfile` second.

For iPhone 16 / `Wide 1.5x`, the ideal 150-180 mm band must be visible inside the bar. The old visual scale could suggest a shorter 80-140 mm range and should not be used when profile/device thresholds are available.

2.0x should remain experimental / not recommended for iPhone 16.

---

# Emergency Debug Panel

Add compact camera diagnostics:

```txt
Camera profile
Recommended profile
High resolution available
High resolution selected
Requested dimensions
Applied dimensions
Fallback reason

Active intrinsics
Reference matrix
Reference/active ratio
Reference warning

ROI center
Focus point
Exposure point
Focus distance to ROI center
```

No force unwrap.

No heavy calculations in SwiftUI body.

---

# Reports

Add to `_diagnostics.json` and `_report.json`:

```txt
cameraHighResolutionProfileAvailable
cameraHighResolutionProfileSelected
cameraRequestedHighResolutionDimensions
cameraAppliedHighResolutionDimensions
cameraHighResolutionFallbackReason

intrinsicsFrameWidth
intrinsicsFrameHeight
intrinsicsLikelyMatchesActiveFormat
intrinsicsFormatWarning

referenceCameraMatrixDiagnosticsEnabled
referenceCameraMatrixSource
referenceCameraMatrixFx
referenceCameraMatrixFy
referenceCameraMatrixCx
referenceCameraMatrixCy
referenceVsActiveFxDelta
referenceVsActiveFyDelta
referenceVsActiveCxDelta
referenceVsActiveCyDelta
referenceVsActiveFxRatio
referenceVsActiveFyRatio
referenceCameraMatrixResolutionMismatchWarning

roiCenterNormalizedX
roiCenterNormalizedY
lastFocusPointNormalizedX
lastFocusPointNormalizedY
lastExposurePointNormalizedX
lastExposurePointNormalizedY
focusPointInsideROI
focusPointDistanceToROICenter
exposurePointInsideROI
exposurePointDistanceToROICenter
```

---

# Implementation Order

## Commit 1

Read-only diagnostics for active intrinsics, reference matrix, ROI center and focus/exposure point.

```bash
git commit -m "Add camera intrinsics reference diagnostics"
```

## Commit 2

Add high-resolution camera profile as experimental.

```bash
git commit -m "Add high resolution camera profile"
```

## Commit 3

Optional focus toward ROI center, disabled by default.

```bash
git commit -m "Add ROI center focus experiment"
```

Do not do Commit 3 until camera diagnostics are stable.

---

# Acceptance Criteria

- app builds
- default camera profile still works
- Wide 1.5x remains recommended for iPhone 16
- 2.0x remains experimental
- high resolution profile is not auto-selected
- reference camera matrix is read-only
- solvePnP primary path still uses active intrinsics
- export/finalization unchanged
- debug panel remains safe
- reports include new fields
- no external app/product names are used
