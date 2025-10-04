if ((($POST_STATUS_CHECK_TO_PR -eq "true") -or ($POST_COMMENTS_TO_PR -eq "true")) -and ((-not $env:SYSTEM_ACCESSTOKEN) -or (-not $env:GITHUB_TOKEN))) {
    if ($REPO_PROVIDER -eq "TfsGit" -and -not $env:SYSTEM_ACCESSTOKEN) {
          Write-Error "Missing SYSTEM_ACCESSTOKEN. Please add 'env: SYSTEM_ACCESSTOKEN: '\`$(System.AccessToken)' to the task declaration in your pipeline YAML to use PR POSTing."
          exit 1
    }
    if ($REPO_PROVIDER -eq "GitHub" -and -not $env:GITHUB_TOKEN) {
          Write-Error "Missing GITHUB_TOKEN environment variable. Set a GitHub personal access token to post comments."
          exit 1
    }  
}

# Set up all necessary variables from ADO environment attributes and construct URLs/headers for any calls
$repositoryId = $env:BUILD_REPOSITORY_ID
$pullRequestId = $env:SYSTEM_PULLREQUEST_PULLREQUESTID
$accessToken = $env:SYSTEM_ACCESSTOKEN
$totalViolations = $env:totalViolations
$escapedProject = [System.Uri]::EscapeDataString($env:SYSTEM_TEAMPROJECT)
$buildUrl = "$env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI$escapedProject/_build/results?buildId=$env:BUILD_BUILDID"
  
$collectionUri = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
Write-Host "Organization is '$collectionUri' and project is '$escapedProject'"
$publishedArtefactURL = "$buildUrl&view=artifacts&type=publishedArtifacts"

$headers = @{
  "Content-Type" = "application/json"
  "Authorization" = "Bearer $accessToken"
}

# POSTing status check to PR logic, with custom link to the pipeline information
# NOTE - Only valid for ADO PRs - GitHub PRs already expose this by default so no extra POST required
if ($POST_STATUS_CHECK_TO_PR -eq "true") {
    switch ($REPO_PROVIDER) {
      "TfsGit" {
            $statusState = if ($env:VIOLATIONS_EXCEEDED -eq "true") { "failed" } else { "succeeded" }
            $status = @{
              "state" = $statusState
              "description" = "Code analysis completed with $totalViolations total violations (all severities). View more pipeline details at: $buildUrl"
              "targetUrl" = $buildUrl
              "context" = @{
                "name" = "Salesforce Code Analyzer - Scan"
                "genre" = "SFCAPipeline"
              }
            }

            $statusJson = $status | ConvertTo-Json -Compress
            $url = "$collectionUri$escapedProject/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId/statuses?api-version=7.1"
            Write-Host "Posting status to pull request at URL: '$url' with status JSON of: '$statusJson'"

            try {
                $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $statusJson -ErrorAction Stop
                Write-Host "Successfully posted status to PR: $($response.context.name) — $($response.state)"
              } catch {
                Write-Warning "Failed to post status: $_"
              }
      }
      "GitHub" {
              Write-Warning "GitHub Status checks are implicitly available, so no extra POST is required - skipping PR status check POST."
      }
      default {
              Write-Warning "Unsupported REPO_PROVIDER '$REPO_PROVIDER' — skipping PR status check POST."
      }
    }
}

# Check if we're POSTing comments to the PR and which provider route we need to take
if ($POST_COMMENTS_TO_PR -eq "true") {
    $commentText = "Salesforce Code Analyzer - analysis completed with '$totalViolations' total violations (all severities). [Published artifacts]($publishedArtefactURL)"
    # Provider-specific config
    switch ($REPO_PROVIDER) {
        "TfsGit" {
            $commentBody = @{
                comments = @(@{
                    content = $commentText
                    commentType = "text"
                })
                status = "active"
            } | ConvertTo-Json -Depth 3

            $commentURI = "$collectionUri$escapedProject/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId/threads?api-version=7.1"
            $headers = $headers # Already set earlier for ADO API in case we're POSTing a status too
        }
        "GitHub" {
            $repoFullName = $env:BUILD_REPOSITORY_NAME
            $prNumber     = $env:SYSTEM_PULLREQUEST_PULLREQUESTNUMBER

            $commentBody = @{
                body = $commentText
            } | ConvertTo-Json -Compress

            $headers = @{
                "Authorization" = "token $($env:GITHUB_TOKEN)"
                "Accept"        = "application/vnd.github+json"
                "User-Agent"    = "AzureDevOpsPipeline"
            }

            $commentURI = "https://api.github.com/repos/$repoFullName/issues/$prNumber/comments"
        }
        default {
            Write-Warning "Unsupported REPO_PROVIDER '$REPO_PROVIDER' — skipping PR comment."
            return
        }
    }

    # Post comment
    try {
        Write-Host "Posting comment to $REPO_PROVIDER PR at URL: $commentURI"
        $response = Invoke-RestMethod -Uri $commentURI -Method Post -Headers $headers -Body $commentBody -ErrorAction Stop

        if ($REPO_PROVIDER -eq "TfsGit") {
            Write-Host "Successfully posted PR comment (Thread ID: $($response.id), Status: $($response.status), Comment: $($response.comments[0].content))"
        }
        elseif ($REPO_PROVIDER -eq "GitHub") {
            Write-Host "Successfully posted GitHub PR comment: $($response.html_url)"
        }
    } catch {
        Write-Warning "Failed to post PR comment for '$REPO_PROVIDER': $_"
    }
}

$JSONOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/results/SFCAv5Results.json"
$POST_INLINE_COMMENTS = 'true'
# TODO: NEED TO ONLY COMMENT ON THE CHANGED LINES IN THE PR, NOT LINES ELSEWHERE IN THE FILE - use the PR hunks for changed lines vs existing lines we can't comment on
if($POST_INLINE_COMMENTS -eq 'true') {
    Write-Host "Looking to leave inline comments on the PR for the relevant violations"
    if (Test-Path $JSONOutputFilePath) {
        # Load the JSON and grab total violations
        $SFCAResultJSON = Get-Content $JSONOutputFilePath -Raw | ConvertFrom-Json
        Write-Host "Grabbed the content from the JSON file for violation/location"
    }

    $changedLinesJson = $env:CHANGED_LINES_PER_FILE
    $changedLinesPerFile = $changedLinesJson | ConvertFrom-Json
    Write-Host "Grabbed the content from the JSON variable for changed lines per file found in ScanDeltaFiles.ps1 - parsing and checking vs violations found"

    Write-Host "Repo root is: '$env:BUILD_SOURCESDIRECTORY' - need to switch this to repo relative paths and construct the comments"
    # Initialize counters
    $violationsInPR = 0
    $violationsOutsidePR = 0
    foreach ($violation in ($SFCAResultJSON.violations)) { 
        
        $msg = "$($violation.rule): $($violation.message)"
        $filePath = $violation.locations[0].file
        $relativePath = $filePath -replace "^/home/vsts/work/[0-9]+/[as]", "" # Replace the '/home/vsts/work/1/a/' full paths
        # TODO: Improve the logic above so we're not having to use filthy regex...
        $line    = $violation.locations[0].startLine
        Write-Host "File path changed from '$filePath' to '$relativePath', msg is '$msg' and line is '$line'"
        # ✅ Check if this line is part of the PR diff
        if (($changedLinesPerFile.PSObject.Properties.Name -contains $relativePath) -and ($changedLinesPerFile.$relativePath -contains $line)) {
            Write-Host "💬 $relativePath`: $line is in diff — eligible for inline comment"
            $violationsInPR++
            # 🧩 Build inline comment body
            $commentBody = @{
                comments = @(@{
                    content = $msg
                    commentType = "text"
                })
                status = "active"
                threadContext = @{
                    filePath = $relativePath
                    rightFileStart = @{ line = $line; offset = 1 }
                    rightFileEnd   = @{ line = $line; offset = 1 }
                }
            } | ConvertTo-Json -Depth 5

            Write-Host "Proposed comment body is: '$commentBody'"
            # POST comment to the right line
            try {
                Write-Host "Posting comment to $REPO_PROVIDER PR at URL: $commentURI"
                $response = Invoke-RestMethod -Uri $commentURI -Method Post -Headers $headers -Body $commentBody -ErrorAction Stop

                if ($REPO_PROVIDER -eq "TfsGit") {
                    Write-Host "Successfully posted PR comment (Thread ID: $($response.id), Status: $($response.status), Comment: $($response.comments[0].content))"
                }
            } catch {
                Write-Error "Failed to post PR comment for '$REPO_PROVIDER': $_"
                exit 1
            }
        }
        else {
            Write-Host "📝 $relativePath`: $line not in diff — skipping inline comment"
            $violationsOutsidePR++
        }
    }
    Write-Host "✅ Violations in PR lines (new issues): '$violationsInPR'"
    Write-Host "⚠️ Violations outside PR lines (tech debt / existing code): '$violationsOutsidePR'"
}