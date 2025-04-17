if ($POST_STATUS_CHECK_TO_PR -eq "true" -and -not $env:SYSTEM_ACCESSTOKEN) {
    Write-Error "Missing SYSTEM_ACCESSTOKEN. Please add 'env: SYSTEM_ACCESSTOKEN: \$(System.AccessToken)' to the task declaration in your pipeline YAML."
    exit 1
}

$repositoryId = $env:BUILD_REPOSITORY_ID
$pullRequestId = $env:SYSTEM_PULLREQUEST_PULLREQUESTID
$accessToken = $env:SYSTEM_ACCESSTOKEN
$totalViolations = $env:totalViolations
$escapedProject = [System.Uri]::EscapeDataString($env:SYSTEM_TEAMPROJECT)
$buildUrl = "$env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI$escapedProject/_build/results?buildId=$env:BUILD_BUILDID"
$statusState = if ($env:VIOLATIONS_EXCEEDED -eq "true") { "failed" } else { "succeeded" }

$status = @{
  "state" = $statusState
  "description" = "Code analysis completed with $totalViolations violations. View details at: $buildUrl"
  "targetUrl" = $buildUrl
  "context" = @{
    "name" = "Salesforce Code Analyzer - Scan"
    "genre" = "SFCAPipeline"
  }
}

$collectionUri = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
Write-Host "Organization is '$collectionUri' and project is '$escapedProject'"
$statusJson = $status | ConvertTo-Json -Compress
$url = "$collectionUri$escapedProject/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId/statuses?api-version=7.1-preview.1"
Write-Host "Posting status to pull request at URL: '$url' with status JSON of: '$statusJson'"

$headers = @{
  "Content-Type" = "application/json"
  "Authorization" = "Bearer $accessToken"
}
try {
    $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $statusJson -ErrorAction Stop
    Write-Host "Successfully posted status to PR: $($response.context.name) — $($response.state)"
  } catch {
    Write-Error "Failed to post status: $_"
  }

