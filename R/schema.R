#' ClinVar relational schema SQL
#'
#' Returns DuckDB DDL for one scalar ClinVar fact table plus compatibility
#' views and append-only, source-versioned PubMed relations. Every ClinVar XML
#' entity is one `clinvar` row identified by `record_kind`; repeated conditions,
#' observations, citations, names, and text are additional rows rather than
#' nested values or Cartesian products. PubMed current and as-of relations use
#' typed source order without deleting historical facts; read-only
#' `pubmed_literature_*` views project all source versions for direct semantic
#' consumers. Literature sections normalize article titles to `section = "title"`
#' and abstracts to `section = "abstract"`, retaining structured labels in
#' `subsection`. The release catalogue and small policy configuration tables
#' remain separate.
#'
#' @return A named character vector of SQL statements.
#' @export
rclinvarbitration_schema_sql <- function() {
  c(
    releases = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_releases (",
      "release_id TEXT PRIMARY KEY, source_path TEXT NOT NULL, source_url TEXT,",
      "source_md5 TEXT, source_bytes UBIGINT, source_kind TEXT,",
      "submission_path TEXT, variant_path TEXT,",
      "imported_at TIMESTAMP NOT NULL DEFAULT current_timestamp)"
    ),
    release_source_url = "ALTER TABLE clinvar_releases ADD COLUMN IF NOT EXISTS source_url TEXT",
    release_source_md5 = "ALTER TABLE clinvar_releases ADD COLUMN IF NOT EXISTS source_md5 TEXT",
    release_source_bytes = "ALTER TABLE clinvar_releases ADD COLUMN IF NOT EXISTS source_bytes UBIGINT",
    release_source_kind = "ALTER TABLE clinvar_releases ADD COLUMN IF NOT EXISTS source_kind TEXT",
    release_submission_path = "ALTER TABLE clinvar_releases ADD COLUMN IF NOT EXISTS submission_path TEXT",
    release_variant_path = "ALTER TABLE clinvar_releases ADD COLUMN IF NOT EXISTS variant_path TEXT",
    pubmed_sources = paste(
      "CREATE TABLE IF NOT EXISTS pubmed_sources (",
      "source_id TEXT PRIMARY KEY, source_ordinal UBIGINT NOT NULL UNIQUE,",
      "source_provider TEXT NOT NULL, source_path TEXT NOT NULL, source_kind TEXT NOT NULL,",
      "source_bytes UBIGINT NOT NULL, source_applied_at TIMESTAMP NOT NULL DEFAULT current_timestamp)"
    ),
    pubmed_source_provider = "ALTER TABLE pubmed_sources ADD COLUMN IF NOT EXISTS source_provider TEXT",
    pubmed_source_ordinal = "ALTER TABLE pubmed_sources ADD COLUMN IF NOT EXISTS source_ordinal UBIGINT",
    pubmed_source_applied_at = "ALTER TABLE pubmed_sources ADD COLUMN IF NOT EXISTS source_applied_at TIMESTAMP",
    pubmed_articles = paste(
      "CREATE TABLE IF NOT EXISTS pubmed_articles (",
      "source_id TEXT NOT NULL, pmid TEXT NOT NULL, source_kind TEXT NOT NULL,",
      "source_record_ordinal UBIGINT NOT NULL, article_title TEXT, publication_date TEXT,",
      "source_date TEXT, is_deleted BOOLEAN NOT NULL, PRIMARY KEY (source_id, pmid))"
    ),
    pubmed_abstracts = paste(
      "CREATE TABLE IF NOT EXISTS pubmed_abstracts (",
      "source_id TEXT NOT NULL, pmid TEXT NOT NULL, source_record_ordinal UBIGINT NOT NULL,",
      "source_entity_ordinal UBIGINT NOT NULL, section TEXT, text TEXT NOT NULL,",
      "PRIMARY KEY (source_id, pmid, source_entity_ordinal))"
    ),
    pubmed_article_identifiers = paste(
      "CREATE TABLE IF NOT EXISTS pubmed_article_identifiers (",
      "source_id TEXT NOT NULL, pmid TEXT NOT NULL, source_record_ordinal UBIGINT NOT NULL,",
      "source_entity_ordinal UBIGINT NOT NULL, identifier_role TEXT NOT NULL,",
      "identifier_source TEXT, identifier TEXT NOT NULL, citation_ordinal UBIGINT,",
      "PRIMARY KEY (source_id, pmid, source_entity_ordinal))"
    ),
    pubmed_mesh_terms = paste(
      "CREATE TABLE IF NOT EXISTS pubmed_mesh_terms (",
      "source_id TEXT NOT NULL, pmid TEXT NOT NULL, source_record_ordinal UBIGINT NOT NULL,",
      "source_entity_ordinal UBIGINT NOT NULL, mesh_type TEXT NOT NULL,",
      "mesh_ui TEXT, term TEXT NOT NULL, PRIMARY KEY (source_id, pmid, source_entity_ordinal))"
    ),
    pubmed_keywords = paste(
      "CREATE TABLE IF NOT EXISTS pubmed_keywords (",
      "source_id TEXT NOT NULL, pmid TEXT NOT NULL, source_record_ordinal UBIGINT NOT NULL,",
      "source_entity_ordinal UBIGINT NOT NULL, keyword TEXT NOT NULL,",
      "PRIMARY KEY (source_id, pmid, source_entity_ordinal))"
    ),
    pubmed_identifier_citation_ordinal = "ALTER TABLE pubmed_article_identifiers ADD COLUMN IF NOT EXISTS citation_ordinal UBIGINT",
    records = paste(
      "CREATE TABLE IF NOT EXISTS clinvar (",
      "release_id TEXT NOT NULL, record_kind TEXT NOT NULL, record_key TEXT NOT NULL,",
      "record_ordinal UBIGINT NOT NULL, entity_ordinal UBIGINT,",
      "vcv_accession TEXT, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "entity_id TEXT, parent_type TEXT, parent_id TEXT,",
      "vcv_version UINTEGER, variation_id UBIGINT, variation_name TEXT,",
      "variation_type TEXT, record_type TEXT, record_status TEXT, species TEXT,",
      "date_created DATE, date_last_updated DATE, most_recent_submission DATE,",
      "number_of_submissions UINTEGER, number_of_submitters UINTEGER,",
      "classification TEXT, review_status TEXT, date_last_evaluated DATE,",
      "parent_allele_entity_id TEXT, allele_id UBIGINT, allele_name TEXT,",
      "variant_type TEXT, canonical_spdi TEXT, assembly TEXT,",
      "assembly_accession_version TEXT, assembly_status TEXT, chromosome TEXT,",
      "sequence_accession TEXT, start UBIGINT, stop UBIGINT, position_vcf UBIGINT,",
      "reference_allele_vcf TEXT, alternate_allele_vcf TEXT, for_display BOOLEAN,",
      "gene_id UBIGINT, gene_symbol TEXT, hgnc_id TEXT, gene_name TEXT,",
      "relationship_type TEXT, source TEXT, accession TEXT, version UINTEGER,",
      "title TEXT, submission_count UINTEGER, source_ordinal UBIGINT,",
      "assertion_id UBIGINT, submitter_name TEXT, submitter_id UBIGINT,",
      "organization_category TEXT, organization_abbreviation TEXT, local_key TEXT,",
      "submitted_assembly TEXT, submission_title TEXT, assertion_type TEXT,",
      "submission_date DATE, contributes_to_aggregate_classification BOOLEAN,",
      "context_type TEXT, context_id TEXT, trait_id TEXT, trait_type TEXT,",
      "trait_set_id TEXT, trait_set_type TEXT, preferred_name TEXT,",
      "database_name TEXT, database_id TEXT, name_type TEXT, value_text TEXT,",
      "xref_type TEXT, origin TEXT, affected_status TEXT, number_tested UINTEGER,",
      "method_type TEXT, citation_type TEXT, abbreviation TEXT, url TEXT,",
      "identifier_source TEXT, identifier TEXT, attribute_type TEXT,",
      "integer_value BIGINT, section TEXT, text_value TEXT,",
      "description TEXT, submitted_phenotype_info TEXT,",
      "reported_phenotype_info TEXT, collection_method TEXT, origin_counts TEXT,",
      "submitted_gene_symbol TEXT, explanation TEXT, policy_version TEXT,",
      "profile_id TEXT, gold_stars INTEGER)"
    ),
    policy_profiles = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_policy_profiles (",
      "policy_version TEXT NOT NULL, profile_id TEXT NOT NULL, description TEXT,",
      "PRIMARY KEY (policy_version, profile_id))"
    ),
    policy_exclusions = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_policy_submitter_exclusions (",
      "policy_version TEXT NOT NULL, profile_id TEXT NOT NULL,",
      "submitter_name TEXT NOT NULL, classification_bin TEXT, reason TEXT)"
    ),
    default_policy_profile = paste0(
      "INSERT INTO clinvar_policy_profiles ",
      "SELECT '", rclinvarbitration_policy_version(), "', 'default', ",
      "'CPG ClinVarbitration 2.2.11 defaults, adapted per disease' ",
      "WHERE NOT EXISTS (SELECT 1 FROM clinvar_policy_profiles WHERE policy_version = '",
      rclinvarbitration_policy_version(), "' AND profile_id = 'default')"
    ),
    variants = paste(
      "CREATE OR REPLACE VIEW clinvar_variants AS SELECT release_id, record_ordinal,",
      "vcv_accession, vcv_version, variation_id, variation_name, variation_type,",
      "record_type, record_status, species, date_created, date_last_updated,",
      "most_recent_submission, number_of_submissions, number_of_submitters,",
      "classification AS aggregate_classification,",
      "review_status AS aggregate_review_status,",
      "date_last_evaluated AS aggregate_date_last_evaluated",
      "FROM clinvar WHERE record_kind = 'variation'"
    ),
    alleles = paste(
      "CREATE OR REPLACE VIEW clinvar_alleles AS SELECT release_id, record_ordinal,",
      "vcv_accession, entity_id AS allele_entity_id, parent_allele_entity_id,",
      "allele_id, variation_id, allele_name AS name, variant_type, canonical_spdi",
      "FROM clinvar WHERE record_kind = 'allele'"
    ),
    locations = paste(
      "CREATE OR REPLACE VIEW clinvar_locations AS SELECT release_id, record_ordinal,",
      "vcv_accession, parent_id AS allele_entity_id, entity_id AS location_id,",
      "assembly, assembly_accession_version, assembly_status, chromosome,",
      "sequence_accession, start, stop, position_vcf, reference_allele_vcf,",
      "alternate_allele_vcf, for_display FROM clinvar WHERE record_kind = 'location'"
    ),
    genes = paste(
      "CREATE OR REPLACE VIEW clinvar_genes AS SELECT release_id, record_ordinal,",
      "vcv_accession, parent_id AS allele_entity_id, entity_id AS gene_entity_id,",
      "gene_id, gene_symbol AS symbol, hgnc_id, gene_name AS full_name,",
      "relationship_type, source FROM clinvar WHERE record_kind = 'gene'"
    ),
    rcvs = paste(
      "CREATE OR REPLACE VIEW clinvar_rcv_assertions AS SELECT release_id,",
      "record_ordinal, vcv_accession, accession AS rcv_accession,",
      "version AS rcv_version, title, classification, review_status,",
      "date_last_evaluated, submission_count FROM clinvar",
      "WHERE record_kind = 'rcv_assertion'"
    ),
    scvs = paste(
      "CREATE OR REPLACE VIEW clinvar_scv_assertions AS SELECT release_id,",
      "record_ordinal, source_ordinal, vcv_accession, entity_id AS assertion_entity_id,",
      "assertion_id, accession AS scv_accession, version AS scv_version,",
      "submitter_name, submitter_id, organization_category,",
      "organization_abbreviation, local_key, submitted_assembly, submission_title,",
      "assertion_type, record_status, classification, review_status,",
      "date_last_evaluated, submission_date, date_created, date_last_updated,",
      "contributes_to_aggregate_classification FROM clinvar",
      "WHERE record_kind = 'scv_assertion'"
    ),
    conditions = paste(
      "CREATE OR REPLACE VIEW clinvar_conditions AS SELECT release_id, record_ordinal,",
      "vcv_accession, rcv_entity_id, scv_entity_id, entity_id AS condition_id,",
      "context_type, context_id, trait_id, trait_type, trait_set_id, trait_set_type,",
      "preferred_name, database_name, database_id,",
      "contributes_to_aggregate_classification FROM clinvar",
      "WHERE record_kind = 'condition'"
    ),
    condition_names = paste(
      "CREATE OR REPLACE VIEW clinvar_condition_names AS SELECT release_id,",
      "record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
      "parent_id AS condition_id, entity_id AS name_id, name_type, value_text AS name",
      "FROM clinvar WHERE record_kind = 'condition_name'"
    ),
    xrefs = paste(
      "CREATE OR REPLACE VIEW clinvar_xrefs AS SELECT release_id, record_ordinal,",
      "vcv_accession, rcv_entity_id, scv_entity_id, context_type, context_id,",
      "entity_id AS xref_id, database_name, database_id, xref_type",
      "FROM clinvar WHERE record_kind = 'xref'"
    ),
    observations = paste(
      "CREATE OR REPLACE VIEW clinvar_observations AS SELECT release_id, record_ordinal,",
      "vcv_accession, scv_entity_id, entity_id AS observation_id, origin, species,",
      "affected_status, number_tested, method_type FROM clinvar",
      "WHERE record_kind = 'observation'"
    ),
    citations = paste(
      "CREATE OR REPLACE VIEW clinvar_citations AS SELECT release_id, record_ordinal,",
      "vcv_accession, rcv_entity_id, scv_entity_id, entity_id AS citation_id,",
      "context_type, context_id, citation_type, abbreviation, url FROM clinvar",
      "WHERE record_kind = 'citation'"
    ),
    citation_identifiers = paste(
      "CREATE OR REPLACE VIEW clinvar_citation_identifiers AS SELECT release_id,",
      "record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
      "parent_id AS citation_id, entity_id AS identifier_entity_id,",
      "identifier_source AS source, identifier FROM clinvar",
      "WHERE record_kind = 'citation_identifier'"
    ),
    attributes = paste(
      "CREATE OR REPLACE VIEW clinvar_attributes AS SELECT release_id, record_ordinal,",
      "vcv_accession, rcv_entity_id, scv_entity_id, entity_id AS attribute_id,",
      "context_type, context_id, attribute_type, integer_value, value_text AS value",
      "FROM clinvar WHERE record_kind = 'attribute'"
    ),
    text = paste(
      "CREATE OR REPLACE VIEW clinvar_text AS",
      "SELECT release_id, record_ordinal, entity_ordinal AS ordinal,",
      "entity_id AS document_id, vcv_accession, rcv_entity_id, scv_entity_id,",
      "context_type, context_id, section, text_value AS text FROM clinvar",
      "WHERE record_kind = 'text' UNION ALL",
      "SELECT release_id, record_ordinal, 0, entity_id, vcv_accession,",
      "rcv_entity_id, scv_entity_id, 'condition', parent_id,",
      "'condition_name:' || coalesce(name_type, 'unspecified'), value_text",
      "FROM clinvar WHERE record_kind = 'condition_name' UNION ALL",
      "SELECT release_id, record_ordinal, 0, entity_id || '#preferred_name',",
      "vcv_accession, rcv_entity_id, scv_entity_id, context_type, context_id,",
      "'condition_preferred_name', preferred_name FROM clinvar",
      "WHERE record_kind = 'condition' AND preferred_name IS NOT NULL UNION ALL",
      "SELECT release_id, record_ordinal, 0, entity_id, vcv_accession,",
      "rcv_entity_id, scv_entity_id, context_type, context_id,",
      "'attribute:' || coalesce(attribute_type, 'unspecified'), value_text",
      "FROM clinvar WHERE record_kind = 'attribute' AND value_text IS NOT NULL"
    ),
    vcf_coordinates = paste(
      "CREATE OR REPLACE VIEW clinvar_vcf AS SELECT l.release_id,",
      "l.record_ordinal, l.record_key AS coordinate_key, l.vcv_accession,",
      "l.parent_id AS allele_entity_id, a.allele_id, a.variation_id,",
      "l.assembly, l.assembly_accession_version, l.sequence_accession,",
      "l.chromosome, CASE WHEN l.sequence_accession IS NOT NULL AND",
      "(NOT starts_with(l.sequence_accession, 'NC_') OR",
      "coalesce(l.chromosome, '') NOT IN ('1', '2', '3', '4', '5', '6', '7', '8',",
      "'9', '10', '11', '12', '13', '14', '15', '16', '17', '18',",
      "'19', '20', '21', '22', 'X', 'Y', 'M', 'MT'))",
      "THEN l.sequence_accession WHEN l.assembly = 'GRCh38' THEN",
      "CASE WHEN l.chromosome IN ('M', 'MT') THEN 'chrM'",
      "ELSE 'chr' || l.chromosome END",
      "ELSE CASE WHEN l.chromosome = 'MT' THEN 'M' ELSE l.chromosome END END",
      "AS contig, l.position_vcf AS position,",
      "l.reference_allele_vcf AS reference,",
      "l.alternate_allele_vcf AS alternate, l.start, l.stop,",
      "l.for_display, a.canonical_spdi FROM clinvar l JOIN clinvar a",
      "ON a.release_id = l.release_id AND a.record_kind = 'allele'",
      "AND a.entity_id = l.parent_id WHERE l.record_kind = 'location'",
      "AND l.assembly IN ('GRCh37', 'GRCh38')",
      "AND l.position_vcf IS NOT NULL AND l.position_vcf > 0",
      "AND l.reference_allele_vcf IS NOT NULL",
      "AND l.alternate_allele_vcf IS NOT NULL",
      "AND trim(l.reference_allele_vcf) <> ''",
      "AND trim(l.alternate_allele_vcf) <> ''",
      "AND lower(l.reference_allele_vcf) <> 'na'",
      "AND lower(l.alternate_allele_vcf) <> 'na'",
      "AND l.reference_allele_vcf <> l.alternate_allele_vcf"
    ),
    normalized_alleles = paste(
      "CREATE OR REPLACE VIEW clinvar_normalized_alleles AS SELECT",
      "release_id, vcv_accession, allele_id, variation_id, assembly, chromosome,",
      "position AS position_vcf, reference, alternate, canonical_spdi",
      "FROM clinvar_vcf"
    ),
    disease_aggregates = paste(
      "CREATE OR REPLACE VIEW clinvar_disease_aggregates AS SELECT",
      "r.release_id, r.vcv_accession, v.variation_id, a.allele_id,",
      "r.rcv_accession, r.rcv_version, r.title AS rcv_title,",
      "c.condition_id, c.trait_set_id, c.database_name AS disease_database,",
      "c.database_id AS disease_identifier, c.preferred_name AS disease_name,",
      "CASE WHEN c.database_name IS NOT NULL AND c.database_id IS NOT NULL",
      "THEN lower(trim(c.database_name)) || ':' || trim(c.database_id)",
      "WHEN c.trait_set_id IS NOT NULL THEN 'clinvar-trait-set:' || c.trait_set_id",
      "WHEN c.preferred_name IS NOT NULL THEN 'name:' || lower(trim(c.preferred_name))",
      "ELSE 'condition:' || c.condition_id END AS disease_key,",
      "r.classification AS aggregate_classification,",
      "r.review_status AS aggregate_review_status,",
      "r.date_last_evaluated AS aggregate_date_last_evaluated,",
      "r.submission_count FROM clinvar_rcv_assertions r",
      "JOIN clinvar_variants v USING (release_id, vcv_accession)",
      "LEFT JOIN clinvar_alleles a ON a.release_id = r.release_id",
      "AND a.vcv_accession = r.vcv_accession AND a.parent_allele_entity_id IS NULL",
      "LEFT JOIN clinvar_conditions c ON c.release_id = r.release_id",
      "AND c.context_type = 'rcv_assertion' AND c.context_id = r.rcv_accession"
    ),
    disease_submissions = paste(
      "CREATE OR REPLACE VIEW clinvar_disease_submissions AS WITH names AS (",
      "SELECT release_id, condition_id,",
      "coalesce(max(name) FILTER (WHERE lower(name_type) = 'preferred'), max(name)) AS disease_name",
      "FROM clinvar_condition_names GROUP BY release_id, condition_id),",
      "canonical_xrefs AS (SELECT release_id, context_id, database_name, database_id",
      "FROM clinvar_xrefs WHERE context_type = 'condition' AND lower(database_name) IN",
      "('medgen', 'mondo', 'omim', 'orphanet', 'mesh', 'umls', 'omim phenotypic series')",
      "QUALIFY row_number() OVER (PARTITION BY release_id, context_id ORDER BY",
      "CASE lower(database_name) WHEN 'medgen' THEN 0 WHEN 'mondo' THEN 1",
      "WHEN 'omim' THEN 2 WHEN 'orphanet' THEN 3 WHEN 'mesh' THEN 4",
      "WHEN 'umls' THEN 5 ELSE 6 END, database_name, database_id, xref_id) = 1),",
      "linked AS (SELECT s.release_id, s.vcv_accession, v.variation_id, a.allele_id,",
      "s.assertion_entity_id, s.scv_accession, s.scv_version, s.assertion_id, s.source_ordinal,",
      "s.submitter_name, s.submitter_id, s.classification, s.review_status,",
      "s.date_last_evaluated, s.submission_date, s.contributes_to_aggregate_classification,",
      "c.condition_id, c.trait_set_id,",
      "coalesce(c.database_name, x.database_name) AS disease_database,",
      "coalesce(c.database_id, x.database_id) AS disease_identifier,",
      "coalesce(c.preferred_name, n.disease_name) AS disease_name",
      "FROM clinvar_scv_assertions s JOIN clinvar_variants v USING (release_id, vcv_accession)",
      "LEFT JOIN clinvar_alleles a ON a.release_id = s.release_id",
      "AND a.vcv_accession = s.vcv_accession AND a.parent_allele_entity_id IS NULL",
      "JOIN clinvar_conditions c ON c.release_id = s.release_id",
      "AND c.context_type = 'scv_assertion' AND c.context_id = s.assertion_entity_id",
      "LEFT JOIN names n ON n.release_id = c.release_id AND n.condition_id = c.condition_id",
      "LEFT JOIN canonical_xrefs x ON x.release_id = c.release_id AND x.context_id = c.condition_id)",
      "SELECT linked.*, CASE WHEN disease_database IS NOT NULL AND disease_identifier IS NOT NULL",
      "THEN lower(trim(disease_database)) || ':' || trim(disease_identifier)",
      "WHEN trait_set_id IS NOT NULL THEN 'clinvar-trait-set:' || trait_set_id",
      "WHEN disease_name IS NOT NULL THEN 'name:' || lower(trim(disease_name))",
      "ELSE 'condition:' || condition_id END AS disease_key FROM linked"
    ),
    hpo_terms = paste(
      "CREATE OR REPLACE VIEW clinvar_hpo_terms AS WITH normalized AS (SELECT",
      "release_id, record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
      "context_type, context_id, xref_id, xref_type,",
      "upper(trim(database_id)) AS raw_hpo_id FROM clinvar_xrefs",
      "WHERE lower(trim(coalesce(database_name, ''))) IN",
      "('hp', 'hpo', 'human phenotype ontology'))",
      "SELECT release_id, record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
      "context_type, context_id, xref_id,",
      "CASE WHEN starts_with(raw_hpo_id, 'HP:') THEN raw_hpo_id",
      "ELSE 'HP:' || raw_hpo_id END AS hpo_id, xref_type FROM normalized",
      "WHERE regexp_matches(raw_hpo_id, '^(HP:)?[0-9]{7}$')"
    ),
    literature_links = paste(
      "CREATE OR REPLACE VIEW clinvar_literature_links AS SELECT",
      "c.release_id, c.record_ordinal, c.vcv_accession, c.rcv_entity_id, c.scv_entity_id,",
      "c.citation_id, c.context_type, c.context_id, c.citation_type, c.abbreviation,",
      "i.identifier_entity_id, i.source, i.identifier,",
      "coalesce(nullif(trim(c.url), ''), CASE",
      "WHEN lower(trim(i.source)) IN ('pubmed', 'pmid')",
      "THEN 'https://pubmed.ncbi.nlm.nih.gov/' || trim(i.identifier) || '/'",
      "WHEN lower(trim(i.source)) = 'doi'",
      "THEN 'https://doi.org/' || trim(i.identifier)",
      "WHEN lower(trim(i.source)) = 'pmc'",
      "THEN 'https://www.ncbi.nlm.nih.gov/pmc/articles/' || trim(i.identifier) || '/'",
      "WHEN lower(trim(i.source)) = 'bookshelf'",
      "THEN 'https://www.ncbi.nlm.nih.gov/books/' || trim(i.identifier) || '/'",
      "END) AS literature_url FROM clinvar_citations c",
      "LEFT JOIN clinvar_citation_identifiers i ON i.release_id = c.release_id",
      "AND i.citation_id = c.citation_id AND i.vcv_accession = c.vcv_accession"
    ),
    semantic_documents = paste(
      "CREATE OR REPLACE VIEW clinvar_semantic_documents AS SELECT",
      "concat_ws(':', t.release_id, t.vcv_accession, t.document_id,",
      "cast(t.record_ordinal AS VARCHAR), cast(t.ordinal AS VARCHAR)) AS semantic_document_id,",
      "t.release_id, t.vcv_accession, t.rcv_entity_id, t.scv_entity_id,",
      "t.context_type, t.context_id, t.section, t.text,",
      "s.scv_accession, s.submitter_name, s.classification AS submitted_classification,",
      "s.review_status AS submitted_review_status, s.date_last_evaluated",
      "FROM clinvar_text t",
      "LEFT JOIN clinvar_scv_assertions s ON s.release_id = t.release_id",
      "AND s.assertion_entity_id = t.scv_entity_id"
    ),
    pubmed_article_events = paste(
      "CREATE OR REPLACE VIEW pubmed_article_events AS SELECT a.*, s.source_ordinal,",
      "s.source_applied_at FROM pubmed_articles a JOIN pubmed_sources s USING (source_id)"
    ),
    pubmed_literature_snapshots = paste(
      "CREATE OR REPLACE VIEW pubmed_literature_snapshots AS SELECT",
      "source_provider AS provider_id, source_id AS snapshot_id,",
      "source_ordinal AS high_water_ordinal, source_applied_at AS effective_at",
      "FROM pubmed_sources"
    ),
    pubmed_literature_article_versions = paste(
      "CREATE OR REPLACE VIEW pubmed_literature_article_versions AS SELECT",
      "s.source_provider AS provider_id, a.pmid AS article_id, a.pmid,",
      "a.source_id AS version_id, s.source_ordinal, a.is_deleted, a.article_title,",
      "a.publication_date, a.source_date FROM pubmed_articles a",
      "JOIN pubmed_sources s USING (source_id)"
    ),
    pubmed_literature_sections = paste(
      "CREATE OR REPLACE VIEW pubmed_literature_sections AS",
      "SELECT s.source_provider AS provider_id, a.pmid AS article_id, a.pmid,",
      "a.source_id AS version_id, s.source_ordinal, 'title' AS section,",
      "CAST(NULL AS TEXT) AS subsection, a.article_title AS text",
      "FROM pubmed_articles a JOIN pubmed_sources s USING (source_id)",
      "WHERE a.article_title IS NOT NULL AND trim(a.article_title) <> ''",
      "UNION ALL SELECT s.source_provider AS provider_id, a.pmid AS article_id, a.pmid,",
      "a.source_id AS version_id, s.source_ordinal, 'abstract' AS section,",
      "a.section AS subsection, a.text FROM pubmed_abstracts a",
      "JOIN pubmed_sources s USING (source_id)"
    ),
    pubmed_current_articles = paste(
      "CREATE OR REPLACE VIEW pubmed_current_articles AS WITH ranked AS (SELECT",
      "a.*, s.source_ordinal, s.source_applied_at, row_number() OVER (PARTITION BY a.pmid",
      "ORDER BY s.source_ordinal DESC) AS source_rank FROM pubmed_articles a",
      "JOIN pubmed_sources s USING (source_id)) SELECT * EXCLUDE (source_rank) FROM ranked",
      "WHERE source_rank = 1 AND NOT is_deleted"
    ),
    pubmed_articles_as_of = paste(
      "CREATE OR REPLACE MACRO pubmed_articles_as_of(requested_source_id) AS TABLE",
      "WITH cutoff AS (SELECT source_ordinal FROM pubmed_sources",
      "WHERE source_id = requested_source_id), ranked AS (SELECT a.*, s.source_ordinal,",
      "s.source_applied_at, row_number() OVER (PARTITION BY a.pmid ORDER BY",
      "s.source_ordinal DESC) AS source_rank FROM pubmed_articles a",
      "JOIN pubmed_sources s USING (source_id) JOIN cutoff c",
      "ON s.source_ordinal <= c.source_ordinal) SELECT * EXCLUDE (source_rank)",
      "FROM ranked WHERE source_rank = 1 AND NOT is_deleted"
    ),
    pubmed_current_abstracts = paste(
      "CREATE OR REPLACE VIEW pubmed_current_abstracts AS SELECT c.* FROM pubmed_abstracts c",
      "JOIN pubmed_current_articles a USING (source_id, pmid)"
    ),
    pubmed_current_article_identifiers = paste(
      "CREATE OR REPLACE VIEW pubmed_current_article_identifiers AS SELECT c.*",
      "FROM pubmed_article_identifiers c JOIN pubmed_current_articles a USING (source_id, pmid)"
    ),
    pubmed_current_mesh_terms = paste(
      "CREATE OR REPLACE VIEW pubmed_current_mesh_terms AS SELECT c.* FROM pubmed_mesh_terms c",
      "JOIN pubmed_current_articles a USING (source_id, pmid)"
    ),
    pubmed_current_keywords = paste(
      "CREATE OR REPLACE VIEW pubmed_current_keywords AS SELECT c.* FROM pubmed_keywords c",
      "JOIN pubmed_current_articles a USING (source_id, pmid)"
    ),
    pubmed_abstracts_as_of = paste(
      "CREATE OR REPLACE MACRO pubmed_abstracts_as_of(requested_source_id) AS TABLE",
      "SELECT c.* FROM pubmed_abstracts c JOIN pubmed_articles_as_of(requested_source_id) a",
      "USING (source_id, pmid)"
    ),
    pubmed_article_identifiers_as_of = paste(
      "CREATE OR REPLACE MACRO pubmed_article_identifiers_as_of(requested_source_id) AS TABLE",
      "SELECT c.* FROM pubmed_article_identifiers c",
      "JOIN pubmed_articles_as_of(requested_source_id) a USING (source_id, pmid)"
    ),
    pubmed_mesh_terms_as_of = paste(
      "CREATE OR REPLACE MACRO pubmed_mesh_terms_as_of(requested_source_id) AS TABLE",
      "SELECT c.* FROM pubmed_mesh_terms c JOIN pubmed_articles_as_of(requested_source_id) a",
      "USING (source_id, pmid)"
    ),
    pubmed_keywords_as_of = paste(
      "CREATE OR REPLACE MACRO pubmed_keywords_as_of(requested_source_id) AS TABLE",
      "SELECT c.* FROM pubmed_keywords c JOIN pubmed_articles_as_of(requested_source_id) a",
      "USING (source_id, pmid)"
    ),
    clinvar_pubmed_articles = paste(
      "CREATE OR REPLACE VIEW clinvar_pubmed_articles AS SELECT",
      "l.release_id AS clinvar_release_id, l.vcv_accession, l.rcv_entity_id,",
      "l.scv_entity_id, l.citation_id, p.pmid, p.source_id AS pubmed_source_id,",
      "p.source_kind AS pubmed_source_kind, p.article_title, p.publication_date,",
      "p.source_date FROM clinvar_literature_links l JOIN pubmed_current_articles p",
      "ON lower(trim(coalesce(l.source, ''))) IN ('pubmed', 'pmid')",
      "AND trim(l.identifier) = p.pmid"
    ),
    rclinvarbitration_policy_sql(),
    gene_summaries = paste(
      "CREATE OR REPLACE VIEW clinvar_gene_summaries AS WITH gene_decisions AS (SELECT DISTINCT",
      "d.policy_version, d.profile_id, d.release_id, d.vcv_accession, d.allele_id,",
      "d.disease_key, d.policy_classification, d.gold_stars, d.latest_date_last_evaluated,",
      "coalesce('ncbigene:' || cast(g.gene_id AS VARCHAR),",
      "'hgnc:' || g.hgnc_id, 'symbol:' || upper(g.symbol)) AS gene_key,",
      "g.gene_id, g.symbol, g.hgnc_id, g.full_name FROM clinvar_genes g",
      "JOIN clinvar_alleles a ON a.release_id = g.release_id",
      "AND a.allele_entity_id = g.allele_entity_id",
      "JOIN clinvar_policy_decisions d ON d.release_id = a.release_id",
      "AND d.vcv_accession = a.vcv_accession AND d.allele_id = a.allele_id",
      "WHERE g.gene_id IS NOT NULL OR g.hgnc_id IS NOT NULL OR g.symbol IS NOT NULL)",
      "SELECT policy_version, profile_id, release_id, gene_key, max(gene_id) AS gene_id,",
      "max(symbol) AS symbol, max(hgnc_id) AS hgnc_id, max(full_name) AS full_name,",
      "count(*) AS disease_decision_count, count(DISTINCT disease_key) AS disease_count,",
      "count(DISTINCT vcv_accession) AS variant_count,",
      "count(DISTINCT allele_id) AS allele_count,",
      "count(*) FILTER (WHERE policy_classification = 'Pathogenic/Likely Pathogenic')",
      "AS pathogenic_disease_decision_count,",
      "count(DISTINCT allele_id) FILTER",
      "(WHERE policy_classification = 'Pathogenic/Likely Pathogenic') AS pathogenic_allele_count,",
      "count(*) FILTER (WHERE policy_classification = 'Benign') AS benign_disease_decision_count,",
      "count(*) FILTER (WHERE policy_classification = 'VUS') AS vus_disease_decision_count,",
      "count(*) FILTER (WHERE policy_classification = 'Conflicting')",
      "AS conflicting_disease_decision_count, max(gold_stars) AS maximum_gold_stars,",
      "max(latest_date_last_evaluated) AS latest_date_last_evaluated",
      "FROM gene_decisions GROUP BY policy_version, profile_id, release_id, gene_key"
    ),
    gene_disease_summaries = paste(
      "CREATE OR REPLACE VIEW clinvar_gene_disease_summaries AS",
      "WITH gene_decisions AS (SELECT DISTINCT",
      "d.policy_version, d.profile_id, d.release_id, d.vcv_accession,",
      "d.allele_id, d.disease_key, d.disease_database, d.disease_identifier,",
      "d.disease_name, d.policy_classification, d.gold_stars,",
      "d.retained_submission_count, d.retained_scv_count,",
      "d.retained_submitter_count, d.latest_date_last_evaluated,",
      "coalesce('ncbigene:' || cast(g.gene_id AS VARCHAR),",
      "'hgnc:' || g.hgnc_id, 'symbol:' || upper(g.symbol)) AS gene_key,",
      "g.gene_id, g.symbol, g.hgnc_id, g.full_name",
      "FROM clinvar_genes g JOIN clinvar_alleles a",
      "ON a.release_id = g.release_id",
      "AND a.allele_entity_id = g.allele_entity_id",
      "JOIN clinvar_policy_decisions d ON d.release_id = a.release_id",
      "AND d.vcv_accession = a.vcv_accession AND d.allele_id = a.allele_id",
      "WHERE g.gene_id IS NOT NULL OR g.hgnc_id IS NOT NULL",
      "OR g.symbol IS NOT NULL), summarized AS (SELECT",
      "policy_version, profile_id, release_id, gene_key,",
      "max(gene_id) AS gene_id, max(symbol) AS symbol,",
      "max(hgnc_id) AS hgnc_id, max(full_name) AS full_name,",
      "disease_key, max(disease_database) AS disease_database,",
      "max(disease_identifier) AS disease_identifier,",
      "max(disease_name) AS disease_name, count(*) AS disease_decision_count,",
      "count(DISTINCT vcv_accession) AS variant_count,",
      "count(DISTINCT allele_id) AS allele_count,",
      "count(*) FILTER (WHERE policy_classification =",
      "'Pathogenic/Likely Pathogenic') AS pathogenic_decision_count,",
      "count(*) FILTER (WHERE policy_classification = 'Benign')",
      "AS benign_decision_count,",
      "count(*) FILTER (WHERE policy_classification = 'VUS')",
      "AS vus_decision_count,",
      "count(*) FILTER (WHERE policy_classification = 'Conflicting')",
      "AS conflicting_decision_count,",
      "max(gold_stars) AS maximum_gold_stars,",
      "max(retained_submitter_count) AS maximum_retained_submitter_count,",
      "sum(retained_scv_count) AS retained_scv_count,",
      "max(latest_date_last_evaluated) AS latest_date_last_evaluated,",
      "count(*) FILTER (WHERE policy_classification =",
      "'Pathogenic/Likely Pathogenic' AND gold_stars >= 3)",
      "AS expert_reviewed_pathogenic_decision_count,",
      "count(*) FILTER (WHERE policy_classification =",
      "'Pathogenic/Likely Pathogenic' AND retained_submitter_count >= 2)",
      "AS multi_submitter_pathogenic_decision_count",
      "FROM gene_decisions GROUP BY policy_version, profile_id, release_id,",
      "gene_key, disease_key), stratified AS (SELECT *, CASE",
      "WHEN expert_reviewed_pathogenic_decision_count > 0",
      "THEN 'expert_reviewed_pathogenic'",
      "WHEN multi_submitter_pathogenic_decision_count > 0",
      "THEN 'multi_submitter_pathogenic'",
      "WHEN pathogenic_decision_count > 0 THEN 'reported_pathogenic'",
      "WHEN conflicting_decision_count > 0 THEN 'conflicting'",
      "WHEN vus_decision_count > 0 THEN 'uncertain'",
      "WHEN benign_decision_count > 0 THEN 'benign_only'",
      "ELSE 'no_classified_evidence' END AS clinvar_evidence_stratum",
      "FROM summarized) SELECT * FROM stratified"
    )
  )
}

