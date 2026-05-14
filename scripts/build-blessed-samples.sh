#!/bin/bash
# build-blessed-samples.sh
# Phase 2 Core Build Pipeline for blessed samples support

set -euo pipefail

BLESSED_SAMPLES_FILE="${BLESSED_SAMPLES_FILE:-/vagrant/blessedSamples.txt}"
LOG_FILE="${LOG_FILE:-/var/log/blessed-samples-build.log}"
SUMMARY_FILE="${SUMMARY_FILE:-/var/log/blessed-samples-summary.log}"
WORK_DIR="${WORK_DIR:-/tmp/blessed-samples}"
HUB_IP="${HUB_IP:-192.168.56.10}"
REGISTRY_URL="${REGISTRY_URL:-${HUB_IP}:5000}"
OH_EXAMPLES_REPO="${OH_EXAMPLES_REPO:-https://raw.githubusercontent.com/open-horizon/examples/master}"
BLESSED_SAMPLES_CREDENTIALS="${BLESSED_SAMPLES_CREDENTIALS:-/vagrant/mycreds.env}"
FAIL_FAST="${FAIL_FAST:-1}"
MANUAL_ORDER_OVERRIDE="${MANUAL_ORDER_OVERRIDE:-0}"

declare -a ENTRY_IDS=()
declare -a BUILD_ORDER=()
declare -a SUMMARY_LINES=()
declare -A ENTRY_REPO=()
declare -A ENTRY_BRANCH=()
declare -A ENTRY_PATH=()
declare -A ENTRY_ARCH=()
declare -A ENTRY_CLONE_DIR=()
declare -A ENTRY_SERVICE_DIR=()
declare -A ENTRY_SERVICE_KEY=()
declare -A ENTRY_IMAGE=()
declare -A ENTRY_STATUS=()
declare -A ENTRY_MESSAGE=()
declare -A SERVICE_TO_ENTRY=()
declare -A DEPENDS_ON=()
declare -A IN_DEGREE=()
declare -A ADJACENCY=()

CONTAINER_RUNTIME=""
CONTAINER_PUSH_CMD=""
HZN_ORG_ID_VALUE=""
HZN_EXCHANGE_USER_AUTH_VALUE=""

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    echo "[$(timestamp)] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO: $*"
}

log_error() {
    log "ERROR: $*" >&2
}

fail() {
    log_error "$*"
    exit 1
}

trim() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

init_log() {
    mkdir -p "$(dirname "${LOG_FILE}")" "$(dirname "${SUMMARY_FILE}")" "${WORK_DIR}"
    : > "${LOG_FILE}"
    : > "${SUMMARY_FILE}"

    log "=========================================="
    log "Blessed Samples Build Script - Phase 2"
    log "=========================================="
    log "Configuration:"
    log "  Blessed Samples File: ${BLESSED_SAMPLES_FILE}"
    log "  Log File: ${LOG_FILE}"
    log "  Summary File: ${SUMMARY_FILE}"
    log "  Work Dir: ${WORK_DIR}"
    log "  Hub IP: ${HUB_IP}"
    log "  Registry URL: ${REGISTRY_URL}"
    log "  OH_EXAMPLES_REPO: ${OH_EXAMPLES_REPO}"
    log "  Credentials File: ${BLESSED_SAMPLES_CREDENTIALS}"
    log "  Fail Fast: ${FAIL_FAST}"
    log "  Manual Order Override: ${MANUAL_ORDER_OVERRIDE}"
    log ""
}

check_config_file() {
    if [ ! -f "${BLESSED_SAMPLES_FILE}" ]; then
        log_info "No blessedSamples.txt file found at ${BLESSED_SAMPLES_FILE}"
        log_info "Skipping blessed samples build"
        exit 0
    fi
}

