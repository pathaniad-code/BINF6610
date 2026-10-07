// Stage 8 · qc_report — one MultiQC report across the cohort: FastQC (stage 1),
// fastp (stage 2) and the duplicate metrics (stage 4), all linked into this
// task's folder by main.nf's mix and collect, where `multiqc .` finds them.
process MULTIQC {
    container params.containers.multiqc

    input:
    path reports        // never named in the script: declared so the reports are linked in

    output:
    path 'cohort_multiqc.html'

    script:
    """
    multiqc --force --filename cohort_multiqc .
    """
}
