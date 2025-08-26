# Change Log
All notable changes to this project will be documented in this file.
 
The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [1.3.0] - 2025-08-26
 
### Added
- Added the capability to leverage the code-analyzer.yml configuration file (with parameter)
- Added the ability to override the --rule-selector flag to use specific engines and/or tags (with parameter)
- Allowed GitHub Repositories to be used in conjunction with the ADO Pipeline, rather than just ADO repos
### Changed
- Token checks before trying PR status checks/comments for both ADO and GitHub
- PR sub function to allow for github activities also
- Logic around gathering git diff source/target branch details between ADO and GitHub
### Fixed 
- Logging issues around full branch scan vs delta PRs
- Severity threshold vs max violation logic issues

## [1.2.2] - 2025-07-23
 
### Added
- Added the capability to run full branch scans instead of relying on PRs via the 'scanFullBranch' parameter, meaning you can conduct one-off/scheduled scans
- Unit testing scaffolding for key subfunctions
- Some placeholders for using Graph Engine in future
### Changed
- Logging around PR vs full branch scan
- Pipeline result logging function for use to wrap up the execution
- Tighter logging for fail/warning/successful builds
- Descriptions and names of task and vss-extension json to move away from 'PR only' wording
- Input table and example usage blocks of README/overview files to show full branch & PR usage 
### Fixed 
- Logging issues for stopping on violations

## [1.1.0] - 2025-06-21
 
### Added
- New scanner output type of 'json' published as an artefact to the same directory, and used to assess severity-based violations instead of the output
- Added SF version output for easy assessment in the logs of SF CLI and Code-Analyzer versions
- Made 'postCommentsToPR' available as a parameter to initially post a summary comment and quick link to the published artefacts as a comment to the PR
### Changed
- Streamlined the pipeline yml file as node/python are preinstalled on ubuntu-latest so aren't needed
- Modified the extensionsToScan example to include other -meta.xml files that could be flagged by the Regex engine for having outdated apiVersions
- Modified the POST subfunction to become extensible for other actions, not just POSTing the status check
### Fixed

 