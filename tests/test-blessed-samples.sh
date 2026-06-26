#!/usr/bin/env bash
# tests/test-blessed-samples.sh
#
# Unit tests for scripts/build-blessed-samples.sh parser and core functions.
# No external dependencies required (no Docker/git/hub VM needed).
# Run: bash tests/test-blessed-samples.sh
#
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/../scripts/build-blessed-samples.sh"
TESTS_PASSED=0
TESTS_FAILED=0

# ---------------------------------------------------------------------------
# Test harness helpers
# ---------------------------------------------------------------------------
pass() {
  echo "  PASS: $1"
  ((TESTS_PASSED++)) || true
}

fail() {
  echo "  FAIL: $1"
  echo "        Expected: $2"
  echo "        Got:      $3"
  ((TESTS_FAILED++)) || true
}

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$description"
  else
    fail "$description" "$expected" "$actual"
  fi
}

assert_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    pass "$description"
  else
    fail "$description" "output containing '$needle'" "$haystack"
  fi
}

assert_exit_code() {
  local description="$1"
  local expected_code="$2"
  local actual_code="$3"
  if [ "$expected_code" = "$actual_code" ]; then
    pass "$description"
  else
    fail "$description" "exit code $expected_code" "exit code $actual_code"
  fi
}

# Create a temp directory for test fixtures, clean up on exit
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ---------------------------------------------------------------------------
# Isolated helpers
# The build script uses [[ "${BASH_SOURCE[0]}" == "${0}" ]] guard so it can
# be safely sourced without executing main.
# ---------------------------------------------------------------------------

run_parse_config() {
  local content="$1"
  local tmpfile="${TMPDIR_TEST}/blessed_test_$$.txt"
  printf '%s\n' "$content" > "$tmpfile"
  bash -c "
    source '${BUILD_SCRIPT}' 2>/dev/null
    parse_config '${tmpfile}' 2>/dev/null
  " 2>/dev/null
  rm -f "$tmpfile"
}

run_parse_config_file() {
  # Returns only stdout (pipe-delimited entries, no error messages)
  local file="$1"
  bash -c "
    source '${BUILD_SCRIPT}' 2>/dev/null
    parse_config '${file}' 2>/dev/null
  " 2>/dev/null
}

