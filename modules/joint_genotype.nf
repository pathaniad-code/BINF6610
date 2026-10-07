// Stage 6 · merge — joint genotyping across the whole cohort: every sample's GVCF
// into one GenomicsDB workspace, then GenotypeGVCFs makes one multi-sample VCF.
// It runs once, on every GVCF and its index at once (two collect()s in main.nf).
//
// As in week 3: every sample in the sheet must have its GVCF, and they go in in
// the sheet's order. Genotyping whichever ones arrived would give a plausible
// cohort VCF of the wrong cohort.
//
// The workspace lives on the node's own disk, as in week 3: under /scratch the
// two steps took 36-96 min on Explorer, in /tmp about 8. The trap removes it.
process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path samplesheet
    path gvcfs
    path tbis
    path ref
    path ref_index
    path ref_dict

    output:
    tuple path('cohort.vcf.gz'), path('cohort.vcf.gz.tbi'), emit: vcf

    script:
    """
    ids=\$(sample_ids.sh ${samplesheet})

    args=()
    missing=0
    for id in \${ids}; do
        if [[ -s "\${id}.g.vcf.gz" ]]; then
            args+=(-V "\${id}.g.vcf.gz")
        else
            echo "missing GVCF for \${id}" >&2
            missing=\$(( missing + 1 ))
        fi
    done
    if [[ "\${missing}" -gt 0 ]]; then
        echo "\${missing} sample(s) have no GVCF - refusing to genotype a partial cohort" >&2
        exit 1
    fi

    tmp=\$(mktemp -d "\${TMPDIR:-/tmp}/genomicsdb.XXXXXX")
    trap 'rm -rf "\$tmp"' EXIT

    gatk GenomicsDBImport \\
        "\${args[@]}" \\
        --genomicsdb-workspace-path "\$tmp/db" \\
        -L ${params.region} \\
        --tmp-dir "\$tmp" \\
        --verbosity WARNING

    gatk GenotypeGVCFs \\
        --reference ${ref} \\
        --variant "gendb://\$tmp/db" \\
        --output cohort.vcf.gz \\
        -L ${params.region} \\
        --tmp-dir "\$tmp" \\
        --verbosity WARNING
    """
}
