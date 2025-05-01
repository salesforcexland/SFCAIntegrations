# Grab any configured variables from the task INPUT, and loop through to create internal env vars for the subfunctions
$USE_SEVERITY_THRESHOLD = $env:INPUT_USESEVERITYTHRESHOLD
Write-Warning "Set USE_SEVERITY_THRESHOLD to: $USE_SEVERITY_THRESHOLD - this dictates whether we're tracking total violations or any violations exceeding a specific threshold"
$env:USE_SEVERITY_THRESHOLD = $USE_SEVERITY_THRESHOLD # ← env vars for use throughout now

$MAXIMUM_VIOLATIONS = $env:INPUT_MAXIMUMVIOLATIONS
Write-Host "Set MAXIMUM_VIOLATIONS to: $MAXIMUM_VIOLATIONS"
$env:MAXIMUM_VIOLATIONS = $MAXIMUM_VIOLATIONS  

$SEVERITY_THRESHOLD = $env:INPUT_SEVERITYTHRESHOLD
Write-Host "Set SEVERITY_THRESHOLD to: $SEVERITY_THRESHOLD"
$env:SEVERITY_THRESHOLD = $SEVERITY_THRESHOLD 

$POST_STATUS_CHECK_TO_PR = $env:INPUT_POSTSTATUSCHECKTOPR
Write-Host "Set POST_STATUS_CHECK_TO_PR to: $POST_STATUS_CHECK_TO_PR"
$env:POST_STATUS_CHECK_TO_PR = $POST_STATUS_CHECK_TO_PR

$EXTENSIONS_TO_SCAN = $env:INPUT_EXTENSIONSTOSCAN
Write-Host "Set EXTENSIONS_TO_SCAN to: $EXTENSIONS_TO_SCAN"
$env:EXTENSIONS_TO_SCAN = $EXTENSIONS_TO_SCAN

$STOP_ON_VIOLATIONS = $env:INPUT_STOPONVIOLATIONS
Write-Host "Set STOP_ON_VIOLATIONS to: $STOP_ON_VIOLATIONS"
$env:STOP_ON_VIOLATIONS = $STOP_ON_VIOLATIONS

# Step 1 – always run to detect changes and set env var
. \"$PSScriptRoot/scripts/ScanDeltaFiles.ps1\"

# Re-fetch after ScanDeltaFiles.ps1 has set it
$RELEVANT_FILES_FOUND = $env:RELEVANT_FILES_FOUND
Write-Host "RELEVANT_FILES_FOUND is: $RELEVANT_FILES_FOUND"

# Step 2>4 – only proceed if RELEVANT_FILES_FOUND is true
if ($RELEVANT_FILES_FOUND -eq "true") {
    Write-Host "Relevant files have been found - handing off to RunScannerAndAnalyse"
    . \"$PSScriptRoot/scripts/RunScannerAndAnalyse.ps1\"

    Write-Host "Scan complete and violations analysed - setting whether violations were exceeded to be '$env:VIOLATIONS_EXCEEDED'"

    if ($POST_STATUS_CHECK_TO_PR -eq "true") {
        Write-Host 'POST status check is true - passing into subfunction'
        . \"$PSScriptRoot/scripts/POSTStatusCheck.ps1\"
    } else {
        Write-Host "POST_STATUS_CHECK_TO_PR is false — skipping status check"
    }

    # Final check to fail the build if needed (env var grabbed from CheckViolations.ps1) - TODO: to optimise logging
    if ($USE_SEVERITY_THRESHOLD -eq "true" -and ([int]$env:thresholdViolations -gt 0) -and $STOP_ON_VIOLATIONS -eq "true") {
        $failMessage = "❌ '$env:thresholdViolations' violations found exceeding the severity threshold of '$SEVERITY_THRESHOLD' and STOP_ON_VIOLATIONS = true — failing the build."
        Write-Host $failMessage
        Write-Host "##vso[task.logissue type=error]$failMessage"
        Write-Host "##vso[task.complete result=Failed;]$failMessage"
    }
    elseif ($env:VIOLATIONS_EXCEEDED -eq "true" -and $STOP_ON_VIOLATIONS -eq "true") {
        $failMessage = "❌ Too many violations ($env:totalViolations/$MAXIMUM_VIOLATIONS) found and STOP_ON_VIOLATIONS = true — failing the build."
        Write-Host $failMessage
        Write-Host "##vso[task.logissue type=error]$failMessage"
        Write-Host "##vso[task.complete result=Failed;]$failMessage"
    }
    elseif ($env:VIOLATIONS_EXCEEDED -eq "true" -and $STOP_ON_VIOLATIONS -eq "false") {
        $warningMessage = "⚠️ Violations ($env:totalViolations) exceeded threshold ($MAXIMUM_VIOLATIONS), but STOP_ON_VIOLATIONS is false — build allowed to pass."
        Write-Host $warningMessage
        Write-Host "##vso[task.logissue type=warning]$warningMessage"
        Write-Host "##vso[task.complete result=SucceededWithIssues;]$warningMessage"
    }
    else {
        Write-Host "✅ Build passed: violations found '$env:totalViolations' are either within the severity threshold, or less than the maximum allowed. Passed."
    }

} else {
    Write-Host "RELEVANT_FILES_FOUND is false — skipping scan, check, and status tasks"
}

