# Salesforce Code Analyzer for Azure DevOps

This extension allows you to run Salesforce Code Analyzer v5 on the changed files in a pull request. It reports code violations, publishes results, and can fail the build to let you block merges. It follows a fail fast approach if there's no relevant files and skips the rest of the logic, gives you artifacts to analyse after a valid run, and provides detailed logs and feedback to that PR once complete.


## Key Features

- Threshold capabilities for the amount of issues you would accept before failing the build, or any issues above a particular severity
- Installs and uses the latest version of Salesforce Code Analyzer, currently v5
- Scans only changed files in PRs (delta scanning), using dynamic engine selection of the code-analyzer package
- Outputs results as artifacts (html report and each changed file) for investigation
- Optional PR status check POST onto the PR for extra visibility

## Requirements

- Azure DevOps (Cloud only), with an available build agent and permissions to configure the pipeline
- Pull request build validation setup using a .yml file and ADO Build Policies
- Your build user having 'Contribute to pull requests' permission if using the 'postStatusCheckToPR' option

## Usage

1. Install this extension in your Azure DevOps organization.
2. Add the task `Salesforce Code Analyzer - ADO PR Scan` to a YAML or Classic build pipeline, using the below example.
3. Assess parameters like `maximumViolations` or `postStatusCheckToPR` to create the right combination for your checks, as outlined below.
4. Consider if you would like to fail builds on total violations, or any issues above a particular severity threshold as outlined [here](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference_code-analyzer_commands_unified.htm#:~:text=t%20%7C%20%2D%2D-,severity,-%2Dthreshold%20SEVERITY%2DTHRESHOLD).
   - I'd recommend using the 'useSeverityThreshold' capability to be much more specific around what types of violation you'd like to fail builds on, rather than total violations.

## Task Inputs

| Name                   | Required      | Type     | Description |
|------------------------|---------------|----------|-------------|
| `maximumViolations`    | No            | Integer  | Max allowed violations before failing (default: `10`) |
| `stopOnViolations`     | No            | Boolean  | Whether to fail the build if violations exceed threshold (default: `true`) |
| `postStatusCheckToPR`  | No            | Boolean  | Whether to POST a result status back to the PR (default: `false`) |
| `extensionsToScan`     | No            | String   | Pipe-delimited list of file extensions to include (default: `cls\|trigger\|js\|html\|page\|cmp\|component\|flow-meta.xml`) |
| `useSeverityThreshold` | No            | Boolean  | Use severity-based failure instead of total violation count |
| `severityThreshold`    | Only if `useSeverityThreshold` is true | PickList | Severity level to fail on (`1` = Critical → `5` = Info) |

## Example usage

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
  # Keep the above installs separate to the task to allow ADO caching, and separate the SFCA-specific elements into the task  
  - task: run-salesforce-code-analyzer@0 # Call the custom task for SF Code Analyzer analysis
    inputs:
        stopOnViolations: true
        useSeverityThreshold: true
        severityThreshold: '3'  # Moderate and above
        extensionsToScan: "cls|trigger|js|html|page|cmp|component|flow-meta.xml"
        postStatusCheckToPR: false
```

  - If you were to set `postStatusCheckToPR` to be `true`, you need to make sure you pass in your SYSTEM_ACCESSTOKEN too so it can leverage your permissions to Contribute to Pull Requests.
  - An example is shown below for how you could do this, making sure you include any other relevant variables in the 'inputs':
```yaml
    inputs:
        postStatusCheckToPR: true
    env: 
        SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

## Links
- [Blog covering wider context and implementation guidance](https://devopslaunchpad.com/blog/salesforce-code-analyzer/)
- [GitHub Repo](https://github.com/salesforcexland/SFCAIntegrations)
- [Salesforce Code Analyzer Docs](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/overview)
- [Submit an Issue](https://github.com/salesforcexland/SFCAIntegrations/issues)

## 📬 Contact
For questions, suggestions, or support, feel free to reach out directly: **crossland9221@gmail.com**