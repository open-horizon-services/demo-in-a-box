#!/usr/bin/env bash
# scripts/build-blessed-samples.sh
#
# Build and publish Open Horizon services listed in blessedSamples.txt.
# Supports both the Issue #21 single-URL format and the Issue #34 enhanced
# 4-field format:
#   <git_repo_url> [<branch_or_tag>] [<service_path>] [<arch>]
#
# Environment variables (all optional):
#   BLESSED_SAMPLES_FILE    Path to blessedSamples.txt  (default: ./blessedSamples.txt)
#   FAIL_FAST               Set to "true" to abort on first failure
#   USE_LOCAL_REGISTRY      Set to "true" to rewrite image names with registry prefix
#   REGISTRY_URL            Local registry URL           (default: 192.168.56.10:5000)
#   OH_EXAMPLES_REPO        Examples repo base URL       (passed through to make publish)
#   BLESSED_SAMPLES_CREDENTIALS  Path to credentials file (default: ./mycreds.env)
#   LOG_FILE                Path to log file override (optional; auto-generated if unset)
#   SUMMARY_FILE            Path for summary file (optional)
#   HUB_IP                  Hub VM IP (default: 192.168.56.10)

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BLESSED_SAMPLES_FILE="${BLESSED_SAMPLES_FILE:-./blessedSamples.txt}"
FAIL_FAST="${FAIL_FAST:-false}"
USE_LOCAL_REGISTRY="${USE_LOCAL_REGISTRY:-false}"
REGISTRY_URL="${REGISTRY_URL:-192.168.56.10:5000}"
OH_EXAMPLES_REPO="${OH_EXAMPLES_REPO:-https://raw.githubusercontent.com/open-horizon/examples/master}"
BLESSED_SAMPLES_CREDENTIALS="${BLESSED_SAMPLES_CREDENTIALS:-./mycreds.env}"
HUB_IP="${HUB_IP:-192.168.56.10}"
WORK_DIR="/tmp/blessed-samples"

# Log file: use override if provided, else generate timestamped name
if [ -z "${LOG_FILE:-}" ]; then
  LOG_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
  LOG_FILE="/var/log/blessed-samples-build-${LOG_TIMESTAMP}.log"
fi

# Host-visible copy (via Vagrant shared folder)
LOG_HOST_COPY="/vagrant/blessed-samples-build-latest.log"

# Counters
SUCCESS_COUNT=0
FAILURE_COUNT=0
FAILED_SERVICES=()

# ---------------------------------------------------------------------------
# 1. Logging
# ---------------------------------------------------------------------------
init_logging() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  # Tee all output to log file; fall back to stdout-only if log dir unavailable
  if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
  fi
  echo "=== Blessed Samples Build Started: $(date) ==="
  echo "=== BLESSED_SAMPLES_FILE: ${BLESSED_SAMPLES_FILE} ==="
  echo "=== OH_EXAMPLES_REPO: ${OH_EXAMPLES_REPO} ==="
  echo "=== REGISTRY_URL: ${REGISTRY_URL} ==="
}

copy_log_to_host() {
  if [ -f "$LOG_FILE" ] && [ -d "/vagrant" ]; then
    cp "$LOG_FILE" "$LOG_HOST_COPY" 2>/dev/null || true
    echo "=== Log copied to ${LOG_HOST_COPY} ==="
  fi
  # Also write summary file if requested
  if [ -n "${SUMMARY_FILE:-}" ]; then
    {
      echo "=== Blessed Samples Build Summary: $(date) ==="
      echo "Successful: ${SUCCESS_COUNT}"
      echo "Failed: ${FAILURE_COUNT}"
      if [ "${#FAILED_SERVICES[@]}" -gt 0 ]; then
        echo "Failed services:"
        for svc in "${FAILED_SERVICES[@]}"; do
          echo "  - ${svc}"
        done
      fi
    } > "$SUMMARY_FILE" 2>/dev/null || true
  fi
}

# Always copy log on exit (success or failure)
trap copy_log_to_host EXIT

