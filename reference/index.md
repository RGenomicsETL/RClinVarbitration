# Package index

## Connection, download, and import

- [`rclinvarbitration_download_clinvar()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_download_clinvar.md)
  : Download official ClinVar source files
- [`rclinvarbitration_extension_path()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_extension_path.md)
  : Locate a version-matched RClinVarbitration DuckDB extension
- [`rclinvarbitration_enable()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_enable.md)
  : Enable native ClinVar and PubMed XML scanning on a DuckDB connection
- [`rclinvarbitration_init()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_init.md)
  : Initialize the ClinVar relational schema
- [`rclinvarbitration_import_flat()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_import_flat.md)
  : Import the official ClinVar flat reports as one tidy table
- [`rclinvarbitration_import_xml()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_import_xml.md)
  : Stream a ClinVar VCV XML release into one relational DuckDB table
- [`rclinvarbitration_import_pubmed()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_import_pubmed.md)
  : Import a PubMed baseline or update XML source

## Parquet outputs

- [`rclinvarbitration_export_clinvarbitration_parquet()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_export_clinvarbitration_parquet.md)
  : Export ClinVarbitration decisions to Parquet
- [`rclinvarbitration_reproduce_clinvarbitration_parquet()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_reproduce_clinvarbitration_parquet.md)
  : Reproduce ClinVarbitration decisions from archived ClinVar flat
  files
- [`rclinvarbitration_publish_ducklake()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_publish_ducklake.md)
  : Publish a tidy ClinVar evidence export to DuckLake

## Schema and policy

- [`rclinvarbitration_schema_sql()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_schema_sql.md)
  : ClinVar relational schema SQL
- [`rclinvarbitration_policy_version()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_policy_version.md)
  : Current ClinVarbitration policy version
- [`rclinvarbitration_policy_sql()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_policy_sql.md)
  : ClinVarbitration policy SQL
- [`rclinvarbitration_disease_release_transitions()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_disease_release_transitions.md)
  : Compare fixed-policy disease decisions between two ClinVar releases
