# 15 — Validation Protocol, Comparator Metrics and Accuracy Evidence

## Status

Draft.

This spec defines how DentalScanner results should be validated.

Current comparisons between app-generated STLs measure repeatability, not absolute clinical accuracy.

True accuracy requires a professional reference scan or calibrated ground-truth model.

## Goal

Create a disciplined testing protocol so changes can be judged with data instead of visual impression only.

The protocol should validate:

- camera profile
- distance range
- ROI/frame mask
- useful observations
- angle diversity
- high resolution profile
- focus behavior
- final STL repeatability
- future absolute accuracy against reference STL

## Key Principle

Do not claim absolute accuracy from app-vs-app STL comparisons.

App-vs-app comparisons measure:

```txt
repeatability
stability
consistency
relative drift
```

They do not measure:

```txt
true clinical accuracy
absolute dimensional correctness
implant-level precision
```

---

# Test Sets

## Controlled iPhone 16 Test

Use:

```txt
iPhone 16 normal
physical wide camera
Wide 1.5x
distance 150–180 mm
same marker setup
same lighting
same operator
same scanning path
```

Minimum:

```txt
5 scans per profile
```

Profiles:

```txt
Wide 1.5x
Wide 1.5x Conservative Focus
Wide 1.5x High Resolution Experimental
Wide 1.0x as fallback/control
```

Do not include 2.0x unless specifically testing failure modes.

## Device Comparison Test

Devices:

```txt
iPhone 11
iPhone 13
iPhone 16
iPhone 16 Pro
```

Each:

```txt
same marker
same object/mold
same lighting
same scan instructions
minimum 3 scans per device/profile
```

## Distance Test

For iPhone 16 Wide 1.5x:

```txt
125–150 mm
150–180 mm
180–220 mm
```

Goal:

```txt
find distance band with best repeatability and focus stability
```

## ROI Test

Run scans intentionally:

```txt
markers centered
markers near border
markers partially outside safe ROI
```

Goal:

```txt
confirm frame mask warnings correlate with worse scans
```

---

# Files to Collect

For every scan:

```txt
STL
_report.json
_diagnostics.json
scan screenshot if possible
device/profile notes
```

CSV outputs:

```txt
scan_quality_ranking.csv
stl_comparison.csv
report_diagnostics.csv
scan_diagnostics_summary.csv
marker_report_diagnostics.csv
marker_timing_diagnostics.csv
all_anchors_component_comparison.csv
anchor_summary.csv
```

---

# Comparator Requirements

The comparator should export, without changing STL/ICP logic:

```txt
deviceModelIdentifier
deviceMarketingName
cameraProfileName
deviceQualityClass
requestedZoomFactor
appliedZoomFactor
currentVideoZoomFactor
activeVideoDimensions
activeFormatDescription

distanceGuideState
distanceGuideMessage

frameMaskQualityState
frameMaskQualityMessage
visibleMarkersInsideFrameMaskCount
visibleMarkersViolatingFrameMaskCount
anyMarkerNearFrameEdge

experimentalQualityModeEnabled
experimentalObservationGateEnabled
experimentalAcceptedObservationCount
experimentalRejectedObservationCount
experimentalRejectedByFrameMaskCount
experimentalRejectedByTooCloseCount
experimentalRejectedByTooFarCount
experimentalRejectedByFocusRiskCount
experimentalUsefulAllMarkersReady
experimentalOverallUsefulProgress

angularStdDeg
angleDiversityScore
angleDiversityReady

cameraHighResolutionProfileSelected
cameraAppliedHighResolutionDimensions

referenceCameraMatrixResolutionMismatchWarning
```

Do not change current score formula until enough data exists.

---

# Ranking Interpretation

Good scan candidate:

```txt
low mean distance
low P95
low alignment rotation
low relative marker std
few ROI violations
few focus-risk rejections
high useful progress
good angle diversity
stable intrinsics/profile metadata
```

Warnings:

```txt
HIGH_MEAN_DISTANCE
HIGH_P95
HIGH_ROTATION
HIGH_GEOMETRY_STD
ROI_VIOLATION
LOW_USEFUL_OBSERVATIONS
LOW_ANGLE_DIVERSITY
FOCUS_RISK_REJECTIONS
HIGH_REJECTED_OBSERVATIONS
UNKNOWN_DEVICE_QUALITY_CLASS
```

Do not add these warnings to scoring until enough scans confirm thresholds.

---

# Reference STL

To measure true accuracy, obtain:

```txt
professional lab scan STL
or calibrated industrial scanner STL
or known-dimension test object
```

Then compare:

```txt
DentalScanner STL vs reference STL
```

Metrics:

```txt
mean error
median error
P90
P95
P99
max error
surface heatmap
component/anchor error
rotation delta
translation delta
```

---

# Acceptance Thresholds

Initial repeatability targets:

```txt
mean app-vs-app distance < 0.35 mm
P95 app-vs-app distance < 0.8 mm
alignment rotation < 8 degrees
relative marker geometry score > 99
low ROI violations
usefulAllMarkersReady = true
```

These are not clinical claims.

Absolute accuracy targets should only be defined after reference STL exists.

---

# Test Report Template

For each test batch, create a markdown report:

```txt
test date
app commit hash
device
camera profile
distance range
lighting
marker version
number of scans
best scan
worst scan
ranking summary
main warnings
conclusion
next action
```

---

# Implementation Order

## Commit 1

Add this spec only.

```bash
git commit -m "Add validation protocol spec"
```

## Commit 2

Update comparator columns after app generates new diagnostics.

```bash
git commit -m "Export experimental quality diagnostics"
```

## Commit 3

Add optional markdown report generator to comparator.

```bash
git commit -m "Add scan validation report"
```

---

# Acceptance Criteria

- every test batch includes app commit hash
- every scan includes STL/report/diagnostics
- comparator supports old scans
- missing fields stay blank
- no score changes without evidence
- no absolute accuracy claim without reference STL
