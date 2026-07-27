# Export ClinVarbitration decisions to Parquet

`schema = "compatibility"` writes the seven columns in Centre for
Population Genomics ClinVarbitration's `clinvar_decisions.tsv`:
`contig`, `position`, `reference`, `alternate`, `clinical_significance`,
`gold_stars`, and `allele_id`.

## Usage

``` r
rclinvarbitration_export_clinvarbitration_parquet(
  con,
  path,
  release_id,
  assembly = c("GRCh38", "GRCh37"),
  profile_id = "default",
  submitter_exclusions = character(),
  schema = c("compatibility", "tidy")
)
```

## Arguments

- con:

  A DuckDB DBI connection initialized with
  [`rclinvarbitration_init()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_init.md).

- path:

  New output `.parquet` file path.

- release_id:

  Imported ClinVar release label to export.

- assembly:

  Genome assembly: `"GRCh38"` or `"GRCh37"`.

- profile_id:

  Policy profile identifier, normally `"default"`.

- submitter_exclusions:

  Additional submitter names to exclude from this export. Matching is
  case-insensitive and ignores surrounding whitespace. These exclusions
  are combined with any exclusions already stored for `profile_id`;
  imported source submissions are not deleted.

- schema:

  Output schema: the upstream-compatible seven-column relation or the
  canonical scalar evidence relation.

## Value

A named list describing the written Parquet file, invisibly.

## Details

`schema = "tidy"` writes the canonical scalar `clinvar` relation.
`record_kind` distinguishes variations, alleles, assembly locations,
source assertions, conditions, genes, observations, citations, text,
attributes, and policy decisions. Every row has its own stable
`record_key`; repeated source elements are rows rather than lists or
structs. `release_id` is kept in the release receipt rather than copied
into every Parquet row.

The compatibility source is the allele-level policy view joined through
`clinvar_vcf`. Both GRCh37 and GRCh38 are supported, including distinct
X/Y locations for one AlleleID. Primary `NC_` placements take precedence
when present. An allele available only on alternate placements retains
its exact sequence accession and is not mislabeled as a
primary-chromosome VCF record.

The file is schema-compatible with the upstream TSV/Hail decision
resource, but is not claimed to be byte-for-byte equivalent: this
package derives submissions and locations from VCV XML, whereas upstream
uses ClinVar's tab-delimited submission and variant summaries. PM5 is
deliberately not exported; Rduckhts/DuckHTS own downstream consequence
and PM5 processing.
