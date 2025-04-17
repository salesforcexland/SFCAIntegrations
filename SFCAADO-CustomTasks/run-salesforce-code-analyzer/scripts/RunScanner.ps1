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
sf code-analyzer run --workspace $workspacePath --output-file $outputFilePath

# 6. Publish the results as a pipeline artifact
Write-Host "##vso[artifact.upload artifactname=salesforce-code-analyzer-results;]$outputFilePath"
Write-Host "Scan complete. Results published as artifact: salesforce-code-analyzer-results"