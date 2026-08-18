#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_path "FASTQ directory" "${FASTQ_DIR}"
require_path "Salmon splici index" "${SALMON_INDEX}"
require_path "three-column transcript-to-gene map" "${T2G_3COL}"
command -v "${SALMON_CMD}" >/dev/null || { echo "Cannot find ${SALMON_CMD}" >&2; exit 2; }
command -v "${ALEVIN_FRY_CMD}" >/dev/null || { echo "Cannot find ${ALEVIN_FRY_CMD}" >&2; exit 2; }

salmon_version=$("${SALMON_CMD}" --version 2>&1)
af_version=$("${ALEVIN_FRY_CMD}" --version 2>&1)
[[ "${salmon_version}" == *"1.10.3"* ]] || echo "WARNING: previous run used Salmon 1.10.3; found ${salmon_version}" >&2
[[ "${af_version}" == *"0.11.2"* ]] || echo "WARNING: previous run used alevin-fry 0.11.2; found ${af_version}" >&2

failed=0
for sample in "${SAMPLES[@]}"; do
    for read in R1 R2; do
        count=$(find "${FASTQ_DIR}" -maxdepth 1 -type f -name "${sample}_S*_L00?_${read}_001.fastq.gz" | wc -l | tr -d ' ')
        if [[ "${count}" -ne 4 ]]; then
            echo "ERROR: expected four ${read} lane FASTQs for ${sample}; found ${count}" >&2
            failed=1
        else
            printf '%-4s %-2s %s lane file(s)\n' "${sample}" "${read}" "${count}"
        fi
    done
done

(( failed == 0 )) || exit 1
echo "Input validation passed for ${#SAMPLES[@]} samples."
