# 14 — Future Marker v3, Extra Points and Robust PnP

## Status

Future design spec.

This spec must not be implemented until the current ArUco-only pipeline has enough diagnostics from:

- device quality profile
- frame mask / ROI
- useful observations
- angle diversity
- camera intrinsics
- high resolution test

Do not mention external app names or product names.

## Goal

Investigate whether the current single-ArUco marker is limiting pose precision.

A marker with more known points may allow:

- more stable solvePnP
- outlier rejection
- RANSAC
- lower sensitivity to one bad ArUco corner
- better pose repeatability
- stronger future bundle adjustment

## Current Limitation

A single square ArUco marker provides a small number of highly important points.

If one corner is blurred, reflected, partially occluded, or distorted by lens edge effects, the pose can be unstable.

Current v1 marker should remain supported.

Do not remove current marker support.

---

# Marker v3 Concept

A future marker may contain:

```txt
ArUco ID for identity
extra printed dots/circles
known 2D/3D point layout
matte/anti-reflective surface
rigid 3D printed body
precise printed alignment
no manually glued sticker if possible
```

The extra points should be geometrically known relative to the marker coordinate system.

## Goals

```txt
more than 4 usable image points
reject bad points
support RANSAC
support robust pose optimization
support quality scoring per point
```

## Non-goals

Do not implement in the first version:

```txt
YOLO
CoreML
ONNX
bundle adjustment
pose graph export
new STL geometry export behavior
```

Start with classical computer vision if possible.

---

# Extra Point Types

Possible point types:

## Circles / Dots

Pros:

```txt
easy to detect
subpixel center estimation possible
many points
RANSAC-friendly
```

Cons:

```txt
lighting/reflection sensitive
requires good print quality
needs robust thresholding
```

## ChArUco-style hybrid

Pros:

```txt
known board geometry
more points than ArUco alone
OpenCV may help
```

Cons:

```txt
may be harder to fit on small dental marker
requires careful physical design
```

## Custom keypoints

Pros:

```txt
can be optimized for this marker
```

Cons:

```txt
requires more custom detection
```

---

# Physical Design Requirements

Before implementing code, define:

```txt
marker size in mm
coordinate system
ArUco size
extra point positions in mm
minimum printed dot diameter
minimum spacing
material finish
print method
expected scan distance
expected camera zoom
```

All dimensions must be stored in a versioned marker profile.

---

# Marker Profile

Add future concept:

```swift
struct MarkerGeometryProfile {
    let id: String
    let name: String
    let version: Int
    let arucoSizeMm: Double
    let markerBodySizeMm: Double
    let objectPoints3D: [Point3D]
    let pointLabels: [String]
}
```

Do not implement if it risks breaking v1.

---

# Robust PnP Diagnostics First

Before replacing solvePnP, add read-only diagnostics.

Per marker:

```txt
pnpInputPointCount
pnpFinitePointCount
pnpInlierCount
pnpOutlierCount
pnpReprojectionMean
pnpReprojectionMax
pnpReprojectionStd
pnpWorstPointLabel
pnpWorstPointError
pnpQualityState
```

For current ArUco v1, these can be based on four corners.

For future marker v3, these can include additional points.

---

# Alternative PnP Read-only Experiment

Add later, behind a feature flag:

```txt
enableAlternativePnPDiagnostics = false
```

Possible methods:

```txt
IPPE
IPPE_SQUARE
solvePnPRansac
iterative solvePnP
```

Fields:

```txt
alternativePnPMethod
alternativePnPAvailable
alternativePnPReprojectionMean
alternativePnPReprojectionMax
alternativePnPInlierCount
alternativePnPTranslationDeltaFromCurrent
alternativePnPRotationDeltaFromCurrent
alternativePnPAccepted
alternativePnPRejectReason
```

Do not use alternative PnP for export at first.

---

# Future RANSAC Requirements

Initial parameters to test:

```txt
ransacMaxReprojError = 1.5
reprojErrorThreshold = 0.6
ransacMaxIterations = 200
ransacConfidence = 0.99
ransacMinInlierCount = 10
ransacMinPointCount = 5
```

These are starting points only.

They must be validated with DentalScanner marker geometry and real scans.

---

# Future Bundle Adjustment / Pose Graph

Do not implement here.

This spec only prepares the marker and PnP foundation.

Bundle adjustment / pose graph should be covered by a separate future spec after marker v3 and robust PnP diagnostics exist.

---

# Reports

Add fields when implemented:

```txt
markerGeometryProfileId
markerGeometryProfileVersion
pnpInputPointCount
pnpFinitePointCount
pnpInlierCount
pnpOutlierCount
pnpReprojectionMean
pnpReprojectionMax
pnpReprojectionStd
pnpWorstPointLabel
pnpWorstPointError
pnpQualityState

alternativePnPMethod
alternativePnPAvailable
alternativePnPReprojectionMean
alternativePnPReprojectionMax
alternativePnPInlierCount
alternativePnPTranslationDeltaFromCurrent
alternativePnPRotationDeltaFromCurrent
alternativePnPAccepted
alternativePnPRejectReason
```

---

# Acceptance Criteria for First Diagnostic Commit

- app builds
- v1 marker still works
- no export behavior changes
- current solvePnP remains primary
- alternative PnP is read-only if implemented
- reports contain PnP diagnostics
- no external app/product names are used
