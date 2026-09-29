# The variant-call image

## Base image
mambaorg/micromamba:2.0.5-ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.49.0

## The pushed image
docker.io/dpathania/variant-call@sha256:5096d67834faa9e00e538bca948a5893bbea8bf56463e922fc5de05f7f90e678

To rerun this in a year, the one thing that cannot be recreated is the exact software, and only *The pushed image* gives it back: pulling that digest returns this image byte for byte, whereas the tag `1.0.0` can be re-pointed and the `.sif` on /scratch is deleted every month. *Versions pinned* and the Dockerfile record what was intended, but a rebuild next year would resolve every dependency that is not pinned against that day's channels, and *Base image* records the digest because the tag itself can move. The rest comes from this repository and the course data: the pipeline code at the submitted commit, the same samplesheet and reference under /courses, and the same `--cpus-per-task` (4), because bwa mem's batches depend on the thread count.
