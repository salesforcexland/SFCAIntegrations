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

$scanArgs = @("--workspace", $workspacePath, "--output-file", $outputFilePath)
if ($env:USE_SEVERITY_THRESHOLD -eq "true" -and $env:SEVERITY_THRESHOLD) {
    $scanArgs += @("--severity-threshold", $env:SEVERITY_THRESHOLD)
}

Write-Host "Scan args to pass to 'sf code-analyzer run' are: '$scanArgs'"
# Run and capture both output and exit code - using Out-String and trim to ensure multi line clean logging in the ADO console
# Grab any std outputs/errors into the variable for parsing later using 2>&1
$scanOutput = (& sf code-analyzer run @scanArgs 2>&1 | Out-String).Trim()
$SFScanExitCode = $LASTEXITCODE

Write-Host "Exit code from scanner: '$SFScanExitCode'"
Write-Host "Raw scanner output:`n$scanOutput"

# Find the total number of violations from the scanner output
if ($scanOutput -match 'Found\s+(\d+)\s+violation') {
    $totalViolations = [int]$matches[1]
    Write-Host "Total violations detected from scan output: $totalViolations"
    $env:totalViolations = $totalViolations
} else {
    Write-Warning "Could not parse total violations from scan output."
}

# Determine failure condition based on selected strategy
if ($env:USE_SEVERITY_THRESHOLD -eq "true") {
    if ($SFScanExitCode -ne 0 -and $scanOutput -match '(\d+)\s+violations met or exceeded the severity threshold') {
        $thresholdBreaches = [int]$matches[1]
        Write-Warning "Violations above the supplied severity threshold: '$thresholdBreaches'"
        $env:thresholdViolations = $thresholdBreaches

        if ($thresholdBreaches -gt 0 -and $env:STOP_ON_VIOLATIONS -eq "true") {
            Write-Error "Failing the build: $thresholdBreaches violations exceeded severity threshold '$env:SEVERITY_THRESHOLD'."
            $env:VIOLATIONS_EXCEEDED = "true"
        } else {
            Write-Host "Severity threshold violations found, but STOP_ON_VIOLATIONS is false — build allowed to pass."
        }
    } else {
        Write-Host "No severity threshold violations found."
        $env:VIOLATIONS_EXCEEDED = "false"
    }
}
elseif ($totalViolations -gt [int]$env:MAXIMUM_VIOLATIONS -and $env:STOP_ON_VIOLATIONS -eq "true") {
    Write-Host "Too many violations '$totalViolations' found — above the threshold of '$env:MAXIMUM_VIOLATIONS'"
    $env:VIOLATIONS_EXCEEDED = "true"
    Write-Error "Failing the build. See the HTML file in Published Artefacts for details."
}
else {
    Write-Host "Violations are within acceptable threshold or STOP_ON_VIOLATIONS is false — build allowed to pass."
}

# 6. Publish the results as a pipeline artifact
Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-results;]$outputFilePath"
Write-Host "Scan complete. Results published as artifact: salesforce-code-analyzer-results"