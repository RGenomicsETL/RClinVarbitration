# Enable native ClinVar and PubMed XML scanning on a DuckDB connection

Loads the package-owned `rclinvarbitration` extension. Its native
`clinvar_xml_entities(path)` and
`rclinvarbitration_pubmed_xml_rows(path)` table functions are concrete
one-pass staging surfaces for
[`rclinvarbitration_import_xml()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_import_xml.md)
and
[`rclinvarbitration_import_pubmed()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_import_pubmed.md).
`rclinvar_json_field()` remains the compact ClinVar field scalar. The
connection must have been created with
`duckdb::duckdb(config = list(allow_unsigned_extensions = "true"))`, as
for any locally built DuckDB extension.

## Usage

``` r
rclinvarbitration_enable(con, extension_path = NULL)
```

## Arguments

- con:

  A DuckDB DBI connection.

- extension_path:

  Optional explicit exact-version extension path.

## Value

`con`, invisibly.
