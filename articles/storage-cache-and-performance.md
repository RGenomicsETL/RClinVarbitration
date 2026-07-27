# Storage, caching, and full-release performance

## What is cached?

RClinVarbitration uses several distinct forms of reuse. Calling all of
them a “cache” hides important lifecycle differences.

### Download cache

[`rclinvarbitration_download_clinvar()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_download_clinvar.md)
stores official NCBI files under
`tools::R_user_dir("RClinVarbitration", "cache")` by default. It accepts
either `release = "latest"` or a specific monthly archive such as
`"2026-03"`.

``` r

latest <- rclinvarbitration_download_clinvar("latest")
archived <- rclinvarbitration_download_clinvar("2026-03")
```

The downloader fetches NCBI’s MD5 sidecar for VCV XML and for current
flat files. A matching local file is reused. A stale or corrupt file is
replaced only after a complete temporary download passes its checksum.
NCBI does not publish adjacent MD5 sidecars for archived flat files, so
those files are reused by name unless `overwrite = TRUE`.

`latest` is a mutable remote alias. For an auditable run, retain the
returned URL and MD5 and assign an immutable `release_id`; selecting an
explicit monthly archive is preferable.

### Exact DuckDB extension artifacts

At package installation, the native C source is built separately for
every supported DuckDB version.
[`rclinvarbitration_enable()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_enable.md)
selects the artifact whose embedded DuckDB version and exact
`PRAGMA platform` value match the active connection. Windows packages
include both `windows_amd64` and R-devel’s `windows_amd64_mingw`
metadata identities over the same Rtools/MinGW machine code because
DuckDB validates that identity literally. This is package-owned
compatibility material, not downloaded code and not a cache that
silently falls back to another DuckDB ABI.

### Persistent relational release store

A file-backed DuckDB database is the durable, queryable conversion of
either the flat reports or VCV XML. Both import paths write one scalar
`clinvar` table; ordinary queries do not rescan or decompress the source
files. Multiple `release_id` values may coexist in one database. The
`clinvar_releases` row records completion and source identity.

``` r

library(DBI)
library(duckdb)

xml <- rclinvarbitration_download_clinvar("2026-03")
db <- file.path(tools::R_user_dir("RClinVarbitration", "data"), "clinvar.duckdb")
dir.create(dirname(db), recursive = TRUE, showWarnings = FALSE)
con <- dbConnect(duckdb(
  dbdir = db,
  config = list(
    allow_unsigned_extensions = "true",
    memory_limit = "2GB",
    preserve_insertion_order = "false",
    threads = "2"
  )
))
rclinvarbitration_enable(con)
rclinvarbitration_import_xml(con, xml, release_id = "ncbi-vcv-2026-03")
```

Passing the downloader’s returned vector directly lets the importer
retain its URL and digest metadata. Extracting only the bare character
path drops that R attribute; `source_url` and `source_md5` can then be
supplied explicitly.

## Import lifecycle

The conversion has four phases:

``` text
XML.GZ forward scan
  -> temporary compact entity relation
  -> scalar clinvar rows, appended in record-kind blocks
  -> clinvar_releases completion marker
  -> temporary relation dropped
```

The native table function performs one forward libxml2 scan and
streaming gzip decompression. It emits one compact temporary row per
selected entity. SQL projects that staging row into the scalar columns
of `clinvar` without an EAV pivot, XML DOM, or R data-frame copy. The
temporary parser payload is not part of the stored or exported schema.

The staging relation is temporary. DuckDB may spill it to
`temp_directory` under the configured memory limit, but its high-water
mark is not retained as free blocks in the durable ClinVar database.
Configure both the database and temporary directory with enough headroom
for the conversion.

The flat importer has a different bounded execution plan. It projects
one `record_kind` at a time into the same `clinvar` table. This releases
the large coordinate-deduplication, submission, and policy states
between projections instead of keeping every branch of one large union
live concurrently. `record_key`, not physical insertion order, is the
row identity.

Public relations commit independently so one enormous transaction is not
held for the complete release. The release-catalogue marker is inserted
only after all projections succeed. An R error removes partial rows and
drops staging. If the process is killed so abruptly that cleanup cannot
run, no completion marker exists; a later import drops stale staging and
clears partial rows for the same `release_id` before writing the release
again.