#' Initialize the ClinVar relational schema
#'
#' @param con A DuckDB DBI connection.
#' @return `con`, invisibly.
#' @export
rclinvarbitration_init <- function(con) {
  layout <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT table_name, table_type FROM information_schema.tables",
      "WHERE table_schema = current_schema()",
      "AND table_name IN ('clinvar', 'clinvar_variants')"
    )
  )
  has_canonical <- any(
    layout$table_name == "clinvar" & layout$table_type == "BASE TABLE"
  )
  has_legacy <- any(
    layout$table_name == "clinvar_variants" &
      layout$table_type == "BASE TABLE"
  )
  if (has_legacy && !has_canonical) {
    stop(
      "This database uses the retired multi-table ClinVar layout. ",
      "Import the release into a new database; in-place initialization would ",
      "replace legacy table names with compatibility views.",
      call. = FALSE
    )
  }
  for (statement in unname(rclinvarbitration_schema_sql())) DBI::dbExecute(con, statement)
  invisible(con)
}

rclinvarbitration_import_statements <- function(release_sql) {
  field <- function(name) paste0("rclinvar_json_field(fields_json, '", name, "')")
  insert <- function(entity_type, fields = character()) {
    common <- c(
      release_id = release_sql,
      record_kind = rclinvarbitration_sql_string(entity_type),
      record_key = paste0(
        rclinvarbitration_sql_string(entity_type), " || '|' || entity_id"
      ),
      record_ordinal = "record_ordinal",
      entity_ordinal = "entity_ordinal",
      vcv_accession = "vcv_accession",
      rcv_entity_id = "rcv_entity_id",
      scv_entity_id = "scv_entity_id",
      entity_id = "entity_id",
      parent_type = "parent_type",
      parent_id = "parent_id"
    )
    values <- c(common, fields)
    paste0(
      "INSERT INTO clinvar (", paste(names(values), collapse = ", "), ") SELECT ",
      paste(unname(values), collapse = ", "),
      " FROM rclinvarbitration_import_entities WHERE entity_type = ",
      rclinvarbitration_sql_string(entity_type)
    )
  }
  c(
    variants = insert(
      "variation",
      c(
        vcv_version = paste0("try_cast(", field("version"), " AS UINTEGER)"),
        variation_id = paste0("try_cast(", field("variation_id"), " AS UBIGINT)"),
        variation_name = field("variation_name"),
        variation_type = field("variation_type"),
        record_type = field("record_type"),
        record_status = field("record_status"),
        species = field("species"),
        date_created = paste0("try_cast(", field("date_created"), " AS DATE)"),
        date_last_updated = paste0(
          "try_cast(", field("date_last_updated"), " AS DATE)"
        ),
        most_recent_submission = paste0(
          "try_cast(", field("most_recent_submission"), " AS DATE)"
        ),
        number_of_submissions = paste0(
          "try_cast(", field("number_of_submissions"), " AS UINTEGER)"
        ),
        number_of_submitters = paste0(
          "try_cast(", field("number_of_submitters"), " AS UINTEGER)"
        ),
        classification = field("classification"),
        review_status = field("review_status"),
        date_last_evaluated = paste0(
          "try_cast(", field("date_last_evaluated"), " AS DATE)"
        )
      )
    ),
    alleles = insert(
      "allele",
      c(
        parent_allele_entity_id = "CASE WHEN parent_type = 'allele' THEN parent_id END",
        allele_id = paste0("try_cast(", field("allele_id"), " AS UBIGINT)"),
        variation_id = paste0("try_cast(", field("variation_id"), " AS UBIGINT)"),
        allele_name = field("name"),
        variant_type = field("variant_type"),
        canonical_spdi = field("canonical_spdi")
      )
    ),
    locations = insert(
      "location",
      c(
        assembly = field("assembly"),
        assembly_accession_version = field("assembly_accession_version"),
        assembly_status = field("assembly_status"),
        chromosome = field("chr"),
        sequence_accession = field("accession"),
        start = paste0("try_cast(", field("start"), " AS UBIGINT)"),
        stop = paste0("try_cast(", field("stop"), " AS UBIGINT)"),
        position_vcf = paste0(
          "try_cast(", field("position_vcf"), " AS UBIGINT)"
        ),
        reference_allele_vcf = field("reference_allele_vcf"),
        alternate_allele_vcf = field("alternate_allele_vcf"),
        for_display = paste0("try_cast(", field("for_display"), " AS BOOLEAN)")
      )
    ),
    genes = insert(
      "gene",
      c(
        gene_id = paste0("try_cast(", field("gene_id"), " AS UBIGINT)"),
        gene_symbol = field("symbol"),
        hgnc_id = field("hgnc_id"),
        gene_name = field("full_name"),
        relationship_type = field("relationship_type"),
        source = field("source")
      )
    ),
    rcvs = insert(
      "rcv_assertion",
      c(
        accession = "entity_id",
        version = paste0("try_cast(", field("version"), " AS UINTEGER)"),
        title = field("title"),
        classification = field("classification"),
        review_status = field("review_status"),
        date_last_evaluated = paste0(
          "try_cast(", field("date_last_evaluated"), " AS DATE)"
        ),
        submission_count = paste0(
          "try_cast(", field("submission_count"), " AS UINTEGER)"
        )
      )
    ),
    scvs = insert(
      "scv_assertion",
      c(
        source_ordinal = "entity_ordinal",
        assertion_id = paste0("try_cast(", field("id"), " AS UBIGINT)"),
        accession = field("scv_accession"),
        version = paste0("try_cast(", field("scv_version"), " AS UINTEGER)"),
        submitter_name = field("submitter_name"),
        submitter_id = paste0("try_cast(", field("submitter_id"), " AS UBIGINT)"),
        organization_category = field("organization_category"),
        organization_abbreviation = field("organization_abbreviation"),
        local_key = field("local_key"),
        submitted_assembly = field("submitted_assembly"),
        submission_title = field("submission_title"),
        assertion_type = field("assertion_type"),
        record_status = field("record_status"),
        classification = field("classification"),
        review_status = field("review_status"),
        date_last_evaluated = paste0(
          "try_cast(", field("date_last_evaluated"), " AS DATE)"
        ),
        submission_date = paste0(
          "try_cast(", field("submission_date"), " AS DATE)"
        ),
        date_created = paste0("try_cast(", field("date_created"), " AS DATE)"),
        date_last_updated = paste0(
          "try_cast(", field("date_last_updated"), " AS DATE)"
        ),
        contributes_to_aggregate_classification = paste0(
          "try_cast(", field("contributes_to_aggregate_classification"),
          " AS BOOLEAN)"
        )
      )
    ),
    conditions = insert(
      "condition",
      c(
        context_type = "parent_type",
        context_id = "parent_id",
        trait_id = field("id"),
        trait_type = field("type"),
        trait_set_id = field("trait_set_id"),
        trait_set_type = field("trait_set_type"),
        preferred_name = field("preferred_name"),
        database_name = field("db"),
        database_id = field("id"),
        contributes_to_aggregate_classification = paste0(
          "try_cast(", field("contributes_to_aggregate_classification"),
          " AS BOOLEAN)"
        )
      )
    ),
    condition_names = insert(
      "condition_name",
      c(
        name_type = field("type"),
        value_text = field("value")
      )
    ),
    xrefs = insert(
      "xref",
      c(
        context_type = "parent_type",
        context_id = "parent_id",
        database_name = field("db"),
        database_id = field("id"),
        xref_type = field("type")
      )
    ),
    observations = insert(
      "observation",
      c(
        origin = field("origin"),
        species = field("species"),
        affected_status = field("affected_status"),
        number_tested = paste0("try_cast(", field("number_tested"), " AS UINTEGER)"),
        method_type = field("method_type")
      )
    ),
    citations = insert(
      "citation",
      c(
        context_type = "parent_type",
        context_id = "parent_id",
        citation_type = field("type"),
        abbreviation = field("abbrev"),
        url = field("url")
      )
    ),
    citation_identifiers = insert(
      "citation_identifier",
      c(
        identifier_source = field("source"),
        identifier = field("identifier")
      )
    ),
    attributes = insert(
      "attribute",
      c(
        context_type = "parent_type",
        context_id = "parent_id",
        attribute_type = field("type"),
        integer_value = paste0(
          "try_cast(", field("integer_value"), " AS BIGINT)"
        ),
        value_text = field("value")
      )
    ),
    text_elements = insert(
      "text",
      c(
        context_type = "parent_type",
        context_id = "parent_id",
        section = paste0("coalesce(", field("section"), ", 'text')"),
        text_value = field("value")
      )
    )
  )
}

