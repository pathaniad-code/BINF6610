// main.nf — the week 1-3 variant-call pipeline, its ten stages as Nextflow processes.
//
// Laptop, smoke dataset:
//   nextflow run main.nf -profile docker \
//       --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb
// Explorer, eight samples: sbatch slurm/nextflow.sbatch
//
// What used to be code around the stages -- the loop over the samplesheet, the
// skip-if-done tests, the job array and afterok, `apptainer exec` -- is now
// Nextflow's job: channels, the work/ cache with -resume, the executor, and the
// container directive.

include { VALIDATE        } from './modules/validate.nf'
include { FASTQC          } from './modules/fastqc.nf'
include { FASTP           } from './modules/fastp.nf'
include { BWA_MEM         } from './modules/bwa_mem.nf'
include { MARKDUPLICATES  } from './modules/markduplicates.nf'
include { HAPLOTYPECALLER } from './modules/haplotypecaller.nf'
include { JOINT_GENOTYPE  } from './modules/joint_genotype.nf'
include { FILTER          } from './modules/filter.nf'
include { MULTIQC         } from './modules/multiqc.nf'
include { PUBLISH         } from './modules/publish.nf'

workflow {
    main:
    // The reference, its index and its dictionary are VALUE channels: file() and
    // files(), never channel.fromPath. Every sample reads them, as often as it needs.
    ref       = file(params.ref)                                // the FASTA
    ref_index = files("${params.ref}.*")                        // its .fai and the BWA index
    ref_dict  = file("${ref.parent}/${ref.baseName}.dict")      // GATK's sequence dictionary

    // Stage -: one item per sample, [meta, reads], each column read by name.
    sheet = file(params.samplesheet)
    ch_samples = channel.fromPath(sheet)
        .splitCsv(header: true)
        .map { row ->
            def meta  = [id: row.sample_id, single_end: row.library_type == 'single']
            def r1    = sheet.parent.resolve(row.r1_fastq)
            def reads = meta.single_end ? [r1] : [r1, sheet.parent.resolve(row.r2_fastq)]
            [meta, reads]
        }

    // Stage 0 · validate: once, given every FASTQ so each is linked into its folder.
    VALIDATE(sheet, ch_samples.map { _meta, reads -> reads }.collect(),
             ref, ref_index, ref_dict)

    // No sample reaches stage 1 or 2 until VALIDATE has succeeded.
    ch_checked = ch_samples
        .combine(VALIDATE.out.sheet)
        .map { meta, reads, _validated -> [meta, reads] }

    // Stages 1-5, once per sample.
    FASTQC(ch_checked)
    FASTP(ch_checked)
    BWA_MEM(FASTP.out.reads, ref, ref_index)
    MARKDUPLICATES(BWA_MEM.out)
    HAPLOTYPECALLER(MARKDUPLICATES.out.bam, ref, ref_index, ref_dict)

    // Stage 6 · merge: once, on every sample's GVCF and its index at once.
    JOINT_GENOTYPE(VALIDATE.out.sheet,
                   HAPLOTYPECALLER.out.gvcf.collect(),
                   HAPLOTYPECALLER.out.tbi.collect(),
                   ref, ref_index, ref_dict)

    // Stage 7 · analyze: hard filter, and variants.tsv.
    FILTER(JOINT_GENOTYPE.out.vcf, ref, ref_index, ref_dict)

    // Stage 8 · qc_report: one MultiQC over the QC files of stages 1, 2 and 4.
    MULTIQC(FASTQC.out.zip
                .mix(FASTP.out.json, MARKDUPLICATES.out.metrics)
                .collect())

    // Stage 9 · publish: samples.tsv and manifest.json (course file, unchanged).
    PUBLISH(VALIDATE.out.sheet, FILTER.out.vcf.mix(FILTER.out.table, MULTIQC.out).collect())

    publish:
    vcf      = FILTER.out.vcf
    variants = FILTER.out.table
    multiqc  = MULTIQC.out
    manifest = PUBLISH.out.manifest
    samples  = PUBLISH.out.samples
}

output {
    vcf {
        path '.'
    }
    variants {
        path '.'
    }
    multiqc {
        path '.'
    }
    manifest {
        path '.'
    }
    samples {
        path '.'
    }
}
