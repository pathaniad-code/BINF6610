#!/bin/bash
#SBATCH --job-name=w2-cohort
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --export=NONE
#SBATCH --output=logs/cohort_%j.out
# Stages 6-9 (merge, analyze, qc_report, publish), once, after every array task
# has succeeded — submit.sh holds it back with afterok.
set -eo pipefail

if [[ ! -s "${SLURM_SUBMIT_DIR}/conf/slurm.env" ]]; then
  echo "no conf/slurm.env in ${SLURM_SUBMIT_DIR} - submit from slurm/ (bash submit.sh)" >&2; exit 78
fi
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

module load miniconda3/25.9.1
source activate "${CONDA_ENV}"

export THREADS="${SLURM_CPUS_PER_TASK}"
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "job=${SLURM_JOB_ID} host=$(hostname) threads=${THREADS}"
df -h /tmp | tail -n 1

bash "${PIPELINE_DIR}/run_pipeline.sh" --samplesheet "${SAMPLESHEET}" --outdir "${RUN_ROOT}" --from merge

CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak bytes: $(cat "$CG/memory.peak" 2>/dev/null || echo n/a)"
