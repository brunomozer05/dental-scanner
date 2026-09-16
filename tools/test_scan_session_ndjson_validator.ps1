Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $PSScriptRoot 'validate_scan_session_ndjson.ps1'
$fixtureDirectory = Join-Path $repositoryRoot 'DentalScannerTests/Fixtures'
$powerShellExecutable = if ($PSVersionTable.PSEdition -eq 'Core') {
    Join-Path $PSHOME 'pwsh'
} else {
    Join-Path $PSHOME 'powershell.exe'
}

$cases = @(
    [pscustomobject]@{
        Fixture = 'valid_completed.ndjson'
        ShouldPass = $true
        ExpectedDiagnostic = 'Validation: PASSED'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'pregate_ab_valid.ndjson'
        ShouldPass = $true
        ExpectedDiagnostic = 'Validation: PASSED'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'duplicate_frame_index.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'frameIndex is not strictly increasing'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'frame_before_header.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'sessionHeader is not the first non-empty record'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'incomplete_session.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'sessionFooter.completed is false'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'incomplete_session.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'expected at least two frameObservation records; found 0'
        AllowIncomplete = $true
    },
    [pscustomobject]@{
        Fixture = 'malformed_record.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'failed JSON parsing'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'malformed_rotation_matrix.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'rotationMatrixRows payload(s) are malformed or non-finite'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'missing_footer.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'expected exactly one sessionFooter; found 0'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'missing_header.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'expected exactly one sessionHeader; found 0'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'record_after_footer.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = 'sessionFooter is not the last non-empty record'
        AllowIncomplete = $false
    },
    [pscustomobject]@{
        Fixture = 'unsupported_schema.ndjson'
        ShouldPass = $false
        ExpectedDiagnostic = "unsupported schemaVersion '2'"
        AllowIncomplete = $false
    }
)

$failures = [System.Collections.Generic.List[string]]::new()

foreach ($case in $cases) {
    $fixturePath = Join-Path $fixtureDirectory $case.Fixture
    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-File',
        $validatorPath,
        '-Path',
        $fixturePath
    )
    if ($case.AllowIncomplete) {
        $arguments += '-AllowIncomplete'
    }

    $output = @(& $powerShellExecutable @arguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $outputText = $output -join [Environment]::NewLine
    $caseName = $case.Fixture
    if ($case.AllowIncomplete) {
        $caseName += ' (-AllowIncomplete)'
    }

    $exitStatusMatches = if ($case.ShouldPass) {
        $exitCode -eq 0
    } else {
        $exitCode -ne 0
    }
    $diagnosticMatches = $outputText.Contains($case.ExpectedDiagnostic)

    if (-not $exitStatusMatches -or -not $diagnosticMatches) {
        $failures.Add(
            "$caseName expected pass=$($case.ShouldPass) and diagnostic " +
            "'$($case.ExpectedDiagnostic)', but exit=$exitCode and output was:`n$outputText"
        )
        Write-Host "FAIL: $caseName"
    } else {
        Write-Host "PASS: $caseName"
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Validator fixture harness failed with $($failures.Count) mismatch(es)."
    foreach ($failure in $failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host "Validator fixture harness passed all $($cases.Count) cases."
exit 0
