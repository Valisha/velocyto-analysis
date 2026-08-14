#!/usr/bin/env bash
#SBATCH --job-name=salmon_map
#SBATCH --array=0-11%3
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=36:00:00
#SBATCH --output=logs/salmon_map_%A_%a.out
#SBATCH --error=logs/salmon_map_%A_%a.err

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

sample="$(sample_for_array_task)"
map_dir="${QUANT_ROOT}/${OUTPUT_PREFIX}_${sample}_map"
require_path "FASTQ directory" "${FASTQ_DIR}"
require_path "Salmon splici index" "${SALMON_INDEX}"
mkdir -p "${QUANT_ROOT}"

mapfile -t reads1 < <(find "${FASTQ_DIR}" -maxdepth 1 -type f -name "${sample}_S*_L00?_R1_001.fastq.gz" | sort)
mapfile -t reads2 < <(find "${FASTQ_DIR}" -maxdepth 1 -type f -name "${sample}_S*_L00?_R2_001.fastq.gz" | sort)
[[ ${#reads1[@]} -eq 4 && ${#reads2[@]} -eq 4 ]] || {
    echo "Expected four R1 and four R2 lane files for ${sample}" >&2
    exit 2
}
[[ ! -e "${map_dir}" ]] || { echo "Refusing to overwrite existing ${map_dir}" >&2; exit 2; }

"${SALMON_CMD}" alevin \
    -i "${SALMON_INDEX}" \
    -l ISR \
    -1 "${reads1[@]}" \
    -2 "${reads2[@]}" \
    --chromium \
    --sketch \
    -p "${LOCAL_CORES}" \
    -o "${map_dir}"

test -s "${map_dir}/map.rad"
