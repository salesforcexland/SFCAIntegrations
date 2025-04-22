Write-Host "Starting Salesforce Code Analyzer v5 scan step..."

# 3. Install SF CLI (latest)
Write-Host "Installing Salesforce CLI..."
npm install -g @salesforce/cli@latest

# 4. Install SFCA v5 plugin
Write-Host "Installing Salesforce Code Analyzer plugin..."
sf plugins install code-analyzer@latest

# 5. Run SFCA v5 scan
$workspacePath = "$env:BUILD_STAGINGDIRECTORY/**"
$outputFilePath = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.html"

Write-Host "Running scan on workspace: $workspacePath"
$SeverityThreshold = 3 # TODO: Update with a passed in parameter
# Run and capture both output and exit code - using Out-String and trim to ensure multi line clean logging in the ADO console
# Grab any std outputs/errors into the variable for parsing later using 2>&1
$scanOutput = (& sf code-analyzer run --workspace $workspacePath --output-file $outputFilePath 2>&1 --severity-threshold $SeverityThreshold | Out-String).Trim()
$SFScanExitCode = $LASTEXITCODE

Write-Host "Exit code from scanner: '$SFScanExitCode'"
Write-Host "Raw scanner output:`n$scanOutput"

# Find the total number of violations using matching from the output
# Always try to get total violations, but only try and get violations exceeding threshold if we've got a non-zero exit code
if ($scanOutput -match 'Found\s+(\d+)\s+violation') {
    $totalViolations = [int]$matches[1]
    Write-Host "Total violations detected from scan output: $totalViolations"
    Write-Host "##vso[task.setvariable variable=totalViolations]$totalViolations" # TODO: may not need to do these since we're not accessing variables in other ADO tasks
    $env:totalViolations = $totalViolations
} else {
    Write-Warning "Could not parse total violations from scan output."
}

if (($totalViolations -gt [int]$env:MAXIMUM_VIOLATIONS) -and ($env:STOP_ON_VIOLATIONS -eq "true")) {
    Write-Host "Too many violations '$totalViolations' found - above the threshold of '$env:MAXIMUM_VIOLATIONS'"
    $env:VIOLATIONS_EXCEEDED = "true"
    Write-Host "##vso[task.setvariable variable=VIOLATIONS_EXCEEDED]true"
    Write-Error "Failing the build. See the HTML file in Published Artefacts for details"
} else {
    Write-Host "Violations '$totalViolations' found but STOP_ON_VIOLATIONS is false so passing"
}

# Only if threshold was exceeded (non-zero exit code), try to capture the threshold breach line
if ($SFScanExitCode -ne 0 -and $scanOutput -match '(\d+)\s+violations met or exceeded the severity threshold') {
    $thresholdBreaches = [int]$matches[1]
    Write-Warning "Violations above the supplied severity threshold: '$thresholdBreaches'"
    Write-Host "##vso[task.setvariable variable=thresholdViolations]$thresholdBreaches"
    $env:thresholdViolations = $thresholdBreaches
}

# 6. Publish the results as a pipeline artifact
Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-results;]$outputFilePath"
Write-Host "Scan complete. Results published as artifact: salesforce-code-analyzer-results"