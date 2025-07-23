$JSONOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.json"
$totalViolations = 0

Write-Host "Assessing violations in file: '$JSONOutputFilePath'"
if (Test-Path $JSONOutputFilePath) {
    # Load the JSON and grab total violations
    $SFCAResultJSON = Get-Content $JSONOutputFilePath -Raw | ConvertFrom-Json
    $env:totalViolations = $SFCAResultJSON.violationCounts.total
    Write-Warning "Grabbed the total violations from the JSON as: '$env:totalViolations'"

    # Only proceed if we've got more than 1 violation, the SF exit code isn't 0, and use_severity_threshold is true, so we can find the violations
    if (($env:USE_SEVERITY_THRESHOLD -eq "true") -and ($env:SFScanExitCode -ne 0) -and ($env:totalViolations -ne 0)) {
        # Severity threshold to fail on (as a number, 1–5) and baseline total of 0
        $threshold = $env:SEVERITY_THRESHOLD
        $severityExceededViolationsTotal = 0
        # Loop from threshold down to 1 (more severe)
        $severityKeys = @($SFCAResultJSON.violationCounts.PSObject.Properties.Name)

        for ($i = [int]$threshold; $i -ge 1; $i--) {
            $sevKey = "sev$i"
            Write-Host "Searching for severity '$sevKey' violations:"
            if ($severityKeys -contains $sevKey) {
                $sevKeyViolations = $SFCAResultJSON.violationCounts.$sevKey
                $severityExceededViolationsTotal += $sevKeyViolations
                Write-Warning "Found '$sevKeyViolations' violations for severity '$sevKey' - adding to the total"
            }
        }
        Write-Host "Total violations at severity '$threshold' and higher: '$severityExceededViolationsTotal'"
        $env:thresholdViolations = $severityExceededViolationsTotal
        if ($severityExceededViolationsTotal -gt 0 -and $env:STOP_ON_VIOLATIONS -eq "true") {
            Write-Warning "Failing the build: '$severityExceededViolationsTotal' violations exceeded severity threshold '$env:SEVERITY_THRESHOLD'."
        } else {
            Write-Host "Severity threshold violations found, but STOP_ON_VIOLATIONS is false — build allowed to pass."
        }
        # Regardless of the stop_on_violations, the violation threshold was exceeded
        $env:VIOLATIONS_EXCEEDED = "true"
    }
    elseif ($env:totalViolations -gt [int]$env:MAXIMUM_VIOLATIONS -and $env:STOP_ON_VIOLATIONS -eq "true") {
        Write-Host "Too many violations '$env:totalViolations' found — above the threshold of '$env:MAXIMUM_VIOLATIONS'"
        $env:VIOLATIONS_EXCEEDED = "true"
        Write-Warning "Failing the build. See the HTML file in Published Artifacts for details."
    }
    else {
        Write-Host "Violations are within acceptable threshold or STOP_ON_VIOLATIONS is false — build allowed to pass."
    }
} else {
    Write-Warning "Results file not found at path: '$JSONOutputFilePath' - aborting"
}
