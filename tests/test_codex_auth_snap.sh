#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

TEST_DIR="$(cd "$(dirname "${0}")" && pwd)"
TOOL_DIR="$(cd "${TEST_DIR}/.." && pwd)"
CLI="${TOOL_DIR}/codex-auth-snap"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

TEST_INDEX=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "${actual}" == "${expected}" ]] || fail "${label}: expected '${expected}', got '${actual}'"
}

assert_contains() {
  local file_path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${file_path}" || {
    printf '%s\n' "--- ${file_path} ---" >&2
    cat "${file_path}" >&2
    fail "missing expected text: ${needle}"
  }
}

assert_not_contains() {
  local file_path="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${file_path}"; then
    printf '%s\n' "--- ${file_path} ---" >&2
    cat "${file_path}" >&2
    fail "unexpected sensitive text: ${needle}"
  fi
}

file_mode() {
  local file_path="$1"
  local mode
  if mode="$(stat -c "%a" "${file_path}" 2>/dev/null)"; then
    printf '%s\n' "${mode}"
    return
  fi
  stat -f "%Lp" "${file_path}"
}

assert_file_exists() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

assert_file_missing() {
  [[ ! -e "$1" ]] || fail "expected path to be missing: $1"
}

assert_dir_mode() {
  local file_path="$1"
  local mode
  mode="$(file_mode "${file_path}")"
  assert_eq "700" "${mode}" "dir mode ${file_path}"
}

assert_file_mode() {
  local file_path="$1"
  local mode
  mode="$(file_mode "${file_path}")"
  assert_eq "600" "${mode}" "file mode ${file_path}"
}

assert_executable_mode() {
  local file_path="$1"
  local mode
  mode="$(file_mode "${file_path}")"
  assert_eq "755" "${mode}" "executable mode ${file_path}"
}

assert_valid_json_file() {
  python3 -m json.tool "$1" >/dev/null
}

assert_json_stdout() {
  python3 -m json.tool "${STDOUT_FILE}" >/dev/null || {
    printf '%s\n' "--- stdout ---" >&2
    cat "${STDOUT_FILE}" >&2 || true
    printf '%s\n' "--- stderr ---" >&2
    cat "${STDERR_FILE}" >&2 || true
    fail "expected JSON stdout"
  }
}

