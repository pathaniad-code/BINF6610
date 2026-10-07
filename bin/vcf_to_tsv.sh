#!/usr/bin/env bash
# vcf_to_tsv.sh <cohort.filtered.vcf.gz>  > variants.tsv
# Stage 7's table: a header line, then one tab-separated line per VCF record.
# Kept here rather than in the FILTER script block, where every \ would be \\.
set -euo pipefail
VCF=${1:?usage: vcf_to_tsv.sh <vcf.gz>}
printf 'chrom\tpos\tref\talt\tqual\tfilter\n'
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' "$VCF"
