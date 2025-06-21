Write-Host "Starting Salesforce Code Analyzer v5 scan step..."

# 3. Install SF CLI (latest)
Write-Host "Installing Salesforce CLI:"
npm install -g @salesforce/cli@latest

Write-Host "Installed Salesforce CLI version:"
sf --version

# 4. Install SFCA v5 plugin
Write-Host "Installing Salesforce Code Analyzer plugin:"
sf plugins install code-analyzer@latest

# 5. Run SFCA v5 scan
$workspacePath = "$env:BUILD_STAGINGDIRECTORY/**"
$HTMLOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.html"
$JSONOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.json"

Write-Host "Running scan on workspace: $workspacePath"
# Output both HTML and JSON for usage later
$scanArgs = @("--workspace", $workspacePath, "--output-file", $HTMLOutputFilePath, "--output-file", $JSONOutputFilePath)
if ($env:USE_SEVERITY_THRESHOLD -eq "true" -and $env:SEVERITY_THRESHOLD) {
    $scanArgs += @("--severity-threshold", $env:SEVERITY_THRESHOLD)
}

Write-Host "Scan args to pass to 'sf code-analyzer run' are: '$scanArgs'"
# Run and capture both std outputs/errors and exit code - using Out-String and trim to ensure multi line clean logging in the ADO console
$scanOutput = (& sf code-analyzer run @scanArgs 2>&1 | Out-String).Trim()
$env:SFScanExitCode = $LASTEXITCODE

Write-Host "Exit code from scanner: '$env:SFScanExitCode'"
Write-Host "Raw scanner output:`n$scanOutput"

# Find the total number of violations from the json file
if (Test-Path $JSONOutputFilePath) {
    Write-Host "Calling sub function ('CheckViolations.ps1') to assess violations from the JSON"
    . "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)/CheckViolations.ps1"
}
elseif ($scanOutput -match 'Found\s+(\d+)\s+violation') {
    # Backup for total violations
    $totalViolations = [int]$matches[1]
    Write-Host "Total violations detected from scan output: $totalViolations"
    $env:totalViolations = $totalViolations
} 
else {
    Write-Warning "Could not parse total violations from scan output or JSON."
}

# 6. Publish the results as a pipeline artifact
Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-results;]$HTMLOutputFilePath"
Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-results;]$JSONOutputFilePath"
Write-Host "Scan complete. Results published as artifact: salesforce-code-analyzer-results"