# ---------------------------------------------------------------------------
# 2. Pre-flight checks
# ---------------------------------------------------------------------------
check_config_file() {
  if [ ! -f "$BLESSED_SAMPLES_FILE" ]; then
    echo "No blessedSamples.txt found at '${BLESSED_SAMPLES_FILE}'. Skipping blessed samples build."
    exit 0
  fi
}

# ---------------------------------------------------------------------------
# 3. Container runtime detection
# ---------------------------------------------------------------------------
detect_container_runtime() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "docker"
  elif command -v podman >/dev/null 2>&1; then
    echo "podman"
  else
    echo "ERROR: Neither Docker nor Podman found on this system" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# 4. Config file parser
#    Emits lines of the form:  repo|branch|path|arch
# ---------------------------------------------------------------------------
parse_config() {
  local file="$1"
  local line_num=0

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    ((line_num++)) || true
    # Strip leading/trailing whitespace
    local line
    line=$(echo "$raw_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Skip comments and blank lines
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

    # Count fields
    local field_count
    field_count=$(echo "$line" | awk '{print NF}')

    local repo branch svc_path arch

    if [ "$field_count" -lt 1 ] || [ "$field_count" -gt 4 ]; then
      echo "ERROR: Invalid line format (expected 1-4 fields, got ${field_count}) at line ${line_num}: ${line}" >&2
      continue
    fi

    read -r repo branch svc_path arch <<< "$(echo "$line" | awk '{print $1, $2, $3, $4}')"

    # Apply defaults for missing fields
    branch="${branch:-master}"
    svc_path="${svc_path:-}"
    arch="${arch:-amd64}"

    # Validate architecture (comma-separated allowed)
    local IFS_SAVED="$IFS"
    IFS=','
    local arch_valid=true
    for a in $arch; do
      case "$a" in
        amd64|arm64|arm|ppc64le) ;;
        *)
          echo "ERROR: Invalid architecture '${a}' at line ${line_num}: ${line}" >&2
          arch_valid=false
          ;;
      esac
    done
    IFS="$IFS_SAVED"
    $arch_valid || continue

    echo "${repo}|${branch}|${svc_path}|${arch}"
  done < "$file"
}

# ---------------------------------------------------------------------------
# 5. Repository cloning
# ---------------------------------------------------------------------------
clone_repo() {
  local repo_url="$1"
  local branch="$2"
  local repo_name
  repo_name=$(basename "$repo_url" .git)
  local clone_dir="${WORK_DIR}/${repo_name}"

  mkdir -p "$WORK_DIR"

  # Remove existing clone
  [ -d "$clone_dir" ] && rm -rf "$clone_dir"

  echo "==> Cloning ${repo_url} (branch: ${branch})..."
  if git clone --depth 1 --branch "$branch" "$repo_url" "$clone_dir" 2>&1; then
    echo "$clone_dir"
    return 0
  fi

  # Shallow clone failed (e.g., server doesn't support it) – try full clone
  echo "WARNING: Shallow clone failed; retrying full clone..."
  if git clone --branch "$branch" "$repo_url" "$clone_dir" 2>&1; then
    echo "$clone_dir"
    return 0
  fi

  echo "ERROR: Failed to clone ${repo_url} (branch: ${branch})" >&2
  return 1
}

# ---------------------------------------------------------------------------
# 6. Service path resolution
# ---------------------------------------------------------------------------
resolve_service_path() {
  local clone_dir="$1"
  local svc_path="$2"
  local resolved

  if [ -n "$svc_path" ]; then
    resolved="${clone_dir}/${svc_path}"
  else
    resolved="$clone_dir"
  fi

  if [ ! -f "${resolved}/horizon/service.definition.json" ]; then
    echo "ERROR: No horizon/service.definition.json found at ${resolved}/horizon/" >&2
    return 1
  fi

  echo "$resolved"
}

# ---------------------------------------------------------------------------
# 7. Dependency resolution (Kahn's topological sort)
#    Input: associative arrays populated by build_dep_graph
#    Output: ordered list of indices into ENTRIES array
# ---------------------------------------------------------------------------

