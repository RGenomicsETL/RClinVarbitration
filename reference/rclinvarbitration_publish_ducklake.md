# Publish a tidy ClinVar evidence export to DuckLake

Registers one tidy Parquet export in a persistent staging table, then
replaces the current evidence set by key in one DuckLake transaction.
New keys are inserted, absent keys are deleted, changed content is
updated, and byte-identical records are left untouched. DuckLake's
native data-change feed is the release-delta authority.

## Usage

``` r
rclinvarbitration_publish_ducklake(
  con,
  export,
  table_name = "clinvar",
  staging_table = "clinvar_incoming",
  ducklake_name = NULL,
  author = "RClinVarbitration",
  commit_message = NULL
)
```

## Arguments

- con:

  A DuckDB DBI connection whose current database is the writable
  DuckLake catalog.

- export:

  The returned value from
  [`rclinvarbitration_export_clinvarbitration_parquet()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_export_clinvarbitration_parquet.md)
  with `schema = "tidy"`, or the returned value from
  [`rclinvarbitration_import_flat()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_import_flat.md)
  when `parquet_path` was supplied.

- table_name:

  Persistent current-decision table.

- staging_table:

  Persistent empty staging table.

- ducklake_name:

  Attached DuckLake catalog. `NULL` uses the current database.

- author:

  Snapshot author.

- commit_message:

  Snapshot message. `NULL` derives one from the export.

## Value

Invisibly returns the publication snapshot, source identity, input row
count, and DuckLake change counts.

## Details

The staging and target tables are initialized once from the Parquet
schema. The staging table is retained because current DuckLake releases
cannot create, register, and drop that table safely in the same
transaction. It is empty before and after every successful publication.
