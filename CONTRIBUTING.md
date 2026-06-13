# Contributing

Thanks for helping improve `codex-auth-snap`.

## Project Scope

This project is a local-only Codex ChatGPT `auth.json` snapshot switcher.

In scope:

- Safer local file handling.
- Clearer diagnostics.
- Better docs.
- Better tests.
- macOS and Linux compatibility fixes.
- Future portability work, if it preserves the same safety boundary.

Out of scope:

- Account sharing.
- Account pooling.
- Automatic account rotation.
- Quota bypass.
- Network calls to OpenAI or any third-party service.
- Token decoding, refreshing, exporting, or printing.

## Development Setup

From the repository root:

```bash
./codex-auth-snap --json version
```

Run the test suite:

```bash
bash tests/test_codex_auth_snap.sh
```

The tests use temporary directories and do not touch your real `~/.codex`.

## Before Opening A Pull Request

Check:

- `bash tests/test_codex_auth_snap.sh` passes.
- `./codex-auth-snap --json version` prints valid JSON.
- No real `auth.json` or `*.auth.json` file is included.
- No docs or tests include real account names, tokens, screenshots, or credential material.
- JSON mode writes only one JSON envelope to stdout.
- Human warnings and diagnostics go to stderr or structured JSON fields.

## JSON Contract

Every command that supports `--json` should return:

```json
{
  "content": [{"type": "text", "text": "short summary"}],
  "structuredContent": {"result": {}},
  "isError": false
}
```

Business failures should return a non-zero exit code and:

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

Do not print token fields, full auth JSON, or long unbounded payloads.

## Style

- Keep the script easy to audit.
- Prefer small, explicit shell functions.
- Preserve strict local-file safety checks.
- Keep error codes stable when possible.
- Add focused tests for new behavior.

## Security Reports

Do not open public issues containing secrets or auth files. Follow [SECURITY.md](SECURITY.md).
