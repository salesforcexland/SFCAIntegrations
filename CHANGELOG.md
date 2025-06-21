# Change Log
All notable changes to this project will be documented in this file.
 
The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).
 
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
 