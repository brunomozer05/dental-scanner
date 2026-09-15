$ErrorActionPreference = "Stop"

$trackedFiles = @(git ls-files)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to enumerate tracked files."
}

$violations = [System.Collections.Generic.List[object]]::new()

foreach ($trackedFile in $trackedFiles) {
    $path = $trackedFile.Replace("\", "/")
    $reason = $null

    if ($path -match "(^|/)_local_reference(/|$)") {
        $reason = "local reference material must not be tracked"
    } elseif (
        $path -match "\.ndjson$" -and
        $path -notmatch "^DentalScannerTests/Fixtures/[^/]+\.ndjson$"
    ) {
        $reason = "session NDJSON is only allowed in DentalScannerTests/Fixtures"
    } elseif (
        $path -match "\.stl$" -and
        $path -notmatch "^DentalScanner/Models/[^/]+\.stl$"
    ) {
        $reason = "STL is only allowed for production assets in DentalScanner/Models"
    } elseif (
        $path -match "(^|/)(DerivedData|build|build-tests|\.build)(/|$)" -or
        $path -match "(^|/)[^/]+\.(xcworkspace|xcodeproj)(/|$)" -or
        $path -match "(^|/)xcuserdata(/|$)" -or
        $path -match "\.xcuserstate$" -or
        $path -match "\.ipa$" -or
        $path -match "^ThirdParty/OpenCV/"
    ) {
        $reason = "generated workspace, downloaded dependency, or local build output must not be tracked"
    } elseif (
        ($path -match "(^|/)\.env(\..+)?$" -and $path -notmatch "\.env\.example$") -or
        $path -match "(^|/)\.secrets(/|$)" -or
        $path -match "(^|/)(id_rsa|id_ed25519)$" -or
        $path -match "\.(p8|p12|pem|mobileprovision)$" -or
        $path -match "(^|/)(credentials|service-account)\.json$"
    ) {
        $reason = "credential or secret file must not be tracked"
    }

    if ($null -ne $reason) {
        $violations.Add([pscustomobject]@{
            Path = $path
            Reason = $reason
        })
    }
}

if ($violations.Count -gt 0) {
    Write-Host (
        "::error title=Repository hygiene check failed::" +
        "$($violations.Count) prohibited tracked file(s)."
    )
    foreach ($violation in $violations) {
        Write-Host "::error file=$($violation.Path)::$($violation.Reason)"
    }
    exit 1
}

Write-Host "Repository hygiene check passed for $($trackedFiles.Count) tracked files."
