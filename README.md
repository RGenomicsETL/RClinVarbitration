
<!-- README.md is generated from README.Rmd. -->

# RClinVarbitration

[![R-CMD-check](https://github.com/RGenomicsETL/RClinVarbitration/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/RGenomicsETL/RClinVarbitration/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/RGenomicsETL/RClinVarbitration/actions/workflows/pkgdown.yaml/badge.svg)](https://rgenomicsetl.github.io/RClinVarbitration/)
[![r-universe](https://rgenomicsetl.r-universe.dev/badges/:name)](https://rgenomicsetl.r-universe.dev/)

`RClinVarbitration` joins ClinVar’s official `variant_summary` and
`submission_summary` reports directly into one tidy DuckDB table. Each
decision, SCV submission, RCV accession, and allele-gene link is one
scalar row. The package applies the ClinVarbitration decision policy
during the same import; no XML database is required for ordinary release
tracking.

VCV XML import remains available when an analysis needs source
observations, citations, or text that the flat reports do not carry.

The package bundles exact-version DuckDB extensions for DuckDB `v1.5.0`
through `v1.5.4`. Connections must allow locally built unsigned
extensions.

## Installation and platforms

``` r
install.packages(
  "RClinVarbitration",
  repos = c(
    rgenomicsetl = "https://rgenomicsetl.r-universe.dev",
    CRAN = "https://cloud.r-project.org"
  )
)
```

Native builds support Linux, macOS, and x86-64 Windows. Linux and macOS
require libxml2, zlib, `pkg-config`, and a C compiler. On Windows,
install a current Rtools release; its target-aware `pkg-config` supplies
the static libxml2 and zlib dependencies. webR is supported separately
through the tested Emscripten build.

## Quick start

``` r
library(DBI)
library(duckdb)
library(RClinVarbitration)

con <- dbConnect(duckdb())
variant_report <- system.file(
  "extdata", "variant_summary_fixture.txt",
  package = "RClinVarbitration"
)
submission_report <- system.file(
  "extdata", "submission_summary_fixture.txt",
  package = "RClinVarbitration"
)

imported <- rclinvarbitration_import_flat(
  con,
  submission_report,
  variant_report,
  release_id = "clinvar-example"
)

dbGetQuery(con, "
  SELECT record_kind, count(*) AS rows
  FROM clinvar
  GROUP BY record_kind
  ORDER BY record_kind
")
```

    ##     record_kind rows
    ## 1        allele    2
    ## 2      decision    1
    ## 3          gene    2
    ## 4      location    3
    ## 5 rcv_assertion    2
    ## 6 scv_assertion    2
    ## 7     variation    2

For a complete current or archived release, download both reports and
use a file-backed database:

``` r
release <- "2026-03"
reports <- rclinvarbitration_download_clinvar(
  release,
  file = c("submission_summary", "variant_summary")
)

full_con <- dbConnect(duckdb(
  dbdir = "clinvar.duckdb",
  config = list(
    memory_limit = "8GB",
    preserve_insertion_order = "false",
    threads = "4"
  )
))
full_import <- rclinvarbitration_import_flat(
  full_con,
  reports[["submission_summary"]],
  reports[["variant_summary"]],
  release_id = paste0("ncbi-clinvar-", release),
  parquet_path = "clinvar-2026-03.parquet"
)
```

The table is deliberately long rather than nested:

| `record_kind`         | One row represents                         |
|:----------------------|:-------------------------------------------|
| `variation`, `allele` | a ClinVar variation or constituent allele  |
| `location`            | one assembly-specific VCF placement        |
| `decision`            | the allele-level ClinVarbitration decision |
| `scv_assertion`       | one submitted classification               |
| `rcv_assertion`       | one RCV accession and phenotype            |
| `gene`                | one allele-gene link                       |

GRCh37 and GRCh38 locations are retained together. `clinvar_vcf` exposes
one-based `position`, `reference`, and `alternate` fields with
conventional `1`/`chr1` primary-contig names. The exact
`sequence_accession` is retained; alternate placements use that
accession as `contig`, and X/Y PAR placements remain separate rows. Raw
`location` rows are still retained when ClinVar lacks a complete VCF
tuple, as occurs for some structural variants; those rows are
deliberately absent from `clinvar_vcf`.

On the measured March 2026 flat reports, the table contains 38,596,056
unique facts in a 4.98 GiB DuckDB file. It retains 4,410,536 GRCh38 and
4,463,601 GRCh37 source locations; 4,389,459 and 4,389,810 respectively
have usable VCF tuples. The full XML source is larger—109,372,736 unique
stored facts—because it also carries observations, citations, names,
cross-references, attributes, and text. These row counts are ordinary
analytical-table scale for DuckDB; the important contract is preserved
assembly and accession identity.

``` r
dbGetQuery(con, "
  SELECT assembly, contig, position, reference, alternate
  FROM clinvar_vcf
  ORDER BY assembly
")
```

    ##   assembly contig position reference alternate
    ## 1   GRCh37      1       90         A         G
    ## 2   GRCh38   chr1      100         A         G

## DuckLake publication and release changes

The [RGenomicsETL `ducklake-r`
fork](https://github.com/RGenomicsETL/ducklake-r) registers that Parquet
without collecting it into R. RClinVarbitration owns the key-based
publication:

``` r
ducklake::set_ducklake_connection(full_con)
ducklake::attach_ducklake("clinvar_lake", lake_path = "clinvar-lake")
publication <- rclinvarbitration_publish_ducklake(full_con, full_import)
changes <- ducklake::get_table_changes(
  "clinvar",
  publication$snapshot_id,
  publication$snapshot_id
)
```

The function initializes persistent staging once, validates keys and
policy identity, and commits inserts, updates, and withdrawals as one
snapshot. Unchanged rows are untouched. DuckLake’s change feed is the
delta authority.

Complete-release row counts and storage depend on the selected source
path: the compact flat reports contain the ordinary arbitration
substrate, while XML adds source entities that are absent from those
reports. The storage vignette records the measured workloads separately
rather than treating them as the same benchmark.

Read the [arbitration
algorithm](https://rgenomicsetl.github.io/RClinVarbitration/articles/arbitration-algorithm.html),
[storage and caching
guide](https://rgenomicsetl.github.io/RClinVarbitration/articles/storage-cache-and-performance.html),
and [semantic/DuckLake/VariantStory
integration](https://rgenomicsetl.github.io/RClinVarbitration/articles/semantic-ducklake-variantstory.html).
The [deviation and differential
audit](https://github.com/RGenomicsETL/RClinVarbitration/blob/main/docs/ERRATA.md)
records known differences from upstream ClinVarbitration and ClinVar.

## Submitter exclusions

Flat imports retain all source submissions. Exclusions change only the
`decision` rows and are recorded in the import receipt. Names are
matched case-insensitively after trimming whitespace.

``` r
rclinvarbitration_import_flat(
  con, submission_report, variant_report,
  release_id = "clinvar-example",
  submitter_exclusions = c("Example laboratory", "Another submitter")
)
```

## Optional XML enrichment

Call `rclinvarbitration_enable()`, `rclinvarbitration_init()`, and
`rclinvarbitration_import_xml()` only when the analysis needs XML-only
observations, citations, attributable text, or disease-scoped assertion
structure. The XML path writes the same scalar `clinvar` table as the
flat import. Compatibility relation names such as `clinvar_locations`
and `clinvar_scv_assertions` are views over that table. XML-derived
policy decisions remain views until an explicit Parquet or DuckLake
publication asks to materialize them.

## Comparison with upstream ClinVarbitration

The policy is pinned to [Centre for Population Genomics
ClinVarbitration](https://github.com/populationgenomics/clinvarbitration)
2.2.11 at commit `658b9f241eb2d43aa11214b153b19c1e18a16337`.

|                     | Upstream 2.2.11                           | RClinVarbitration                        |
|:--------------------|:------------------------------------------|:-----------------------------------------|
| Primary input       | NCBI submission and variant summary files | the same two reports                     |
| Runtime             | Python, Hail, Nextflow, bcftools          | R, DuckDB, package-owned C extension     |
| Decision scope      | allele                                    | allele; optional XML disease enrichment  |
| Main outputs        | TSV, Hail Table, VCF, PM5 resource        | one tidy DuckDB/Parquet relation         |
| Submitter exclusion | `site_blacklist` / `-b`                   | `submitter_exclusions` or named profiles |
| PM5                 | included                                  | out of scope                             |

The shared decision rules include the 2016 ACMG date filter,
classification bins, 60/20 majority rule, strong-review precedence, and
star calculation. The compatibility export retains the upstream
seven-column decision schema. An exact-input execution of the pinned
upstream Python TSV stage and this package’s flat reproducer over the
complete March 2026 archives produced the same 4,125,389 keys with zero
classification or star differences. Input, code, configuration, and
output digests are in the [oracle
manifest](https://github.com/RGenomicsETL/RClinVarbitration/blob/main/inst/audits/march-2026-flat-exact-oracle.dcf).

The independently matched XML/flat audit classified every one of the 16
shared value differences and 361 key-set differences with source-row
receipts. Most come from NCBI flat rows whose classification is `-`
while XML carries a current classification; the remainder are one
duplicate-SCV identity case, five source vocabulary differences, and two
nested compound alleles. The [ERRATA
audit](https://github.com/RGenomicsETL/RClinVarbitration/blob/main/docs/ERRATA.md)
contains the full counts and receipts. A published Zenodo release with
16,865 reference-only keys used an unpinned source snapshot; it is not
the exact-input conformance result.

One deliberate edge-case difference is that RClinVarbitration applies
the qualified Illumina benign exclusion declared by upstream. At the
pinned commit, the Python implementation’s inner-loop `continue` does
not actually remove that submission, so compatibility here follows the
documented policy rather than that implementation accident.

## Evidence retrieval and reanalysis

A second motivation is to make ClinVar evidence reusable, not only to
annotate known alleles. The flat table retains submission descriptions,
phenotype strings, RCVs, and gene links. Optional XML enrichment adds
citations, normalized HPO links, and other attributable observations.
These are joinable inputs for
[`ducksemantics`](https://github.com/RGenomicsETL/ducksemantics),
DuckLake release history, and the source-observation model planned by
[`VariantStory`](https://github.com/RGenomicsETL/VariantStory).

These workflows retrieve and rank evidence; an embedding neighbor does
not classify a variant. Provider identity, release, source rows,
deterministic evidence admission, and human review must remain explicit.

## Acknowledgements

The decision policy is adapted from Centre for Population Genomics
ClinVarbitration 2.2.11 under its MIT license. ClinVar source data are
provided by NCBI.
