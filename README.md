# codex-auth-snap

English | [中文](README.zh-CN.md)

Tiny, auditable, offline Codex ChatGPT `auth.json` snapshot switcher for macOS, Linux, and Windows, built for high-volume coding workflows with multiple authorized ChatGPT accounts.

`codex-auth-snap` is a minimal local CLI for developers who code a lot with Codex and want a clean way to switch between their own authorized ChatGPT accounts on one machine. It saves and restores local `auth.json` snapshots. It has no third-party runtime dependencies, does not install a dependency tree, does not call the network, and never prints credential contents.

This project is not affiliated with OpenAI.

## Why This Project Exists

Codex ChatGPT auth can be stored in:

```text
$CODEX_HOME/auth.json
```

If you have more than one authorized Codex account on the same Mac, Linux, or Windows machine, switching accounts is really a local file operation: save the current `auth.json`, restore another one, then restart Codex so it rereads the file.

This tool makes that workflow explicit, repeatable, and easy to inspect.

## Who It Is For

This project is for developers, builders, and AI power users who:

- Use Codex heavily for programming, refactoring, debugging, and agentic coding.
- Keep multiple authorized ChatGPT or ChatGPT Plus accounts for legitimate personal, work, region, team, or billing separation.
- Want fast account switching without browser gymnastics, dependency-heavy tools, background agents, or network services.
- Prefer a tiny local CLI whose behavior can be inspected in one file.

It is not for credential sharing, account pooling, or policy evasion.

## Highlights

- **Tiny CLI logic**: separate bash and PowerShell scripts, direct file operations, no daemon, no background service.
- **Zero third-party runtime dependencies**: no npm package tree, no pip environment, no bundled dependency chain.
- **Smaller supply-chain attack surface**: the CLI uses platform-native system tools: `plutil`, BSD `stat`, and `shasum` on macOS; `python3`, GNU `stat`, and `sha256sum` on Linux; PowerShell JSON, hash, and ACL APIs on Windows.
- **Offline by design**: no network requests, no OpenAI API calls, no telemetry.
- **Concrete safety properties**: strict POSIX file permissions on macOS/Linux, Windows reparse point refusal, best-effort ACL tightening, bounded JSON output, token redaction, cloud-sync warnings.
- **Easy to audit**: the core behavior is in small OS-specific scripts, and the test suite uses temporary directories only.

## Search Keywords

Useful search terms for this project:

```text
Codex account switcher
Codex auth switcher
Codex auth.json switcher
Codex login switcher
OpenAI Codex account switcher
ChatGPT account switcher
ChatGPT Plus account switcher
multiple ChatGPT accounts
multiple Codex accounts
switch ChatGPT accounts on macOS
switch ChatGPT accounts on Linux
switch ChatGPT accounts on Windows
offline CLI
no dependency CLI
zero dependency shell script
zero dependency PowerShell script
supply chain safe CLI
local-first auth switcher
macOS bash CLI
Linux bash CLI
Windows PowerShell CLI
```

Suggested GitHub topics:

```text
codex
chatgpt
openai
codex-cli
codex-auth
auth-switcher
account-switcher
chatgpt-plus
macos
linux
windows
bash
powershell
cli
offline
no-dependencies
supply-chain-security
local-first
```

## Security Claim

No CLI can honestly promise absolute safety against malware, a compromised local user account, or manual credential sharing.

What `codex-auth-snap` does promise is narrower and verifiable:

- It never sends network requests.
- It never calls `codex logout`.
- It never refreshes tokens.
- It never decodes JWTs.
- It never prints `access_token`, `refresh_token`, `id_token`, or full `auth.json` content.
- It refuses symlinked auth paths and state files.
- On macOS and Linux, it writes state directories with mode `700`.
- On macOS and Linux, it writes auth snapshots and state files with mode `600`.
- On Windows, it refuses reparse points and uses best-effort ACL tightening for the current user.

Treat every `auth.json` and `*.auth.json` as a password.

## What It Does

- Saves the active Codex ChatGPT `auth.json` as a named local snapshot.
- Restores a saved snapshot into `$CODEX_HOME/auth.json`.
- Supports a safe login flow for adding another account.
- Keeps snapshot and state file permissions strict.
- Provides a `doctor` command for local diagnostics.
- Provides `--json` output for automation and agent-friendly tooling.

## What It Does Not Do

- It does not share, pool, sell, or broker accounts.
- It does not bypass usage limits, bans, rate limits, or policy enforcement.
- It does not automate account rotation.
- It does not call OpenAI APIs or any other network service.
- It does not parse, export, or print token values.

Only use this tool with accounts that you own or are explicitly authorized to use.

## Platform Support

Supported platforms:

- macOS and Linux through `./codex-auth-snap`
- Windows through `.\codex-auth-snap.ps1`
- bash on macOS/Linux
- Windows PowerShell 5+ or PowerShell 7+
- Codex configured for file-backed ChatGPT auth

Platform-specific system tools are intentionally handled in separate code paths:

- macOS: `plutil`, BSD `stat`, `shasum`
- Linux: `python3`, GNU `stat`, `sha256sum`
- Windows: PowerShell `ConvertFrom-Json`, `Get-FileHash`, `Get-Acl`, `Set-Acl`

## Install

From the repository root, install the script into your user bin directory:

```bash
./codex-auth-snap install
```

