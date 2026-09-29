# The variant-call image

**Base image:** `mambaorg/micromamba:2.0.5-ubuntu24.04`

**Recipe:** `containers/Dockerfile` (conda-forge + bioconda, every tool pinned)

| Tool | Version in the image | Course env |
|---|---|---|
| bwa | 0.7.19 (reports 0.7.19-r1273) | 0.7.19 |
| samtools | 1.24 | 1.24 |
| bcftools | 1.24 | 1.24 |
| gatk4 | 4.6.2.0 | 4.6.2.0 |
| fastqc | 0.12.1 | 0.12.1 |
| fastp | 1.3.7 | 1.3.7 |
| multiqc | 1.35 | 1.35 |
| git | 2.49.0 | (not in env; stage 9 runs `git rev-parse`) |

**Pushed image:** `docker.io/dpathania/variant-call@sha256:5096d67834faa9e00e538bca948a5893bbea8bf56463e922fc5de05f7f90e678`

Tag `dpathania/variant-call:1.0.0`, built on a laptop with `docker build --platform linux/amd64`.

**Getting it back:** `slurm/pull.sbatch` pulls by digest, not by tag, so a re-pushed tag cannot change what runs:

    apptainer pull variant-call-1.0.0.sif \
        docker://docker.io/dpathania/variant-call@sha256:5096d67834faa9e00e538bca948a5893bbea8bf56463e922fc5de05f7f90e678
