# Changelog

All notable changes to WhoThere will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **BREAKING**: WhoThere now uses the host application's repo instead of its own
- Resources now get their repo from config: `config :who_there, repo: MyApp.Repo`
- Installer rewritten to use Igniter for proper Phoenix/Ash integration
- Removed `WhoThere.Repo` as the default repo (still available for testing)

### Added
- `WhoThere.Config` module for centralized configuration
- Proper package metadata for Hex publishing
- Ash formatter plugin in `.formatter.exs`
- Tenant resolver generator in installer
- Better documentation for multi-tenant setup

### Fixed
- Added `require_atomic? false` to update actions that use function changes

## [0.1.0] - 2024-XX-XX

### Added
- Initial release
- Session tracking without cookies (fingerprint-based)
- Page view and event tracking
- Bot detection
- Geographic data collection (privacy-respecting)
- Multi-tenant support via tenant_id attribute
- Daily analytics aggregation
- Phoenix LiveDashboard integration
- Telemetry integration
