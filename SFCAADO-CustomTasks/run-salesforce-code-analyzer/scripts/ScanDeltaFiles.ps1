$targetfolder = "$env:BUILD_STAGINGDIRECTORY/"

# Currently only runs on PRs as it depends on the delta to scan and generate the report, rather than a full branch worth of files
$BUILD_REASON = $env:BUILD_REASON
Write-Host "Build reason is - '$BUILD_REASON'"

if ($BUILD_REASON -match 'PullRequest') {
    $SOURCE_BRANCH_NAME = $env:SYSTEM_PULLREQUEST_SOURCEBRANCH -replace '^refs/heads/', 'origin/'
    $TARGET_BRANCH_NAME = "origin/$($env:SYSTEM_PULLREQUEST_TARGETBRANCHNAME)"
    Write-Host "Triggered by PullRequest - Source: $SOURCE_BRANCH_NAME, Target: $TARGET_BRANCH_NAME"

    $changes = git diff --name-only --relative --diff-filter=AMCR "$TARGET_BRANCH_NAME...$SOURCE_BRANCH_NAME"
    Write-Host "Changes:`n$changes"

    $pattern = "\.($env:EXTENSIONS_TO_SCAN)$"
    Write-Host "Passed in file extensions to scan are: $pattern"

    $changesArray = @($changes -split "`n")
    $RelevantFilesForScanning = $changesArray | Where-Object { $_ -match $pattern }

    $RelevantFilesFound = if ($RelevantFilesForScanning.Count -gt 0) { "true" } else { "false" }
    # Set the ADO variable
    Write-Host "##vso[task.setvariable variable=RELEVANT_FILES_FOUND;isOutput=true]$RelevantFilesFound"
    # Make it available to the core orchestrator and further subprocesses
    $env:RELEVANT_FILES_FOUND = $RelevantFilesFound
    Write-Host "RELEVANT_FILES_FOUND set to: $env:RELEVANT_FILES_FOUND"

    if ($RelevantFilesFound -eq "true") {
        Write-Host "Copying relevant files..."
        foreach ($file in $RelevantFilesForScanning) {
            Write-Host "Copying: $file"
            $target = Join-Path $targetfolder $file
            New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
            Copy-Item $file $target -Force
        }
    
        Write-Host "Uploading scanned delta files as pipeline artifact..."
        Write-Host "##vso[artifact.upload artifactname=scanned-delta-files]$env:BUILD_STAGINGDIRECTORY"
    } else {
        Write-Host "No relevant files found. Skipping downstream steps."
    }
} else {
    Write-Host "Not a PullRequest build. Skipping diff logic."
    $env:RELEVANT_FILES_FOUND = "false"
    Write-Host "##vso[task.setvariable variable=RELEVANT_FILES_FOUND]false"
}