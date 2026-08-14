#!/usr/bin/env bash
#SBATCH --job-name=scvelo
#SBATCH --cpus-per-task=8
#SBATCH --mem=96G
#SBATCH --time=48:00:00
#SBATCH --output=logs/scvelo_%j.out
#SBATCH --error=logs/scvelo_%j.err

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

mkdir -p "${ANALYSIS_ROOT}"
args=("${SCRIPT_DIR}/03_run_scvelo.py" \
    --quant-root "${QUANT_ROOT}" \
    --output-prefix "${OUTPUT_PREFIX}" \
    --samples "${SAMPLES_FILE}" \
    --output "${ANALYSIS_ROOT}" \
    --color "${PLOT_COLOR}" \
    --root-key "${ROOT_KEY}")
[[ -z "${ANNOTATION_H5AD}" ]] || args+=(--annotation "${ANNOTATION_H5AD}")
[[ -z "${ROOT_CLUSTER}" ]] || args+=(--root-cluster "${ROOT_CLUSTER}")
[[ -z "${ROOT_CELL}" ]] || args+=(--root-cell "${ROOT_CELL}")
"${PYTHON_CMD}" "${args[@]}"