run_parse_config_stderr() {
  # Returns combined stdout+stderr for error-checking
  local file="$1"
  bash -c "
    source '${BUILD_SCRIPT}' 2>/dev/null
    parse_config '${file}' 2>&1
  "
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
echo "====================================================="
echo "Blessed Samples Test Suite"
echo "====================================================="
echo ""

# --- 13.1: Script exists and is executable ---
echo "--- Test group: Script basics ---"
if [ -f "$BUILD_SCRIPT" ] && [ -x "$BUILD_SCRIPT" ]; then
  pass "Script exists and is executable"
else
  fail "Script exists and is executable" "file exists + executable" "not found or not executable"
fi

# --- 13.2: Absent blessedSamples.txt → exit 0 + informational message ---
echo "--- Test group: Absent/empty config file ---"
absent_file="${TMPDIR_TEST}/nonexistent_$$_$(date +%s).txt"
absent_output=$(BLESSED_SAMPLES_FILE="$absent_file" bash "$BUILD_SCRIPT" "$absent_file" 2>&1)
absent_exit=$?
assert_exit_code "Absent file exits with code 0" "0" "$absent_exit"
assert_contains "Absent file prints informational message" "Skipping" "$absent_output"

# --- 13.3: Empty file → exit 0 ---
empty_file="${TMPDIR_TEST}/empty_$$.txt"
touch "$empty_file"
empty_output=$(BLESSED_SAMPLES_FILE="$empty_file" bash "$BUILD_SCRIPT" "$empty_file" 2>&1)
empty_exit=$?
assert_exit_code "Empty file exits with code 0" "0" "$empty_exit"

# --- 13.4: Comments-only file → exit 0 ---
comments_file="${TMPDIR_TEST}/comments_$$.txt"
printf '# This is a comment\n# Another comment\n\n# blank above\n' > "$comments_file"
comments_output=$(BLESSED_SAMPLES_FILE="$comments_file" bash "$BUILD_SCRIPT" "$comments_file" 2>&1)
comments_exit=$?
assert_exit_code "Comments-only file exits with code 0" "0" "$comments_exit"

# --- 13.5: Single-URL format → defaults applied ---
echo "--- Test group: Config file parsing ---"
result=$(run_parse_config "https://github.com/org/repo.git")
assert_eq "Single URL: repo field" \
  "https://github.com/org/repo.git" \
  "$(echo "$result" | cut -d'|' -f1)"
assert_eq "Single URL: branch defaults to master" \
  "master" \
  "$(echo "$result" | cut -d'|' -f2)"
assert_eq "Single URL: path defaults to empty" \
  "" \
  "$(echo "$result" | cut -d'|' -f3)"
assert_eq "Single URL: arch defaults to amd64" \
  "amd64" \
  "$(echo "$result" | cut -d'|' -f4)"

# --- 13.6: Two-field line → correct branch extracted ---
result=$(run_parse_config "https://github.com/org/repo.git main")
assert_eq "Two fields: branch extracted" \
  "main" \
  "$(echo "$result" | cut -d'|' -f2)"
assert_eq "Two fields: path still empty" \
  "" \
  "$(echo "$result" | cut -d'|' -f3)"
assert_eq "Two fields: arch still amd64" \
  "amd64" \
  "$(echo "$result" | cut -d'|' -f4)"

# --- 13.7: Three-field line → branch and path extracted ---
result=$(run_parse_config "https://github.com/org/repo.git v2.31 edge/services/foo")
assert_eq "Three fields: branch extracted" \
  "v2.31" \
  "$(echo "$result" | cut -d'|' -f2)"
assert_eq "Three fields: path extracted" \
  "edge/services/foo" \
  "$(echo "$result" | cut -d'|' -f3)"
assert_eq "Three fields: arch still amd64" \
  "amd64" \
  "$(echo "$result" | cut -d'|' -f4)"

# --- 13.8: Four-field line → all fields extracted ---
result=$(run_parse_config "https://github.com/org/repo.git main edge/services/cpu arm64")
assert_eq "Four fields: repo" \
  "https://github.com/org/repo.git" \
  "$(echo "$result" | cut -d'|' -f1)"
assert_eq "Four fields: branch" \
  "main" \
  "$(echo "$result" | cut -d'|' -f2)"
assert_eq "Four fields: path" \
  "edge/services/cpu" \
  "$(echo "$result" | cut -d'|' -f3)"
assert_eq "Four fields: arch" \
  "arm64" \
  "$(echo "$result" | cut -d'|' -f4)"

# --- 13.9: Multi-arch comma value → passed through as-is ---
result=$(run_parse_config "https://github.com/org/repo.git main edge/services/cpu amd64,arm64")
assert_eq "Multi-arch: arch field contains comma-separated value" \
  "amd64,arm64" \
  "$(echo "$result" | cut -d'|' -f4)"

# --- 13.10: Five-field line → logged as error, skipped, run continues ---
echo "--- Test group: Error handling ---"
two_line_file="${TMPDIR_TEST}/two_lines_$$.txt"
printf '%s\n%s\n' \
  'https://github.com/org/repo.git a b c d extra_field' \
  'https://github.com/org/good.git' > "$two_line_file"
five_field_combined=$(run_parse_config_stderr "$two_line_file")
assert_contains "Five fields: error message logged" \
  "Invalid line format" \
  "$five_field_combined"
good_lines=$(run_parse_config_file "$two_line_file" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "Five fields: remaining valid line still processed" \
  "1" \
  "$good_lines"

# --- 13.11: Invalid arch value → entry skipped ---
invalid_file="${TMPDIR_TEST}/invalid_arch_$$.txt"
printf 'https://github.com/org/repo.git main /path x86\n' > "$invalid_file"
invalid_combined=$(run_parse_config_stderr "$invalid_file")
assert_contains "Invalid arch: error message logged" \
  "Invalid architecture" \
  "$invalid_combined"
valid_lines=$(run_parse_config_file "$invalid_file" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "Invalid arch: entry not emitted to stdout" \
  "0" \
  "$valid_lines"

# --- 13.12 + 13.13: Docker/Podman runtime detection (via mocked PATH) ---
echo "--- Test group: Runtime detection ---"

# Create mock docker binary
MOCK_DOCKER_DIR="${TMPDIR_TEST}/mock_docker_$$"
mkdir -p "$MOCK_DOCKER_DIR"
cat > "${MOCK_DOCKER_DIR}/docker" <<'EOF'
#!/bin/sh
if [ "$1" = "info" ]; then exit 0; fi
exit 0
EOF
chmod +x "${MOCK_DOCKER_DIR}/docker"

docker_result=$(
  bash -c "
    source '${BUILD_SCRIPT}' 2>/dev/null
    PATH='${MOCK_DOCKER_DIR}:\${PATH}' detect_container_runtime 2>/dev/null
  " 2>/dev/null
)
assert_eq "Docker detected when docker info succeeds" "docker" "$docker_result"

# Create mock podman binary (no docker in PATH)
MOCK_PODMAN_DIR="${TMPDIR_TEST}/mock_podman_$$"
mkdir -p "$MOCK_PODMAN_DIR"
cat > "${MOCK_PODMAN_DIR}/podman" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${MOCK_PODMAN_DIR}/podman"

podman_result=$(
  bash -c "
    source '${BUILD_SCRIPT}' 2>/dev/null
    PATH='${MOCK_PODMAN_DIR}' detect_container_runtime 2>/dev/null
  " 2>/dev/null
)
assert_eq "Podman detected when docker absent" "podman" "$podman_result"

# --- 13.14: Topological sort orders B after A when B depends on A ---
echo "--- Test group: Dependency resolution ---"
topo_result=$(
  bash -c "
    source '${BUILD_SCRIPT}' 2>/dev/null
    ENTRIES=('a' 'b')
    IN_DEGREE=([0]=0 [1]=1)
    ADJ_LIST=([0]='1' [1]='')
    topological_sort 2>/dev/null
  " 2>/dev/null
)
assert_eq "Topological sort: B ordered after A (indices 0 1)" "0 1" "$topo_result"

# --- 13.15: Circular dependency → exit 1 with error message ---
circular_output=$(
  bash -c "
    source '${BUILD_SCRIPT}' 2>/dev/null
    ENTRIES=('a' 'b')
    IN_DEGREE=([0]=1 [1]=1)
    ADJ_LIST=([0]='1' [1]='0')
    topological_sort 2>&1
  " 2>&1
)
if echo "$circular_output" | grep -qiE "Circular|circular"; then
  pass "Circular dependency: error message emitted"
else
  fail "Circular dependency: error message emitted" "output containing 'Circular'" "$circular_output"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "====================================================="
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
echo "====================================================="

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
