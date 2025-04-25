# TODO: LIKELY REDUNDANT NOW DUE TO V5 OUTPUTTING THE RESULTS/ERRORS/EXIT CODE UNLIKE V4 WHICH DIDN'T OUTPUT THE TOTAL IN THE LOGS
$resultsFile = "$env:BUILD_ARTIFACTSTAGINGDIRECTORY/SFCAv5Results.html"
$totalViolations = 0

Write-Host "Assessing violations in file: $resultsFile"

if (Test-Path $resultsFile) {
    $SFCAHTMLOutput = Get-Content -Path $resultsFile -Raw
    $violationsPattern = '"violationCounts":{(.*?)}'

    if ($SFCAHTMLOutput -match $violationsPattern) {
        $violationCounts = $matches[1]

        if ($violationCounts -match '"total":(\d+)') {
            $totalViolations = [int]$matches[1]
        }

        Write-Host "Total Code Violations: '$totalViolations'"
        $env:totalViolations = $totalViolations

        if (($totalViolations -gt [int]$env:MAXIMUM_VIOLATIONS) -and ($env:STOP_ON_VIOLATIONS -eq "true")) {
            Write-Host "Too many violations '$totalViolations' found - above the threshold of '$env:MAXIMUM_VIOLATIONS'"
            $env:VIOLATIONS_EXCEEDED = "true"
            Write-Error "Failing the build. See the HTML file in Published Artefacts for details"
        } else {
            Write-Host "Violations '$totalViolations' found but STOP_ON_VIOLATIONS is false so passing"
        }
    } else {
        Write-Host "No violations found in the HTML file or the pattern did not match - assuming 0"
    }
} else {
    Write-Host "Results file not found at path: $resultsFile"
}