# Import the official ClinVar flat reports as one tidy table

Joins `variant_summary` and `submission_summary` directly in DuckDB. The
resulting `clinvar` table has one scalar row per variation, allele,
assembly location, decision, SCV submission, RCV accession, or
allele-gene link, identified by `record_kind`. It is the same canonical
table used by
[`rclinvarbitration_import_xml()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_import_xml.md).
Location rows retain source coordinates even when ClinVar does not
provide a complete VCF tuple (for example some CNVs). `clinvar_vcf`
contains only locations with a usable one-based position and non-missing
REF/ALT.

## Usage

``` r
rclinvarbitration_import_flat(
  con,
  submission_path,
  variant_path,
  release_id,
  parquet_path = NULL,
  assembly = c("GRCh38", "GRCh37"),
  profile_id = "default",
  submitter_exclusions = character()
)
```

## Arguments

- con:

  A DuckDB DBI connection.

- submission_path:

  Official `submission_summary*.txt.gz`.

- variant_path:

  Official `variant_summary*.txt.gz`.

- release_id:

  Immutable source-release label stored with the imported rows and
  returned in the import receipt.

- parquet_path:

  Optional new Parquet path for the same tidy table. The returned import
  receipt can be passed directly to
  [`rclinvarbitration_publish_ducklake()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_publish_ducklake.md).

- assembly:

  One or both of `"GRCh38"` and `"GRCh37"`. Both are imported by
  default; policy decisions are computed once, preferring GRCh38 as the
  coordinate source when both are present.

- profile_id:

  Policy profile recorded on decision rows.

- submitter_exclusions:

  Submitters excluded from the policy decision.

## Value

Invisibly returns the table name, release identity, source paths and
byte sizes, and row counts by record kind.

## Details

This is the compact default substrate for ClinVarbitration and temporal
analysis. XML import remains available for evidence absent from the flat
reports, including richer attributable observations and XML-only text.
