-- q2 · Which runs included NA12878, and as what?
SELECT run_samples.run_id,
       run_samples.condition
FROM run_samples
WHERE run_samples.sample_id = 'NA12878';