validate_repo_url() {
    local repo_url="$1"
    if [[ "${repo_url}" =~ ^https?://.+\.git$ ]]; then
        return 0
    fi

    if [[ "${repo_url}" =~ ^https?:// ]]; then
        return 0
    fi

    return 1
}

validate_branch() {
    local branch="$1"
    [ -z "${branch}" ] && return 0
    [[ "${branch}" =~ ^[a-zA-Z0-9/_.-]+$ ]]
}

validate_service_path() {
    local service_path="$1"
    [ -z "${service_path}" ] && return 0
    [[ ! "${service_path}" =~ ^/ ]] && [[ ! "${service_path}" =~ \.\. ]]
}

validate_arches() {
    local arch="$1"
    local valid_archs="amd64|arm64|arm|ppc64le|s390x"
    local part

    [ -z "${arch}" ] && return 0

    IFS=',' read -ra arch_parts <<< "${arch}"
    for part in "${arch_parts[@]}"; do
        part="$(trim "${part}")"
        [[ "${part}" =~ ^(${valid_archs})$ ]] || return 1
    done
}

parse_config() {
    local line line_num=0 field_count repo branch service_path arch entry_id
    local valid_count=0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_num++))
        line="$(trim "${line}")"

        if [[ -z "${line}" ]] || [[ "${line}" =~ ^# ]]; then
            continue
        fi

        field_count=$(wc -w <<< "${line}" | tr -d ' ')
        repo=""
        branch=""
        service_path=""
        arch="amd64"

        case "${field_count}" in
            1)
                repo="${line}"
                branch="master"
                ;;
            2)
                read -r repo branch <<< "${line}"
                ;;
            3)
                read -r repo branch service_path <<< "${line}"
                ;;
            4)
                read -r repo branch service_path arch <<< "${line}"
                ;;
            *)
                fail "Line ${line_num}: Invalid format. Expected 1-4 whitespace-separated fields."
                ;;
        esac

        validate_repo_url "${repo}" || fail "Line ${line_num}: Invalid repository URL: ${repo}"
        validate_branch "${branch}" || fail "Line ${line_num}: Invalid branch name: ${branch}"
        validate_service_path "${service_path}" || fail "Line ${line_num}: Invalid service path: ${service_path}"
        validate_arches "${arch}" || fail "Line ${line_num}: Invalid architecture list: ${arch}"

        entry_id="entry_${valid_count}"
        ENTRY_IDS+=("${entry_id}")
        ENTRY_REPO["${entry_id}"]="${repo}"
        ENTRY_BRANCH["${entry_id}"]="${branch}"
        ENTRY_PATH["${entry_id}"]="${service_path}"
        ENTRY_ARCH["${entry_id}"]="${arch}"
        ENTRY_STATUS["${entry_id}"]="pending"
        ENTRY_MESSAGE["${entry_id}"]="parsed"

        log_info "Parsed ${entry_id}: repo=${repo} branch=${branch} path=${service_path:-<auto>} arch=${arch}"
        ((valid_count++))
    done < "${BLESSED_SAMPLES_FILE}"

    if [ ${#ENTRY_IDS[@]} -eq 0 ]; then
        log_info "No active entries found in ${BLESSED_SAMPLES_FILE}"
        exit 0
    fi
}

detect_container_runtime() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
        CONTAINER_PUSH_CMD="docker"
    elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
        CONTAINER_PUSH_CMD="podman"
    else
        fail "Neither Docker nor Podman is available and functional"
    fi

    log_info "Using container runtime: ${CONTAINER_RUNTIME}"
}

load_credentials() {
    if [ ! -f "${BLESSED_SAMPLES_CREDENTIALS}" ]; then
        fail "Credentials file not found: ${BLESSED_SAMPLES_CREDENTIALS}"
    fi

    # shellcheck disable=SC1090
    source "${BLESSED_SAMPLES_CREDENTIALS}"

    HZN_ORG_ID_VALUE="${HZN_ORG_ID:-}"
    HZN_EXCHANGE_USER_AUTH_VALUE="${HZN_EXCHANGE_USER_AUTH:-}"

    [ -n "${HZN_ORG_ID_VALUE}" ] || fail "HZN_ORG_ID missing from credentials file"
    [ -n "${HZN_EXCHANGE_USER_AUTH_VALUE}" ] || fail "HZN_EXCHANGE_USER_AUTH missing from credentials file"

    log_info "Loaded exchange credentials for org: ${HZN_ORG_ID_VALUE}"
}

