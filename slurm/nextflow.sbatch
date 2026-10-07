#!/bin/bash
#SBATCH --job-name=nf-head
#SBATCH --account=binf6610.202710
#SBATCH --partition=courses
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=nf-head-%j.out
#SBATCH --export=NONE
# The head job: Nextflow itself runs here, and submits every task as a Slurm job
# of its own. Submit from the repository: sbatch slurm/nextflow.sbatch
set -euo pipefail

module load miniconda3/25.9.1
source activate /courses/BINF6610.202710/shared/env/binf6610

export NXF_APPTAINER_CACHEDIR=/scratch/${USER}/nxf-apptainer
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache

cd "${SLURM_SUBMIT_DIR}"
nextflow run main.nf -profile explorer -resume -ansi-log false \
    --samplesheet /courses/BINF6610.202710/data/samplesheet-variant8.csv \
    --ref /courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa \
    --region chr20:1-10000000 \
    --outdir results
