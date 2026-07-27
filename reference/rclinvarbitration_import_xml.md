# Stream a ClinVar VCV XML release into one relational DuckDB table

The native extension reads `.xml` and `.xml.gz` with a libxml2 forward
reader. One compact row per selected ClinVar entity is written to
temporary spill-backed staging in one XML pass, projected into the
scalar `clinvar` table, and dropped. Repeated XML entities become
additional rows; no XML DOM, durable JSON, nested value, generic
parser-node graph, or R data-frame materialization is used.
Compatibility relations are views over `clinvar`.

## Usage

``` r
rclinvarbitration_import_xml(
  con,
  path,
  release_id,
  replace = FALSE,
  source_url = NULL,
  source_md5 = NULL
)
```

## Arguments

- con:

  A DuckDB DBI connection.

- path:

  Path to an official ClinVar VCV XML or XML.GZ release.

- release_id:

  User-supplied release label stored with every row.

- replace:

  Replace rows already stored for `release_id`?

- source_url:

  Optional source URL for the release catalogue. When `path` is returned
  directly by
  [`rclinvarbitration_download_clinvar()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_download_clinvar.md),
  its download metadata supplies this value automatically.

- source_md5:

  Optional 32-character source MD5 digest. Download metadata is used
  automatically when available.

## Value

A named numeric vector with imported entity counts.
