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
2. Add the task `Salesforce Code Analyzer - ADO PR Scan` to a YAML or Classic build pipeline.
3. Set optional parameters like `maximumViolations` or `postStatusCheckToPR`.

## Links

- [GitHub Repo](https://github.com/sam-gearset/SFCAIntegrations/tree/feature/SFCAADO-CustomTask-SplitAndV1)
- [Documentation](https://github.com/sam-gearset/SFCAIntegrations/tree/feature/SFCAADO-CustomTask-SplitAndV1)
- [Submit an Issue](https://github.com/sam-gearset/SFCAIntegrations/issues)