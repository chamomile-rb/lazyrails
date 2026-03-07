# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-03-06

### Added

- Split-pane TUI with 14 panels: Status, Server, Routes, Database, Models, Tests, Gems, Rake, Console, Credentials, Logs, Mailers, Jobs, Custom Commands
- Rails introspection via `rails runner` for routes, migrations, models, associations, validations, rake tasks
- Fallback schema.rb parsing when Rails can't boot
- Dev server management (start/stop/restart) with bin/dev support
- Live log tailing with slow request and error filtering
- Test runner with per-file and full-suite execution (RSpec and Minitest)
- Interactive table data browser with WHERE, ORDER BY, and pagination
- Generator menu for models, migrations, controllers, scaffolds, jobs, mailers, channels, and stimulus controllers
- Rails console integration with expression evaluation
- Credentials viewer with per-environment decryption
- Mailer preview rendering
- Solid Queue jobs panel with retry, discard, dispatch, and status filtering
- Gem management with update and homepage links
- Command log with full history and undo support
- Three-tier confirmation system (green/yellow/red) for destructive operations
- Custom commands via `.lazyrails.yml` configuration
- Filterable panels with `/` search