#' Stream a ClinVar VCV XML release into one relational DuckDB table
#'
#' The native extension reads `.xml` and `.xml.gz` with a libxml2 forward
#' reader. One compact row per selected ClinVar entity is written to temporary
#' spill-backed staging in one XML pass, projected into the scalar `clinvar`
#' table, and dropped. Repeated XML entities become additional rows; no XML DOM,
#' durable JSON, nested value, generic parser-node graph, or R data-frame
#' materialization is used. Compatibility relations are views over `clinvar`.
#'
#' @param con A DuckDB DBI connection.
#' @param path Path to an official ClinVar VCV XML or XML.GZ release.
#' @param release_id User-supplied release label stored with every row.
#' @param replace Replace rows already stored for `release_id`?
#' @param source_url Optional source URL for the release catalogue. When `path`
#'   is returned directly by [rclinvarbitration_download_clinvar()], its download
#'   metadata supplies this value automatically.
#' @param source_md5 Optional 32-character source MD5 digest. Download metadata
#'   is used automatically when available.
#' @return A named numeric vector with imported entity counts.
#' @export
rclinvarbitration_import_xml <- function(
    con, path, release_id, replace = FALSE,
    source_url = NULL, source_md5 = NULL) {
  download <- attr(path, "download", exact = TRUE)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("`path` must name an existing ClinVar XML or XML.GZ file.", call. = FALSE)
  }
  if (is.data.frame(download) && nrow(download) == 1L &&
      all(c("url", "md5") %in% names(download))) {
    if (is.null(source_url)) source_url <- download$url[[1L]]
    if (is.null(source_md5) && !is.na(download$md5[[1L]])) source_md5 <- download$md5[[1L]]
  }
  validate_optional_text <- function(value, name) {
    if (!is.null(value) && (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value))) {
      stop("`", name, "` must be NULL or a non-empty character scalar.", call. = FALSE)
    }
  }
  validate_optional_text(source_url, "source_url")
  validate_optional_text(source_md5, "source_md5")
  if (!is.null(source_md5) && !grepl("^[[:xdigit:]]{32}$", source_md5)) {
    stop("`source_md5` must be a 32-character hexadecimal MD5 digest.", call. = FALSE)
  }
  if (!is.character(release_id) || length(release_id) != 1L || is.na(release_id) || !nzchar(release_id)) {
    stop("`release_id` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.logical(replace) || length(replace) != 1L || is.na(replace)) {
    stop("`replace` must be TRUE or FALSE.", call. = FALSE)
  }
  rclinvarbitration_init(con)
  release_sql <- rclinvarbitration_sql_string(release_id)
  source_bytes <- unname(file.info(path)$size)
  source_path <- normalizePath(path, mustWork = TRUE)
  path_sql <- rclinvarbitration_sql_string(source_path)
  source_url_sql <- if (is.null(source_url)) "NULL" else rclinvarbitration_sql_string(source_url)
  source_md5_sql <- if (is.null(source_md5)) "NULL" else rclinvarbitration_sql_string(tolower(source_md5))
  existing <- DBI::dbGetQuery(
    con,
    paste0("SELECT count(*) AS n FROM clinvar_releases WHERE release_id = ", release_sql)
  )$n[[1L]]
  if (existing > 0 && !replace) {
    stop("`release_id` already exists; use `replace = TRUE` to replace it.", call. = FALSE)
  }

  tables <- c("clinvar", "clinvar_releases")
  staging_table <- "rclinvarbitration_import_entities"
  import_started <- FALSE
  import_complete <- FALSE
  delete_release <- function() {
    for (table in tables) {
      DBI::dbExecute(con, paste0("DELETE FROM ", table, " WHERE release_id = ", release_sql))
    }
  }
  on.exit({
    if (import_started && !import_complete) {
      for (table in tables) {
        try(
          DBI::dbExecute(con, paste0("DELETE FROM ", table, " WHERE release_id = ", release_sql)),
          silent = TRUE
        )
      }
    }
    try(DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", staging_table)), silent = TRUE)
  }, add = TRUE)

  # Materialize before mutating an existing release. TEMP keeps the import
  # high-water mark out of the durable catalogue; DuckDB may spill its blocks
  # to temp_directory under the configured memory limit.
  DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", staging_table))
  DBI::dbExecute(
    con,
    paste0(
      "CREATE TEMP TABLE ", staging_table,
      " AS SELECT * FROM clinvar_xml_entities(", path_sql, ")"
    )
  )

  # Each record kind is appended as one contiguous block. A release catalogue
  # row is written only after every kind succeeds, and on-exit cleanup removes
  # partial rows after an error.
  import_started <- TRUE
  # Clear both a complete replaced release and any rows left by a process that
  # was terminated before its release catalogue marker could be written.
  delete_release()
  for (statement in rclinvarbitration_import_statements(release_sql)) DBI::dbExecute(con, statement)
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO clinvar_releases ",
      "(release_id, source_path, source_url, source_md5, source_bytes, source_kind) VALUES (",
      release_sql, ", ", path_sql, ", ", source_url_sql, ", ", source_md5_sql,
      ", ", sprintf("%.0f", source_bytes), ", 'vcv_xml')"
    )
  )
  import_complete <- TRUE
  DBI::dbExecute(con, paste("DROP TABLE", staging_table))

  count_kinds <- c(
    variants = "variation",
    alleles = "allele",
    rcv_assertions = "rcv_assertion",
    scv_assertions = "scv_assertion",
    conditions = "condition",
    observations = "observation",
    citations = "citation",
    text = "text"
  )
  vapply(count_kinds, function(kind) {
    DBI::dbGetQuery(
      con,
      paste0(
        "SELECT count(*) AS n FROM clinvar WHERE release_id = ", release_sql,
        " AND record_kind = ", rclinvarbitration_sql_string(kind)
      )
    )$n[[1L]]
  }, numeric(1))
}
