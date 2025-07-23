# tests/CheckViolations.Tests.ps1
$scriptPath = "$PSScriptRoot/../run-salesforce-code-analyzer-dev/scripts/CheckViolations.ps1"

Describe "CheckViolations.ps1" {
    BeforeEach {
        # Arrange test env
        $env:BUILD_STAGINGDIRECTORY = "$PSScriptRoot/tmp"
        New-Item -ItemType Directory -Path $env:BUILD_STAGINGDIRECTORY -Force | Out-Null
        $env:USE_SEVERITY_THRESHOLD = "true"
        $env:SFScanExitCode = 1
        $env:SEVERITY_THRESHOLD = "3"
        $env:STOP_ON_VIOLATIONS = "true"
        $env:MAXIMUM_VIOLATIONS = "10"
    }

    AfterEach {
        #Remove-Item -Path $env:BUILD_STAGINGDIRECTORY -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "When JSON file exists with violations above severity threshold" {
        It "should detect and sum the relevant severities, then set env vars and emit warnings" {
            # Arrange: Create a fake JSON results file
            $fakeResults = @{
                violationCounts = @{
                    total = 7
                    sev5 = 2
                    sev4 = 1
                    sev3 = 1
                    sev2 = 3
                }
            }
            $fakeResults | ConvertTo-Json | Set-Content -Path "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.json"

            $file = "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.json"
            # 👉 Confirm it was created
            Write-Host "DEBUG: Checking if file exists: $file"
            Test-Path $file | Should -BeTrue

            # 👉 Inspect file content
            Write-Host "DEBUG: Contents of JSON:"
            Get-Content $file | Write-Host

            # Act: Run the script
            $Output = & $scriptPath # TODO: FIX LOGIC IN HERE RELATING TO TOTALVIOLATIONS

            # Assert: Total violations picked up
            $env:totalViolations | Should -Be 7

            # Should sum severity 3, 4, 5 only
            $env:thresholdViolations | Should -Be 4
            $env:VIOLATIONS_EXCEEDED | Should -Be "true"

            $Output | Should -Match "Found '1' violations for severity 'sev3'"
            $Output | Should -Match "Found '1' violations for severity 'sev4'"
            $Output | Should -Match "Found '2' violations for severity 'sev5'"
        }
    }

    <#Context "When JSON file exists but violations are within limits" {
        It "should not exceed threshold and not fail build if STOP_ON_VIOLATIONS is false" {
            # Arrange
            $env:STOP_ON_VIOLATIONS = "false"
            $fakeResults = @{
                violationCounts = @{
                    total = 3
                    sev3 = 0
                    sev4 = 0
                    sev5 = 0
                }
            }
            $fakeResults | ConvertTo-Json | Set-Content -Path "$env:BUILD_STAGINGDIRECTORY/SFCAv5Results.json"

            # Act
            $Output = & $scriptPath

            $env:totalViolations | Should -Be 3
            $env:thresholdViolations | Should -Be 0
            $env:VIOLATIONS_EXCEEDED | Should -Be $null # Should stay unset
            $Output | Should -Match "Violations are within acceptable threshold"
        }
    }

    Context "When JSON file does not exist" {
        It "should warn and skip processing" {
            # Act
            $Output = & $scriptPath

            $Output | Should -Match "Results file not found"
        }
    }#>
}