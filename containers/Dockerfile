# variant-call — the assignment pipeline's tools, pinned to the course environment.
FROM mambaorg/micromamba:2.0.5-ubuntu24.04

# conda-forge and bioconda only; every tool pinned to the course env's version.
# git is here because stage 9 runs `git rev-parse`.
RUN micromamba install -y -n base \
      -c conda-forge -c bioconda --override-channels \
      bwa=0.7.19 \
      samtools=1.24 \
      bcftools=1.24 \
      gatk4=4.6.2.0 \
      fastqc=0.12.1 \
      fastp=1.3.7 \
      multiqc=1.35 \
      git=2.49.0 \
 && micromamba clean --all --yes

ENV PATH=/opt/conda/bin:$PATH
USER mambauser
