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

Write-Host "---- PR Status check section ----"
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

Write-Host "---- PR Commenting Section ----"
# Set the base ADO comment URI up for use in inline comments and/or summary
$commentURI = "$collectionUri$escapedProject/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId/threads?api-version=7.1"
# We've already uploaded the published artefacts at this point, but keep using the build staging directory for now
$JSONOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/results/SFCAv5Results.json"
if($env:INPUT_POSTINLINECOMMENTSTOPR -eq 'true') {
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
    # Initialize counters for better summary commenting
    $violationsInPR = 0
    $violationsOutsidePR = 0
    $commentCounter = 0 # Count how many comments we POST, and use a hard limit to prevent overloading the PR
    foreach ($violation in ($SFCAResultJSON.violations)) { 
        $msg = "$($violation.rule): $($violation.message)"
        $filePath = $violation.locations[0].file
        $relativePath = $filePath -replace "^/home/vsts/work/[0-9]+/[as]/", "" # Replace the '/home/vsts/work/1/a' full paths - messaround here with leading slashes...
        # TODO: Improve the logic above so we're not having to use filthy regex...
        $line    = $violation.locations[0].startLine
        Write-Host "File path changed from '$filePath' to '$relativePath', msg is '$msg' and line is '$line'"
        # ✅ Check if this line is part of the PR diff
        if (($changedLinesPerFile.PSObject.Properties.Name -contains $relativePath) -and ($changedLinesPerFile.$relativePath -contains $line)) {
            Write-Host "💬 $relativePath`: $line is in diff — eligible for inline comment"
            $violationsInPR++
            # TODO: Handle the severity if filtering on that - .severity from .json file, and $env:INPUT_SEVERITYTHRESHOLD for the passed in value
            # If we filter on the right severity here though, the maths won't add up for issues in PR vs tech debt...
            # Build the inline comment body
            $messageContent = "⚠️ Engine: " + $violation.engine + " - Message: " + $msg
            if($null -ne $violation.resources) {
                $messageContent = $messageContent + " - Relevant resource: $($violation.resources)"
            }
            $commentBody = @{
                comments = @(@{
                    content = $messageContent
                    commentType = "text"
                })
                status = "active"
                threadContext = @{
                    filePath = "/" + $relativePath
                    rightFileStart = @{ line = $line; offset = 1 }
                    rightFileEnd   = @{ line = $line; offset = 1 }
                }
            } | ConvertTo-Json -Depth 5

            Write-Host "Scaffolded the comment body to pass to the ADO API"
            # POST comment to the right line on the PR
            try {
                Write-Host "Posting comment to $REPO_PROVIDER PR at URL: $commentURI"
                $response = Invoke-RestMethod -Uri $commentURI -Method Post -Headers $headers -Body $commentBody -ErrorAction Stop
                $commentCounter++ # Increment the total posted comments
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
        # Put a synthetic limit here so we're not overloading the PR
        # TODO: Expose this as a param? change to 20/30 by default?
        if ($commentCounter -ge 50) {
            Write-Warning "Reached 50 comments — stopping further inline POSTs - see the full html/json report for all issues."
            break
        }
    }
    Write-Host "✅ Violations in PR lines (new issues): '$violationsInPR'"
    Write-Host "⚠️ Violations outside PR lines (tech debt / existing code): '$violationsOutsidePR'"
}

# Check if we're POSTing comments to the PR and which provider route we need to take
if ($POST_COMMENTS_TO_PR -eq "true") {
    Write-Host "Summary comment requested - checking violation count and whether we did inline comments"
    if (($env:INPUT_POSTINLINECOMMENTSTOPR -eq 'true') -and ($totalViolations -gt 0)) {
        Write-Host "Inline comments POSTed and violations above 0, so we have the violations in and out of the PR to summarise"
        # 🧮 Calculate totals and percentages
        $totalViolations = $violationsInPR + $violationsOutsidePR
        $percentPR = if ($totalViolations -gt 0) { [math]::Round(($violationsInPR / $totalViolations) * 100, 1) } else { 0 }
        $percentOutside = if ($totalViolations -gt 0) { [math]::Round(($violationsOutsidePR / $totalViolations) * 100, 1) } else { 0 }

        # 🧠 Build Markdown summary comment - handling the picky indentation requirements
$commentText = @"
## 🧠 Salesforce Code Analysis Summary

| Type | Count | Percentage |
|------|--------|-------------|
| 🆕 **New issues (in PR changes)** | $violationsInPR | $percentPR% |
| 🧹 **Existing issues (tech debt)** | $violationsOutsidePR | $percentOutside% |

**Total violations:** $totalViolations

---

### 🔍 Highlights
- Found **$violationsInPR** potential new issues introduced in this PR.
- Detected **$violationsOutsidePR** existing issues in surrounding code (tech debt).
- New issues represent **$percentPR%** of all violations identified.

---

> 💡 _Tip: See the full report here - [Published artifacts]($publishedArtefactURL)._
"@
    }
    else {
        Write-Host "No inline comments, so just summarise the total violations with a link to the published artefacts (even if 0)"
        # 🧠 Build Markdown summary comment
$commentText = @"
## 🧠 Salesforce Code Analysis Summary

**Total violations:** $totalViolations

---

> 💡 _Tip: See the full report here - [Published artifacts]($publishedArtefactURL)._
"@
    }

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