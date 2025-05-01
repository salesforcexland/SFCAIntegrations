# Salesforce Code Analyzer - Azure DevOps PR Scan Task

This Azure DevOps extension provides a custom pipeline task that runs **Salesforce Code Analyzer v5** against PR-only delta changes in your Salesforce codebase. It supports configurable failure criteria, publishes scan artifacts, and optionally posts a status check back to the PR.

See [this](https://devopslaunchpad.com/blog/salesforce-code-analyzer/) detailed blog for further information.
---

## 🔍 What It Does

- Detects delta files in PRs (`cls`, `trigger`, `js`, `html`, `cmp`, `flow-meta.xml`, etc.)
- Runs [Salesforce Code Analyzer v5](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/overview)
- Supports **two failure modes**:
  - Max total violations exceeded
  - Any violations exceeding a **severity threshold** (Info → Critical)
- Publishes HTML scan results and delta files as pipeline artifacts
- Optionally posts a **status check** to the PR with success/failure

---

## ✅ Requirements

- Pipeline must run on `ubuntu-latest`
- Node.js 20+ and Python 3.10+ must be available (via `UseNode@1` and `UsePythonVersion@0`)
- PR build validation policies must be set up to control trigger behavior
- `checkout` step must override `fetchDepth` to 0 for proper git diffing

---

## 🧩 Task Inputs

| Name                   | Required      | Type     | Description |
|------------------------|---------------|----------|-------------|
| `maximumViolations`    | No            | Integer  | Max allowed violations before failing (default: `10`) |
| `stopOnViolations`     | No            | Boolean  | Whether to fail the build if violations exceed threshold (default: `true`) |
| `postStatusCheckToPR`  | No            | Boolean  | Whether to POST a result status back to the PR (default: `false`) |
| `extensionsToScan`     | No            | String   | Pipe-delimited list of file extensions to include (default: `cls\|trigger\|js\|html\|page\|cmp\|component\|flow-meta.xml`) |
| `useSeverityThreshold` | No            | Boolean  | Use severity-based failure instead of total violation count |
| `severityThreshold`    | Only if `useSeverityThreshold` is true | PickList | Severity level to fail on (`1` = Critical → `5` = Info) |

---

## 🔐 Required Permissions

If `postStatusCheckToPR` is set to `true`, you must add the following to your pipeline YAML:

```yaml
env:
  SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```
This allows the task to authenticate against the Azure DevOps API to post the result, as long as your build service user has the 'Contribute to Pull Requests' permission.

---

## 📁 Output

- Published artefacts on the Pipeline Build, including:
- Scan results HTML: `SFCAv5Results.html`
- Delta files scanned: Copied into artifact directory under 'scanned-delta-files'
- Optional status posted back to the source PR if necessary

---

## 🧪 Example Usage

```yaml 
trigger: none
pr: none  # We'll trigger this pipeline via branch policy for PRs

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
  - task: run-salesforce-code-analyzer@0
    inputs:
      stopOnViolations: true
      useSeverityThreshold: true
      severityThreshold: '3'  # Moderate and above
      extensionsToScan: "cls|trigger|js|html|page|cmp|component|flow-meta.xml"
      postStatusCheckToPR: true
    env:
      SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

---

## 📚 Resources

- [Detailed blog](https://devopslaunchpad.com/blog/salesforce-code-analyzer/)
- [Salesforce Code Analyzer Docs](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/overview)
- [Submit an Issue](https://github.com/sam-gearset/SFCAIntegrations/issues)

---

## 📬 Contact
For questions, suggestions, or support, feel free to reach out directly: [crossland9221@gmail.com]