# Global arrays for dependency graph
declare -a ENTRIES=()          # "repo|branch|path|arch" entries in file order
declare -a ENTRY_KEYS=()       # service spec key (org/service/version) per entry index
declare -A IN_DEGREE=()        # in_degree[idx] = count of unresolved deps
declare -A ADJ_LIST=()         # adj_list[dep_idx] = space-separated dependents

extract_service_key() {
  local svc_dir="$1"
  local def="${svc_dir}/horizon/service.definition.json"
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.org // "unknown") + "/" + .url + "/" + .version' "$def" 2>/dev/null || echo "unknown"
  else
    # Fallback: grep for url field
    local url
    url=$(grep '"url"' "$def" | head -1 | sed 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    echo "${url:-unknown}"
  fi
}

extract_required_services() {
  local svc_dir="$1"
  local def="${svc_dir}/horizon/service.definition.json"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.requiredServices[]?.url // empty' "$def" 2>/dev/null || true
  else
    grep '"url"' "$def" | tail -n +2 | sed 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true
  fi
}

topological_sort() {
  # Returns space-separated indices in build order
  local -a queue=()
  local -a sorted=()
  local idx

  # Initialize queue with zero-in-degree nodes
  for idx in "${!ENTRIES[@]}"; do
    if [ "${IN_DEGREE[$idx]:-0}" -eq 0 ]; then
      queue+=("$idx")
    fi
  done

  while [ "${#queue[@]}" -gt 0 ]; do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")
    sorted+=("$current")

    # Reduce in-degree for dependents
    local dependents="${ADJ_LIST[$current]:-}"
    for dep in $dependents; do
      IN_DEGREE[$dep]=$(( ${IN_DEGREE[$dep]:-1} - 1 ))
      if [ "${IN_DEGREE[$dep]}" -eq 0 ]; then
        queue+=("$dep")
      fi
    done
  done

  if [ "${#sorted[@]}" -ne "${#ENTRIES[@]}" ]; then
    echo "ERROR: Circular dependency detected among blessed services" >&2
    return 1
  fi

  echo "${sorted[@]}"
}

# ---------------------------------------------------------------------------
# 8. Service building
# ---------------------------------------------------------------------------
QEMU_SETUP_DONE=false

setup_qemu_emulation() {
  if [ "$QEMU_SETUP_DONE" = "false" ]; then
    echo "==> Setting up QEMU multi-arch emulation..."
    docker run --privileged --rm tonistiigi/binfmt --install all 2>&1 || true
    QEMU_SETUP_DONE=true
  fi
}

build_service() {
  local svc_dir="$1"
  local runtime="$2"
  local arch="$3"

  echo "==> Building service in ${svc_dir} (runtime: ${runtime}, arch: ${arch})..."

  if [ ! -f "${svc_dir}/Makefile" ]; then
    echo "ERROR: No Makefile found in ${svc_dir}" >&2
    return 1
  fi

  # Determine if we need multi-arch build
  local need_multiarch=false
  local IFS_SAVED="$IFS"
  IFS=','
  local arch_list=($arch)
  IFS="$IFS_SAVED"

  for a in "${arch_list[@]}"; do
    if [ "$a" != "amd64" ]; then
      need_multiarch=true
      break
    fi
  done

  if [ "$need_multiarch" = "true" ]; then
    # Build platform string (e.g., linux/amd64,linux/arm64)
    local platforms=""
    for a in "${arch_list[@]}"; do
      platforms="${platforms},linux/${a}"
    done
    platforms="${platforms#,}"  # strip leading comma

    if [ "$runtime" = "docker" ]; then
      setup_qemu_emulation
      (cd "$svc_dir" && docker buildx build --platform "$platforms" . 2>&1) || return 1
    elif [ "$runtime" = "podman" ]; then
      setup_qemu_emulation
      (cd "$svc_dir" && podman build --platform "$platforms" . 2>&1) || return 1
    fi
  else
    # Standard single-arch build via Makefile
    (cd "$svc_dir" && make build 2>&1) || return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# 9. Image extraction, tagging, and registry push
# ---------------------------------------------------------------------------
extract_image_name() {
  local svc_dir="$1"
  local def="${svc_dir}/horizon/service.definition.json"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.deployment.services | to_entries[0].value.image // empty' "$def" 2>/dev/null \
      || jq -r '.deployment | if type == "string" then . else empty end' "$def" 2>/dev/null \
      || echo ""
  else
    grep '"image"' "$def" | head -1 | sed 's/.*"image"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo ""
  fi
}

push_to_registry() {
  local svc_dir="$1"
  local runtime="$2"
  local image_name="$3"

  if [ -z "$image_name" ]; then
    echo "WARNING: Could not determine image name; skipping registry push"
    return 0
  fi

  local registry_tag="${REGISTRY_URL}/${image_name##*/}"
  echo "==> Tagging ${image_name} → ${registry_tag}..."
  "${runtime}" tag "$image_name" "$registry_tag" 2>&1 || {
    echo "WARNING: Failed to tag image ${image_name}; skipping push"
    return 0
  }

  echo "==> Pushing ${registry_tag} to local registry..."
  "${runtime}" push "$registry_tag" 2>&1 || {
    echo "WARNING: Failed to push ${registry_tag}; continuing (registry push is best-effort)"
    return 0
  }

  echo "✓ Image pushed to ${registry_tag}"

  # If USE_LOCAL_REGISTRY=true, rewrite image name in service definition
  if [ "${USE_LOCAL_REGISTRY}" = "true" ] && command -v jq >/dev/null 2>&1; then
    local def="${svc_dir}/horizon/service.definition.json"
    local tmp="${def}.tmp"
    jq --arg new_img "$registry_tag" \
      'walk(if type == "object" and has("image") then .image = $new_img else . end)' \
      "$def" > "$tmp" && mv "$tmp" "$def"
    echo "✓ Rewrote image name in service.definition.json to ${registry_tag}"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# 10. Service publishing
# ---------------------------------------------------------------------------
publish_service() {
  local svc_dir="$1"

  echo "==> Publishing service from ${svc_dir}..."

  # Source credentials
  local creds_file="$BLESSED_SAMPLES_CREDENTIALS"
  if [ -f "$creds_file" ]; then
    # shellcheck disable=SC1090
    set +u
    source "$creds_file"
    set -u
  else
    echo "WARNING: Credentials file '${creds_file}' not found; using existing environment"
  fi

  # Export OH_EXAMPLES_REPO for make targets (preserves Issue #21 behavior)
  export OH_EXAMPLES_REPO

  if (cd "$svc_dir" && make --dry-run publish >/dev/null 2>&1); then
    (cd "$svc_dir" && make publish 2>&1) || return 1
  else
    (cd "$svc_dir" && hzn exchange service publish -f horizon/service.definition.json 2>&1) || return 1
  fi

  echo "✓ Service published successfully"
  return 0
}

# ---------------------------------------------------------------------------
# 11. Build summary
# ---------------------------------------------------------------------------
print_summary() {
  echo ""
  echo "=== Build Summary ==="
  echo "Successful: ${SUCCESS_COUNT}"
  echo "Failed:     ${FAILURE_COUNT}"
  if [ "${#FAILED_SERVICES[@]}" -gt 0 ]; then
    echo "Failed services:"
    for svc in "${FAILED_SERVICES[@]}"; do
      echo "  ✗ ${svc}"
    done
  fi
  echo "=== Build Complete: $(date) ==="
}

# ---------------------------------------------------------------------------
# 12. Main execution
# ---------------------------------------------------------------------------
main() {
  init_logging
  check_config_file

  local runtime
  runtime=$(detect_container_runtime)
  echo "==> Using container runtime: ${runtime}"

  mkdir -p "$WORK_DIR"

  # ---- Phase A: Parse all entries from config file ----
  local raw_entries=()
  while IFS= read -r entry; do
    raw_entries+=("$entry")
  done < <(parse_config "$BLESSED_SAMPLES_FILE")

  if [ "${#raw_entries[@]}" -eq 0 ]; then
    echo "No valid entries found in ${BLESSED_SAMPLES_FILE}. Nothing to build."
    print_summary
    exit 0
  fi

  # ---- Phase B: Clone all repos and map service directories ----
  # We need service dirs to build the dependency graph
  declare -a svc_dirs=()
  declare -a valid_entries=()

  for entry in "${raw_entries[@]}"; do
    IFS='|' read -r repo branch svc_path arch <<< "$entry"

    local clone_dir
    if clone_dir=$(clone_repo "$repo" "$branch"); then
      local resolved_dir
      if resolved_dir=$(resolve_service_path "$clone_dir" "$svc_path"); then
        svc_dirs+=("$resolved_dir")
        valid_entries+=("$entry")
        ENTRIES+=("$entry")
        ENTRY_KEYS+=($(extract_service_key "$resolved_dir"))
        IN_DEGREE[${#ENTRIES[@]}-1]=0
      else
        echo "✗ Skipping (no service definition): ${repo}/${svc_path}"
        ((FAILURE_COUNT++)) || true
        FAILED_SERVICES+=("${repo}/${svc_path}")
      fi
    else
      echo "✗ Skipping (clone failed): ${repo}"
      ((FAILURE_COUNT++)) || true
      FAILED_SERVICES+=("$repo")
    fi
  done

  # ---- Phase C: Build dependency graph ----
  local num_entries="${#ENTRIES[@]}"
  for ((i=0; i<num_entries; i++)); do
    local key="${ENTRY_KEYS[$i]}"
    local req_svcs
    req_svcs=$(extract_required_services "${svc_dirs[$i]}")
    for req in $req_svcs; do
      # Find the index of this required service
      for ((j=0; j<num_entries; j++)); do
        if echo "${ENTRY_KEYS[$j]}" | grep -q "$req"; then
          # j must be built before i
          ADJ_LIST[$j]="${ADJ_LIST[$j]:-} $i"
          IN_DEGREE[$i]=$(( ${IN_DEGREE[$i]:-0} + 1 ))
          break
        fi
      done
    done
  done

  # ---- Phase D: Topological sort ----
  local sorted_indices
  if ! sorted_indices=$(topological_sort); then
    echo "ERROR: Dependency resolution failed. Aborting."
    print_summary
    exit 1
  fi

  # ---- Phase E: Build, tag, push, publish in sorted order ----
  for idx in $sorted_indices; do
    local entry="${ENTRIES[$idx]}"
    local svc_dir="${svc_dirs[$idx]}"
    IFS='|' read -r repo branch svc_path arch <<< "$entry"
    local label="${repo##*/}/${svc_path:-root}"

    echo ""
    echo "=== Processing: ${label} (arch: ${arch}) ==="

    local service_ok=true

    # Build
    if ! build_service "$svc_dir" "$runtime" "$arch"; then
      echo "✗ Build failed: ${label}"
      ((FAILURE_COUNT++)) || true
      FAILED_SERVICES+=("$label")
      if [ "$FAIL_FAST" = "true" ]; then
        echo "FAIL_FAST=true; aborting."
        print_summary
        exit 1
      fi
      service_ok=false
    fi

    if [ "$service_ok" = "true" ]; then
      # Extract image name and push to registry
      local image_name
      image_name=$(extract_image_name "$svc_dir")
      push_to_registry "$svc_dir" "$runtime" "$image_name"

      # Publish to Exchange
      if publish_service "$svc_dir"; then
        echo "✓ Success: ${label}"
        ((SUCCESS_COUNT++)) || true
      else
        echo "✗ Publish failed: ${label}"
        ((FAILURE_COUNT++)) || true
        FAILED_SERVICES+=("$label")
        if [ "$FAIL_FAST" = "true" ]; then
          echo "FAIL_FAST=true; aborting."
          print_summary
          exit 1
        fi
      fi
    fi
  done

  print_summary

  if [ "$FAILURE_COUNT" -gt 0 ]; then
    exit 1
  fi
}

# Only run main when executed directly (not when sourced for unit testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
