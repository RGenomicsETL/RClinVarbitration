rclinvarbitration_validate_profile <- function(con, profile_id) {
  version_sql <- rclinvarbitration_sql_string(rclinvarbitration_policy_version())
  profile_sql <- rclinvarbitration_sql_string(profile_id)
  n_profile <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS n FROM clinvar_policy_profiles WHERE policy_version = ",
      version_sql, " AND profile_id = ", profile_sql
    )
  )$n[[1L]]
  if (n_profile != 1) {
    stop("`profile_id` is not a configured ClinVarbitration policy profile.", call. = FALSE)
  }
  invisible(NULL)
}

rclinvarbitration_compatibility_select_sql <- function(
    release_sql, assembly_sql, profile_sql, policy_query = NULL) {
  policy_source <- if (is.null(policy_query)) {
    "clinvar_policy_allele_decisions p "
  } else {
    paste0("(", policy_query, ") p ")
  }
  paste0(
    "SELECT DISTINCT ",
    "CASE WHEN l.assembly = 'GRCh38' THEN ",
    "CASE WHEN l.chromosome IN ('M', 'MT') THEN 'chrM' ELSE 'chr' || l.chromosome END ",
    "ELSE CASE WHEN l.chromosome = 'MT' THEN 'M' ELSE l.chromosome END END AS contig, ",
    "cast(l.position_vcf AS INTEGER) AS position, ",
    "l.reference_allele_vcf AS reference, l.alternate_allele_vcf AS alternate, ",
    "p.policy_classification AS clinical_significance, ",
    "cast(p.gold_stars AS INTEGER) AS gold_stars, cast(p.allele_id AS INTEGER) AS allele_id ",
    "FROM ", policy_source,
    "JOIN clinvar_alleles a ON a.release_id = p.release_id ",
    "AND a.vcv_accession = p.vcv_accession AND a.allele_id = p.allele_id ",
    "AND a.parent_allele_entity_id IS NULL ",
    "JOIN clinvar_locations l ON l.release_id = a.release_id ",
    "AND l.vcv_accession = a.vcv_accession AND l.allele_entity_id = a.allele_entity_id ",
    "WHERE p.release_id = ", release_sql, " AND p.profile_id = ", profile_sql,
    " AND l.assembly = ", assembly_sql,
    " AND l.chromosome IN ('1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', ",
    "'12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', 'X', 'Y', 'M', 'MT') ",
    " AND l.position_vcf IS NOT NULL AND l.reference_allele_vcf IS NOT NULL ",
    "AND l.alternate_allele_vcf IS NOT NULL ",
    "AND lower(l.reference_allele_vcf) <> 'na' AND lower(l.alternate_allele_vcf) <> 'na' ",
    "AND l.reference_allele_vcf <> l.alternate_allele_vcf ",
    "AND length(l.reference_allele_vcf) + length(l.alternate_allele_vcf) <= 40 ",
    "AND regexp_full_match(l.reference_allele_vcf, '^[ACGTN]+$') ",
    "AND regexp_full_match(l.alternate_allele_vcf, '^[ACGTN]+$')"
  )
}

