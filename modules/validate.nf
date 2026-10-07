// Stage 0 · validate — check every input before anything is computed.
// A task runs in a folder of its own, so it is given every FASTQ of every sample
// (main.nf collects them) and Nextflow links each one in under its file name;
// bin/validate_samplesheet.sh opens them by that name. Its output is the
// samplesheet itself, and main.nf makes every sample wait for it (combine).
process VALIDATE {
    container params.containers.tools

    input:
    path samplesheet
    path fastqs         // never named in the script: declared so the FASTQs are linked in
    path ref
    path ref_index      // the .fai and the BWA index, beside the FASTA
    path ref_dict

    output:
    path samplesheet, emit: sheet

    script:
    """
    validate_samplesheet.sh ${samplesheet} ${ref} ${ref_dict}
    """
}
