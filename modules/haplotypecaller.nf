// Stage 5 · quantify — per-sample calling into a GVCF, restricted to the region.
// The GVCF and its index go only to JOINT_GENOTYPE, through collect(), so both
// are plain paths: a collect() of [meta, file] items would hand it the maps too.
process HAPLOTYPECALLER {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam), path(bai)
    path ref
    path ref_index
    path ref_dict

    output:
    path "${meta.id}.g.vcf.gz",     emit: gvcf
    path "${meta.id}.g.vcf.gz.tbi", emit: tbi

    script:
    """
    gatk HaplotypeCaller \\
        --input ${bam} \\
        --output ${meta.id}.g.vcf.gz \\
        --reference ${ref} \\
        -L ${params.region} \\
        -ERC GVCF \\
        --native-pair-hmm-threads ${task.cpus} \\
        --tmp-dir . \\
        --verbosity WARNING
    """
}
