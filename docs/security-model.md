# Security Model

`codex-auth-snap` is a local file tool. Its security model is intentionally small and easy to audit.

## Assets

The sensitive assets are:

- `$CODEX_HOME/auth.json`
- `*.auth.json` snapshots
- `$CODEX_AUTH_SNAP_HOME/accounts/`
- `$CODEX_AUTH_SNAP_HOME/before-login/`
- `$CODEX_AUTH_SNAP_HOME/current`
- `$CODEX_AUTH_SNAP_HOME/pending-login`

Treat every auth snapshot as a password.

## Trust Boundary

The tool runs under your local user account. It reads and writes local files only.

It does not:

- Send network requests.
- Call OpenAI APIs.
- Call `codex logout`.
- Decode JWTs.
- Refresh tokens.
- Print token values.
- Share snapshots with another machine or user.

## Local Protections

The CLI is designed to reduce common local mistakes:

- `umask 077` is set for strict default permissions.
- State directories are created with mode `700`.
- Auth snapshots and state files are written with mode `600`.
- Symlinked auth paths and state files are refused.
- `doctor` detects invalid JSON, wrong permissions, symlinks, pending login state, cloud-synced-looking paths, and stale installed copies.
- `list` shows short hashes instead of credential contents.

## Non-Goals

The tool does not protect against:

- A compromised local user account.
- Malware running as your user.
- Manual exfiltration of auth snapshots.
- Cloud sync tools copying snapshots after you place state in a synced directory.
- Concurrent use of the same account snapshot by multiple Codex sessions.
- External account policy, billing, usage, or enforcement decisions.

## Safe Operating Rules

- Use this tool only with accounts you own or are authorized to use.
- Do not copy auth snapshots to another machine.
- Do not share snapshots with another person.
- Do not store snapshot state inside iCloud, Dropbox, Google Drive, OneDrive, or similar folders.
- Restart Codex CLI or Codex App after switching.
- Run `codex-auth-snap --json doctor` when something looks wrong.

## Recovery Steps

If a snapshot might have been exposed:

1. Stop using that snapshot.
2. Remove it with `codex-auth-snap remove <name>`.
3. Sign out or revoke sessions through the relevant account controls if available.
4. Log in again with `codex login`.
5. Save a fresh snapshot with `codex-auth-snap save <name>`.
6. Run `codex-auth-snap --json doctor`.

If a login flow is stuck:

1. Run `codex-auth-snap --json doctor`.
2. If `pending_login` appears, decide whether to finish or abort the login.
3. Use `codex-auth-snap finish-login` after a successful `codex login`.
4. Use `codex-auth-snap abort-login` to restore the hidden previous auth.

Only use `--force` after inspecting the affected files.
