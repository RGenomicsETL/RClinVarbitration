# RClinVarbitration architecture — current

RClinVarbitration owns ClinVar source facts, release identity,
disease/allele arbitration, and source XML ingestion/publication for
literature linked to clinical interpretation.

- The scalar `clinvar` relation and its release catalogue are the
  ClinVar source authority. Tidy Parquet retains `release_id`; DuckLake
  publication validates that identity, policy, profile, and keys.
- The pinned ClinVarbitration policy is evaluated at disease and allele
  grain.
  [`rclinvarbitration_disease_release_transitions()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_disease_release_transitions.md)
  compares two imported releases under one configured profile; it is a
  selection relation, not a case-ranking or metric surface.
- The package-owned libxml2 DuckDB extension contains concrete forward
  scanners for ClinVar VCV XML and PubMed baseline/update XML. The
  tested PubMed shapes are `PubmedArticle`, `PubmedBookArticle`, and
  multi-PMID `DeleteCitation`. PMID is article authority; DOI and PMCID
  are identifiers; citation identifiers retain their reference ordinal.
  Imports append scalar, source-versioned `pubmed_*` facts in the
  selected DuckDB or DuckLake catalog. `pubmed_sources.source_ordinal`
  is typed application order; `pubmed_current_*` and
  `pubmed_*_as_of(source_id)` select effective visible facts without
  erasing deletion-hidden history. `source_provider` and snapshot
  identity remain separate from article identifiers and future provider
  provenance. The read-only `pubmed_literature_snapshots`,
  `pubmed_literature_article_versions`, and `pubmed_literature_sections`
  views are the canonical all-version handoff to ducksemantics: the
  sections view emits title rows as `section = 'title'` and abstract
  rows as `section = 'abstract'`, preserving structured PubMed labels in
  `subsection`. This package owns source identity and temporal facts;
  ducksemantics consumes those relations for retrieval/grounding without
  a dependency, cache, or shadow copy.
- Europe PMC is the next concrete enrichment/fetch source. It is not
  implemented here: full text is demand-driven for shortlisted articles,
  never a baseline-wide ingest. Unmodeled PubMed DTD elements are not
  projected as facts; the package makes no full-DTD coverage claim.

Boundaries are deliberate: ducksemantics owns semantic retrieval and
grounding; VariantStory owns case policy and ranking; VariantStoryBench
owns evaluation. This package does not add semantic screening, provider
object hierarchies, generic XML frameworks, metric summaries,
cache/checksum/ledger frameworks, Python/model dependencies, or nested
source receipts.
