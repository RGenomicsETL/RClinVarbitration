# Import a PubMed baseline or update XML source

Streams concrete PubMed baseline or update XML through the package-owned
libxml2 DuckDB extension. PMID is the article authority; DOI and PMCID
are retained as ordinary article identifiers when supplied. Each import
appends immutable source-versioned rows. `DeleteCitation` appends an
explicit deleted article event; it does not erase earlier article or
child facts.

## Usage

``` r
rclinvarbitration_import_pubmed(
  con,
  path,
  source_id,
  source_kind = c("baseline", "update")
)
```

## Arguments

- con:

  A DuckDB DBI connection with
  [`rclinvarbitration_enable()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_enable.md)
  loaded.

- path:

  Path to a PubMed baseline or update XML or XML.GZ file.

- source_id:

  Immutable source snapshot or update label.

- source_kind:

  Whether `path` is a `"baseline"` or `"update"` source.

## Value

Invisibly returns source identity, typed source ordinal, and scalar row
counts.

## Details

The caller's current DuckDB or DuckLake catalog owns the resulting
`pubmed_*` relations. `pubmed_current_*` selects the latest non-deleted
event per PMID, while `pubmed_*_as_of(source_id)` table macros select a
historical cutoff. This importer does not fetch Europe PMC or perform
semantic screening.