repo_basename() {
    local repo_url="$1"
    local name
    name="$(basename "${repo_url}")"
    name="${name%.git}"
    printf '%s' "${name}"
}

clone_repo() {
    local entry_id="$1"
    local repo_url="${ENTRY_REPO[${entry_id}]}"
    local branch="${ENTRY_BRANCH[${entry_id}]}"
    local repo_name clone_dir

    repo_name="$(repo_basename "${repo_url}")"
    clone_dir="${WORK_DIR}/${entry_id}-${repo_name}"

    rm -rf "${clone_dir}"
    log_info "Cloning ${repo_url} (branch/tag: ${branch}) into ${clone_dir}"
    git clone --depth 1 --branch "${branch}" "${repo_url}" "${clone_dir}" >> "${LOG_FILE}" 2>&1

    ENTRY_CLONE_DIR["${entry_id}"]="${clone_dir}"
}

find_service_dir() {
    local entry_id="$1"
    local clone_dir="${ENTRY_CLONE_DIR[${entry_id}]}"
    local configured_path="${ENTRY_PATH[${entry_id}]}"
    local service_dir=""

    if [ -n "${configured_path}" ]; then
        service_dir="${clone_dir}/${configured_path}"
        [ -d "${service_dir}" ] || fail "${entry_id}: Service path not found: ${service_dir}"
    else
        service_dir="$(find "${clone_dir}" -path '*/horizon/service.definition.json' -print | head -n 1 | xargs -I{} dirname "$(dirname "{}")")"
        [ -n "${service_dir}" ] || fail "${entry_id}: Could not auto-detect service directory"
    fi

    [ -f "${service_dir}/horizon/service.definition.json" ] || fail "${entry_id}: Missing horizon/service.definition.json in ${service_dir}"
    ENTRY_SERVICE_DIR["${entry_id}"]="${service_dir}"
    log_info "${entry_id}: Service directory resolved to ${service_dir}"
}

extract_json_field() {
    local file="$1"
    local python_expr="$2"
    python3 -c "import json; data=json.load(open('${file}')); ${python_expr}" 2>/dev/null
}

discover_service_metadata() {
    local entry_id="$1"
    local definition_file="${ENTRY_SERVICE_DIR[${entry_id}]}/horizon/service.definition.json"
    local image service_name service_org service_arch service_key

    image="$(extract_json_field "${definition_file}" "print(data.get('deployment',{}).get('services',{}).get(list(data.get('deployment',{}).get('services',{}).keys())[0],{}).get('image',''))")"
    service_name="$(extract_json_field "${definition_file}" "print(data.get('label','') or data.get('name',''))")"
    service_org="$(extract_json_field "${definition_file}" "print(data.get('org',''))")"
    service_arch="$(extract_json_field "${definition_file}" "print(data.get('arch',''))")"

    [ -n "${image}" ] || fail "${entry_id}: Unable to determine image name from service definition"
    [ -n "${service_name}" ] || service_name="$(basename "${ENTRY_SERVICE_DIR[${entry_id}]}")"
    [ -n "${service_org}" ] || service_org="${HZN_ORG_ID_VALUE}"
    [ -n "${service_arch}" ] || service_arch="${ENTRY_ARCH[${entry_id}]%%,*}"

    service_key="${service_org}/${service_name}:${service_arch}"

    ENTRY_IMAGE["${entry_id}"]="${image}"
    ENTRY_SERVICE_KEY["${entry_id}"]="${service_key}"
    SERVICE_TO_ENTRY["${service_key}"]="${entry_id}"
    DEPENDS_ON["${entry_id}"]=""
    IN_DEGREE["${entry_id}"]=0

    log_info "${entry_id}: Service key=${service_key} image=${image}"
}

