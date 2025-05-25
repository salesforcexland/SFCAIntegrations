$JSONOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.json"
$totalViolations = 0

Write-Host "Assessing violations in file: '$JSONOutputFilePath'"
if (Test-Path $JSONOutputFilePath) {
    # Load the JSON and grab total violations
    $SFCAResultJSON = Get-Content $JSONOutputFilePath -Raw | ConvertFrom-Json
    $env:totalViolations = $SFCAResultJSON.violationCounts.total
    Write-Warning "Grabbed the total violations from the JSON as: '$env:totalViolations'"

    # Severity threshold to fail on (as a number, 1–5)
    $threshold = $env:SEVERITY_THRESHOLD

    # Start with 0 violations
    $severityExceededViolationsTotal = 0

    # Loop from threshold down to 1 (more severe)
    for ($i = [int]$threshold; $i -ge 1; $i--) {
        $sevKey = "sev$i"
        Write-Host "Searching for severity '$sevKey' violations:"
        if ($SFCAResultJSON.violationCounts.PSObject.Properties.Name -contains $sevKey) {
            $sevKeyViolations = $SFCAResultJSON.violationCounts.$sevKey
            $severityExceededViolationsTotal += $sevKeyViolations
            Write-Warning "Found '$sevKeyViolations' violations for severity '$sevKey' - adding to the total"
        }
    }
    Write-Host "Total violations at severity '$threshold' and higher: '$severityExceededViolationsTotal'"
} else {
    Write-Host "Results file not found at path: '$JSONOutputFilePath'"
}