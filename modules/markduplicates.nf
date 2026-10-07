// Stage 4 · postprocess — coordinate-sort, index, and mark duplicates.
// GATK needs the .bai beside the BAM it reads, so the dedup BAM travels with it.
// The duplicate metrics go only to MULTIQC, through collect(): a plain path.
process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.dedup.bam"), path("${meta.id}.dedup.bam.bai"), emit: bam
    path "${meta.id}.dup_metrics.txt",                                             emit: metrics

    script:
    """
    samtools sort -@ ${task.cpus} -T sort_${meta.id} -o ${meta.id}.sorted.bam ${bam}
    samtools index ${meta.id}.sorted.bam

    gatk MarkDuplicates \\
        --INPUT ${meta.id}.sorted.bam \\
        --OUTPUT ${meta.id}.dedup.bam \\
        --METRICS_FILE ${meta.id}.dup_metrics.txt \\
        --TMP_DIR . \\
        --QUIET true \\
        --VERBOSITY WARNING

    samtools index ${meta.id}.dedup.bam
    """
}
