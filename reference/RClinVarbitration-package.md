# RClinVarbitration: relational ClinVar evidence in DuckDB

A DuckDB-native tidy ClinVar store. Flat reports and optional VCV XML
both feed one scalar `clinvar` table. The default flat path creates
variation, allele, GRCh37/GRCh38 location, decision, SCV, RCV, and gene
rows. The package-owned native extension adds XML-only observations,
conditions, citations, attributes, and attributable text to the same
contract.

## See also

Useful links:

- <https://github.com/RGenomicsETL/RClinVarbitration>

- <https://rgenomicsetl.github.io/RClinVarbitration/>

- Report bugs at
  <https://github.com/RGenomicsETL/RClinVarbitration/issues>

## Author

**Maintainer**: Sounkou Mahamane Toure <sounkoutoure@gmail.com>

Authors:

- Sounkou Mahamane Toure <sounkoutoure@gmail.com>

Other contributors:

- DuckDB Foundation (Bundled DuckDB C extension headers) \[copyright
  holder\]

- Centre for Population Genomics (ClinVarbitration 2.2.11
  decision-policy semantics) \[copyright holder\]
