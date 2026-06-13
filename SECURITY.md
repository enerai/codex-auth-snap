# Security Policy

## Supported Versions

Security fixes target the latest released version of `codex-auth-snap`.

## Sensitive Files

Treat these files as passwords:

- `$CODEX_HOME/auth.json`
- `*.auth.json`
- Files under `$CODEX_AUTH_SNAP_HOME/accounts/`
- Files under `$CODEX_AUTH_SNAP_HOME/before-login/`

Do not upload, commit, paste, email, or attach these files to issues.

## Reporting A Vulnerability

If the repository has private vulnerability reporting enabled, use that first.

If it is not available, open a GitHub issue with a minimal description that does not include secrets, tokens, full paths that reveal private account identity, or raw auth files. The maintainer can then arrange a private follow-up channel if needed.

Good reports include:

- The `codex-auth-snap version` output.
- Your operating system and version.
- The exact command you ran.
- The non-sensitive `doctor` issue code, if one is available.
- A redacted explanation of what went wrong.

Do not include:

- `access_token`
- `refresh_token`
- `id_token`
- Full `auth.json`
- Full `*.auth.json`
- Screenshots that reveal account identity

## Security Boundaries

`codex-auth-snap` is local-only. It does not send network requests, does not call OpenAI APIs, does not decode JWTs, and does not refresh tokens.

The tool protects against common local mistakes:

- It refuses symlinked auth paths.
- It keeps state directories at mode `700`.
- It keeps auth snapshots and state files at mode `600`.
- It warns about cloud-synced-looking state paths.
- It avoids printing token fields or full auth JSON.

The tool does not protect against:

- Malware or other local processes with access to your user account.
- Manual copying of auth snapshots to another machine.
- Sharing snapshots with another person.
- Running concurrent Codex sessions against the same account snapshot.
- Account, billing, usage, or policy enforcement by any external service.

See [docs/security-model.md](docs/security-model.md) for more detail.
