# Changelog

## RClinVarbitration 0.1.1

- Add an enhanced disease-decision Parquet schema with a stable record
  key, complete-row SHA-256 receipt, policy counts, and deterministic
  nested SCV, RCV, and gene receipts. RCV items keep their own disease
  keys instead of implying equivalence with an SCV disease key. The
  source release receipt remains separate so DuckLake snapshot changes,
  rather than a second package-local delta engine, remain the change
  authority.

- Add `clinvar_gene_disease_summaries` with descriptive,
  policy-versioned ClinVar evidence strata. These support retrieval and
  temporal reanalysis but are not represented as gene-validity
  classifications.

- Add `submitter_exclusions` to the XML-derived Parquet exporter. Direct
  exclusions are normalized case-insensitively, combined with a selected
  named profile, and applied without deleting imported source
  submissions.

- Replace the full-release executable README with a concise quick start
  and an explicit comparison with upstream ClinVarbitration.

- Add native x86-64 Windows extension builds using Rtools-provided
  libxml2, zlib, and target-aware `pkg-config`; retain Linux, macOS, and
  webR builds. Runtime artifact selection now matches exact DuckDB
  platform metadata and includes both `windows_amd64` and R-devel’s
  `windows_amd64_mingw` identities.

- Add
  [`rclinvarbitration_download_clinvar()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_download_clinvar.md)
  for checksum-validated current or monthly archived VCV XML downloads
  and optional flat-file validation inputs. Download URL, digest, and
  source byte size can flow into the release catalogue.

- Add `clinvar_hpo_terms`, `clinvar_literature_links`,
  `clinvar_semantic_documents`, and disease-aware
  `clinvar_gene_summaries` for semantic retrieval, gene panels,
  literature review, DuckLake publication, and VariantStory integration.

- Add pkgdown vignettes for the complete arbitration algorithm,
  storage/cache lifecycle and measured full-release performance, and
  semantic/DuckLake/ VariantStory integration. Add a rendered
  `docs/ERRATA.md` audit of intentional deviations and observed
  XML/flat/upstream differentials.

- Execute the pinned upstream TSV algorithm on exact March 2026 flat
  inputs: all 4,125,389 keys and values match the package reproducer.
  Classify all 377 XML/flat key or value differences with source-row
  receipts, and quantify sample/method/observed-data/consequence XML
  structure coverage.

- Add release-differential tests for disease keys, SCV replacement,
  withdrawn assertions, compound alleles, and mitochondrial locations,
  plus curated real HPO and PubMed context projections.

- Add experimental webR/WebAssembly support. The package now builds its
  version-matched DuckDB extension as an Emscripten side module and has
  a browser smoke test that loads it and imports the compressed VCV
  fixture.

- Project compact parser rows with the package-owned
  `rclinvar_json_field()` scalar rather than DuckDB’s separately
  downloadable JSON extension. Imports now require no extension
  download, including in browser/webR runtimes.

- Remove the premature local `v1` policy suffix; preserve the pinned
  `cpg-clinvarbitration-2.2.11` identifier, source-order strong-review
  rule, and separate disease- and allele-level decision views.

- Add Parquet exporters for the VCV-derived allele policy and for
  direct, SQL-only reproduction of ClinVarbitration from versioned NCBI
  flat-file archives, plus a retained differential script for published
  Zenodo releases.

- Retain imported SCV source order for deterministic strong-review
  decisions.

- Bundle exact `C_STRUCT_UNSTABLE` extension artifacts for DuckDB
  `v1.5.0` through `v1.5.4`, selected from the enabled connection’s
  engine version.

- Replace generic XML node/edge/statement persistence with a one-pass,
  ClinVar-specific entity scan and focused VCV, allele, location, gene,
  RCV, SCV, condition, observation, citation, attribute, and
  evidence-text relations. Staging now stores one JSON-backed row per
  selected entity and requires no release-wide EAV grouping.
  Release-scale tables use logical keys without memory-resident ART
  indexes, and each projection commits separately; the release catalogue
  marks completion and failed imports clean partial rows.

- Add `clinvar_disease_aggregates` and `clinvar_disease_submissions` as
  direct RCV- and SCV-level disease-policy inputs, with canonical
  disease identifiers selected independently of the complete retained
  cross-reference relation.

- Add the `cpg-clinvarbitration-2.2.11` SQL policy, configurable
  submitter-blinding profiles, and `clinvar_policy_pathogenic_alleles`
  as the disease-specific P/LP join surface for Rduckhts/DuckHTS.

- Execute the README quick start against the bundled real VCV fixture.
  The separately receipted full-release benchmark remains file-backed
  and does not rerun during README rendering.

## RClinVarbitration 0.1.0

- First public release.
- Added a package-owned DuckDB C extension with
  `clinvar_xml_statements(path)`, a single-threaded libxml2 forward scan
  of ClinVar VCV XML and XML.GZ releases.
- Added semantic SQL materialization for ordered XML nodes, edges,
  literals, and discovery text, with a real NCBI VCV XML.GZ fixture.
- The first artifact supports exactly DuckDB `v1.5.3` on Unix-like
  hosts; it fails closed for other engine versions.
