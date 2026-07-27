# ClinVar relational schema SQL

Returns DuckDB DDL for one scalar ClinVar fact table plus compatibility
views. Every XML entity is one `clinvar` row identified by
`record_kind`; repeated conditions, observations, citations, names, and
text are additional rows rather than nested values or Cartesian
products. The release catalogue and small policy configuration tables
remain separate.

## Usage

``` r
rclinvarbitration_schema_sql()
```

## Value

A named character vector of SQL statements.
