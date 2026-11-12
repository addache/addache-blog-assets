#!/usr/bin/env bash
# Source this file from the same working folder as settings.local.sh.
# Usage: save_settings EXECUTION_ROLE_ARN TASK_ROLE_ARN
# Only pass names of non-secret variables. Indexed arrays are supported.
_SETTINGS_LOCAL_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/settings.local.sh"

save_settings() {
  local __persist_name __persist_declaration __persist_assignment __persist_line
  local __persist_skip __persist_tmp
  local -a __persist_assignments=()
  [[ $# -gt 0 ]] || { echo 'Pass variable names to save_settings.' >&2; return 1; }
  [[ -f "$_SETTINGS_LOCAL_PATH" && ! -L "$_SETTINGS_LOCAL_PATH" ]] || {
    echo 'Create a regular settings.local.sh file first.' >&2; return 1;
  }
  for __persist_name in "$@"; do
    [[ "$__persist_name" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
      echo 'Use uppercase variable names for saved settings.' >&2; return 1;
    }
    __persist_declaration="$(declare -p "$__persist_name" 2>/dev/null)" || {
      printf 'Variable is not set: %s\n' "$__persist_name" >&2; return 1;
    }
    case "$__persist_declaration" in
      'declare -a '*)
        # declare -p produces Bash-escaped array values. Remove only its prefix.
        __persist_assignment="${__persist_declaration#declare -a }"
        [[ "$__persist_assignment" != *=\(\) ]] || {
          printf 'Array is empty: %s\n' "$__persist_name" >&2; return 1;
        }
        ;;
      'declare -- '*|'declare -x '*)
        [[ -n "${!__persist_name}" && "${!__persist_name}" != None && "${!__persist_name}" != null ]] || {
          printf 'Value is empty or unavailable: %s\n' "$__persist_name" >&2; return 1;
        }
        printf -v __persist_assignment '%s=%q' "$__persist_name" "${!__persist_name}"
        ;;
      *)
        printf 'Unsupported variable type: %s\n' "$__persist_name" >&2; return 1;
        ;;
    esac
    __persist_assignments+=("$__persist_assignment")
  done
  __persist_tmp="$(mktemp "${_SETTINGS_LOCAL_PATH}.tmp.XXXXXX")" || return 1
  if ! {
    chmod 600 "$__persist_tmp" && {
      while IFS= read -r __persist_line || [[ -n "$__persist_line" ]]; do
        __persist_skip=false
        for __persist_name in "$@"; do
          if [[ "$__persist_line" =~ ^[[:space:]]*(export[[:space:]]+)?${__persist_name}[[:space:]]*= ]]; then
            __persist_skip=true
            break
          fi
        done
        if [[ "$__persist_skip" == false ]]; then printf '%s\n' "$__persist_line"; fi
      done < "$_SETTINGS_LOCAL_PATH"
      printf '%s\n' "${__persist_assignments[@]}"
    } > "$__persist_tmp"
  }; then
    rm -f -- "$__persist_tmp"
    return 1
  fi
  if ! mv -f -- "$__persist_tmp" "$_SETTINGS_LOCAL_PATH"; then
    rm -f -- "$__persist_tmp"
    return 1
  fi
}
