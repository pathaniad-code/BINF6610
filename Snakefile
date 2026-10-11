# variant-call, in Snakemake: the ten stages of weeks 1-4 as rules.
#
# `rule all` names the files the run must end with. For each one Snakemake finds
# the rule whose output pattern matches it, then does the same for that rule's
# inputs, back to the FASTQs. The order of the jobs comes from which file each
# rule needs, not from the order the rules are written in.
#
# Laptop, smoke dataset:
#   snakemake --profile profiles/laptop \
#       --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb
# Explorer, eight samples: sbatch slurm/snakemake.sbatch

import csv
import os
import re

from snakemake.utils import min_version

min_version("9.0")

configfile: "config.yaml"

# A --config key that nothing reads would be ignored without a word, so refuse it.
KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}; known: {', '.join(sorted(KNOWN))}")
for key in ("samplesheet", "ref", "region"):
    if not config.get(key):
        raise ValueError(f"give --config {key}=...")

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")       # bin/ is not on the PATH: call scripts by their path
IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

# The reference and the files beside it, named once here. Every rule that reads
# them lists the ones it needs as inputs, so Snakemake checks they exist.
REF = config["ref"]                                                       # the FASTA
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]  # bwa's index
REF_DICT = os.path.splitext(REF)[0] + ".dict"                             # smoke.dict, not smoke.fa.dict
REGION = config["region"]

# ---------------------------------------------------------------------------
# The samplesheet, read once, in plain Python, before any rule runs.
# Columns are read by name; a FASTQ path is absolute or relative to the
# samplesheet's folder, so the smoke sheet and the Explorer sheet both work.
# ---------------------------------------------------------------------------
SHEET = config["samplesheet"]
with open(SHEET) as fh:
    ROWS = [row for row in csv.DictReader(fh) if row.get("sample_id")]
SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]


def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(os.path.abspath(SHEET)), path)


READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}


def one_of(names):
    """A wildcard pattern matching exactly
    these sample names, or nothing at all."""
    return "|".join(map(re.escape, names)) \
        if names else "(?!)"


def trimmed(wildcards):
    """The trimmed reads of one sample: two files if paired, one if single-end."""
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]



# ---------------------------------------------------------------------------
# What the run asks for. Every other job is worked out backwards from these.
# ---------------------------------------------------------------------------
rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json",


# Every rule below writes what its command prints to stderr into its own log
# under logs/, one per sample where the output has {sample}. A failed job's
# output is deleted and its log is kept: that is where to look.

# Stage 0 · validate — the samplesheet, every FASTQ, the reference and its
# indexes, before anything computes. A rule must make a file to be needed, so
# this one makes a copy of the samplesheet, only if the checks pass. fastqc and
# both fastp rules take that copy as an input, so no sample starts before it.
rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        "work/validate/samplesheet.csv",
    log:
        "logs/validate.log",
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} {input.ref_dict}"
        " && cp {input.sheet} {output}) 2> {log}"


# Stage 1 · qc_raw — FastQC on the reads as they arrived.
# {sample} is a wildcard: which samples this runs for is decided by who asks for
# work/fastqc/<sample> (multiqc, in stage 8). FastQC names its files after the
# FASTQs, so the rule's output is the folder it writes into.
rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        directory("work/fastqc/{sample}"),
    threads: 2
    log:
        "logs/fastqc/{sample}.log",
    container: IMAGES["fastqc"]
    shell:
        "(mkdir -p {output} && fastqc --quiet --threads {threads} -o {output} {input.reads}) 2> {log}"


# Stage 2 · trim — adapters and low-quality tails, with fastp.
# Two rules, because a rule's outputs are fixed: a paired sample makes two
# trimmed files, a single-end sample one. wildcard_constraints say which samples
# each rule may make, so for every sample exactly one rule fits.
rule fastp_paired:
    input:
        r1=lambda wc: READS[wc.sample][0],
        r2=lambda wc: READS[wc.sample][1],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(PAIRED),
    threads: 4
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "fastp --in1 {input.r1} --in2 {input.r2}"
        " --out1 {output.r1} --out2 {output.r2}"
        " --json {output.json} --html {output.html}"
        " --thread {threads} 2> {log}"


rule fastp_single:
    input:
        r1=lambda wc: READS[wc.sample][0],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(SINGLE),
    threads: 4
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "fastp --in1 {input.r1}"
        " --out1 {output.r1}"
        " --json {output.json} --html {output.html}"
        " --thread {threads} 2> {log}"


# Stage 3 · align — BWA-MEM against the reference, piped into a BAM.
# The read group's SM is the sample_id: that is how every column of the GVCF and
# the cohort VCF is matched back to a row of the samplesheet. A raw string, so
# bwa gets the two characters \t, not a tab. bwa mem takes one FASTQ or two at
# the end of its command, so trimmed() needs no paired/single choice here.
# threads: 4, as week 4's Explorer profile gave BWA_MEM: bwa's records depend
# on its thread count, so this keeps step 10's checksums comparable.
rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        ref_index=REF_BWA,
    output:
        "work/align/{sample}.bam",
    params:
        rg=lambda wc: rf"@RG\tID:{wc.sample}\tSM:{wc.sample}\tLB:{wc.sample}\tPL:ILLUMINA",
    threads: 4
    log:
        "logs/bwa_mem/{sample}.log",
    container: IMAGES["bwa"]
    shell:
        "(bwa mem -t {threads} -R '{params.rg}' {input.ref} {input.reads}"
        " | samtools view -b -o {output} -) 2> {log}"