On Windows, use the PowerShell script:

```powershell
powershell -ExecutionPolicy Bypass -File .\codex-auth-snap.ps1 install
```

The default install paths are:

```text
macOS/Linux: $HOME/.local/bin/codex-auth-snap
Windows:     $HOME/.local/bin/codex-auth-snap.ps1
```

If `~/.local/bin` is on your `PATH`, you can run:

```bash
codex-auth-snap version
```

On Windows:

```powershell
codex-auth-snap.ps1 version
```

You can also install to a custom location:

```bash
./codex-auth-snap install --bin-dir "$HOME/bin"
./codex-auth-snap install --prefix "$HOME/.local"
```

On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\codex-auth-snap.ps1 install --bin-dir "$HOME\bin"
powershell -ExecutionPolicy Bypass -File .\codex-auth-snap.ps1 install --prefix "$HOME\.local"
```

`install` copies the current script. Re-run `install` after upgrading the repository checkout.

## Quick Start

Initialize Codex file-backed auth:

```bash
codex-auth-snap init --fix
codex-auth-snap --json doctor
```

Save the account that is currently logged in:

```bash
codex login
codex-auth-snap save personal
```

Add another account:

```bash
codex-auth-snap begin-login work
codex login
codex-auth-snap finish-login
```

Switch accounts:

```bash
codex-auth-snap use personal
# Restart Codex CLI or Codex App so it reads the restored auth.json.

codex-auth-snap use work
# Restart Codex CLI or Codex App again.
```

List saved snapshots:

```bash
codex-auth-snap list
codex-auth-snap current
```

Read the full guide in [docs/quickstart.md](docs/quickstart.md).

## Paths

Default Codex auth path:

```text
CODEX_HOME=${CODEX_HOME:-$HOME/.codex}
AUTH_FILE=$CODEX_HOME/auth.json
```

Default snapshot state path:

```text
CODEX_AUTH_SNAP_HOME=${CODEX_AUTH_SNAP_HOME:-$HOME/.codex-auth-snap}
```

State layout:

```text
$CODEX_AUTH_SNAP_HOME/
├── accounts/
├── meta/
├── before-login/
├── current
├── pending-login
└── lock/
```

Permission rules:

```text
directories: 700
auth.json / *.auth.json / meta / current / pending-login: 600
```

On Windows, the PowerShell script refuses reparse points and uses best-effort ACL tightening instead of POSIX `600`/`700` modes.

`CODEX_AUTH_SWITCH_HOME` and `CODEX_SWAP_HOME` are still accepted as legacy state directory variables for migration. If multiple variables are set, `CODEX_AUTH_SNAP_HOME` wins.

## Commands

```text
codex-auth-snap [--json] init [--fix] [--force]
codex-auth-snap [--json] save <name> [--force]
codex-auth-snap [--json] use <name> [--force]
codex-auth-snap [--json] begin-login <name> [--force]
codex-auth-snap [--json] finish-login [name] [--force]
codex-auth-snap [--json] abort-login [--force]
codex-auth-snap [--json] install [--prefix <dir>|--bin-dir <dir>] [--force]
codex-auth-snap [--json] list
codex-auth-snap [--json] current
codex-auth-snap [--json] remove <name> [--active-too]
codex-auth-snap [--json] doctor
codex-auth-snap [--json] paths
codex-auth-snap [--json] version
```

Windows uses the same commands with `codex-auth-snap.ps1`.

Account names may contain ASCII letters, digits, dots, underscores, and hyphens.

## JSON Output

All commands support `--json`. In JSON mode, stdout contains one envelope:

```json
{
  "content": [{"type": "text", "text": "short summary"}],
  "structuredContent": {"result": {}},
  "isError": false
}
```

Business failures return a non-zero exit code:

```json
{
  "content": [{"type": "text", "text": "short error"}],
  "structuredContent": {
    "error": {
      "code": "stable_error_code",
      "message": "what failed",
      "retryable": false,
      "field_errors": [],
      "suggested_fix": "what to do next"
    }
  },
  "isError": true
}
```

JSON output is intentionally bounded. `list` only shows account aliases, saved timestamps, current markers, and short hashes.

## Safety

- Do not commit auth snapshots.
- Do not share auth snapshots.
- Do not copy auth snapshots to another machine.
- Do not place snapshot state in iCloud, Dropbox, Google Drive, OneDrive, or another sync directory.
- Do not run multiple Codex sessions against the same account snapshot at the same time.
- Restart Codex CLI or Codex App after switching accounts.

See [SECURITY.md](SECURITY.md) and [docs/security-model.md](docs/security-model.md).

## Troubleshooting

Run:

```bash
codex-auth-snap --json doctor
```

On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\codex-auth-snap.ps1 --json doctor
```

`doctor` checks local paths, file-backed auth configuration, state permissions, symlink risk, invalid JSON, pending login state, installed copy drift, cloud sync path risk, and running Codex processes.

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Tests

The test suite uses temporary directories and does not touch your real `~/.codex`:

```bash
bash tests/test_codex_auth_snap.sh
bash tests/test_codex_auth_snap_windows_contract.sh
```

The Windows contract test performs static checks when PowerShell is unavailable. If `pwsh` or `powershell` is available, it also runs JSON/init/save/list smoke tests against temporary directories.

## License

MIT. See [LICENSE](LICENSE).
