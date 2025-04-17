# Salesforce Code Analyzer - Azure DevOps PR Scan Task

This Azure DevOps extension provides a custom pipeline task that runs **Salesforce Code Analyzer v5** against delta (PR-only) changes in your Salesforce source code. It supports configurable violation thresholds, optional status check reporting back to the pull request, and full artifact publication of scan results.

---

## 🔍 What It Does

- Detects changed files in PRs (`cls`, `trigger`, `js`, `html`, `cmp`, `flow-meta.xml`, etc.)
- Runs [Salesforce Code Analyzer v5](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/overview)
- Fails the build if violations exceed a threshold
- Optionally posts a status check back to the PR
- Publishes scan output as pipeline artifacts

---

## ✅ Requirements

- Pipeline must run on `ubuntu-latest`
- Node.js 20+ and Python 3.10+ must be present (can be installed via `UseNode@1` and `UsePythonVersion@0`)
- PR validation must be configured on your repo for the pipeline to trigger correctly

---

## 📦 Inputs

| Name                 | Required | Description |
|----------------------|----------|-------------|
| `maximumViolations` | ❌       | Max allowed violations before failing the build (default: `10`) |
| `postStatusCheckToPR` | ❌     | `true/false` — whether to post a PR status check (default: `false`) |

---

## 🔐 Required Permissions

If `postStatusCheckToPR` is enabled, make sure to add:
```yaml
env:
  SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```
This allows the task to authenticate against the Azure DevOps API to post the result.

---

## 📁 Output

- Scan results HTML: `SFCAv5Results.html`
- Delta files scanned: Copied into artifact directory
- Optional status posted back to the source PR

---

## 🧪 Example Usage

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
      maximumViolations: '41'
      extensionsToScan: "cls|trigger|js|html|page|cmp|component|flow-meta.xml"
      postStatusCheckToPR: false
      stopOnViolations: true
```

---

## 📸 Screenshot

![screenshot](images/screenshot.png)

---

## 📚 Resources

- [Salesforce Code Analyzer Docs](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/overview)
- [GitHub Repository](https://github.com/your-org/your-repo) <!-- update if applicable -->
- [File an Issue](https://github.com/your-org/your-repo/issues) <!-- update if applicable -->

---
