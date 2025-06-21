if ((($POST_STATUS_CHECK_TO_PR -eq "true") -or ($POST_COMMENTS_TO_PR -eq "true")) -and -not $env:SYSTEM_ACCESSTOKEN) {
    Write-Error "Missing SYSTEM_ACCESSTOKEN. Please add 'env: SYSTEM_ACCESSTOKEN: '\`$(System.AccessToken)' to the task declaration in your pipeline YAML to use PR POSTing."
    exit 1
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

$headers = @{
  "Content-Type" = "application/json"
  "Authorization" = "Bearer $accessToken"
}

# POSTing status check to PR logic, with custom link to the pipeline information
if ($POST_STATUS_CHECK_TO_PR -eq "true") {
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

# POSTing summary comment to PR logic, linking to the published artefacts directly for easier access to the HTML/JSON reports
if ($POST_COMMENTS_TO_PR -eq "true") {
  $publishedArtefactURL = "$buildUrl&view=artifacts&type=publishedArtifacts"
  # Construct comment body linking to published artefacts
  $commentBody = @{
      comments = @(@{
          content = "Salesforce Code Analyzer - analysis completed with '$totalViolations' total violations (all severities). [Published artifacts]($publishedArtefactURL)"
          commentType = "text"
      })
      status = "active"
  } | ConvertTo-Json -Depth 3

  # PR thread endpoint
  $commentURI = "$collectionUri$escapedProject/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId/threads?api-version=7.1"
  try {
      $response = Invoke-RestMethod -Uri $commentURI -Method Post -Headers $headers -Body $commentBody -ErrorAction Stop
      Write-Host "Successfully posted PR comment (Thread ID: $($response.id), Status: $($response.status), Comment: $($response.comments[0].content))"
    } catch {
      Write-Warning "Failed to post comment: $_"
    }
}
