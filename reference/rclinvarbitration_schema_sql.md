# ClinVar relational schema SQL

Returns DuckDB DDL for one scalar ClinVar fact table plus compatibility
views and append-only, source-versioned PubMed relations. Every ClinVar
XML entity is one `clinvar` row identified by `record_kind`; repeated
conditions, observations, citations, names, and text are additional rows
rather than nested values or Cartesian products. PubMed current and
as-of relations use typed source order without deleting historical
facts; read-only `pubmed_literature_*` views project all source versions
for direct semantic consumers. Literature sections normalize article
titles to `section = "title"` and abstracts to `section = "abstract"`,
retaining structured labels in `subsection`. The release catalogue and
small policy configuration tables remain separate.

## Usage

``` r
rclinvarbitration_schema_sql()
```

## Value

A named character vector of SQL statements.
