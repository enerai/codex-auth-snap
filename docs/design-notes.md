# Design Notes

`codex-auth-snap` is intentionally a small shell CLI instead of a daemon, browser extension, or network service.

## Design Goals

- Keep all credential material local.
- Make account switching explicit and reversible.
- Avoid hidden background behavior.
- Keep the script easy to audit.
- Provide machine-readable output for automation.
- Prefer safe failure over clever recovery.

## Core Model

Codex reads ChatGPT credentials from:

```text
$CODEX_HOME/auth.json
```

The switcher stores named snapshots under:

```text
$CODEX_AUTH_SNAP_HOME/accounts/<name>.auth.json
```

Switching to an account means copying that snapshot back to active `auth.json`.

Before switching away from the current account, the tool first tries to save the active `auth.json` back into the current snapshot. This preserves local token refreshes that may have been written by Codex while the account was active.

## Login Flow

Adding another account uses a two-step flow:

```bash
codex-auth-snap begin-login work
codex login
codex-auth-snap finish-login
```

`begin-login` hides the current active `auth.json` under `before-login/` so Codex can create a fresh login. `finish-login` saves the newly created active auth file as the requested snapshot.

If the login is abandoned, `abort-login` restores the hidden previous auth file when it is safe to do so.

## Why Not `codex logout`

The tool avoids `codex logout` because the desired operation is only local file isolation. Removing or invalidating a session is a broader account-level action than this tool needs.

## Why No Network Calls

The tool does not need network access to save or restore local auth snapshots. Avoiding network calls keeps the trust boundary simple and makes the script easier to review.

## Why Refuse Symlinks

Auth snapshots are sensitive. Symlinks can redirect writes into unexpected locations or cloud-synced directories. The tool refuses symlinked auth paths and state files instead of trying to infer user intent.

## Why JSON Envelopes

Every command can run with `--json`. JSON mode returns a stable envelope with:

- `content`
- `structuredContent`
- `isError`

This makes the CLI easier for scripts and coding agents to call safely. It also keeps errors structured enough to retry or explain without parsing prose.

## Platform Notes

The first public release targets macOS. The script uses zsh, `plutil`, and BSD `stat -f`.

Linux support would require a portability pass for JSON validation, JSON field checks, file mode inspection, and process detection.