json_get() {
  local expr="$1"
  python3 - "$STDOUT_FILE" "$expr" <<'PY'
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

new_case() {
  TEST_INDEX=$((TEST_INDEX + 1))
  CASE_ROOT="${TMP_ROOT}/case-${TEST_INDEX}"
  CODEX_HOME_DIR="${CASE_ROOT}/codex-home"
  SWITCH_HOME_DIR="${CASE_ROOT}/switch-home"
  HOME_DIR="${CASE_ROOT}/home"
  FAKE_BIN_DIR="${CASE_ROOT}/fake-bin"
  STDOUT_FILE="${CASE_ROOT}/stdout.txt"
  STDERR_FILE="${CASE_ROOT}/stderr.txt"
  CALL_LOG="${CASE_ROOT}/calls.log"
  mkdir -p "${CODEX_HOME_DIR}" "${SWITCH_HOME_DIR}" "${HOME_DIR}" "${FAKE_BIN_DIR}"
  : >"${CALL_LOG}"
  cat >"${FAKE_BIN_DIR}/pgrep" <<'SH'
#!/usr/bin/env bash
if [[ "${FAKE_CODEX_RUNNING:-0}" == "1" ]]; then
  exit 0
fi
exit 1
SH
  chmod +x "${FAKE_BIN_DIR}/pgrep"
  cat >"${FAKE_BIN_DIR}/codex" <<'SH'
#!/usr/bin/env bash
echo "codex $*" >>"${FAKE_CALL_LOG}"
exit 0
SH
  chmod +x "${FAKE_BIN_DIR}/codex"
  cat >"${FAKE_BIN_DIR}/uname" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-s" && -n "${FAKE_UNAME_S:-}" ]]; then
  printf '%s\n' "${FAKE_UNAME_S}"
  exit 0
fi
/usr/bin/uname "$@"
SH
  chmod +x "${FAKE_BIN_DIR}/uname"
  cat >"${FAKE_BIN_DIR}/stat" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" && "${2:-}" == "%a" ]]; then
  /usr/bin/stat -f "%Lp" "$3"
  exit 0
fi
/usr/bin/stat "$@"
SH
  chmod +x "${FAKE_BIN_DIR}/stat"
  cat >"${FAKE_BIN_DIR}/sha256sum" <<'SH'
#!/usr/bin/env bash
hash="$(shasum -a 256 "$1" | awk '{print $1}')"
printf '%s  %s\n' "${hash}" "$1"
SH
  chmod +x "${FAKE_BIN_DIR}/sha256sum"
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
  chmod 600 "${file_path}"
}

write_non_chatgpt_auth() {
  local file_path="$1"
  mkdir -p "$(dirname "${file_path}")"
  cat >"${file_path}" <<'JSON'
{"auth_mode":"api","api_key":"not-a-chatgpt-auth"}
JSON
  chmod 600 "${file_path}"
}

run_cli() {
  local expected="$1"
  shift
  set +e
  PATH="${FAKE_BIN_DIR}:${PATH}" \
  HOME="${HOME_DIR}" \
  FAKE_UNAME_S="${FAKE_UNAME_S:-}" \
  FAKE_CALL_LOG="${CALL_LOG}" \
  CODEX_HOME="${CODEX_HOME_DIR}" \
  CODEX_AUTH_SNAP_HOME="${SWITCH_HOME_DIR}" \
  "${CLI}" "$@" >"${STDOUT_FILE}" 2>"${STDERR_FILE}"
  local exit_status=$?
  set -e
  if [[ "${exit_status}" -ne "${expected}" ]]; then
    printf '%s\n' "command failed with unexpected status ${exit_status}, expected ${expected}: ${CLI} $*" >&2
    printf '%s\n' "--- stdout ---" >&2
    cat "${STDOUT_FILE}" >&2 || true
    printf '%s\n' "--- stderr ---" >&2
    cat "${STDERR_FILE}" >&2 || true
    exit 1
  fi
}

test_cli_is_bash_compatible() {
  bash -n "${CLI}" || fail "codex-auth-snap must parse with bash"

  new_case
  set +e
  PATH="${FAKE_BIN_DIR}:${PATH}" \
  HOME="${HOME_DIR}" \
  FAKE_UNAME_S="${FAKE_UNAME_S:-}" \
  FAKE_CALL_LOG="${CALL_LOG}" \
  CODEX_HOME="${CODEX_HOME_DIR}" \
  CODEX_AUTH_SNAP_HOME="${SWITCH_HOME_DIR}" \
  bash "${CLI}" --json version >"${STDOUT_FILE}" 2>"${STDERR_FILE}"
  local exit_status=$?
  set -e
  assert_eq "0" "${exit_status}" "bash version status"
  assert_json_stdout
  assert_eq "0.3.0" "$(json_get structuredContent.result.version)" "bash version output"
}

test_linux_platform_helpers_do_not_require_plutil() {
  new_case
  local FAKE_UNAME_S=Linux
  cat >"${FAKE_BIN_DIR}/plutil" <<'SH'
#!/usr/bin/env bash
echo "plutil should not be used in Linux mode" >&2
exit 127
SH
  chmod +x "${FAKE_BIN_DIR}/plutil"

  run_cli 0 --json init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "linux"
  run_cli 0 --json save linux
  assert_json_stdout
  assert_eq "linux" "$(json_get structuredContent.result.name)" "linux save account"
  assert_file_exists "${SWITCH_HOME_DIR}/accounts/linux.auth.json"
  assert_file_mode "${SWITCH_HOME_DIR}/accounts/linux.auth.json"
  assert_not_contains "${STDERR_FILE}" "plutil should not be used"

  run_cli 0 --json list
  assert_json_stdout
  assert_eq "linux" "$(json_get structuredContent.result.accounts.0.name)" "linux list account"

  run_cli 0 --json doctor
  assert_json_stdout
  assert_eq "true" "$(json_get structuredContent.result.ok)" "linux doctor ok"
  assert_not_contains "${STDERR_FILE}" "plutil should not be used"
}

test_init_fix_creates_dirs_and_config() {
  new_case
  run_cli 0 --json init --fix
  assert_json_stdout
  assert_eq "false" "$(json_get isError)" "init isError"
  assert_contains "${CODEX_HOME_DIR}/config.toml" 'cli_auth_credentials_store = "file"'
  assert_dir_mode "${CODEX_HOME_DIR}"
  assert_dir_mode "${SWITCH_HOME_DIR}"
  assert_dir_mode "${SWITCH_HOME_DIR}/accounts"
  assert_dir_mode "${SWITCH_HOME_DIR}/meta"
  assert_dir_mode "${SWITCH_HOME_DIR}/before-login"

  new_case
  mkdir -p "${CODEX_HOME_DIR}"
  printf '%s\n' 'model = "gpt-5.5"' >"${CODEX_HOME_DIR}/config.toml"
  run_cli 0 --json init --fix
  assert_contains "${CODEX_HOME_DIR}/config.toml" 'cli_auth_credentials_store = "file"'
  assert_not_contains "${CODEX_HOME_DIR}/config.toml" '\ncli_auth_credentials_store'
}

test_install_copies_executable_to_user_bin() {
  new_case
  local install_bin="${CASE_ROOT}/install-bin"

  run_cli 0 --json install --bin-dir "${install_bin}"
  assert_json_stdout
  assert_eq "false" "$(json_get isError)" "install isError"
  assert_eq "${install_bin}/codex-auth-snap" "$(json_get structuredContent.result.install_path)" "install path"
  assert_file_exists "${install_bin}/codex-auth-snap"
  assert_executable_mode "${install_bin}/codex-auth-snap"
  assert_file_exists "${SWITCH_HOME_DIR}/meta/install.json"
  assert_file_mode "${SWITCH_HOME_DIR}/meta/install.json"
  assert_contains "${install_bin}/codex-auth-snap" 'VERSION="0.3.0"'
  assert_not_contains "${STDOUT_FILE}" "fake-refresh"
}

test_install_refuses_unrelated_existing_file_without_force() {
  new_case
  local install_bin="${CASE_ROOT}/install-bin"
  mkdir -p "${install_bin}"
  printf '%s\n' '#!/bin/sh' >"${install_bin}/codex-auth-snap"
  printf '%s\n' 'echo unrelated' >>"${install_bin}/codex-auth-snap"
  chmod 755 "${install_bin}/codex-auth-snap"

  run_cli 1 --json install --bin-dir "${install_bin}"
  assert_json_stdout
  assert_eq "install_target_exists" "$(json_get structuredContent.error.code)" "unrelated install target code"

  run_cli 0 --json install --bin-dir "${install_bin}" --force
  assert_json_stdout
  assert_contains "${install_bin}/codex-auth-snap" 'Local Codex ChatGPT auth.json snapshot switcher'
}

test_doctor_reports_installed_version_mismatch() {
  new_case
  local install_bin="${CASE_ROOT}/install-bin"
  mkdir -p "${install_bin}"
  cat >"${install_bin}/codex-auth-snap" <<'SH'
#!/usr/bin/env bash
VERSION="0.0.1"
usage() {
  printf '%s\n' "Local Codex ChatGPT auth.json snapshot switcher"
}
SH
  chmod 755 "${install_bin}/codex-auth-snap"

  run_cli 0 --json --bin-dir "${install_bin}" doctor
  assert_json_stdout
  assert_eq "false" "$(json_get isError)" "doctor stale install isError"
  assert_contains "${STDOUT_FILE}" "installed_version_mismatch"
  assert_contains "${STDOUT_FILE}" '"installed_version":"0.0.1"'
}

test_save_rejects_missing_auth_and_invalid_names() {
  new_case
  run_cli 0 init --fix
  run_cli 1 --json save personal
  assert_json_stdout
  assert_eq "true" "$(json_get isError)" "missing auth isError"
  assert_eq "auth_missing" "$(json_get structuredContent.error.code)" "missing auth code"

  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 1 --json save ../x
  assert_json_stdout
  assert_eq "invalid_name" "$(json_get structuredContent.error.code)" "invalid name code"
}

test_save_rejects_non_chatgpt_auth_without_force() {
  new_case
  run_cli 0 init --fix
  write_non_chatgpt_auth "${CODEX_HOME_DIR}/auth.json"

  run_cli 1 --json save api
  assert_json_stdout
  assert_eq "not_chatgpt_auth" "$(json_get structuredContent.error.code)" "non ChatGPT auth code"

  run_cli 0 --json save api --force
  assert_json_stdout
  assert_eq "false" "$(json_get isError)" "forced save isError"
  assert_file_exists "${SWITCH_HOME_DIR}/accounts/api.auth.json"
}

test_save_valid_auth_writes_snapshot_meta_and_current_without_leaks() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 --json save personal
  assert_json_stdout
  assert_eq "false" "$(json_get isError)" "save isError"
  assert_file_exists "${SWITCH_HOME_DIR}/accounts/personal.auth.json"
  assert_file_exists "${SWITCH_HOME_DIR}/meta/personal.json"
  assert_eq "personal" "$(cat "${SWITCH_HOME_DIR}/current")" "current account"
  assert_file_mode "${SWITCH_HOME_DIR}/accounts/personal.auth.json"
  assert_file_mode "${SWITCH_HOME_DIR}/meta/personal.json"
  assert_file_mode "${SWITCH_HOME_DIR}/current"
  assert_valid_json_file "${SWITCH_HOME_DIR}/meta/personal.json"
  assert_not_contains "${STDOUT_FILE}" "fake-refresh-personal"
  assert_not_contains "${STDERR_FILE}" "fake-refresh-personal"
}

