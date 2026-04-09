# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

### Added
- None yet.

### Changed
- None yet.

### Fixed
- None yet.

### Security
- None yet.

## [0.2.0] - 2026-04-09

### Added
- Tasky now runs as the Argo CD-managed workload and uses MongoDB for persistence.
- Manual GCP operations guidance was added for Artifact Registry, GKE, VM access, and troubleshooting.

### Changed
- GitOps rendered manifests were aligned with the current deployment flow and secret handling.
- CI and release automation were tightened around the app, infra, and GitOps paths.

### Fixed
- Tasky runtime configuration was aligned with the deployed port and MongoDB environment variables.
- Argo CD and Dex configuration issues were cleaned up to avoid malformed rendered values.

### Security
- Secret handling was moved to SOPS-encrypted values and rendered plaintext secrets were removed.
- Security scans and policy exceptions were updated to match the exercise environment.

## [0.1.0] - 2026-04-08

### Added
- Initial exercise-ready baseline release.

### Changed
- None.

### Fixed
- None.

### Security
- Baseline security controls and CI scanning in place.
