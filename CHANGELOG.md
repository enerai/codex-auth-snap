# Changelog

All notable changes to this project will be documented in this file.

## 0.2.0 - 2026-06-07

### Added

- Public GitHub project scaffold.
- MIT license.
- macOS GitHub Actions test workflow.
- Public README, quickstart, security policy, troubleshooting guide, and contribution guide.
- Local-only Codex ChatGPT `auth.json` snapshot switching CLI.
- Commands for `init`, `save`, `use`, `begin-login`, `finish-login`, `abort-login`, `install`, `list`, `current`, `remove`, `doctor`, `paths`, and `version`.
- Agent-friendly JSON envelope output through `--json`.
- Local diagnostics through `doctor`.
- zsh test suite using temporary directories.

### Security

- Refuses symlinked auth paths and state files.
- Uses mode `700` for state directories.
- Uses mode `600` for auth snapshots and state files.
- Avoids printing token fields or full auth JSON.
- Warns about cloud-synced-looking state paths.

### Notes

- First public release scope is macOS-only.
- Linux support is not claimed yet.