test_use_switches_active_and_stashes_rotated_current() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal-v1"
  run_cli 0 save personal
  write_auth "${CODEX_HOME_DIR}/auth.json" "work-v1"
  run_cli 0 save work
  write_auth "${CODEX_HOME_DIR}/auth.json" "work-rotated"

  run_cli 0 --json use personal
  assert_json_stdout
  assert_contains "${CODEX_HOME_DIR}/auth.json" "fake-refresh-personal-v1"
  assert_contains "${SWITCH_HOME_DIR}/accounts/work.auth.json" "fake-refresh-work-rotated"
  assert_eq "personal" "$(cat "${SWITCH_HOME_DIR}/current")" "current after use"
  assert_file_mode "${CODEX_HOME_DIR}/auth.json"
  assert_not_contains "${STDOUT_FILE}" "fake-refresh-work-rotated"
}

test_use_recovers_from_corrupt_active_auth() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 save personal
  write_auth "${CODEX_HOME_DIR}/auth.json" "work"
  run_cli 0 save work
  printf '%s\n' "{not json" >"${CODEX_HOME_DIR}/auth.json"
  chmod 600 "${CODEX_HOME_DIR}/auth.json"

  run_cli 0 --json use personal
  assert_json_stdout
  assert_contains "${CODEX_HOME_DIR}/auth.json" "fake-refresh-personal"
  assert_contains "${STDERR_FILE}" "WARN:"
  assert_eq "personal" "$(cat "${SWITCH_HOME_DIR}/current")" "current after corrupt active recovery"
}

