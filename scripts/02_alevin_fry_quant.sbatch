#!/usr/bin/env bash
#SBATCH --job-name=af_quant
#SBATCH --array=0-11%4
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/af_quant_%A_%a.out
#SBATCH --error=logs/af_quant_%A_%a.err

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

sample="$(sample_for_array_task)"
map_dir="${QUANT_ROOT}/${OUTPUT_PREFIX}_${sample}_map"
quant_dir="${QUANT_ROOT}/${OUTPUT_PREFIX}_${sample}_quant"
result_dir="${QUANT_ROOT}/${OUTPUT_PREFIX}_${sample}_quant_res"
require_path "RAD mapping output" "${map_dir}/map.rad"
require_path "three-column transcript-to-gene map" "${T2G_3COL}"
[[ ! -e "${quant_dir}" && ! -e "${result_dir}" ]] || {
    echo "Refusing to overwrite an existing quantification for ${sample}" >&2
    exit 2
}

# Match the Irene Exp2 workflow: forward orientation, knee permit list,
# collation, then CellRanger-like USA quantification.
"${ALEVIN_FRY_CMD}" generate-permit-list \
    -d fw -k -t "${LOCAL_CORES}" \
    -i "${map_dir}" -o "${quant_dir}"
"${ALEVIN_FRY_CMD}" collate \
    -t "${LOCAL_CORES}" -i "${quant_dir}" -r "${map_dir}"
"${ALEVIN_FRY_CMD}" quant \
    -t "${LOCAL_CORES}" \
    -i "${quant_dir}" \
    -o "${result_dir}" \
    --tg-map "${T2G_3COL}" \
    --resolution cr-like \
    --use-mtx

test -s "${result_dir}/alevin/quants_mat.mtx"
grep -q '"usa_mode": true' "${result_dir}/quant.json"
