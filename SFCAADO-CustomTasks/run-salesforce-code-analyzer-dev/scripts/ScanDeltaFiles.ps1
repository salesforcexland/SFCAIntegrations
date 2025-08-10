Write-Host "Checking whether we're in a PR or not, and proceeding to find delta files for scanning"
$targetfolder = "$env:BUILD_STAGINGDIRECTORY/"
$BUILD_REASON = $env:BUILD_REASON
$REPO_PROVIDER = $env:BUILD_REPOSITORY_PROVIDER
Write-Host "Build reason is - '$BUILD_REASON'"
Write-Host "Repository provider is - '$REPO_PROVIDER'"

if ($BUILD_REASON -match 'PullRequest') {
    if ($REPO_PROVIDER -eq "GitHub") {
        # GitHub Repos
        $SOURCE_BRANCH_NAME = $env:SYSTEM_PULLREQUEST_SOURCEBRANCH -replace '^refs/heads/', ''
        $TARGET_BRANCH_NAME = $env:SYSTEM_PULLREQUEST_TARGETBRANCH -replace '^refs/heads/', ''

        Write-Host "GitHub PR - Source: $SOURCE_BRANCH_NAME, Target: $TARGET_BRANCH_NAME - explicitly fetching"

        # Fetch branches explicitly
        git fetch origin +refs/heads/${SOURCE_BRANCH_NAME}:refs/remotes/origin/${SOURCE_BRANCH_NAME}
        git fetch origin +refs/heads/${TARGET_BRANCH_NAME}:refs/remotes/origin/${TARGET_BRANCH_NAME}
        git branch -a
        $TARGET_BRANCH = "refs/remotes/origin/$TARGET_BRANCH_NAME"
        $SOURCE_BRANCH = "refs/remotes/origin/$SOURCE_BRANCH_NAME"
    } else {
        # Azure Repos
        $SOURCE_BRANCH = $env:SYSTEM_PULLREQUEST_SOURCEBRANCH -replace '^refs/heads/', 'origin/'
        $TARGET_BRANCH = "origin/$($env:SYSTEM_PULLREQUEST_TARGETBRANCHNAME)"
        
        Write-Host "Azure Repos PR - Source: $SOURCE_BRANCH, Target: $TARGET_BRANCH"
    }
    # Single git diff regardless of repo type, using the right ref or branch name
    Write-Host "Running git diff between '$TARGET_BRANCH' and '$SOURCE_BRANCH' on provider '$REPO_PROVIDER'"
    $changes = git diff --name-only --relative --diff-filter=AMCR "$TARGET_BRANCH...$SOURCE_BRANCH"
    Write-Host "Changes:`n$changes"

    $pattern = "\.($env:EXTENSIONS_TO_SCAN)$"
    Write-Host "Passed in file extensions to scan are: $pattern"

    $changesArray = @($changes -split "`n")
    $RelevantFilesForScanning = $changesArray | Where-Object { $_ -match $pattern }

    $RelevantFilesFound = if ($RelevantFilesForScanning.Count -gt 0) { "true" } else { "false" }
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
        Write-Warning "No relevant files found. Skipping downstream steps."
    }
} else {
    Write-Warning "Not a PullRequest build. Skipping diff logic."
    $env:RELEVANT_FILES_FOUND = "false"
}