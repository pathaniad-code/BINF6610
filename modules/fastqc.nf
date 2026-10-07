// Stage 1 · qc_raw — FastQC on the reads as they arrived.
// ${reads} is every FASTQ of the sample: two for paired, one for single-end.
// The zips go only to MULTIQC, through collect(), so they are a plain path.
process FASTQC {
    tag "${meta.id}"
    container params.containers.fastqc

    input:
    tuple val(meta), path(reads)

    output:
    path '*_fastqc.zip', emit: zip

    script:
    """
    fastqc --quiet --threads ${task.cpus} ${reads}
    """
}