test_use_text_output_uses_real_newline() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 save personal
  write_auth "${CODEX_HOME_DIR}/auth.json" "work"
  run_cli 0 save work

  run_cli 0 use personal
  assert_contains "${STDOUT_FILE}" "Switched to: personal"
  assert_contains "${STDOUT_FILE}" "Restart Codex CLI/App for the change to take effect."
  assert_not_contains "${STDOUT_FILE}" "\\n"
}

test_use_missing_and_symlink_snapshot_are_rejected() {
  new_case
  run_cli 0 init --fix
  run_cli 1 --json use missing
  assert_json_stdout
  assert_eq "snapshot_missing" "$(json_get structuredContent.error.code)" "missing snapshot code"

  write_auth "${CODEX_HOME_DIR}/auth.json" "target"
  ln -s "${CODEX_HOME_DIR}/auth.json" "${SWITCH_HOME_DIR}/accounts/link.auth.json"
  run_cli 1 --json use link
  assert_json_stdout
  assert_eq "symlink_refused" "$(json_get structuredContent.error.code)" "symlink snapshot code"
}

test_begin_login_hides_active_writes_pending_and_never_calls_logout() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal-v1"
  run_cli 0 save personal
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal-rotated"

  run_cli 0 --json begin-login work
  assert_json_stdout
  assert_file_missing "${CODEX_HOME_DIR}/auth.json"
  assert_eq "work" "$(cat "${SWITCH_HOME_DIR}/pending-login")" "pending login"
  assert_contains "${SWITCH_HOME_DIR}/accounts/personal.auth.json" "fake-refresh-personal-rotated"
  assert_file_exists "${SWITCH_HOME_DIR}/before-login/active-hidden.work.json"
  local backups=("${SWITCH_HOME_DIR}/before-login"/auth.before-login.work.*.json)
  (( ${#backups[@]} == 1 )) || fail "expected one work before-login backup, got ${#backups[@]}"
  [[ ! -s "${CALL_LOG}" ]] || fail "codex command should not be called"
  assert_not_contains "${STDOUT_FILE}" "fake-refresh-personal-rotated"
}

test_begin_login_text_output_matches_codex_login_flow() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 save personal

  run_cli 0 begin-login main-us
  assert_contains "${STDOUT_FILE}" "Run codex login for the target account."
  assert_contains "${STDOUT_FILE}" "Codex will open the login page."
  assert_contains "${STDOUT_FILE}" "codex-auth-snap finish-login"
  assert_not_contains "${STDOUT_FILE}" "switch your browser"
  assert_not_contains "${STDOUT_FILE}" "\\n"
}

test_begin_login_rejects_stale_named_hidden() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  write_auth "${SWITCH_HOME_DIR}/before-login/active-hidden.work.json" "stale"

  run_cli 1 --json begin-login work
  assert_json_stdout
  assert_eq "stale_hidden" "$(json_get structuredContent.error.code)" "stale hidden code"
  assert_contains "${CODEX_HOME_DIR}/auth.json" "fake-refresh-personal"
}

