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

$JSONOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.json"
$POST_INLINE_COMMENTS = 'true'
if($POST_INLINE_COMMENTS -eq 'true') {
    if (Test-Path $JSONOutputFilePath) {
        # Load the JSON and grab total violations
        $SFCAResultJSON = Get-Content $JSONOutputFilePath -Raw | ConvertFrom-Json
    }
}