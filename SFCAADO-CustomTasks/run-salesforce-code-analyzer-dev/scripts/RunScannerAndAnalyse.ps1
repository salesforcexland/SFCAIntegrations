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

Write-Host "Current env:PATH is '$env:PATH'"
# Check and install SF CLI if needed
if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
    Write-Host "SF CLI not found. Installing..."
    npm install -g @salesforce/cli
} else {
    Write-Host "SF CLI already installed, using cache"
}

Write-Host "SF CLI version:"
sf --version
Write-Host "Installing Code Analyzer plugin (latest)..."
sf plugins install code-analyzer@latest
sf plugins

# 4. Run SFCA v5 scan
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
    Write-Host "Delta PR scan requested - passing the copied files in '$env:BUILD_STAGINGDIRECTORY/**' into the --workspace param"
    $workspacePath = "$env:BUILD_STAGINGDIRECTORY/**"
}

Write-Host "Running scan on workspace: '$workspacePath' - preparing the rest of the scan arguments"
# Scaffold the workspace first, and add in the extra parameters as we need to for engines, severity threshold, outputs etc
$scanArgs = @("--workspace", $workspacePath)
# Handle multiple rule selectors - as of v5.6.1, these can be passed in with brackets and colons as delimeters, so handle those
if ($env:RULE_SELECTOR) {
    Write-Host "Rule selectors passed in are: '$env:RULE_SELECTOR' - any brackets/colons for multiple engines/tags are already handled in the scanner call later"
    $rawSelector = $env:RULE_SELECTOR

    $scanArgs += @("--rule-selector", $rawSelector)
    Write-Host "Adding in --rule-selector '$rawSelector' to the args"
}
if ($env:USE_SEVERITY_THRESHOLD -eq "true" -and $env:SEVERITY_THRESHOLD) {
    $scanArgs += @("--severity-threshold", $env:SEVERITY_THRESHOLD)
}
if($ConfigFileValid) {
    Write-Host "Config file '$CodeAnalyzerYmlFilePath' available - adding to the scan args"
    $scanArgs += @("--config-file", $CodeAnalyzerYmlFilePath)
}

# Always-required outputs - html comes in as default from the task.json, so exclude this, but json is needed for violation analysis
$requiredFormats = @("json")
# Valid formats map (normalize aliases -> canonical extension, ignoring htm and sarif.json)
$validFormats = @{
    "csv"        = "csv"
    "html"       = "html"
    "htm"        = "html"
    "json"       = "json"
    "sarif"      = "sarif"
    "sarif.json" = "sarif"
    "xml"        = "xml"
}
# Start with the defaults, since we need json for accurate rule assessments, and html is the most human-readable output with flexible filtering built-in
$formats = @($requiredFormats)

# Add user-specified formats (comma separated)
if ($env:OUTPUT_FILE_TYPES) { 
    Write-Host "Additional output formats requested: '$env:OUTPUT_FILE_TYPES'"
    $extraFormats = $env:OUTPUT_FILE_TYPES -split "," # Split on commas if there's more than 1 provided
    foreach ($format in $extraFormats) {
        $trimmedFormat = $format.Trim().ToLower()
        if ($validFormats.ContainsKey($trimmedFormat)) {
            $formats += $validFormats[$trimmedFormat]
        } else {
            Write-Warning "Unsupported output format '$trimmedFormat' ignored. Supported: csv, html, json, sarif, xml"
        }
    }
}

# Deduplicate (case-insensitive) - make sure we're not passing multiple of the same output type
$formats = $formats | Sort-Object -Unique

# Stage and create a results folder to house the 1 or more output types in
$resultsFolder = Join-Path $env:BUILD_STAGINGDIRECTORY "results"
# Ensure folder is created before the output files can save there or else the runner will fail
New-Item -ItemType Directory -Force -Path $resultsFolder | Out-Null

# Generate output files to pass to the scanner
foreach ($format in $formats) {
    $outPath = Join-Path $resultsFolder "SFCAv5Results.$format"
    $scanArgs += @("--output-file", $outPath)
    Write-Host "Adding output format '$format' -> $outPath"
}

Write-Host "Scan args to pass to 'sf code-analyzer run' are: '$scanArgs'"
# Run and capture both std outputs/errors and exit code - using Out-String and trim to ensure multi line clean logging in the ADO console
$scanOutput = (& sf code-analyzer run @scanArgs 2>&1 | Out-String).Trim()
$env:SFScanExitCode = $LASTEXITCODE

Write-Host "Exit code from scanner: '$env:SFScanExitCode'"
Write-Host "Raw scanner output:`n$scanOutput"

# Find the total number of violations from the json file (in the results folder)
if (Test-Path (Join-Path $resultsFolder "SFCAv5Results.json")) {
    Write-Host "Calling sub function ('CheckViolations.ps1') to assess violations from the JSON"
    . "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)/CheckViolations.ps1"
}
elseif ($scanOutput -match 'Found\s+(\d+)\s+violation') {
    # Backup for total violations
    $totalViolations = [int]$matches[1]
    Write-Warning "Couldn't find the json file - total violations detected from raw scan output: '$totalViolations'"
    $env:totalViolations = $totalViolations
} 
else {
    Write-Error "Could not parse total violations from scan output or JSON - cannot proceed."
    exit 1
}

# 5. Publish the results as a pipeline artifact
Write-Host "Scan complete. Uploading all scanner output files to 'salesforce-code-analyzer-results' in published artefacts"
# Upload 1 output folder of files since there could be 1 or multiple
Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-results;]$resultsFolder"
if($ConfigFileValid) {
    Write-Host "Valid config file found and used - uploading config folder to 'salesforce-code-analyzer-config' in published artefacts"
    Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-config]$configFolder"
}