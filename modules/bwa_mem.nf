// Stage 3 · align — BWA-MEM against the reference, piped into a BAM.
// The read group's SM is the sample_id: that is how every column of the GVCF and
// the cohort VCF is matched back to a row of the samplesheet.
// bwa mem takes one FASTQ or two at the end of its command, so ${reads} (every
// file of the sample) needs no paired/single choice.
// The reference and its index arrive as value channels: every sample reads them.
process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.bam")

    script:
    def rg = "@RG\\tID:${meta.id}\\tSM:${meta.id}\\tLB:${meta.id}\\tPL:ILLUMINA"
    """
    bwa mem -t ${task.cpus} -R '${rg}' ${ref} ${reads} \\
        | samtools view -b -o ${meta.id}.bam -
    """
}
