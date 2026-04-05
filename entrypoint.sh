#!/bin/bash

set -Eeuo pipefail

readonly DEFAULT_BUCKET_ALIAS="default"
readonly DEFAULT_PROTOCOL="https"
readonly COSCLI_CONFIG_FILENAME=".cos.yaml"
readonly COSCLI_DOWNLOAD_BASE_URL="https://github.com/tencentyun/coscli/releases/download"
readonly COSCLI_RELEASES_API_URL="https://api.github.com/repos/tencentyun/coscli/releases"

require_input() {
  local input_name="$1"
  local display_name="$2"

  if [ -z "${!input_name:-}" ]; then
    echo "::error::Required ${display_name} parameter"
    exit 1
  fi
}

cleanup() {
  if [ -n "${COSCLI_TMP_DIR:-}" ] && [ -d "$COSCLI_TMP_DIR" ]; then
    rm -rf "$COSCLI_TMP_DIR"
  fi
}

fail() {
  echo "::error::$1"
  exit 1
}

resolve_coscli_architecture() {
  local dpkg_architecture

  dpkg_architecture="$(dpkg --print-architecture)"

  case "$dpkg_architecture" in
    amd64)
      printf '%s' 'linux-amd64'
      ;;
    arm64)
      printf '%s' 'linux-arm64'
      ;;
    *)
      fail "Unsupported architecture: ${dpkg_architecture}"
      ;;
  esac
}

resolve_latest_coscli_version() {
  local latest_release_json
  local latest_version

  latest_release_json="$(curl --fail --silent --show-error --location \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "${COSCLI_RELEASES_API_URL}/latest")" || fail "Failed to resolve the latest coscli release"

  latest_version="$(printf '%s\n' "$latest_release_json" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

  if [ -z "$latest_version" ]; then
    fail "Failed to parse the latest coscli release version"
  fi

  printf '%s' "$latest_version"
}

normalize_coscli_version() {
  local requested_version

  requested_version="$(trim_whitespace "${1:-}")"

  if [ -z "$requested_version" ]; then
    resolve_latest_coscli_version
    return
  fi

  case "$requested_version" in
    v*)
      printf '%s' "$requested_version"
      ;;
    *)
      printf 'v%s' "$requested_version"
      ;;
  esac
}

install_coscli() {
  local resolved_version
  local coscli_architecture
  local download_url

  resolved_version="$(normalize_coscli_version "${INPUT_COSCLI_VERSION:-}")"
  coscli_architecture="$(resolve_coscli_architecture)"
  download_url="${COSCLI_DOWNLOAD_BASE_URL}/${resolved_version}/coscli-${resolved_version}-${coscli_architecture}"

  echo "Downloading coscli ${resolved_version} (${coscli_architecture})"

  curl --fail --silent --show-error --location \
    "$download_url" \
    --output "$COSCLI_BIN_PATH" || fail "Failed to download coscli from ${download_url}"

  chmod +x "$COSCLI_BIN_PATH" || fail "Failed to make coscli executable"

  echo "Using coscli version: ${resolved_version}"
  "$COSCLI_BIN_PATH" --version || fail "Failed to run coscli"
}