resolve_dependencies() {
    local entry_id definition_file deps raw_dep normalized dep_entry

    for entry_id in "${ENTRY_IDS[@]}"; do
        definition_file="${ENTRY_SERVICE_DIR[${entry_id}]}/horizon/service.definition.json"
        raw_dep="$(python3 - <<PY
import json
with open("${definition_file}", "r", encoding="utf-8") as f:
    data = json.load(f)
required = data.get("requiredServices", [])
for item in required:
    if isinstance(item, dict):
        org = item.get("org", "")
        url = item.get("url", "")
        version = item.get("versionRange", "")
        arch = item.get("arch", "")
        print(f"{org}|{url}|{version}|{arch}")
PY
)"
        while IFS= read -r deps; do
            [ -n "${deps}" ] || continue
            IFS='|' read -r dep_org dep_url dep_version dep_arch <<< "${deps}"
            dep_arch="${dep_arch:-${ENTRY_ARCH[${entry_id}]%%,*}}"
            normalized="${dep_org}/${dep_url}:${dep_arch}"
            dep_entry="${SERVICE_TO_ENTRY[${normalized}]:-}"

            if [ -n "${dep_entry}" ]; then
                DEPENDS_ON["${entry_id}"]="${DEPENDS_ON[${entry_id}]} ${dep_entry}"
                ADJACENCY["${dep_entry}"]="${ADJACENCY[${dep_entry}]} ${entry_id}"
                IN_DEGREE["${entry_id}"]=$(( ${IN_DEGREE[${entry_id}]} + 1 ))
                log_info "${entry_id}: depends on ${dep_entry} (${normalized})"
            else
                log_info "${entry_id}: dependency ${normalized} not managed by blessed samples; assuming external"
            fi
        done <<< "${raw_dep}"
    done
}

