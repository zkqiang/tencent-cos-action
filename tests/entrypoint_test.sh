#!/bin/bash

set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ENTRYPOINT_PATH="${REPOSITORY_ROOT}/entrypoint.sh"
readonly ACTION_METADATA_PATH="${REPOSITORY_ROOT}/action.yml"
readonly TEST_TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEST_TMP_DIR"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_file_contains() {
  local file_path="$1"
  local expected="$2"

  grep -Fq -- "$expected" "$file_path" || fail "Expected ${file_path} to contain: ${expected}"
}

assert_file_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  local file_contents

  file_contents="$(<"$file_path")"
  if [[ "$file_contents" == *"$unexpected"* ]]; then
    fail "Expected ${file_path} not to contain: ${unexpected}"
  fi
}

run_action() {
  local endpoint_type="$1"
  local capture_path="$2"
  local output_path="$3"
  local -a command=(bash "$ENTRYPOINT_PATH")
  local -a environment=(
    "PATH=${TEST_TMP_DIR}/bin:${PATH}"
    "INPUT_COMMANDS=ls cos://default/"
    "INPUT_SECRET_ID=test-secret-id"
    "INPUT_SECRET_KEY=test-secret-key"
    "INPUT_BUCKET=test-bucket-1234567890"
    "INPUT_REGION=ap-guangzhou"
    "INPUT_COSCLI_VERSION=v1.0.9"
    "TEST_CAPTURE_PATH=${capture_path}"
    "TEST_FAKE_COSCLI_SOURCE=${TEST_TMP_DIR}/fake-coscli"
  )

  if [ "$endpoint_type" != '__omitted__' ]; then
    command+=("$endpoint_type")
  fi

  env "${environment[@]}" "${command[@]}" >"$output_path" 2>&1
}

trap cleanup EXIT
mkdir -p "${TEST_TMP_DIR}/bin"

cat > "${TEST_TMP_DIR}/bin/dpkg" <<'EOF'
#!/bin/bash
printf '%s\n' amd64
EOF

cat > "${TEST_TMP_DIR}/bin/curl" <<'EOF'
#!/bin/bash
set -Eeuo pipefail

output_path=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output" ]; then
    output_path="$2"
    shift 2
    continue
  fi
  shift
done

[ -n "$output_path" ] || exit 1
cp "$TEST_FAKE_COSCLI_SOURCE" "$output_path"
EOF

cat > "${TEST_TMP_DIR}/fake-coscli" <<'EOF'
#!/bin/bash
set -Eeuo pipefail

if [ "${1:-}" = "--version" ]; then
  echo 'coscli version test'
  exit 0
fi

config_path=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--config-path" ]; then
    config_path="$2"
    shift 2
    continue
  fi
  shift
done

[ -n "$config_path" ] || exit 1
cp "$config_path" "$TEST_CAPTURE_PATH"
EOF

chmod +x "${TEST_TMP_DIR}/bin/dpkg" "${TEST_TMP_DIR}/bin/curl" "${TEST_TMP_DIR}/fake-coscli"

assert_file_contains "$ACTION_METADATA_PATH" 'endpoint-type:'
assert_file_contains "$ACTION_METADATA_PATH" "default: 'default'"
assert_file_contains "$ACTION_METADATA_PATH" "'\${{ inputs.endpoint-type }}'"

run_action '__omitted__' "${TEST_TMP_DIR}/omitted-config.yml" "${TEST_TMP_DIR}/omitted-output.log"
assert_file_contains "${TEST_TMP_DIR}/omitted-config.yml" 'endpoint: cos.ap-guangzhou.myqcloud.com'

run_action 'default' "${TEST_TMP_DIR}/default-config.yml" "${TEST_TMP_DIR}/default-output.log"
assert_file_contains "${TEST_TMP_DIR}/default-config.yml" 'endpoint: cos.ap-guangzhou.myqcloud.com'

run_action 'accelerate' "${TEST_TMP_DIR}/accelerate-config.yml" "${TEST_TMP_DIR}/accelerate-output.log"
assert_file_contains "${TEST_TMP_DIR}/accelerate-config.yml" 'endpoint: cos.accelerate.myqcloud.com'

run_action 'accelerate-internal' "${TEST_TMP_DIR}/accelerate-internal-config.yml" "${TEST_TMP_DIR}/accelerate-internal-output.log"
assert_file_contains "${TEST_TMP_DIR}/accelerate-internal-config.yml" 'endpoint: cos-internal.accelerate.tencentcos.cn'

if run_action 'unsupported' "${TEST_TMP_DIR}/invalid-config.yml" "${TEST_TMP_DIR}/invalid-output.log"; then
  fail 'Unsupported endpoint type unexpectedly succeeded'
fi
assert_file_contains "${TEST_TMP_DIR}/invalid-output.log" 'Unsupported endpoint type: unsupported'

for invalid_endpoint_type in '' ' accelerate' 'Accelerate' $'accelerate\n'; do
  if run_action "$invalid_endpoint_type" "${TEST_TMP_DIR}/invalid-config.yml" "${TEST_TMP_DIR}/invalid-output.log"; then
    fail 'Invalid endpoint type unexpectedly succeeded'
  fi
done

injected_endpoint_type=$'unsupported\n::warning::injected'
if run_action "$injected_endpoint_type" "${TEST_TMP_DIR}/injected-config.yml" "${TEST_TMP_DIR}/injected-output.log"; then
  fail 'Endpoint type containing a workflow command unexpectedly succeeded'
fi
assert_file_contains "${TEST_TMP_DIR}/injected-output.log" 'unsupported%0A::warning::injected'
assert_file_not_contains "${TEST_TMP_DIR}/injected-output.log" $'unsupported\n::warning::injected'

echo 'entrypoint endpoint tests passed'
