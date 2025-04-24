# Salesforce Code Analyzer for Azure DevOps

This extension runs Salesforce Code Analyzer v5 on the changed files in a pull request. It reports code violations, publishes results, and can fail the build to let you block merges.

## Key Features

- Scans only changed files in PRs (delta scanning)
- Uses the latest version of Salesforce Code Analyzer, currently v5
- Outputs results as artifacts (html report and each changed file)
- Optional PR status check POST onto the PR
- Threshold capabilities for the amount of issues you would accept before failing the build

## Requirements

- Azure DevOps (Cloud only)
- Pull request build validation setup using a .yml file and ADO Build Policies

## Usage

1. Install this extension in your Azure DevOps organization.
2. Add the task `Salesforce Code Analyzer - ADO PR Scan` to a YAML or Classic build pipeline, using the below example.
3. Assess parameters like `maximumViolations` or `postStatusCheckToPR` to create the right combination for your checks.
4. Consider if you would like to fail builds on total violations, or any issues above a particular severity threshold as outlined [here]https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference_code-analyzer_commands_unified.htm#:~:text=t%20%7C%20%2D%2D-,severity,-%2Dthreshold%20SEVERITY%2DTHRESHOLD.

```yaml 
trigger: none 
pr: none      # We don't need any branch/PR triggers here as we'll control it with Build Policies

pool:
  vmImage: ubuntu-latest

steps:
  - checkout: self
    fetchDepth: 0 # Make sure we're overriding 'shallow fetch' here to retrieve all git history
  - task: UseNode@1
    inputs:
      version: '22.x' # Ensure we have NodeJS 22.x at minimum to install SF CLI/Code Analyzer plugin later
      checkLatest: true
    displayName: 'Install NodeJS'
  - task: UsePythonVersion@0
    inputs:
      versionSpec: '3.10' # Ensure we have Python 3.10 at minimum for the Code Analyzer Flow engine
      addToPath: true
    displayName: 'Ensure Python 3.10+ is Available'
    
  - task: run-salesforce-code-analyzer@0 # Call the custom task for SF Code Analyzer analysis
    inputs:
      maximumViolations: '10'
      extensionsToScan: "cls|trigger|js|html|page|cmp|component|flow-meta.xml"
      postStatusCheckToPR: false
      stopOnViolations: true
```

  - If you were to set `postStatusCheckToPR` to be `true`, you need to make sure you pass in the below too so it can leverage your access token:
```yaml
    env: SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

## Links

- [GitHub Repo](https://github.com/sam-gearset/SFCAIntegrations/tree/feature/SFCAADO-CustomTask-SplitAndV1)
- [Documentation](https://github.com/sam-gearset/SFCAIntegrations/tree/feature/SFCAADO-CustomTask-SplitAndV1)
- [Submit an Issue](https://github.com/sam-gearset/SFCAIntegrations/issues)