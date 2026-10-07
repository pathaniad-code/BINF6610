// Stage 2 · trim — adapters and low-quality tails, with fastp.
// meta.single_end chooses the command, as library_type did in week 1.
// Two outputs: the trimmed reads go on to BWA_MEM, the JSON report to MULTIQC.
process FASTP {
    tag "${meta.id}"
    container params.containers.fastp

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path('*.trim.fastq.gz'), emit: reads
    path "${meta.id}.fastp.json",             emit: json

    script:
    if (meta.single_end)
        """
        fastp \\
            --in1 ${reads} \\
            --out1 ${meta.id}_R1.trim.fastq.gz \\
            --json ${meta.id}.fastp.json \\
            --html ${meta.id}.fastp.html \\
            --thread ${task.cpus}
        """
    else
        """
        fastp \\
            --in1 ${reads[0]} --in2 ${reads[1]} \\
            --out1 ${meta.id}_R1.trim.fastq.gz \\
            --out2 ${meta.id}_R2.trim.fastq.gz \\
            --json ${meta.id}.fastp.json \\
            --html ${meta.id}.fastp.html \\
            --thread ${task.cpus}
        """
}
