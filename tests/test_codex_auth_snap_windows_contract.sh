#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${0}")" && pwd)"
TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"
PS1="${TOOL_DIR}/codex-auth-snap.ps1"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_exists() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

assert_contains() {
  local file_path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${file_path}" || fail "missing expected text in ${file_path}: ${needle}"
}

assert_contains_any() {
  local file_path="$1"
  local first="$2"
  local second="$3"
  grep -Fq "${first}" "${file_path}" && return 0
  grep -Fq "${second}" "${file_path}" && return 0
  fail "missing expected text in ${file_path}: ${first} or ${second}"
}

assert_not_contains() {
  local file_path="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${file_path}"; then
    fail "unexpected text in ${file_path}: ${needle}"
  fi
}

assert_json_stdout() {
  local file_path="$1"
  python3 -m json.tool "${file_path}" >/dev/null || {
    printf '%s\n' "--- ${file_path} ---" >&2
    cat "${file_path}" >&2 || true
    fail "expected JSON output"
  }
}

json_get() {
  local file_path="$1"
  local expr="$2"
  python3 - "$file_path" "$expr" <<'PY'
from __future__ import annotations

import json
import sys

path, expr = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
value = data
for part in expr.split("."):
    if part == "":
        continue
    if part.isdigit():
        value = value[int(part)]
    else:
        value = value[part]
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

write_auth() {
  local file_path="$1"
  local label="$2"
  mkdir -p "$(dirname "${file_path}")"
  cat >"${file_path}" <<JSON
{
  "auth_mode": "chatgpt",
  "tokens": {
    "access_token": "fake-access-${label}",
    "id_token": "fake-id-${label}",
    "refresh_token": "fake-refresh-${label}",
    "account_id": "fake-account-${label}"
  },
  "last_refresh": "2026-05-16T20:30:00Z"
}
JSON
}

test_windows_script_static_contract() {
  assert_file_exists "${PS1}"
  assert_not_contains "${PS1}" "#!/usr/bin/env bash"
  assert_contains "${PS1}" "Local Codex ChatGPT auth.json snapshot switcher"
  assert_contains "${PS1}" '$script:Version = "0.3.0"'
  assert_contains "${PS1}" "CODEX_AUTH_SNAP_HOME"
  assert_contains "${PS1}" "CODEX_AUTH_SWITCH_HOME"
  assert_contains "${PS1}" "CODEX_SWAP_HOME"
  assert_contains "${PS1}" "Write-Ok"
  assert_contains "${PS1}" "Write-ErrorEnvelope"
  assert_contains "${PS1}" "Test-AccountName"
  assert_contains "${PS1}" "Invoke-CodexAuthSnap"

  local command
  for command in init save use begin-login finish-login abort-login install list current remove doctor paths version; do
    assert_contains_any "${PS1}" "'${command}'" "\"${command}\""
  done
}

find_powershell() {
  if command -v pwsh >/dev/null 2>&1; then
    command -v pwsh
    return 0
  fi
  if command -v powershell >/dev/null 2>&1; then
    command -v powershell
    return 0
  fi
  return 1
}

run_powershell_file() {
  local pwsh_bin="$1"
  shift
  "${pwsh_bin}" -NoProfile -ExecutionPolicy Bypass -File "${PS1}" "$@"
}

test_windows_script_powershell_smoke_if_available() {
  local pwsh_bin
  if ! pwsh_bin="$(find_powershell)"; then
    printf '%s\n' "skip - PowerShell is not available; static Windows contract checked"
    return 0
  fi

  local case_root="${TMP_ROOT}/pwsh-smoke"
  local codex_home="${case_root}/codex-home"
  local snap_home="${case_root}/snap-home"
  local stdout_file="${case_root}/stdout.json"
  local stderr_file="${case_root}/stderr.txt"
  mkdir -p "${codex_home}" "${snap_home}"

  CODEX_HOME="${codex_home}" \
  CODEX_AUTH_SNAP_HOME="${snap_home}" \
  run_powershell_file "${pwsh_bin}" --json version >"${stdout_file}" 2>"${stderr_file}"
  assert_json_stdout "${stdout_file}"
  [[ "$(json_get "${stdout_file}" structuredContent.result.version)" == "0.3.0" ]] || fail "unexpected version output"

  CODEX_HOME="${codex_home}" \
  CODEX_AUTH_SNAP_HOME="${snap_home}" \
  run_powershell_file "${pwsh_bin}" --json init --fix >"${stdout_file}" 2>"${stderr_file}"
  assert_json_stdout "${stdout_file}"
  assert_contains "${codex_home}/config.toml" 'cli_auth_credentials_store = "file"'

  write_auth "${codex_home}/auth.json" "personal"
  CODEX_HOME="${codex_home}" \
  CODEX_AUTH_SNAP_HOME="${snap_home}" \
  run_powershell_file "${pwsh_bin}" --json save personal >"${stdout_file}" 2>"${stderr_file}"
  assert_json_stdout "${stdout_file}"
  [[ "$(json_get "${stdout_file}" structuredContent.result.name)" == "personal" ]] || fail "unexpected save output"
  assert_file_exists "${snap_home}/accounts/personal.auth.json"
  assert_not_contains "${stdout_file}" "fake-refresh-personal"
  assert_not_contains "${stderr_file}" "fake-refresh-personal"

  CODEX_HOME="${codex_home}" \
  CODEX_AUTH_SNAP_HOME="${snap_home}" \
  run_powershell_file "${pwsh_bin}" --json list >"${stdout_file}" 2>"${stderr_file}"
  assert_json_stdout "${stdout_file}"
  [[ "$(json_get "${stdout_file}" structuredContent.result.accounts.0.name)" == "personal" ]] || fail "unexpected list output"
}

test_windows_script_static_contract
test_windows_script_powershell_smoke_if_available
printf '%s\n' "ok - codex-auth-snap Windows contract tests passed"
