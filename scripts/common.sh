#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${REPO_DIR}/config/config.env}"
SAMPLES_FILE="${SAMPLES_FILE:-${REPO_DIR}/config/samples.tsv}"

[[ -r "${CONFIG_FILE}" ]] || { echo "Cannot read ${CONFIG_FILE}" >&2; exit 2; }
[[ -r "${SAMPLES_FILE}" ]] || { echo "Cannot read ${SAMPLES_FILE}" >&2; exit 2; }
# shellcheck source=../config/config.env
source "${CONFIG_FILE}"

mapfile -t SAMPLES < <(awk -F '\t' 'NR > 1 && $1 != "" {print $1}' "${SAMPLES_FILE}")
[[ ${#SAMPLES[@]} -gt 0 ]] || { echo "No samples in ${SAMPLES_FILE}" >&2; exit 2; }

sample_for_array_task() {
    local task_id="${SLURM_ARRAY_TASK_ID:?Run as a SLURM array task}"
    (( task_id >= 0 && task_id < ${#SAMPLES[@]} )) || {
        echo "Array index ${task_id} is outside 0..$((${#SAMPLES[@]} - 1))" >&2
        exit 2
    }
    printf '%s\n' "${SAMPLES[$task_id]}"
}

require_path() {
    local label="$1" path="$2"
    [[ -e "${path}" ]] || { echo "Missing ${label}: ${path}" >&2; exit 2; }
}