topological_sort() {
    local -a queue=()
    local -a resolved=()
    local entry_id current neighbor

    if [ "${MANUAL_ORDER_OVERRIDE}" = "1" ]; then
        BUILD_ORDER=("${ENTRY_IDS[@]}")
        log_info "Manual ordering override enabled; using file order"
        return 0
    fi

    for entry_id in "${ENTRY_IDS[@]}"; do
        if [ "${IN_DEGREE[${entry_id}]}" -eq 0 ]; then
            queue+=("${entry_id}")
        fi
    done

    while [ ${#queue[@]} -gt 0 ]; do
        current="${queue[0]}"
        queue=("${queue[@]:1}")
        resolved+=("${current}")

        for neighbor in ${ADJACENCY[${current}]:-}; do
            IN_DEGREE["${neighbor}"]=$(( ${IN_DEGREE[${neighbor}]} - 1 ))
            if [ "${IN_DEGREE[${neighbor}]}" -eq 0 ]; then
                queue+=("${neighbor}")
            fi
        done
    done

    if [ ${#resolved[@]} -ne ${#ENTRY_IDS[@]} ]; then
        fail "Circular dependency detected while resolving blessed sample services"
    fi

    BUILD_ORDER=("${resolved[@]}")
    log_info "Resolved build order: ${BUILD_ORDER[*]}"
}

tag_image_for_registry() {
    local source_image="$1"
    local image_name="${source_image##*/}"
    printf '%s/%s' "${REGISTRY_URL}" "${image_name}"
}

build_service() {
    local entry_id="$1"
    local service_dir="${ENTRY_SERVICE_DIR[${entry_id}]}"
    local arch="${ENTRY_ARCH[${entry_id}]}"

    log_info "${entry_id}: Building service in ${service_dir} for arch=${arch}"
    (
        cd "${service_dir}"
        if [ ! -f "Makefile" ]; then
            fail "${entry_id}: No Makefile found in ${service_dir}"
        fi

        if [ "${CONTAINER_RUNTIME}" = "docker" ] && [[ "${arch}" == *,* ]]; then
            make build BUILD_ARCH="${arch}" CONTAINER_RUNTIME="${CONTAINER_RUNTIME}"
        else
            make build CONTAINER_RUNTIME="${CONTAINER_RUNTIME}" ARCH="${arch}"
        fi
    ) >> "${LOG_FILE}" 2>&1
}

push_images() {
    local entry_id="$1"
    local source_image="${ENTRY_IMAGE[${entry_id}]}"
    local target_image

    target_image="$(tag_image_for_registry "${source_image}")"
    log_info "${entry_id}: Tagging image ${source_image} as ${target_image}"
    "${CONTAINER_RUNTIME}" tag "${source_image}" "${target_image}" >> "${LOG_FILE}" 2>&1
    log_info "${entry_id}: Pushing ${target_image}"
    "${CONTAINER_PUSH_CMD}" push "${target_image}" >> "${LOG_FILE}" 2>&1
}

publish_service() {
    local entry_id="$1"
    local service_dir="${ENTRY_SERVICE_DIR[${entry_id}]}"
    local definition_file="${service_dir}/horizon/service.definition.json"

    log_info "${entry_id}: Publishing service definition to exchange"
    (
        export HZN_ORG_ID="${HZN_ORG_ID_VALUE}"
        export HZN_EXCHANGE_USER_AUTH="${HZN_EXCHANGE_USER_AUTH_VALUE}"
        cd "${service_dir}"
        if [ -f "Makefile" ]; then
            make publish >> "${LOG_FILE}" 2>&1 || hzn exchange service publish -f "${definition_file}" >> "${LOG_FILE}" 2>&1
        else
            hzn exchange service publish -f "${definition_file}" >> "${LOG_FILE}" 2>&1
        fi
        hzn exchange service list | grep -F "${ENTRY_SERVICE_KEY[${entry_id}]%%:*}" >> "${LOG_FILE}" 2>&1
    )
}

record_summary() {
    local entry_id="$1"
    local status="$2"
    local message="$3"
    local line
    line="$(timestamp) | ${entry_id} | ${status} | ${message}"
    SUMMARY_LINES+=("${line}")
    echo "${line}" >> "${SUMMARY_FILE}"
    ENTRY_STATUS["${entry_id}"]="${status}"
    ENTRY_MESSAGE["${entry_id}"]="${message}"
}

prepare_entries() {
    local entry_id

    for entry_id in "${ENTRY_IDS[@]}"; do
        clone_repo "${entry_id}"
        find_service_dir "${entry_id}"
        discover_service_metadata "${entry_id}"
    done

    resolve_dependencies
    topological_sort
}

run_pipeline() {
    local entry_id
    local failures=0

    for entry_id in "${BUILD_ORDER[@]}"; do
        log_info "=== Processing ${entry_id} (${ENTRY_REPO[${entry_id}]}) ==="

        if build_service "${entry_id}" && push_images "${entry_id}" && publish_service "${entry_id}"; then
            record_summary "${entry_id}" "success" "Built, pushed, and published ${ENTRY_SERVICE_KEY[${entry_id}]}"
            log_info "${entry_id}: Success"
        else
            failures=$((failures + 1))
            record_summary "${entry_id}" "failed" "Pipeline failed for ${ENTRY_SERVICE_KEY[${entry_id}]}"
            log_error "${entry_id}: Failed"

            if [ "${FAIL_FAST}" = "1" ]; then
                fail "Stopping after first failure because FAIL_FAST=1"
            fi
        fi
    done

    log "=========================================="
    log "Blessed Samples Summary"
    log "=========================================="
    printf '%s\n' "${SUMMARY_LINES[@]}" | tee -a "${LOG_FILE}"

    [ "${failures}" -eq 0 ] || exit 1
}

main() {
    init_log
    check_config_file
    parse_config
    detect_container_runtime
    load_credentials
    prepare_entries
    run_pipeline
}

main "$@"
