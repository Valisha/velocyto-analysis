#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"
mkdir -p logs

"${SCRIPT_DIR}/00_validate_inputs.sh"
map_job=$(sbatch --parsable "${SCRIPT_DIR}/01_salmon_alevin_map.sbatch")
quant_job=$(sbatch --parsable --dependency="afterok:${map_job}" "${SCRIPT_DIR}/02_alevin_fry_quant.sbatch")
scvelo_job=$(sbatch --parsable --dependency="afterok:${quant_job}" "${SCRIPT_DIR}/03_scvelo.sbatch")
printf 'Salmon mapping job: %s\nalevin-fry quant job: %s\nscVelo job: %s\n' "${map_job}" "${quant_job}" "${scvelo_job}"
