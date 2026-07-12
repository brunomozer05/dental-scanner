param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [switch]$AllowIncomplete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message)
}

function Has-Property {
    param($Object, [string]$Name)
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Require-Properties {
    param($Object, [string[]]$Names, [string]$Context)
    foreach ($name in $Names) {
        if (-not (Has-Property $Object $name)) {
            Add-Failure "$Context missing required field '$name'"
        }
    }
}

function Convert-ToFiniteDouble {
    param($Value)
    try {
        $number = [Convert]::ToDouble(
            $Value,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        if (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) {
            return $number
        }
    } catch {
        return $null
    }
    return $null
}

function Test-IdentityMatrixRows {
    param($Rows)
    $rowsArray = @($Rows)
    if ($rowsArray.Count -ne 3) {
        return $null
    }

    $expected = @(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
    $names = @('x', 'y', 'z')
    $isIdentity = $true

    for ($row = 0; $row -lt 3; $row++) {
        for ($column = 0; $column -lt 3; $column++) {
            if (-not (Has-Property $rowsArray[$row] $names[$column])) {
                return $null
            }
            $value = Convert-ToFiniteDouble $rowsArray[$row].($names[$column])
            if ($null -eq $value) {
                return $null
            }
            if ([Math]::Abs($value - $expected[($row * 3) + $column]) -gt 1e-12) {
                $isIdentity = $false
            }
        }
    }

    return $isIdentity
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Error "NDJSON file not found: $Path"
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$fileInfo = Get-Item -LiteralPath $resolvedPath
$lines = [System.IO.File]::ReadAllLines($resolvedPath)
$records = [System.Collections.Generic.List[object]]::new()
$parseFailureLines = [System.Collections.Generic.List[int]]::new()

for ($index = 0; $index -lt $lines.Count; $index++) {
    $lineNumber = $index + 1
    $line = $lines[$index]
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    try {
        $record = $line | ConvertFrom-Json -ErrorAction Stop
        if ($record -is [System.Array]) {
            Add-Failure "line $lineNumber is a JSON array; expected one JSON object"
            continue
        }
        $records.Add([pscustomobject]@{ LineNumber = $lineNumber; Value = $record })
    } catch {
        $parseFailureLines.Add($lineNumber)
        Add-Failure "line $lineNumber failed JSON parsing: $($_.Exception.Message)"
    }
}

if ($fileInfo.Length -le 0) {
    Add-Failure 'file is empty'
}
if ($records.Count -lt 4) {
    Add-Failure 'expected at least header, two frameObservation records, and footer'
}

$recordTypeCounts = @{}
foreach ($entry in $records) {
    $record = $entry.Value
    Require-Properties $record @('recordType', 'schemaVersion') "line $($entry.LineNumber)"
    if (-not (Has-Property $record 'recordType')) {
        continue
    }
    $recordType = [string]$record.recordType
    $currentCount = if ($recordTypeCounts.ContainsKey($recordType)) {
        [int]$recordTypeCounts[$recordType]
    } else {
        0
    }
    $recordTypeCounts[$recordType] = $currentCount + 1
    if ($recordType -notin @('sessionHeader', 'frameObservation', 'sessionFooter')) {
        Add-Failure "line $($entry.LineNumber) has unknown recordType '$recordType'"
    }
    if ((Has-Property $record 'schemaVersion') -and [int]$record.schemaVersion -ne 1) {
        Add-Failure "line $($entry.LineNumber) has unsupported schemaVersion '$($record.schemaVersion)'"
    }
}

$headers = @($records | Where-Object {
    (Has-Property $_.Value 'recordType') -and $_.Value.recordType -eq 'sessionHeader'
})
$frames = @($records | Where-Object {
    (Has-Property $_.Value 'recordType') -and $_.Value.recordType -eq 'frameObservation'
})
$footers = @($records | Where-Object {
    (Has-Property $_.Value 'recordType') -and $_.Value.recordType -eq 'sessionFooter'
})

if ($headers.Count -ne 1) { Add-Failure "expected exactly one sessionHeader; found $($headers.Count)" }
if ($footers.Count -ne 1) { Add-Failure "expected exactly one sessionFooter; found $($footers.Count)" }
if ($frames.Count -lt 2) { Add-Failure "expected at least two frameObservation records; found $($frames.Count)" }

$header = if ($headers.Count -eq 1) { $headers[0] } else { $null }
$footer = if ($footers.Count -eq 1) { $footers[0] } else { $null }

if ($null -ne $header) {
    if ($header.LineNumber -ne $records[0].LineNumber) {
        Add-Failure 'sessionHeader is not the first non-empty record'
    }
    Require-Properties $header.Value @(
        'sessionIdentifier', 'captureStartedTimestamp', 'deviceModelIdentifier',
        'osVersion', 'cameraProfileId', 'cameraProfileName', 'markerProfile',
        'expectedPhysicalMarkerIds', 'featureFlags'
    ) "line $($header.LineNumber) sessionHeader"
}

if ($null -ne $footer) {
    if ($footer.LineNumber -ne $records[$records.Count - 1].LineNumber) {
        Add-Failure 'sessionFooter is not the last non-empty record'
    }
    Require-Properties $footer.Value @(
        'completed', 'captureEndedTimestamp', 'framesEnqueued', 'framesWritten',
        'frameWriteFailureCount', 'frameOrderViolationCount', 'limitReached',
        'fileSizeBytes'
    ) "line $($footer.LineNumber) sessionFooter"
}

$frameIndices = [System.Collections.Generic.List[int64]]::new()
$frameTimestamps = [System.Collections.Generic.List[double]]::new()
$matrixCount = 0
$identityMatrixCount = 0
$nonIdentityMatrixCount = 0
$invalidMatrixCount = 0
$markerObservationCount = 0

foreach ($entry in $frames) {
    $record = $entry.Value
    Require-Properties $record @('frame') "line $($entry.LineNumber) frameObservation"
    if (-not (Has-Property $record 'frame')) { continue }
    $frame = $record.frame
    Require-Properties $frame @(
        'frameIndex', 'timestampSeconds', 'frameWidth', 'frameHeight',
        'intrinsicsAvailable', 'cameraProfileId', 'cameraProfileName',
        'markerObservations'
    ) "line $($entry.LineNumber) frame"

    if (Has-Property $frame 'frameIndex') {
        $frameIndices.Add([int64]$frame.frameIndex)
    }
    if (Has-Property $frame 'timestampSeconds') {
        $timestamp = Convert-ToFiniteDouble $frame.timestampSeconds
        if ($null -eq $timestamp) {
            Add-Failure "line $($entry.LineNumber) has non-finite timestampSeconds"
        } else {
            $frameTimestamps.Add($timestamp)
        }
    }
    if ((Has-Property $frame 'intrinsicsAvailable') -and [bool]$frame.intrinsicsAvailable) {
        Require-Properties $frame @('intrinsicFx', 'intrinsicFy', 'intrinsicCx', 'intrinsicCy') `
            "line $($entry.LineNumber) frame intrinsics"
        foreach ($intrinsicName in @('intrinsicFx', 'intrinsicFy', 'intrinsicCx', 'intrinsicCy')) {
            if ((Has-Property $frame $intrinsicName) -and
                $null -eq (Convert-ToFiniteDouble $frame.$intrinsicName)) {
                Add-Failure "line $($entry.LineNumber) has non-finite $intrinsicName"
            }
        }
    }
    if ($null -ne $header) {
        if ((Has-Property $header.Value 'cameraProfileId') -and
            (Has-Property $frame 'cameraProfileId') -and
            $frame.cameraProfileId -ne $header.Value.cameraProfileId) {
            Add-Failure "line $($entry.LineNumber) cameraProfileId differs from sessionHeader"
        }
        if ((Has-Property $header.Value 'cameraProfileName') -and
            (Has-Property $frame 'cameraProfileName') -and
            $frame.cameraProfileName -ne $header.Value.cameraProfileName) {
            Add-Failure "line $($entry.LineNumber) cameraProfileName differs from sessionHeader"
        }
    }

    if (-not (Has-Property $frame 'markerObservations')) { continue }
    foreach ($marker in @($frame.markerObservations)) {
        $markerObservationCount++
        Require-Properties $marker @(
            'markerId', 'markerSource', 'markerProfileId', 'imageCorners',
            'objectPoints', 'rotationVector', 'rotationMatrixRows',
            'translationVector', 'usedPointCount', 'poseFinite',
            'intrinsicsFinite', 'observationValid'
        ) "line $($entry.LineNumber) markerObservation"
        if ($null -ne $header -and
            (Has-Property $header.Value 'markerProfile') -and
            (Has-Property $marker 'markerProfileId') -and
            $marker.markerProfileId -ne $header.Value.markerProfile) {
            Add-Failure "line $($entry.LineNumber) markerProfileId differs from sessionHeader"
        }

        foreach ($vectorName in @('rotationVector', 'translationVector')) {
            if (Has-Property $marker $vectorName) {
                Require-Properties -Object $marker.$vectorName -Names @('x', 'y', 'z') `
                    -Context "line $($entry.LineNumber) markerObservation.$vectorName"
            }
        }

        if (Has-Property $marker 'rotationMatrixRows') {
            $matrixCount++
            $identityResult = Test-IdentityMatrixRows $marker.rotationMatrixRows
            if ($null -eq $identityResult) {
                $invalidMatrixCount++
            } elseif ($identityResult) {
                $identityMatrixCount++
            } else {
                $nonIdentityMatrixCount++
            }
        }
    }
}

for ($index = 1; $index -lt $frameIndices.Count; $index++) {
    if ($frameIndices[$index] -le $frameIndices[$index - 1]) {
        Add-Failure "frameIndex is not strictly increasing at frame record $($index + 1)"
    }
}
for ($index = 1; $index -lt $frameTimestamps.Count; $index++) {
    if ($frameTimestamps[$index] -lt $frameTimestamps[$index - 1]) {
        Add-Failure "timestampSeconds decreases at frame record $($index + 1)"
    }
}

if ($markerObservationCount -eq 0) {
    Add-Failure 'no marker observations were captured'
}
if ($matrixCount -eq 0) {
    Add-Failure 'no rotationMatrixRows payload was captured'
} elseif ($invalidMatrixCount -gt 0) {
    Add-Failure "$invalidMatrixCount rotationMatrixRows payload(s) are malformed or non-finite"
} elseif ($nonIdentityMatrixCount -eq 0) {
    Add-Failure 'all captured rotationMatrixRows payloads are identity matrices'
}

if ($null -ne $footer) {
    if (-not $AllowIncomplete -and -not [bool]$footer.Value.completed) {
        Add-Failure 'sessionFooter.completed is false'
    }
    if ([int64]$footer.Value.framesWritten -ne $frames.Count) {
        Add-Failure "footer framesWritten does not match frameObservation count"
    }
    if ([int64]$footer.Value.framesEnqueued -ne [int64]$footer.Value.framesWritten) {
        Add-Failure 'footer framesEnqueued does not equal framesWritten'
    }
    if ([int64]$footer.Value.frameWriteFailureCount -ne 0) {
        Add-Failure 'footer reports frame write failures'
    }
    if ([int64]$footer.Value.frameOrderViolationCount -ne 0) {
        Add-Failure 'footer reports frame order violations'
    }
    if ([bool]$footer.Value.limitReached) {
        Add-Failure 'footer reports capture file limit reached'
    }
    if ([int64]$footer.Value.fileSizeBytes -ne $fileInfo.Length) {
        Add-Failure "footer fileSizeBytes does not match actual file size"
    }
}

$sessionIdentifiers = @(
    $headers |
        ForEach-Object { $_.Value.sessionIdentifier } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Sort-Object -Unique
)
$firstFrameIndex = if ($frameIndices.Count -gt 0) { $frameIndices[0] } else { $null }
$lastFrameIndex = if ($frameIndices.Count -gt 0) { $frameIndices[$frameIndices.Count - 1] } else { $null }
$firstTimestamp = if ($frameTimestamps.Count -gt 0) { $frameTimestamps[0] } else { $null }
$lastTimestamp = if ($frameTimestamps.Count -gt 0) { $frameTimestamps[$frameTimestamps.Count - 1] } else { $null }

Write-Output "File: $resolvedPath"
Write-Output "Bytes: $($fileInfo.Length)"
Write-Output "Non-empty JSON records: $($records.Count)"
Write-Output "JSON parse failure lines: $(if ($parseFailureLines.Count) { $parseFailureLines -join ', ' } else { 'none' })"
$recordTypeSummary = (($recordTypeCounts.Keys | Sort-Object) | ForEach-Object {
    "$_=$($recordTypeCounts[$_])"
}) -join ', '
Write-Output "Record types: $recordTypeSummary"
Write-Output "Session identifiers: $(if ($sessionIdentifiers.Count) { $sessionIdentifiers -join ', ' } else { 'none' })"
Write-Output "Frame index range: $firstFrameIndex -> $lastFrameIndex"
Write-Output "Timestamp range: $firstTimestamp -> $lastTimestamp"
Write-Output "Marker observations: $markerObservationCount"
Write-Output "Rotation matrices: total=$matrixCount, nonIdentity=$nonIdentityMatrixCount, identity=$identityMatrixCount, invalid=$invalidMatrixCount"

if ($failures.Count -gt 0) {
    Write-Output "Validation: FAILED ($($failures.Count) issue(s))"
    foreach ($failure in $failures) {
        Write-Output "- $failure"
    }
    exit 1
}

Write-Output 'Validation: PASSED'
exit 0