rclinvarbitration_enhanced_select_sql <- function(
    release_sql, assembly_sql, profile_sql) {
  content_columns <- c(
    "record_key", "assembly", "contig", "position", "reference", "alternate",
    "policy_version", "profile_id", "vcv_accession", "variation_id",
    "allele_id", "disease_key", "disease_database", "disease_identifier",
    "disease_name", "clinical_significance", "gold_stars",
    "modern_filter_applied", "eligible_submission_count",
    "retained_submission_count", "retained_scv_count",
    "retained_submitter_count", "pathogenic_count", "benign_count",
    "uncertain_count", "latest_date_last_evaluated", "scv_submissions",
    "rcv_aggregates", "genes"
  )
  content_receipt_sql <- paste(
    paste0(
      "coalesce(cast(", content_columns, " AS VARCHAR), '<NULL>')"
    ),
    collapse = ", "
  )
  paste0(
    "WITH scv_rows AS (SELECT DISTINCT d.release_id, d.vcv_accession, ",
    "d.allele_id, d.disease_key, d.assertion_entity_id, d.scv_accession, ",
    "d.scv_version, d.submitter_name, d.submitter_id, d.classification, ",
    "d.review_status, d.date_last_evaluated, d.submission_date ",
    "FROM clinvar_disease_submissions d WHERE d.release_id = ", release_sql,
    "), scv_sources AS (SELECT release_id, vcv_accession, allele_id, ",
    "disease_key, list(struct_pack(",
    "assertion_entity_id := assertion_entity_id, accession := scv_accession, ",
    "version := scv_version, submitter_name := submitter_name, ",
    "submitter_id := submitter_id, classification := classification, ",
    "review_status := review_status, ",
    "date_last_evaluated := date_last_evaluated, ",
    "submission_date := submission_date) ORDER BY ",
    "coalesce(scv_accession, ''), scv_version, assertion_entity_id) ",
    "AS scv_submissions FROM scv_rows GROUP BY release_id, vcv_accession, ",
    "allele_id, disease_key), ",
    "rcv_rows AS (SELECT DISTINCT release_id, vcv_accession, allele_id, ",
    "disease_key, disease_database, disease_identifier, disease_name, ",
    "rcv_accession, rcv_version, rcv_title, ",
    "aggregate_classification, aggregate_review_status, ",
    "aggregate_date_last_evaluated, submission_count ",
    "FROM clinvar_disease_aggregates WHERE release_id = ", release_sql,
    "), rcv_sources AS (SELECT release_id, vcv_accession, allele_id, ",
    "list(struct_pack(disease_key := disease_key, ",
    "disease_database := disease_database, ",
    "disease_identifier := disease_identifier, disease_name := disease_name, ",
    "accession := rcv_accession, ",
    "version := rcv_version, title := rcv_title, ",
    "classification := aggregate_classification, ",
    "review_status := aggregate_review_status, ",
    "date_last_evaluated := aggregate_date_last_evaluated, ",
    "submission_count := submission_count) ORDER BY ",
    "rcv_accession, rcv_version) AS rcv_aggregates FROM rcv_rows ",
    "GROUP BY release_id, vcv_accession, allele_id), ",
    "gene_rows AS (SELECT DISTINCT a.release_id, a.vcv_accession, a.allele_id, ",
    "coalesce('ncbigene:' || cast(g.gene_id AS VARCHAR), ",
    "'hgnc:' || g.hgnc_id, 'symbol:' || upper(g.symbol)) AS gene_key, ",
    "g.gene_id, g.symbol, g.hgnc_id, g.full_name ",
    "FROM clinvar_genes g JOIN clinvar_alleles a ",
    "ON a.release_id = g.release_id ",
    "AND a.allele_entity_id = g.allele_entity_id ",
    "WHERE g.release_id = ", release_sql, " AND ",
    "(g.gene_id IS NOT NULL OR g.hgnc_id IS NOT NULL OR g.symbol IS NOT NULL)",
    "), gene_sources AS (SELECT release_id, vcv_accession, allele_id, ",
    "list(struct_pack(gene_key := gene_key, gene_id := gene_id, ",
    "symbol := symbol, hgnc_id := hgnc_id, full_name := full_name) ",
    "ORDER BY gene_key) AS genes FROM gene_rows ",
    "GROUP BY release_id, vcv_accession, allele_id), ",
    "decision_rows AS (SELECT l.assembly, ",
    "CASE WHEN l.assembly = 'GRCh38' THEN ",
    "CASE WHEN l.chromosome IN ('M', 'MT') THEN 'chrM' ",
    "ELSE 'chr' || l.chromosome END ",
    "ELSE CASE WHEN l.chromosome = 'MT' THEN 'M' ELSE l.chromosome END ",
    "END AS contig, cast(l.position_vcf AS INTEGER) AS position, ",
    "l.reference_allele_vcf AS reference, ",
    "l.alternate_allele_vcf AS alternate, p.policy_version, p.profile_id, ",
    "p.vcv_accession, p.variation_id, p.allele_id, p.disease_key, ",
    "p.disease_database, p.disease_identifier, p.disease_name, ",
    "p.policy_classification AS clinical_significance, ",
    "cast(p.gold_stars AS INTEGER) AS gold_stars, ",
    "p.modern_filter_applied, p.eligible_submission_count, ",
    "p.retained_submission_count, p.retained_scv_count, ",
    "p.retained_submitter_count, p.pathogenic_count, p.benign_count, ",
    "p.uncertain_count, p.latest_date_last_evaluated, ",
    "s.scv_submissions, r.rcv_aggregates, g.genes ",
    "FROM clinvar_policy_decisions p ",
    "JOIN clinvar_alleles a ON a.release_id = p.release_id ",
    "AND a.vcv_accession = p.vcv_accession AND a.allele_id = p.allele_id ",
    "AND a.parent_allele_entity_id IS NULL ",
    "JOIN clinvar_locations l ON l.release_id = a.release_id ",
    "AND l.vcv_accession = a.vcv_accession ",
    "AND l.allele_entity_id = a.allele_entity_id ",
    "LEFT JOIN scv_sources s ON s.release_id = p.release_id ",
    "AND s.vcv_accession = p.vcv_accession ",
    "AND s.allele_id IS NOT DISTINCT FROM p.allele_id ",
    "AND s.disease_key = p.disease_key ",
    "LEFT JOIN rcv_sources r ON r.release_id = p.release_id ",
    "AND r.vcv_accession = p.vcv_accession ",
    "AND r.allele_id IS NOT DISTINCT FROM p.allele_id ",
    "LEFT JOIN gene_sources g ON g.release_id = p.release_id ",
    "AND g.vcv_accession = p.vcv_accession ",
    "AND g.allele_id IS NOT DISTINCT FROM p.allele_id ",
    "WHERE p.release_id = ", release_sql, " AND p.profile_id = ", profile_sql,
    " AND l.assembly = ", assembly_sql,
    " AND l.chromosome IN ('1', '2', '3', '4', '5', '6', '7', '8', '9', ",
    "'10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', ",
    "'21', '22', 'X', 'Y', 'M', 'MT') ",
    "AND l.position_vcf IS NOT NULL AND l.reference_allele_vcf IS NOT NULL ",
    "AND l.alternate_allele_vcf IS NOT NULL ",
    "AND lower(l.reference_allele_vcf) <> 'na' ",
    "AND lower(l.alternate_allele_vcf) <> 'na' ",
    "AND l.reference_allele_vcf <> l.alternate_allele_vcf ",
    "AND length(l.reference_allele_vcf) + length(l.alternate_allele_vcf) <= 40 ",
    "AND regexp_full_match(l.reference_allele_vcf, '^[ACGTN]+$') ",
    "AND regexp_full_match(l.alternate_allele_vcf, '^[ACGTN]+$')) ",
    ", keyed_rows AS (SELECT concat_ws('|', policy_version, profile_id, ",
    "assembly, contig, ",
    "cast(position AS VARCHAR), reference, alternate, vcv_accession, ",
    "cast(allele_id AS VARCHAR), disease_key) AS record_key, * ",
    "FROM decision_rows) SELECT *, sha256(concat_ws(chr(31), ",
    content_receipt_sql, ")) AS content_sha256 FROM keyed_rows"
  )
}

