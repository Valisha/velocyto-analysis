#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
cd "${REPO_DIR}"
mkdir -p logs

run_array_stage() {
    local stage="$1" script="$2" index sample log_file
    for index in "${!SAMPLES[@]}"; do
        sample="${SAMPLES[$index]}"
        log_file="logs/${stage}_${sample}.log"
        if [[ "${stage}" == "salmon_map" && -s "${QUANT_ROOT}/${OUTPUT_PREFIX}_${sample}_map/map.rad" ]]; then
            echo "SKIP ${stage} ${sample}: complete output exists"
            continue
        fi
        if [[ "${stage}" == "af_quant" \
              && -s "${QUANT_ROOT}/${OUTPUT_PREFIX}_${sample}_quant_res/alevin/quants_mat.mtx" \
              && -s "${QUANT_ROOT}/${OUTPUT_PREFIX}_${sample}_quant_res/quant.json" ]]; then
            echo "SKIP ${stage} ${sample}: complete output exists"
            continue
        fi

        echo "START ${stage} ${sample}; log: ${log_file}"
        if SLURM_ARRAY_TASK_ID="${index}" bash "${script}" >"${log_file}" 2>&1; then
            echo "DONE  ${stage} ${sample}"
        else
            status=$?
            echo "FAILED ${stage} ${sample} (exit ${status}); last log lines:" >&2
            tail -50 "${log_file}" >&2
            exit "${status}"
        fi
    done
}

"${SCRIPT_DIR}/00_validate_inputs.sh"
run_array_stage salmon_map "${SCRIPT_DIR}/01_salmon_alevin_map.sbatch"
run_array_stage af_quant "${SCRIPT_DIR}/02_alevin_fry_quant.sbatch"

echo "START scVelo; log: logs/scvelo_local.log"
if bash "${SCRIPT_DIR}/03_scvelo.sbatch" >logs/scvelo_local.log 2>&1; then
    echo "DONE  scVelo"
else
    status=$?
    echo "FAILED scVelo (exit ${status}); last log lines:" >&2
    tail -50 logs/scvelo_local.log >&2
    exit "${status}"
fi
