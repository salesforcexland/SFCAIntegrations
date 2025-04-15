# Pull in custom input from task.json
$MAXIMUM_VIOLATIONS = $env:INPUT_MAXIMUMVIOLATIONS
Write-Host "Set MAXIMUM_VIOLATIONS to: $MAXIMUM_VIOLATIONS"
Write-Host "##vso[task.setvariable variable=MAXIMUM_VIOLATIONS]$MAXIMUM_VIOLATIONS"
$env:MAXIMUM_VIOLATIONS = $MAXIMUM_VIOLATIONS  # ← export to env for child scripts

$POST_STATUS_CHECK_TO_PR = $env:INPUT_POSTSTATUSCHECKTOPR
Write-Host "Set POST_STATUS_CHECK_TO_PR to: $POST_STATUS_CHECK_TO_PR"
Write-Host "##vso[task.setvariable variable=POST_STATUS_CHECK_TO_PR]$POST_STATUS_CHECK_TO_PR"
$env:POST_STATUS_CHECK_TO_PR = $POST_STATUS_CHECK_TO_PR

# Set reusable token
Write-Host "##vso[task.setvariable variable=SYSTEM_ACCESSTOKEN]$env:SYSTEM_ACCESSTOKEN"

# Set constants / inferred defaults
$STOP_ON_VIOLATIONS = "true"
$EXTENSIONS_TO_SCAN = "cls|trigger|js|html|page|cmp|component|flow-meta.xml"

Write-Host "##vso[task.setvariable variable=STOP_ON_VIOLATIONS]$STOP_ON_VIOLATIONS"
$env:STOP_ON_VIOLATIONS = $STOP_ON_VIOLATIONS  # ← ensures child scripts receive it
Write-Host "##vso[task.setvariable variable=EXTENSIONS_TO_SCAN]$EXTENSIONS_TO_SCAN"
$env:EXTENSIONS_TO_SCAN = $EXTENSIONS_TO_SCAN  # ← Add this line

# Step 1 – always run to detect changes and set env var
. \"$PSScriptRoot/scripts/ScanDeltaFiles.ps1\"

# Re-fetch after ScanDeltaFiles.ps1 has set it
$RELEVANT_FILES_FOUND = $env:RELEVANT_FILES_FOUND
Write-Host "RELEVANT_FILES_FOUND is: $RELEVANT_FILES_FOUND"

# Step 2 – only proceed if RELEVANT_FILES_FOUND is true
if ($RELEVANT_FILES_FOUND -eq "true") {
    . \"$PSScriptRoot/scripts/RunScanner.ps1\"
    Write-Host "Scanner has been ran - now checking violations"
    . \"$PSScriptRoot/scripts/CheckViolations.ps1\"
    Write-Host "Checked the violations - setting whether violations were exceeded"
    $VIOLATIONS_EXCEEDED = $env:VIOLATIONS_EXCEEDED

    if ($POST_STATUS_CHECK_TO_PR -eq "true") {
        Write-Host 'POST status check is true - passing into subfunction'
        . \"$PSScriptRoot/scripts/POSTStatusCheck.ps1\"
    } else {
        Write-Host "POST_STATUS_CHECK_TO_PR is false — skipping status check"
    }

    # Final check to fail the build if needed (env var grabbed from CheckViolations.ps1)
    if ($VIOLATIONS_EXCEEDED -eq "true" -and $STOP_ON_VIOLATIONS -eq "true") {
        $failMessage = "❌ Too many violations ($env:totalViolations) found and STOP_ON_VIOLATIONS = true — failing the build."
        Write-Host $failMessage
        Write-Host "##vso[task.logissue type=error]$failMessage"
        Write-Host "##vso[task.complete result=Failed;]$failMessage"
    } else {
        Write-Host "Build passed: either violations are within threshold ($env:totalViolations/$MAXIMUM_VIOLATIONS) or STOP_ON_VIOLATIONS is false."
    }
} else {
    Write-Host "RELEVANT_FILES_FOUND is false — skipping scan, check, and status tasks"
}