trim_whitespace() {
  local raw_value="$1"

  raw_value="${raw_value#"${raw_value%%[![:space:]]*}"}"
  raw_value="${raw_value%"${raw_value##*[![:space:]]}"}"

  printf '%s' "$raw_value"
}

finalize_current_token() {
  if [ "$CURRENT_TOKEN_STARTED" -eq 0 ]; then
    return
  fi

  CURRENT_COMMAND_PARTS+=("$CURRENT_TOKEN")

  CURRENT_TOKEN=""
  CURRENT_TOKEN_STARTED=0
  CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=0
}

parse_command_line() {
  local raw_command_line="$1"
  local command_line
  local current_character
  local index

  command_line="$(trim_whitespace "$raw_command_line")"

  if [ -z "$command_line" ]; then
    PARSED_COMMAND_PARTS=()
    return
  fi

  if [[ "$command_line" =~ ^-[[:space:]]*(.*)$ ]]; then
    command_line="${BASH_REMATCH[1]}"
    command_line="$(trim_whitespace "$command_line")"
  fi

  if [ -z "$command_line" ]; then
    fail "Invalid commands parameter: empty command entry"
  fi

  CURRENT_TOKEN=""
  CURRENT_TOKEN_STARTED=0
  CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=0
  IN_SINGLE_QUOTE=0
  IN_DOUBLE_QUOTE=0
  ESCAPE_NEXT_CHARACTER=0
  CURRENT_COMMAND_PARTS=()

  for (( index = 0; index < ${#command_line}; index++ )); do
    current_character="${command_line:index:1}"

    if [ "$ESCAPE_NEXT_CHARACTER" -eq 1 ]; then
      CURRENT_TOKEN+="$current_character"
      CURRENT_TOKEN_STARTED=1
      CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=1
      ESCAPE_NEXT_CHARACTER=0
      continue
    fi

    if [ "$IN_SINGLE_QUOTE" -eq 1 ]; then
      if [ "$current_character" = "'" ]; then
        IN_SINGLE_QUOTE=0
        CURRENT_TOKEN_STARTED=1
        CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=1
      else
        CURRENT_TOKEN+="$current_character"
        CURRENT_TOKEN_STARTED=1
      fi

      continue
    fi

    if [ "$IN_DOUBLE_QUOTE" -eq 1 ]; then
      case "$current_character" in
        '\\')
          ESCAPE_NEXT_CHARACTER=1
          CURRENT_TOKEN_STARTED=1
          CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=1
          ;;
        '"')
          IN_DOUBLE_QUOTE=0
          CURRENT_TOKEN_STARTED=1
          CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=1
          ;;
        *)
          CURRENT_TOKEN+="$current_character"
          CURRENT_TOKEN_STARTED=1
          ;;
      esac

      continue
    fi

    case "$current_character" in
      [[:space:]])
        finalize_current_token
        ;;
      "'")
        IN_SINGLE_QUOTE=1
        CURRENT_TOKEN_STARTED=1
        CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=1
        ;;
      '"')
        IN_DOUBLE_QUOTE=1
        CURRENT_TOKEN_STARTED=1
        CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=1
        ;;
      '\\')
        ESCAPE_NEXT_CHARACTER=1
        CURRENT_TOKEN_STARTED=1
        CURRENT_TOKEN_WAS_QUOTED_OR_ESCAPED=1
        ;;
      *)
        CURRENT_TOKEN+="$current_character"
        CURRENT_TOKEN_STARTED=1
        ;;
    esac
  done

  if [ "$ESCAPE_NEXT_CHARACTER" -eq 1 ]; then
    fail "Invalid commands parameter: trailing escape character"
  fi

  if [ "$IN_SINGLE_QUOTE" -eq 1 ] || [ "$IN_DOUBLE_QUOTE" -eq 1 ]; then
    fail "Invalid commands parameter: unterminated quote"
  fi

  finalize_current_token

  if [ "$CURRENT_TOKEN_STARTED" -ne 0 ]; then
    fail "Invalid commands parameter: internal parsing error"
  fi

  if [ "${#CURRENT_COMMAND_PARTS[@]}" -eq 0 ]; then
    fail "Invalid commands parameter: empty command entry"
  fi

  PARSED_COMMAND_PARTS=("${CURRENT_COMMAND_PARTS[@]}")
}

run_command() {
  local printable_command

  printf -v printable_command '%q ' "${PARSED_COMMAND_PARTS[@]}"
  printable_command="${printable_command% }"

  echo "Running command: coscli ${printable_command}"

  "$COSCLI_BIN_PATH" --config-path "$COSCLI_CONFIG_PATH" --init-skip "${PARSED_COMMAND_PARTS[@]}"
}

trap cleanup EXIT

require_input "INPUT_COMMANDS" "Commands"
require_input "INPUT_SECRET_ID" "SecretId"
require_input "INPUT_SECRET_KEY" "SecretKey"
require_input "INPUT_BUCKET" "Bucket"
require_input "INPUT_REGION" "Region"

readonly COSCLI_TMP_DIR="$(mktemp -d)"
readonly COSCLI_CONFIG_PATH="${COSCLI_TMP_DIR}/${COSCLI_CONFIG_FILENAME}"
readonly COSCLI_BIN_PATH="${COSCLI_TMP_DIR}/coscli"
readonly COSCLI_ENDPOINT="cos.${INPUT_REGION}.myqcloud.com"

install_coscli

cat > "$COSCLI_CONFIG_PATH" <<EOF
cos:
  base:
    secretid: ${INPUT_SECRET_ID}
    secretkey: ${INPUT_SECRET_KEY}
    sessiontoken: ""
    protocol: ${DEFAULT_PROTOCOL}
  buckets:
    - name: ${INPUT_BUCKET}
      alias: ${DEFAULT_BUCKET_ALIAS}
      region: ${INPUT_REGION}
      endpoint: ${COSCLI_ENDPOINT}
      ofs: false
EOF

RAW_COMMANDS="$INPUT_COMMANDS"
PARSED_COMMAND_PARTS=()
executed_command_count=0

while IFS= read -r command_line || [ -n "$command_line" ]; do
  trimmed_command_line="$(trim_whitespace "$command_line")"

  if [ -z "$trimmed_command_line" ]; then
    continue
  fi

  parse_command_line "$command_line"
  run_command
  executed_command_count=$((executed_command_count + 1))
done <<< "$RAW_COMMANDS"

if [ "$executed_command_count" -eq 0 ]; then
  fail "Required Commands parameter"
fi

echo "Commands ran successfully"
