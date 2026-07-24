# RClinVarbitration 0.1.1

- Replace the release-scale multi-table layout with one scalar `clinvar` table.
  `record_kind` identifies variations, alleles, locations, genes, RCVs, SCVs,
  conditions, observations, citations, attributes, text, and flat-import
  policy decisions. Repeated source elements remain rows rather than nested
  values. XML-derived policy decisions remain SQL views and are materialized
  only by an explicit export. The former public relation names remain
  query-compatible views.
- Add `rclinvarbitration_import_flat()` as the compact default import. It joins
  official `variant_summary` and `submission_summary` reports directly into
  the canonical table. The XML importer now feeds the same table when richer
  source evidence is needed. Release-scale flat imports execute one bounded
  record-kind projection at a time so large deduplication and policy states do
  not remain live together.
- Retain GRCh37 and GRCh38 locations side by side. `clinvar_vcf` exposes their
  VCF `CHROM/POS/REF/ALT` tuples, preserves exact sequence accessions, keeps
  alternate placements distinct, and does not collapse X/Y PAR placements.
  Source locations lacking a complete VCF tuple remain in `clinvar`.
  Allele-level decisions and allele-gene facts deduplicate at their semantic
  keys even when one allele has multiple placements or a source gene list
  repeats a token.
- Add `rclinvarbitration_publish_ducklake()` as the single key-based
  publication path for tidy ClinVar exports. It registers Parquet without
  collecting rows in R, leaves unchanged records untouched, publishes inserts,
  updates, and withdrawals in one snapshot, and returns native DuckLake
  change counts.
- Use temporary spill-backed XML staging and project each record kind as one
  contiguous block. Staging no longer leaves its high-water mark as free
  blocks in the durable database. A legacy-layout guard prevents old base
  tables from being overwritten by compatibility views.
- Give every canonical row a stable `record_key`. Tidy Parquet omits the
  repeated release label, keeps the release receipt separately, contains no
  nested columns, and is compared exactly by DuckLake.
- Add `clinvar_gene_disease_summaries` with descriptive, policy-versioned
  ClinVar evidence strata. These support retrieval and temporal reanalysis but
  are not represented as gene-validity classifications.
- Add case-insensitive submitter exclusions and named policy profiles without
  deleting imported source submissions.
- Add `clinvar_hpo_terms`, `clinvar_literature_links`,
  `clinvar_semantic_documents`, and disease-aware `clinvar_gene_summaries` for
  source-attributed retrieval and VariantStory integration.
- Add `rclinvarbitration_download_clinvar()` for current or archived VCV XML,
  `submission_summary`, and `variant_summary` releases.
- Add native x86-64 Windows extension builds using Rtools-provided libxml2,
  zlib, and target-aware `pkg-config`; retain Linux, macOS, and webR builds.
  Runtime artifact selection now matches exact DuckDB platform metadata and
  includes both `windows_amd64` and R-devel's `windows_amd64_mingw` identities.
- Execute the pinned upstream TSV algorithm on exact March 2026 flat inputs:
  all 4,125,389 keys and values match the package reproducer. Classify all 377
  XML/flat key or value differences with source-row receipts, and quantify
  sample/method/observed-data/consequence XML structure coverage.
- Add release-differential tests for disease keys, SCV replacement, withdrawn
  assertions, compound alleles, and mitochondrial locations, plus curated real
  HPO and PubMed context projections.
- Add experimental webR/WebAssembly support. The package now builds its
  version-matched DuckDB extension as an Emscripten side module and has a
  browser smoke test that loads it and imports the compressed VCV fixture.
- Project compact parser rows with the package-owned `rclinvar_json_field()`
  scalar rather than DuckDB's separately downloadable JSON extension. Imports
  require no extension download, including in browser/webR runtimes.
- Remove the premature local `v1` policy suffix; preserve the pinned
  `cpg-clinvarbitration-2.2.11` identifier, source-order strong-review rule,
  and separate disease- and allele-level decision views.
- Retain imported SCV source order for deterministic strong-review decisions.
- Bundle exact `C_STRUCT_UNSTABLE` extension artifacts for DuckDB `v1.5.0`
  through `v1.5.4`, selected from the enabled connection's engine version.

# RClinVarbitration 0.1.0

- First public release.
- Added a package-owned DuckDB C extension with
  `clinvar_xml_statements(path)`, a single-threaded libxml2 forward scan of
  ClinVar VCV XML and XML.GZ releases.
- Added semantic SQL materialization for ordered XML nodes, edges, literals,
  and discovery text, with a real NCBI VCV XML.GZ fixture.
- The first artifact supports exactly DuckDB `v1.5.3` on Unix-like hosts; it
  fails closed for other engine versions.