`replace = TRUE` stages and validates the XML scan before deleting the
existing release. A scan failure therefore leaves the previous complete
release intact. A later projection failure is cleaned up and does not
restore the replaced rows, so production publication should use a new
immutable release ID and switch consumers only after success.

## What remains virtual?

Compatibility relations such as `clinvar_scv_assertions` and derived
relations such as `clinvar_policy_decisions`, `clinvar_gene_summaries`,
and `clinvar_semantic_documents` are SQL views. DuckDB plans them
against the one stored `clinvar` table on each query.

For repeated delivery workloads, explicitly materialize a release- and
policy-versioned result to Parquet, a DuckDB table, or DuckLake. Do not
replace the auditable source tables with only the final classification
label.

The package deliberately avoids ART indexes on the release-scale table.
Their build and maintenance memory cost is undesirable during ingestion;
analytical filters, scans, joins, Parquet statistics, and downstream
materializations are the intended execution path.

DuckDB’s buffer manager may retain recently read blocks in process
memory and spill intermediates to `temp_directory`. That runtime buffer
cache is managed by DuckDB and disappears when the process exits. It is
different from the durable database and the NCBI download cache.

## Measured complete-release conversions

The two official source products serve different purposes and are
measured separately. The committed receipts are
`inst/benchmarks/full-flat-release-2026-03.dcf` and
`inst/benchmarks/full-release-2026-07-02.dcf`.

| Measurement | March 2026 flat reports | 2 July 2026 VCV XML |
|:---|---:|---:|
| Compressed source | 807,089,080 bytes | 5,824,540,370 bytes |
| Import wall time | 220.279 sec | 1,712.347 sec |
| Unique stored facts | 38,596,056 | 109,372,736 |
| Durable DuckDB file | 5,348,274,176 bytes | 9,378,738,176 bytes |
| Bytes per stored fact | 138.57 | 85.75 |
| Peak process RSS | 10,695,620 KiB | 10,593,308 KiB |
| GRCh38 raw / VCF locations | 4,410,536 / 4,389,459 | 4,465,523 / 4,444,013 |
| GRCh37 raw / VCF locations | 4,463,601 / 4,389,810 | 4,518,795 / 4,444,344 |
| Duplicate `record_key` values | 0 | 0 |
| Nested durable columns | 0 | 0 |

The flat total includes 4,124,600 stored policy decisions. XML stores
source facts only; its 4,273,846 derived allele decisions remain virtual
until an explicit publication. A tidy XML publication with those
decisions therefore contains 113,646,582 rows. That cardinality is not
itself a DuckDB concern. Keeping GRCh37 and GRCh38 coordinates, exact
sequence accessions, alternate placements, separate X/Y placements, and
source locations without usable VCF tuples is the more important
property.

Both runs used DuckDB 1.5.3 on Linux, an 13th Gen Intel(R) Core(TM)
i5-13500, 4 DuckDB threads, a 8GB DuckDB memory limit, and
`preserve_insertion_order = false`. A DuckDB memory limit is not a
process RSS limit: native parsing, compression, allocators, and other
process memory remain outside the configured buffer budget.

The XML measurement reused database blocks released by an immediately
preceding failed policy-materialization experiment, and both runs used a
warm filesystem cache. The final XML checkpoint had 35,417 live and 360
free 256-KiB blocks. These are observed engineering measurements, not
cold-cache or cross-machine guarantees.

The timed scope is the import function. Connection creation, package
loading, final `CHECKPOINT`, and process startup are excluded. Complete
process times were 225.11 seconds for the flat reports and 1,715.47
seconds for XML.

Run the benchmark with:

``` sh
CLINVAR_DUCKDB_MEMORY_LIMIT=8GB \
CLINVAR_DUCKDB_THREADS=4 \
Rscript tools/benchmark_full_release.R \
  ClinVarVCVRelease_2026-03.xml.gz \
  clinvar-2026-03.duckdb \
  ncbi-vcv-2026-03 \
  clinvar-2026-03-benchmark.dcf
```

Use `/usr/bin/time -v` or the platform equivalent around that command
when an operating-system peak-RSS measurement is required.
