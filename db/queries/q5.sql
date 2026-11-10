-- q5 · Where is each run's VCF, and its checksum?
SELECT runs.run_id,
       runs.folder || '/cohort.filtered.vcf.gz' AS file,
       outputs.sha256
FROM runs
LEFT JOIN outputs ON outputs.run_id = runs.run_id
                 AND outputs.path = 'cohort.filtered.vcf.gz';
