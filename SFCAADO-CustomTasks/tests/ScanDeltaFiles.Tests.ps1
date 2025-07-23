# tests/ScanDeltaFiles.Tests.ps1
Describe "ScanDeltaFiles.ps1" {
  BeforeAll {
        $scriptPath = "$PSScriptRoot/../run-salesforce-code-analyzer-dev/scripts/ScanDeltaFiles.ps1"
  }

  Context "When BUILD_REASON indicates PullRequest" {
    BeforeEach {
        $env:BUILD_REASON = "PullRequest"
        $env:SYSTEM_PULLREQUEST_SOURCEBRANCH = "refs/heads/feature/test"
        $env:SYSTEM_PULLREQUEST_TARGETBRANCHNAME = "main"
        $env:EXTENSIONS_TO_SCAN = "cls|trigger"
        $env:BUILD_STAGINGDIRECTORY = "$PSScriptRoot/tmp"
    }

    It "should find relevant files if git diff returns matching files" {
        # Mock git diff to simulate changed files
        Mock git { "src/classes/MyClass.cls`nsrc/classes/MyOtherClass.trigger" }

        # Mock filesystem operations so they don't run
        Mock New-Item { }
        Mock Copy-Item { }

        . $scriptPath

        $env:RELEVANT_FILES_FOUND | Should -Be "true"
    }

    It "should not find relevant files if git diff returns non-matching files" {
        Mock git { "src/scripts/IgnoreMe.ps1" }
        Mock New-Item { }
        Mock Copy-Item { }

        . $scriptPath

        $env:RELEVANT_FILES_FOUND | Should -Be "false"
    }

    It 'should copy relevant files and upload artifact if relevant files found' {
        $env:BUILD_REASON = 'PullRequest'
        $env:SYSTEM_PULLREQUEST_SOURCEBRANCH = 'feature/test'
        $env:SYSTEM_PULLREQUEST_TARGETBRANCHNAME = 'main'
        $env:EXTENSIONS_TO_SCAN = 'cls|trigger'
        $env:BUILD_STAGINGDIRECTORY = "$PSScriptRoot/tmp"

        # Fake source files
        New-Item -Path 'src/classes' -ItemType Directory -Force | Out-Null
        Set-Content -Path 'src/classes/MyClass.cls' -Value '// dummy'
        Set-Content -Path 'src/classes/MyOtherClass.trigger' -Value '// dummy'

        Mock git { "src/classes/MyClass.cls`nsrc/classes/MyOtherClass.trigger" }

        # Act
        & "$PSScriptRoot/../run-salesforce-code-analyzer-dev/scripts/ScanDeltaFiles.ps1"

        # Assert: Relevant files found = true
        $env:RELEVANT_FILES_FOUND | Should -Be 'true'

        # Assert: Files should exist in staging
        Test-Path "$env:BUILD_STAGINGDIRECTORY/src/classes/MyClass.cls" | Should -BeTrue
        Test-Path "$env:BUILD_STAGINGDIRECTORY/src/classes/MyOtherClass.trigger" | Should -BeTrue

        # Clean up
        Remove-Item 'src' -Recurse -Force
        Remove-Item $env:BUILD_STAGINGDIRECTORY -Recurse -Force
    }
  }

  Context "When BUILD_REASON is not PullRequest" {
    BeforeEach {
        $env:BUILD_REASON = "Manual"
    }

    It "should skip and set RELEVANT_FILES_FOUND to false" {
        . $scriptPath

        $env:RELEVANT_FILES_FOUND | Should -Be "false"
    }
  }
}