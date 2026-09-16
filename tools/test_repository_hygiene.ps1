Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$checkerPath = Join-Path $PSScriptRoot 'check_repository_hygiene.ps1'
$powerShellExecutable = if ($PSVersionTable.PSEdition -eq 'Core') {
    Join-Path $PSHOME 'pwsh'
} else {
    Join-Path $PSHOME 'powershell.exe'
}
$temporaryRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("dental-scanner-hygiene-{0}" -f [System.Guid]::NewGuid().ToString('N'))

$cases = @(
    [pscustomobject]@{
        Name = 'approved repository paths'
        Paths = @(
            'DentalScanner/Source.swift',
            'DentalScanner/Models/reference.stl',
            'DentalScannerTests/Fixtures/session.ndjson'
        )
        ShouldPass = $true
        ExpectedDiagnostic = 'Repository hygiene check passed'
    },
    [pscustomobject]@{
        Name = 'local reference material'
        Paths = @('_local_reference/notes.txt')
        ShouldPass = $false
        ExpectedDiagnostic = 'local reference material must not be tracked'
    },
    [pscustomobject]@{
        Name = 'session NDJSON outside fixtures'
        Paths = @('captures/session.ndjson')
        ShouldPass = $false
        ExpectedDiagnostic = 'session NDJSON is only allowed in DentalScannerTests/Fixtures'
    },
    [pscustomobject]@{
        Name = 'STL outside production models'
        Paths = @('captures/scan.stl')
        ShouldPass = $false
        ExpectedDiagnostic = 'STL is only allowed for production assets in DentalScanner/Models'
    },
    [pscustomobject]@{
        Name = 'local build output'
        Paths = @('build/output.txt')
        ShouldPass = $false
        ExpectedDiagnostic = 'generated workspace, downloaded dependency, or local build output must not be tracked'
    },
    [pscustomobject]@{
        Name = 'generated Xcode workspace'
        Paths = @('DentalScanner.xcworkspace/contents.xcworkspacedata')
        ShouldPass = $false
        ExpectedDiagnostic = 'generated workspace, downloaded dependency, or local build output must not be tracked'
    },
    [pscustomobject]@{
        Name = 'Xcode user data'
        Paths = @('local/xcuserdata/user.xcuserdatad/settings.plist')
        ShouldPass = $false
        ExpectedDiagnostic = 'generated workspace, downloaded dependency, or local build output must not be tracked'
    },
    [pscustomobject]@{
        Name = 'IPA package'
        Paths = @('artifacts/DentalScanner.ipa')
        ShouldPass = $false
        ExpectedDiagnostic = 'generated workspace, downloaded dependency, or local build output must not be tracked'
    },
    [pscustomobject]@{
        Name = 'downloaded OpenCV'
        Paths = @('ThirdParty/OpenCV/opencv2.xcframework/Info.plist')
        ShouldPass = $false
        ExpectedDiagnostic = 'generated workspace, downloaded dependency, or local build output must not be tracked'
    },
    [pscustomobject]@{
        Name = 'credential filename'
        Paths = @('.env')
        ShouldPass = $false
        ExpectedDiagnostic = 'credential or secret file must not be tracked'
    }
)

function New-TestRepository {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [string[]] $TrackedPaths
    )

    New-Item -ItemType Directory -Path $Path | Out-Null
    & git -C $Path init --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to initialize temporary Git repository at '$Path'."
    }

    foreach ($trackedPath in $TrackedPaths) {
        $nativeRelativePath = $trackedPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $fullPath = Join-Path $Path $nativeRelativePath
        $parentDirectory = Split-Path -Parent $fullPath
        New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
        New-Item -ItemType File -Path $fullPath | Out-Null
    }

    & git -C $Path add --force -- $TrackedPaths
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to stage test paths in temporary Git repository at '$Path'."
    }
}

function Invoke-HygieneChecker {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryPath
    )

    Push-Location $RepositoryPath
    try {
        $output = @(
            & $powerShellExecutable -NoLogo -NoProfile -File $checkerPath 2>&1 |
                ForEach-Object { $_.ToString() }
        )
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output -join [Environment]::NewLine
    }
}

$failures = [System.Collections.Generic.List[string]]::new()

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

    for ($index = 0; $index -lt $cases.Count; $index++) {
        $case = $cases[$index]
        $repositoryPath = Join-Path $temporaryRoot ("case-{0}" -f $index)
        New-TestRepository -Path $repositoryPath -TrackedPaths $case.Paths
        $result = Invoke-HygieneChecker -RepositoryPath $repositoryPath

        $exitStatusMatches = if ($case.ShouldPass) {
            $result.ExitCode -eq 0
        } else {
            $result.ExitCode -ne 0
        }
        $diagnosticMatches = $result.Output.Contains($case.ExpectedDiagnostic)

        if (-not $exitStatusMatches -or -not $diagnosticMatches) {
            $failures.Add(
                "$($case.Name) expected pass=$($case.ShouldPass) and diagnostic " +
                "'$($case.ExpectedDiagnostic)', but exit=$($result.ExitCode) and output was:`n$($result.Output)"
            )
            Write-Host "FAIL: $($case.Name)"
        } else {
            Write-Host "PASS: $($case.Name)"
        }
    }
} finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $isExpectedTemporaryPath = (
        $resolvedTemporaryRoot.StartsWith(
            $resolvedSystemTemp,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith('dental-scanner-hygiene-')
    )
    if ($isExpectedTemporaryPath -and (Test-Path -LiteralPath $resolvedTemporaryRoot)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Repository hygiene harness failed with $($failures.Count) mismatch(es)."
    foreach ($failure in $failures) {
        Write-Host "- $failure"
    }
    exit 1
}

Write-Host "Repository hygiene harness passed all $($cases.Count) cases."
exit 0