# Stage 4 · postprocess — coordinate-sort, index, and mark duplicates.
# GATK needs the .bai beside the BAM it reads, so the dedup BAM's index is an
# output too. The duplicate metrics go to MultiQC in stage 8.
rule markduplicates:
    input:
        "work/align/{sample}.bam",
    output:
        bam="work/dedup/{sample}.dedup.bam",
        bai="work/dedup/{sample}.dedup.bam.bai",
        metrics="work/dedup/{sample}.dup_metrics.txt",
    params:
        tmp="work/dedup/{sample}.tmp",
    threads: 2
    log:
        "logs/markduplicates/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        """
        (rm -rf {params.tmp} && mkdir -p {params.tmp}
         samtools sort -@ {threads} -T {params.tmp}/sort -o {params.tmp}/sorted.bam {input}
         samtools index {params.tmp}/sorted.bam
         gatk MarkDuplicates \
             --INPUT {params.tmp}/sorted.bam \
             --OUTPUT {output.bam} \
             --METRICS_FILE {output.metrics} \
             --TMP_DIR {params.tmp} \
             --QUIET true \
             --VERBOSITY WARNING
         samtools index {output.bam}
         rm -rf {params.tmp}) 2> {log}
        """


# Stage 5 · quantify — per-sample calling into a GVCF, restricted to the region.
# The region is a value, so it goes in params: a changed region reruns the rule.
rule haplotypecaller:
    input:
        bam="work/dedup/{sample}.dedup.bam",
        bai="work/dedup/{sample}.dedup.bam.bai",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi",
    params:
        region=REGION,
        tmp="work/gvcf/{sample}.tmp",
    threads: 8
    log:
        "logs/haplotypecaller/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        """
        (rm -rf {params.tmp} && mkdir -p {params.tmp}
         gatk HaplotypeCaller \
             --input {input.bam} \
             --output {output.gvcf} \
             --reference {input.ref} \
             -L {params.region} \
             -ERC GVCF \
             --native-pair-hmm-threads {threads} \
             --tmp-dir {params.tmp} \
             --verbosity WARNING
         rm -rf {params.tmp}) 2> {log}
        """


# Stage 6 · merge — joint genotyping across the whole cohort: every sample's GVCF
# into one GenomicsDB workspace, then GenotypeGVCFs makes one multi-sample VCF.
# This is the barrier. expand() writes out one GVCF per row of the samplesheet,
# in the sheet's order, so this job cannot start until every sample has one:
# Snakemake's version of week 4's collect() and its missing-GVCF check.
# The workspace lives on the node's own disk (/tmp), as in weeks 3-4; the trap
# removes it. ${{...}} is bash's ${...}: single braces are Snakemake's.
rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
    params:
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs),
        region=REGION,
    threads: 2
    log:
        "logs/joint_genotype.log",
    container: IMAGES["gatk"]
    shell:
        """
        (tmp=$(mktemp -d "${{TMPDIR:-/tmp}}/genomicsdb.XXXXXX")
         trap 'rm -rf "$tmp"' EXIT

         gatk GenomicsDBImport \
             {params.variants} \
             --genomicsdb-workspace-path "$tmp/db" \
             -L {params.region} \
             --tmp-dir "$tmp" \
             --verbosity WARNING

         gatk GenotypeGVCFs \
             --reference {input.ref} \
             --variant "gendb://$tmp/db" \
             --output {output.vcf} \
             -L {params.region} \
             --tmp-dir "$tmp" \
             --verbosity WARNING) 2> {log}
        """


# Stage 7 · analyze — hard-filter the cohort VCF, then write it out as a table.
# A filter, not a subset: records that fail get FILTER != PASS and stay in the
# file, so variants.tsv has one line per record of cohort.filtered.vcf.gz.
# GATK writes the .tbi beside the VCF itself. bin/vcf_to_tsv.sh prints the header
# line, then one tab-separated line per record.
rule filter:
    input:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv",
    params:
        tmp="work/filter/tmp",
    threads: 2
    log:
        "logs/filter.log",
    container: IMAGES["gatk"]
    shell:
        """
        (rm -rf {params.tmp} && mkdir -p {params.tmp}
         gatk VariantFiltration \
             --reference {input.ref} \
             --variant {input.vcf} \
             --output {output.vcf} \
             --filter-name "QD2"  --filter-expression "QD < 2.0" \
             --filter-name "FS60" --filter-expression "FS > 60.0" \
             --filter-name "MQ40" --filter-expression "MQ < 40.0" \
             --filter-name "SOR3" --filter-expression "SOR > 3.0" \
             --tmp-dir {params.tmp} \
             --verbosity WARNING
         {BIN}/vcf_to_tsv.sh {output.vcf} > {output.table}
         rm -rf {params.tmp}) 2> {log}
        """


# Stage 8 · qc_report — one MultiQC report across the cohort, from the QC files
# of stages 1, 2 and 4. They are given by name: MultiQC run on . would read the
# whole repository. -f lets it replace an earlier report instead of writing
# multiqc_report_1.html, which is not the file this rule promised.
rule multiqc:
    input:
        expand("work/fastqc/{sample}", sample=SAMPLES),
        expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        expand("work/dedup/{sample}.dup_metrics.txt", sample=SAMPLES),
    output:
        f"{OUT}/multiqc_report.html",
    log:
        "logs/multiqc.log",
    container: IMAGES["multiqc"]
    shell:
        "(multiqc -q -f -o work/multiqc {input}"
        " && cp work/multiqc/multiqc_report.html {output}) 2> {log}"


# Stage 9 · publish — the course's rules/publish.smk, unchanged. It writes
# samples.tsv and manifest.json from what it is given here: stage 0's copy of
# the samplesheet, and the files the manifest describes.
PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]
include: "rules/publish.smk"