test_finish_login_uses_pending_and_clears_it() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 save personal
  run_cli 0 begin-login work
  write_auth "${CODEX_HOME_DIR}/auth.json" "work-new"

  run_cli 0 --json finish-login
  assert_json_stdout
  assert_file_exists "${SWITCH_HOME_DIR}/accounts/work.auth.json"
  assert_contains "${SWITCH_HOME_DIR}/accounts/work.auth.json" "fake-refresh-work-new"
  assert_eq "work" "$(cat "${SWITCH_HOME_DIR}/current")" "current after finish"
  assert_file_missing "${SWITCH_HOME_DIR}/pending-login"
  assert_file_missing "${SWITCH_HOME_DIR}/before-login/active-hidden.work.json"
  local leftovers=("${SWITCH_HOME_DIR}/before-login"/auth.before-login.work.*.json)
  (( ${#leftovers[@]} == 0 )) || fail "expected finish-login to clean work backups, got ${#leftovers[@]}"

  new_case
  run_cli 0 init --fix
  run_cli 1 --json finish-login
  assert_json_stdout
  assert_eq "pending_missing" "$(json_get structuredContent.error.code)" "finish without pending code"
}

test_abort_login_restores_named_hidden_auth_without_overwriting_active() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 save personal
  run_cli 0 begin-login work
  write_auth "${SWITCH_HOME_DIR}/before-login/active-hidden.other.json" "wrong-hidden"
  touch -t 203001010000 "${SWITCH_HOME_DIR}/before-login/active-hidden.other.json"

  run_cli 0 --json abort-login
  assert_json_stdout
  assert_file_exists "${CODEX_HOME_DIR}/auth.json"
  assert_contains "${CODEX_HOME_DIR}/auth.json" "fake-refresh-personal"
  assert_file_missing "${SWITCH_HOME_DIR}/pending-login"
  assert_file_missing "${SWITCH_HOME_DIR}/before-login/active-hidden.work.json"
  local work_backups=("${SWITCH_HOME_DIR}/before-login"/auth.before-login.work.*.json)
  (( ${#work_backups[@]} == 0 )) || fail "expected abort-login to clean work backups, got ${#work_backups[@]}"

  run_cli 0 begin-login work
  write_auth "${CODEX_HOME_DIR}/auth.json" "new-active"
  run_cli 1 --json abort-login
  assert_json_stdout
  assert_eq "active_exists" "$(json_get structuredContent.error.code)" "abort active exists code"
  assert_contains "${CODEX_HOME_DIR}/auth.json" "fake-refresh-new-active"
}

test_remove_current_snapshot_does_not_delete_active_auth() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 save personal
  run_cli 0 --json remove personal
  assert_json_stdout
  assert_file_missing "${SWITCH_HOME_DIR}/accounts/personal.auth.json"
  assert_file_missing "${SWITCH_HOME_DIR}/meta/personal.json"
  assert_file_missing "${SWITCH_HOME_DIR}/current"
  assert_file_exists "${CODEX_HOME_DIR}/auth.json"
}

test_list_current_paths_and_doctor_json_contract() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 save personal

  run_cli 0 --json list
  assert_json_stdout
  assert_eq "personal" "$(json_get structuredContent.result.accounts.0.name)" "list account name"
  assert_eq "true" "$(json_get structuredContent.result.accounts.0.current)" "list current"
  assert_not_contains "${STDOUT_FILE}" "fake-refresh-personal"

  run_cli 0 current
  assert_eq "personal" "$(cat "${STDOUT_FILE}")" "current stdout"

  run_cli 0 --json paths
  assert_json_stdout
  assert_eq "${CODEX_HOME_DIR}" "$(json_get structuredContent.result.codex_home)" "paths codex_home"

  chmod 755 "${SWITCH_HOME_DIR}/accounts"
  ln -s "${CODEX_HOME_DIR}/auth.json" "${SWITCH_HOME_DIR}/accounts/symlink.auth.json"
  run_cli 1 --json doctor
  assert_json_stdout
  assert_eq "true" "$(json_get isError)" "doctor error with symlink"
  assert_contains "${STDOUT_FILE}" "symlink_refused"
  assert_contains "${STDOUT_FILE}" "bad_permissions"
  assert_not_contains "${STDOUT_FILE}" "fake-refresh-personal"
}

test_doctor_healthy_state_returns_ok() {
  new_case
  run_cli 0 init --fix
  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  run_cli 0 save personal

  run_cli 0 --json doctor
  assert_json_stdout
  assert_eq "false" "$(json_get isError)" "healthy doctor isError"
  assert_eq "true" "$(json_get structuredContent.result.ok)" "healthy doctor ok"
}

test_invalid_json_and_lock_conflict_are_rejected() {
  new_case
  run_cli 0 init --fix
  printf '%s\n' '{not json' >"${CODEX_HOME_DIR}/auth.json"
  chmod 600 "${CODEX_HOME_DIR}/auth.json"
  run_cli 1 --json save broken
  assert_json_stdout
  assert_eq "invalid_json" "$(json_get structuredContent.error.code)" "invalid json code"

  write_auth "${CODEX_HOME_DIR}/auth.json" "personal"
  mkdir "${SWITCH_HOME_DIR}/lock"
  run_cli 1 --json save personal
  assert_json_stdout
  assert_eq "lock_exists" "$(json_get structuredContent.error.code)" "lock code"
}

test_codex_swap_legacy_env_var_is_accepted() {
  new_case
  local legacy_home="${CASE_ROOT}/legacy-switch-home"
  mkdir -p "${legacy_home}"
  set +e
  PATH="${FAKE_BIN_DIR}:${PATH}" \
  FAKE_CALL_LOG="${CALL_LOG}" \
  CODEX_HOME="${CODEX_HOME_DIR}" \
  CODEX_SWAP_HOME="${legacy_home}" \
  "${CLI}" --json init --fix >"${STDOUT_FILE}" 2>"${STDERR_FILE}"
  local exit_status=$?
  set -e
  assert_eq "0" "${exit_status}" "legacy env init status"
  assert_json_stdout
  assert_dir_mode "${legacy_home}/accounts"
}

test_codex_auth_switch_legacy_env_var_is_accepted() {
  new_case
  local legacy_home="${CASE_ROOT}/legacy-auth-switch-home"
  mkdir -p "${legacy_home}"
  set +e
  PATH="${FAKE_BIN_DIR}:${PATH}" \
  FAKE_CALL_LOG="${CALL_LOG}" \
  CODEX_HOME="${CODEX_HOME_DIR}" \
  CODEX_AUTH_SWITCH_HOME="${legacy_home}" \
  "${CLI}" --json init --fix >"${STDOUT_FILE}" 2>"${STDERR_FILE}"
  local exit_status=$?
  set -e
  assert_eq "0" "${exit_status}" "auth switch legacy env init status"
  assert_json_stdout
  assert_dir_mode "${legacy_home}/accounts"
}

test_init_fix_force_replaces_non_file_credentials_store() {
  new_case
  mkdir -p "${CODEX_HOME_DIR}"
  printf '%s\n' 'cli_auth_credentials_store = "memory"' >"${CODEX_HOME_DIR}/config.toml"

  run_cli 0 --json init --fix --force
  assert_json_stdout
  assert_contains "${CODEX_HOME_DIR}/config.toml" 'cli_auth_credentials_store = "file"'
  assert_not_contains "${CODEX_HOME_DIR}/config.toml" 'cli_auth_credentials_store = "memory"'
}

run_all() {
  test_cli_is_bash_compatible
  test_linux_platform_helpers_do_not_require_plutil
  test_init_fix_creates_dirs_and_config
  test_install_copies_executable_to_user_bin
  test_install_refuses_unrelated_existing_file_without_force
  test_doctor_reports_installed_version_mismatch
  test_save_rejects_missing_auth_and_invalid_names
  test_save_rejects_non_chatgpt_auth_without_force
  test_save_valid_auth_writes_snapshot_meta_and_current_without_leaks
  test_use_switches_active_and_stashes_rotated_current
  test_use_recovers_from_corrupt_active_auth
  test_use_text_output_uses_real_newline
  test_use_missing_and_symlink_snapshot_are_rejected
  test_begin_login_hides_active_writes_pending_and_never_calls_logout
  test_begin_login_text_output_matches_codex_login_flow
  test_begin_login_rejects_stale_named_hidden
  test_finish_login_uses_pending_and_clears_it
  test_abort_login_restores_named_hidden_auth_without_overwriting_active
  test_remove_current_snapshot_does_not_delete_active_auth
  test_list_current_paths_and_doctor_json_contract
  test_doctor_healthy_state_returns_ok
  test_invalid_json_and_lock_conflict_are_rejected
  test_codex_auth_switch_legacy_env_var_is_accepted
  test_codex_swap_legacy_env_var_is_accepted
  test_init_fix_force_replaces_non_file_credentials_store
  printf '%s\n' "ok - codex-auth-snap tests passed"
}

run_all
