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

$EXTENSIONS_TO_SCAN = $env:INPUT_EXTENSIONSTOSCAN
Write-Host "Set EXTENSIONS_TO_SCAN to: $EXTENSIONS_TO_SCAN"
$env:EXTENSIONS_TO_SCAN = $EXTENSIONS_TO_SCAN

$STOP_ON_VIOLATIONS = $env:INPUT_STOPONVIOLATIONS
Write-Host "Set STOP_ON_VIOLATIONS to: $STOP_ON_VIOLATIONS"
$env:STOP_ON_VIOLATIONS = $STOP_ON_VIOLATIONS

$POST_STATUS_CHECK_TO_PR = $env:INPUT_POSTSTATUSCHECKTOPR
Write-Host "Set POST_STATUS_CHECK_TO_PR to: $POST_STATUS_CHECK_TO_PR"
$env:POST_STATUS_CHECK_TO_PR = $POST_STATUS_CHECK_TO_PR

$POST_COMMENTS_TO_PR = $env:INPUT_POSTCOMMENTSTOPR
Write-Host "Set POST_COMMENTS_TO_PR to: $POST_COMMENTS_TO_PR"
$env:POST_COMMENTS_TO_PR = $POST_COMMENTS_TO_PR

$SCAN_FULL_BRANCH = $env:INPUT_SCANFULLBRANCH
Write-Host "Set SCAN_FULL_BRANCH to: $SCAN_FULL_BRANCH"
$env:SCAN_FULL_BRANCH = $SCAN_FULL_BRANCH

# If scanFullBranch is true, skip the delta logic entirely
if ($SCAN_FULL_BRANCH -eq "true") {
    # TODO: In future, we could pass the Graph Engine flag in here for full scans using engine 'sfge' (https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/guide/engine-sfge.html)
    Write-Host "Scan full branch requested — skipping ScanDeltaFiles and running full scan on the branch '$env:BUILD_SOURCEBRANCH'."
    . "$PSScriptRoot/scripts/RunScannerAndAnalyse.ps1"
}
else {
    # Normal delta flow for PRs
    Write-Host "Scan full branch is FALSE — checking we're in a PR and only scanning if we have relevant files in the delta"
    # Step 1 – always run to detect changes and set env var
    . \"$PSScriptRoot/scripts/ScanDeltaFiles.ps1\"

    # Re-fetch after ScanDeltaFiles.ps1 has set it
    $RELEVANT_FILES_FOUND = $env:RELEVANT_FILES_FOUND
    Write-Host "RELEVANT_FILES_FOUND is: $RELEVANT_FILES_FOUND"

    # Step 2>4 – only proceed if RELEVANT_FILES_FOUND is true (meaning we must be in a PR)
    if ($RELEVANT_FILES_FOUND -eq "true") {
        $env:VIOLATIONS_EXCEEDED = "false" # Staging this as false and only flip to true if we find issues
        Write-Host "Relevant files have been found - handing off to RunScannerAndAnalyse"
        . \"$PSScriptRoot/scripts/RunScannerAndAnalyse.ps1\"

        Write-Host "Scan complete and violations analysed - setting whether violations were exceeded to be '$env:VIOLATIONS_EXCEEDED'"

        if (($POST_STATUS_CHECK_TO_PR -eq "true") -or ($POST_COMMENTS_TO_PR -eq "true")) {
            Write-Host 'POST PR Actions requested - passing into subfunction'
            . \"$PSScriptRoot/scripts/POSTPRActions.ps1\"
        } else {
            Write-Host "POST PR actions (status/comments) are false — skipping"
        }
    } else {
        Write-Host "RELEVANT_FILES_FOUND is false — skipping scan, check, and status tasks"
    }
}

# Custom logging function for the ADO Pipeline results
function WriteTaskResult {
    param( [string]$Message, [string]$Type, [string]$Result )
    Write-Host $Message
    Write-Host "##vso[task.logissue type=$Type]$Message"
    Write-Host "##vso[task.complete result=$Result;]$Message"
}
# Considering the different routes a user could take via parameters, only check these if anything legitimate has happened
if (($SCAN_FULL_BRANCH -eq "true") -or ($RELEVANT_FILES_FOUND -eq "true")) {
    # Final check to fail the build if needed (env var grabbed from CheckViolations.ps1)
    if ($USE_SEVERITY_THRESHOLD -eq "true" -and ([int]$env:thresholdViolations -gt 0) -and $STOP_ON_VIOLATIONS -eq "true") {
        $failMessage = "❌ '$env:thresholdViolations' violations found exceeding the severity threshold of '$SEVERITY_THRESHOLD' and STOP_ON_VIOLATIONS = true — failing the build."
        WriteTaskResult -Message $failMessage -Type 'error' -Result 'Failed'
    }
    elseif ($env:VIOLATIONS_EXCEEDED -eq "true" -and $STOP_ON_VIOLATIONS -eq "true") {
        $failMessage = "❌ Too many violations ($env:totalViolations/$MAXIMUM_VIOLATIONS) found and STOP_ON_VIOLATIONS = true — failing the build."
        WriteTaskResult -Message $failMessage -Type 'error' -Result 'Failed'
    }
    elseif ($env:VIOLATIONS_EXCEEDED -eq "true" -and $STOP_ON_VIOLATIONS -eq "false") {
        $warningMessage = "⚠️ Violations ($env:totalViolations) exceeded threshold ($MAXIMUM_VIOLATIONS), but STOP_ON_VIOLATIONS is false — build allowed to pass."
        WriteTaskResult -Message $warningMessage -Type 'warning' -Result 'SucceededWithIssues'
    }
    else {
        Write-Host "✅ Build passed: violations found '$env:totalViolations' are either within the severity threshold, or less than the maximum allowed. Passed."
    }
}
else {
    $message = "No valid parameters passed for full branch or PR scan - build complete"
    Write-Host "##vso[task.complete result=Succeeded;]$message"
}


