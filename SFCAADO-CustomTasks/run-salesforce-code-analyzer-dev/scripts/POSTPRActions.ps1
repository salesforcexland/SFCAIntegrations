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
Write-Host "---- Metrics section ----"
# Work out the distribution of new vs existing issues across the files involved in the PR, for inline commenting (if selected) and metrics
function Get-ViolationDistribution {
    param (
        [string]$JSONOutputFilePath,
        [string]$ChangedLinesJson
    )

    if (!(Test-Path $JSONOutputFilePath)) {
        throw "JSON output file not found: $JSONOutputFilePath"
    }

    $SFCAResultJSON = Get-Content $JSONOutputFilePath -Raw | ConvertFrom-Json
    $changedLinesPerFile = $ChangedLinesJson | ConvertFrom-Json

    $violationsInPR = @()
    $violationsOutsidePR = @()

    foreach ($violation in $SFCAResultJSON.violations) {
        $filePath = $violation.locations[0].file
        $relativePath = $filePath -replace "^/home/vsts/work/[0-9]+/[as]/", ""
        $line = $violation.locations[0].startLine

        if (($changedLinesPerFile.PSObject.Properties.Name -contains $relativePath) -and
            ($changedLinesPerFile.$relativePath -contains $line)) {
            $violationsInPR += $violation
        } else {
            $violationsOutsidePR += $violation
        }
    }

    return @{
        InPR = $violationsInPR
        OutsidePR = $violationsOutsidePR
    }
}
# We've already uploaded the published artefacts at this point, but keep using the build staging directory for now
$JSONOutputFilePath = "$env:BUILD_STAGINGDIRECTORY/results/SFCAv5Results.json"
Write-Host "Evaluating violations vs PR diff..."
$distribution = Get-ViolationDistribution -JSONOutputFilePath $JSONOutputFilePath -ChangedLinesJson $env:CHANGED_LINES_PER_FILE
$violationsInPR = $distribution.InPR
$violationsInPRCount = $violationsInPR.Count # May seem redundant, but used in a lot of places so better to grab it now
$violationsOutsidePR = $distribution.OutsidePR
$violationsOutsidePRCount = $violationsOutsidePR.Count
Write-Host "Found '$violationsInPRCount' violations in PR lines, and '$violationsOutsidePRCount' outside those lines across the rest of the file/s."

# Always calculate total debt, even if not posting inline
$totalViolations = $violationsInPRCount + $violationsOutsidePRCount
$percentPR = if ($totalViolations -gt 0) { [math]::Round(($violationsInPRCount / $totalViolations) * 100, 1) } else { 0 }
$percentOutside = if ($totalViolations -gt 0) { [math]::Round(($violationsOutsidePRCount / $totalViolations) * 100, 1) } else { 0 }
Write-Host "Found '$violationsInPRCount' potential new issues introduced in this PR."
Write-Host "Detected '$violationsOutsidePRCount' existing issues in surrounding code (tech debt)."
Write-Host "New issues represent '$percentPR%' of all violations identified"

Write-Host "---- PR Commenting Section ----"
# Set the base ADO comment URI up for use in inline comments and/or summary
$commentURI = "$collectionUri$escapedProject/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId/threads?api-version=7.1"

if($env:INPUT_POSTINLINECOMMENTSTOPR -eq 'true') {
    Write-Host "Looking to leave inline comments on the PR for the relevant violations"
    Write-Host "Repo root is: '$env:BUILD_SOURCESDIRECTORY' - need to switch this to repo relative paths and construct the comments"
    $commentCounter = 0 # Count how many comments we POST, and use a hard limit to prevent overloading the PR
    foreach ($violation in $violationsInPR) {
        $msg = "$($violation.rule): $($violation.message)"
        $filePath = $violation.locations[0].file
        $relativePath = $filePath -replace "^/home/vsts/work/[0-9]+/[as]/", ""
        $line = $violation.locations[0].startLine

        $messageContent = "⚠️ Engine: " + $violation.engine + " - Message: " + $msg
        if ($null -ne $violation.resources) {
            $messageContent += " - Relevant resource: $($violation.resources)"
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

        try {
            Write-Host "Posting comment '$messageContent' to URL: '$commentURI'"
            $response = Invoke-RestMethod -Uri $commentURI -Method Post -Headers $headers -Body $commentBody -ErrorAction Stop
            $commentCounter++

            if ($REPO_PROVIDER -eq "TfsGit") {
                Write-Host "✅ Posted PR comment (Thread ID: $($response.id)) — $($violation.rule)"
            }
        } catch {
            Write-Warning "Failed to post PR comment: $_"
        }

        if ($commentCounter -ge 20) {
            Write-Warning "Reached 20 comments — stopping further inline POSTs."
            break
        }
    }

    Write-Host "✅ Violations in PR lines (new issues): '$($violationsInPR.Count)'"
    Write-Host "⚠️ Violations outside PR lines (tech debt / existing code): '$($violationsOutsidePR.Count)'"
}

# Check if we're POSTing comments to the PR and which provider route we need to take
if ($POST_COMMENTS_TO_PR -eq "true") {
    Write-Host "Summary comment requested - checking violation count and whether we did inline comments"
    if ($totalViolations -gt 0) {
        Write-Host "Violations are above 0, so we have the violations in and out of the PR to summarise"
        # 🧠 Build Markdown summary comment - handling the picky indentation requirements
$commentText = @"
## 🧠 Salesforce Code Analysis Summary

| Type | Count | Percentage |
|------|--------|-------------|
| 🆕 **New issues (in PR changes)** | $violationsInPRCount | $percentPR% |
| 🧹 **Existing issues (tech debt)** | $violationsOutsidePRCount | $percentOutside% |

**Total violations (all severities, for your chosen --rule-selector):** $totalViolations

---

### 🔍 Highlights
- Found **$violationsInPRCount** potential new issues introduced in this PR.
- Detected **$violationsOutsidePRCount** existing issues in surrounding code (tech debt) - _NOTE: These issues would not be commented on in the PR_.
- New issues represent **$percentPR%** of all violations identified.

---

> 💡 _Tip: See the full report here - [Published artifacts]($publishedArtefactURL)._
"@
    }
    else {
        Write-Host "No violations found, so just showcase 0 issues found and link to the published artefacts"
        # 🧠 Build Markdown summary comment
$commentText = @"
## 🧠 Salesforce Code Analysis Summary

**Total violations (all severities, for your chosen --rule-selector):** $totalViolations

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