Write-Host "Starting Salesforce Code Analyzer v5 scan step..."

# Check if we've got a custom code-analyzer.yml/yaml file passed in, and verify it exists first - failing early here
if(-not [string]::IsNullOrWhiteSpace($env:CONFIG_FILE_PATH)) {
    # Logic here to test it and validate, then copy to a a build/published location for further use
    $rawPath = $env:CONFIG_FILE_PATH
    # Resolve to absolute path
    if (-not (Split-Path $rawPath -IsAbsolute)) {
        $configFilePath = Join-Path $env:BUILD_SOURCESDIRECTORY $rawPath
    } else {
        $configFilePath = $rawPath
    }
    Write-Host "Config file provided at raw path of '$rawPath' and absolute path resolved to be '$configFilePath' - checking it exists (as yml) and is ready for copying"
    if ((Test-Path $configFilePath -PathType Leaf) -and ($configFilePath.ToLower().EndsWith(".yml") -or $configFilePath.ToLower().EndsWith(".yaml"))) {
        # Create a dedicated folder in the staging directory
        $configFolder = Join-Path $env:BUILD_STAGINGDIRECTORY "salesforce-code-analyzer-config"
        New-Item -ItemType Directory -Force -Path $configFolder | Out-Null

        # Copy the YAML config into that folder
        $CodeAnalyzerYmlFilePath = Join-Path $configFolder "code-analyzer.yml"
        Copy-Item -Path $configFilePath -Destination $CodeAnalyzerYmlFilePath -Force
        Write-Host "Config file '$configFilePath' copied to the build staging directory at '$CodeAnalyzerYmlFilePath'"
        $ConfigFileValid = $true
    }
    else {
        Write-Warning "⚠ Config file not found at: '$configFilePath'. Proceeding without it."
    }
}

# 3. Install SF CLI (latest)
Write-Host "Installing Salesforce CLI:"
npm install -g @salesforce/cli@latest

Write-Host "Installed Salesforce CLI version:"
sf --version

# 4. Install SFCA v5 plugin
Write-Host "Installing Salesforce Code Analyzer plugin:"
sf plugins install code-analyzer@latest

# 5. Run SFCA v5 scan
Write-Host "Checked out branch ref is: $env:BUILD_SOURCEBRANCH"
# If scanning the whole branch, use the sources directory and output the parent folders we find
# If scanning only specific files, use the outputted files in the artefacts directory
if ($env:SCAN_FULL_BRANCH -eq "true") {
    Write-Host "----------------------------------------"
    Write-Host "🔍 Salesforce Code Analyzer: Starting recursive full branch scan on workspace: '$env:BUILD_SOURCESDIRECTORY'"
    Write-Host "Root folders in workspace:"
    Get-ChildItem -Name -Path $env:BUILD_SOURCESDIRECTORY
    Write-Host "----------------------------------------"
    $workspacePath = "$env:BUILD_SOURCESDIRECTORY"
} else {
    # Delta scanning logic sets a file list or narrower path.
    Write-Host "Full branch scan requested - passing the copied files in '$env:BUILD_STAGINGDIRECTORY/**' into the --workspace param"
    $workspacePath = "$env:BUILD_STAGINGDIRECTORY/**"
}
$HTMLOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.html"
$JSONOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.json"

Write-Host "Running scan on workspace: $workspacePath"
# Output both HTML and JSON for usage later
# TODO: if running a full branch scan, we could pass in a Graph Engine flag in future to override and run '--rule-selector sfge'
$scanArgs = @("--rule-selector", $env:RULE_SELECTOR, "--workspace", $workspacePath, "--output-file", $HTMLOutputFilePath, "--output-file", $JSONOutputFilePath)
if ($env:USE_SEVERITY_THRESHOLD -eq "true" -and $env:SEVERITY_THRESHOLD) {
    $scanArgs += @("--severity-threshold", $env:SEVERITY_THRESHOLD)
}
if($ConfigFileValid) {
    Write-Host "Config file '$CodeAnalyzerYmlFilePath' available - adding to the scan args"
    $scanArgs += @("--config-file", $CodeAnalyzerYmlFilePath)
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
    Write-Error "Could not parse total violations from scan output or JSON - cannot proceed."
    exit 1
}

# 6. Publish the results as a pipeline artifact
Write-Host "Scan complete. Uploading HTML and JSON outputs to 'salesforce-code-analyzer-results' in published artefacts"
Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-results;]$HTMLOutputFilePath"
Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-results;]$JSONOutputFilePath"
if($ConfigFileValid) {
    Write-Host "Valid config file found and used - uploading config folder to 'salesforce-code-analyzer-config' in published artefacts"
    Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-config]$configFolder"
}