#' Export ClinVarbitration decisions to Parquet
#'
#' `schema = "compatibility"` writes the seven columns in Centre for Population
#' Genomics ClinVarbitration's `clinvar_decisions.tsv`: `contig`, `position`,
#' `reference`, `alternate`, `clinical_significance`, `gold_stars`, and
#' `allele_id`.
#'
#' `schema = "enhanced"` writes one disease-specific decision per assembly
#' locus and allele. It retains a stable `record_key`, a `content_sha256` over
#' the complete row, policy identity, VCV and disease identifiers, decision
#' counts and dates, and deterministically ordered nested SCV, RCV, and gene
#' receipts. The source release receipt is returned by the function rather than
#' copied into every row. A DuckLake merge can therefore skip rows whose
#' content receipt is unchanged across source snapshots.
#'
#' SCV receipts are attached to their exact disease decision. RCV receipts are
#' allele-level context and retain their own disease keys inside each nested
#' item; the exporter does not claim that an RCV disease key is equivalent to
#' an SCV key merely because both occur under the same allele.
#'
#' The compatibility source is the allele-level policy view. The enhanced
#' source is the disease-level decision view. Both GRCh37 and GRCh38 are
#' supported, and both retain every qualifying source locus, including distinct
#' X/Y locations for one AlleleID.
#'
#' The file is schema-compatible with the upstream TSV/Hail decision resource,
#' but is not claimed to be byte-for-byte equivalent: this package derives
#' submissions and locations from VCV XML, whereas upstream uses ClinVar's
#' tab-delimited submission and variant summaries. PM5 is deliberately not
#' exported; Rduckhts/DuckHTS own downstream consequence and PM5 processing.
#'
#' @param con A DuckDB DBI connection initialized with
#'   [rclinvarbitration_init()].
#' @param path New output `.parquet` file path.
#' @param release_id Imported ClinVar release label to export.
#' @param assembly Genome assembly: `"GRCh38"` or `"GRCh37"`.
#' @param schema Output schema: the upstream-compatible seven-column relation
#'   or the source-rich disease-decision relation.
#' @param profile_id Policy profile identifier, normally `"default"`.
#' @param submitter_exclusions Additional submitter names to exclude from this
#'   export. Matching is case-insensitive and ignores surrounding whitespace.
#'   These exclusions are combined with any exclusions already stored for
#'   `profile_id`; imported source submissions are not deleted.
#' @return A named list describing the written Parquet file, invisibly.
#' @export
rclinvarbitration_export_clinvarbitration_parquet <- function(
    con, path, release_id, assembly = c("GRCh38", "GRCh37"), profile_id = "default",
    submitter_exclusions = character(),
    schema = c("compatibility", "enhanced")) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("`path` must be a non-empty output file path.", call. = FALSE)
  }
  if (!is.character(release_id) || length(release_id) != 1L || is.na(release_id) || !nzchar(release_id)) {
    stop("`release_id` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.character(profile_id) || length(profile_id) != 1L || is.na(profile_id) || !nzchar(profile_id)) {
    stop("`profile_id` must be a non-empty character scalar.", call. = FALSE)
  }
  submitter_exclusions <- rclinvarbitration_normalize_submitter_exclusions(submitter_exclusions)
  assembly <- match.arg(assembly)
  schema <- match.arg(schema)
  if (identical(schema, "enhanced") && length(submitter_exclusions)) {
    stop(
      "`schema = \"enhanced\"` requires a named policy profile; store ",
      "submitter exclusions in that profile instead of passing ad hoc exclusions.",
      call. = FALSE
    )
  }
  path <- normalizePath(path, mustWork = FALSE)
  if (!dir.exists(dirname(path))) {
    stop("The parent directory of `path` does not exist.", call. = FALSE)
  }
  if (file.exists(path)) {
    stop("`path` already exists; refuse to overwrite it.", call. = FALSE)
  }

  release_sql <- rclinvarbitration_sql_string(release_id)
  assembly_sql <- rclinvarbitration_sql_string(assembly)
  n_release <- DBI::dbGetQuery(
    con,
    paste0("SELECT count(*) AS n FROM clinvar_releases WHERE release_id = ", release_sql)
  )$n[[1L]]
  if (!identical(n_release, 1)) {
    stop("`release_id` is not an imported ClinVar release.", call. = FALSE)
  }

  rclinvarbitration_validate_profile(con, profile_id)
  profile_sql <- rclinvarbitration_sql_string(profile_id)
  policy_query <- if (length(submitter_exclusions)) {
    exclusion_sql <- paste(
      rclinvarbitration_sql_string(submitter_exclusions), collapse = ", "
    )
    rclinvarbitration_allele_policy_query(
      rclinvarbitration_policy_version(),
      profile_predicate = paste0("p.profile_id = ", profile_sql),
      submitter_exclusion_predicate = paste0(
        "c.submitter_normalized NOT IN (", exclusion_sql, ")"
      )
    )
  } else {
    NULL
  }
  select_sql <- if (identical(schema, "compatibility")) {
    rclinvarbitration_compatibility_select_sql(
      release_sql = release_sql,
      assembly_sql = assembly_sql,
      profile_sql = profile_sql,
      policy_query = policy_query
    )
  } else {
    rclinvarbitration_enhanced_select_sql(
      release_sql = release_sql,
      assembly_sql = assembly_sql,
      profile_sql = profile_sql
    )
  }
  n_rows <- DBI::dbGetQuery(con, paste0("SELECT count(*) AS n FROM (", select_sql, ")"))$n[[1L]]
  DBI::dbExecute(
    con,
    paste0(
      "COPY (", select_sql,
      ") TO ", rclinvarbitration_sql_string(path),
      " (FORMAT PARQUET, COMPRESSION ZSTD)"
    )
  )
  invisible(list(
    path = path,
    rows = n_rows,
    release_id = release_id,
    assembly = assembly,
    schema = schema,
    profile_id = profile_id,
    submitter_exclusions = submitter_exclusions,
    policy_version = rclinvarbitration_policy_version(),
    release_receipt = DBI::dbGetQuery(
      con,
      paste0(
        "SELECT release_id, source_path, source_url, source_md5, source_bytes, ",
        "imported_at FROM clinvar_releases WHERE release_id = ", release_sql
      )
    )
  ))
}
