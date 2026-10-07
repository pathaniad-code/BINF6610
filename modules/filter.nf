// Stage 7 · analyze — hard-filter the cohort VCF, then write it out as a table.
// A filter, not a subset: records that fail get FILTER != PASS and stay in the
// file. variants.tsv has one line per record of cohort.filtered.vcf.gz.
process FILTER {
    container params.containers.gatk

    input:
    tuple path(vcf), path(tbi)
    path ref
    path ref_index
    path ref_dict

    output:
    path 'cohort.filtered.vcf.gz', emit: vcf
    path 'variants.tsv',           emit: table

    script:
    """
    gatk VariantFiltration \\
        --reference ${ref} \\
        --variant ${vcf} \\
        --output cohort.filtered.vcf.gz \\
        --filter-name "QD2"  --filter-expression "QD < 2.0" \\
        --filter-name "FS60" --filter-expression "FS > 60.0" \\
        --filter-name "MQ40" --filter-expression "MQ < 40.0" \\
        --filter-name "SOR3" --filter-expression "SOR > 3.0" \\
        --tmp-dir . \\
        --verbosity WARNING

    vcf_to_tsv.sh cohort.filtered.vcf.gz > variants.tsv
    """
}
