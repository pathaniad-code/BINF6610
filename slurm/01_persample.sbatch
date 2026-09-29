#!/bin/bash
#SBATCH --job-name=w2-persample
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --array=1-8
#SBATCH --cpus-per-task=4
#SBATCH --mem=20G
#SBATCH --time=00:30:00
#SBATCH --export=NONE
#SBATCH --output=logs/persample_%A_%a.out
# Stages 0-5 for ONE sample, as one task of an array. This file decides WHICH
# sample runs and with what resources; the pipeline decides what to do to it.
set -eo pipefail          # no -u: kept from week 2; the job sources slurm.env with optional vars

# $SLURM_SUBMIT_DIR, not $(dirname "$0"): sbatch runs a COPY of this script from
# /var/spool/slurmd, so $0 is not in slurm/ and conf/ is not beside it.
if [[ ! -s "${SLURM_SUBMIT_DIR}/conf/slurm.env" ]]; then
  echo "no conf/slurm.env in ${SLURM_SUBMIT_DIR} - submit from slurm/ (bash submit.sh)" >&2; exit 78
fi
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"


export THREADS="${SLURM_CPUS_PER_TASK}"      # from Slurm, never typed as a number
export TMPDIR="/tmp/${SLURM_JOB_ID}"         # the node's own disk
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT               # runs on success, failure, scancel and TIMEOUT

# Task N runs samplesheet row N below the header.
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")
[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no row ${SLURM_ARRAY_TASK_ID} in ${SAMPLESHEET}" >&2; exit 64; }

# TROUBLESHOOTING #2 only: `touch slurm/BREAK_TASK_3` makes task 3 fail on purpose.
if [[ -e "${SLURM_SUBMIT_DIR}/BREAK_TASK_${SLURM_ARRAY_TASK_ID}" ]]; then
  echo "task ${SLURM_ARRAY_TASK_ID}: deliberate failure for TROUBLESHOOTING.md" >&2; exit 1
fi

echo "job=${SLURM_JOB_ID} task=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} host=$(hostname) sample=${SAMPLE} threads=${THREADS}"
df -h /tmp | tail -n 1

SIF=/scratch/${USER}/containers/variant-call-1.0.0.sif
apptainer exec --cleanenv \
    --bind "${PIPELINE_DIR}",/scratch/${USER},/courses/BINF6610.202710 \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    "${SIF}" bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"

# the exact memory high-water mark, for RESOURCES.md
CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak bytes: $(cat "$CG/memory.peak" 2>/dev/null || echo n/a)"
