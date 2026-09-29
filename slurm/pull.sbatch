#!/bin/bash
#SBATCH -A binf6610.202710
#SBATCH -p courses
#SBATCH -c 8 --mem=16G -t 01:00:00
#SBATCH -J variant-call-pull
#SBATCH -o pull-%j.out
#
# Fetch the pushed image by digest on a compute node, then record the versions
# inside it. The login node kills long apptainer conversions partway.
set -euo pipefail

# Keep the download cache and build temp out of the quota'd $HOME.
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
export APPTAINER_TMPDIR=/tmp/${USER}-apptainer-${SLURM_JOB_ID}
trap 'rm -rf "${APPTAINER_TMPDIR}"' EXIT
mkdir -p "${APPTAINER_CACHEDIR}" "${APPTAINER_TMPDIR}" "/scratch/${USER}/containers"

SIF=/scratch/${USER}/containers/variant-call-1.0.0.sif
apptainer pull --force "${SIF}" \
    docker://docker.io/dpathania/variant-call@sha256:5096d67834faa9e00e538bca948a5893bbea8bf56463e922fc5de05f7f90e678

cd "${SLURM_SUBMIT_DIR}"
mkdir -p cluster-run-container
apptainer exec --cleanenv "${SIF}" bash tests/print_versions.sh \
    | tee cluster-run-container/versions-image.txt
