-- q3 · How many variants, and how many PASS, in each run?
SELECT runs.run_id,
       COUNT(variants.run_id) AS n_variants,
       COALESCE(SUM(variants.filter = 'PASS'), 0) AS n_pass
FROM runs
LEFT JOIN variants ON variants.run_id = runs.run_id
GROUP BY runs.run_id;
