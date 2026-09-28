#!/usr/bin/env bash
# slurm/submit.sh — two sbatch calls and one dependency. Run it FROM slurm/:
#   cd slurm && bash submit.sh
#   ARRAY=1-9 bash submit.sh        (TROUBLESHOOTING #3)
#   RUN_TAG=test bash submit.sh     (a separate run folder: /scratch/$USER/w2-run-test)
set -euo pipefail
[[ -f conf/slurm.env && -f 01_persample.sbatch ]] || { echo "run from slurm/: cd slurm && bash submit.sh" >&2; exit 1; }

source conf/slurm.env
mkdir -p logs                     # Slurm will not create the log folder itself

# The array size comes from the samplesheet, not from a number typed twice.
N=$(awk -F',' 'NR > 1 && $1 != "" { n++ } END { print n + 0 }' "${SAMPLESHEET}")
ARRAY=${ARRAY:-1-${N}}
EXPORT=--export=NONE
[[ -n "${RUN_TAG:-}" ]] && EXPORT=--export=RUN_TAG=${RUN_TAG}

ARRAY_ID=$(sbatch --parsable -p "$PARTITION" -A "$ACCOUNT" --array="${ARRAY}" "${EXPORT}" 01_persample.sbatch)
ARRAY_ID=${ARRAY_ID%%;*}

# afterok, not afterany: one failed sample must stop the cohort job, not shrink the cohort.
COHORT_ID=$(sbatch --parsable -p "$PARTITION" -A "$ACCOUNT" \
            --dependency=afterok:${ARRAY_ID} --kill-on-invalid-dep=yes "${EXPORT}" 02_cohort.sbatch)
COHORT_ID=${COHORT_ID%%;*}

echo "samples in sheet : ${N}"
echo "per-sample array : ${ARRAY_ID}  (--array=${ARRAY})"
echo "cohort job       : ${COHORT_ID}  (afterok:${ARRAY_ID})"
echo "watch            : squeue -u ${USER}"
echo "measure          : seff ${ARRAY_ID}_1 ; seff ${COHORT_ID}"
