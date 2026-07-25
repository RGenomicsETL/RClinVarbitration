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
    paste0(
      "(SELECT release_id, vcv_accession, variation_id, allele_id, ",
      "classification AS policy_classification, gold_stars, profile_id ",
      "FROM clinvar WHERE record_kind = 'decision' UNION ALL ",
      "SELECT p.release_id, p.vcv_accession, p.variation_id, p.allele_id, ",
      "p.policy_classification, p.gold_stars, p.profile_id ",
      "FROM clinvar_policy_allele_decisions p WHERE NOT EXISTS (",
      "SELECT 1 FROM clinvar d WHERE d.release_id = p.release_id ",
      "AND d.record_kind = 'decision' AND d.profile_id = p.profile_id ",
      "AND d.allele_id IS NOT DISTINCT FROM p.allele_id)) p "
    )
  } else {
    paste0("(", policy_query, ") p ")
  }
  paste0(
    "SELECT DISTINCT ",
    "l.contig, cast(l.position AS INTEGER) AS position, ",
    "l.reference, l.alternate, ",
    "p.policy_classification AS clinical_significance, ",
    "cast(p.gold_stars AS INTEGER) AS gold_stars, cast(p.allele_id AS INTEGER) AS allele_id ",
    "FROM ", policy_source,
    "JOIN clinvar_vcf l ON l.release_id = p.release_id ",
    "AND l.allele_id IS NOT DISTINCT FROM p.allele_id ",
    "WHERE p.release_id = ", release_sql, " AND p.profile_id = ", profile_sql,
    " AND l.assembly = ", assembly_sql,
    "AND lower(l.reference) <> 'na' AND lower(l.alternate) <> 'na' ",
    "AND l.reference <> l.alternate ",
    "AND length(l.reference) + length(l.alternate) <= 40 ",
    "AND regexp_full_match(l.reference, '^[ACGTN]+$') ",
    "AND regexp_full_match(l.alternate, '^[ACGTN]+$') ",
    "QUALIFY CASE WHEN l.sequence_accession IS NULL OR ",
    "starts_with(l.sequence_accession, 'NC_') THEN 0 ELSE 1 END = ",
    "min(CASE WHEN l.sequence_accession IS NULL OR ",
    "starts_with(l.sequence_accession, 'NC_') THEN 0 ELSE 1 END) OVER (",
    "PARTITION BY l.release_id, l.allele_id, l.assembly)"
  )
}

rclinvarbitration_tidy_select_sql <- function(
    release_sql, assembly_sql, profile_sql) {
  paste0(
    "WITH source_rows AS (SELECT * EXCLUDE (release_id) FROM clinvar ",
    "WHERE release_id = ", release_sql, " AND record_kind <> 'decision' ",
    "AND (record_kind <> 'location' OR assembly = ", assembly_sql, ")), ",
    "stored_decision_rows AS (SELECT * EXCLUDE (release_id) FROM clinvar ",
    "WHERE release_id = ", release_sql, " AND record_kind = 'decision' ",
    "AND profile_id = ", profile_sql, "), computed_decision_rows AS (SELECT ",
    "'decision' AS record_kind, ",
    "'decision|' || p.vcv_accession || '|' || cast(p.allele_id AS VARCHAR) ",
    "|| '|' || p.profile_id AS record_key, a.record_ordinal, ",
    "a.record_ordinal AS entity_ordinal, p.vcv_accession, ",
    "'decision:' || p.vcv_accession || ':' || cast(p.allele_id AS VARCHAR) ",
    "|| ':' || p.profile_id AS entity_id, 'allele' AS parent_type, ",
    "a.allele_entity_id AS parent_id, p.variation_id, p.allele_id, ",
    "p.policy_classification AS classification, p.policy_version, p.profile_id, ",
    "p.gold_stars FROM clinvar_policy_allele_decisions p ",
    "JOIN clinvar_alleles a ON a.release_id = p.release_id ",
    "AND a.vcv_accession = p.vcv_accession ",
    "AND a.allele_id IS NOT DISTINCT FROM p.allele_id ",
    "AND a.parent_allele_entity_id IS NULL WHERE p.release_id = ", release_sql,
    " AND p.profile_id = ", profile_sql, " AND NOT EXISTS (SELECT 1 FROM ",
    "stored_decision_rows d WHERE d.allele_id IS NOT DISTINCT FROM p.allele_id)) ",
    "SELECT * FROM source_rows UNION ALL BY NAME SELECT * FROM stored_decision_rows ",
    "UNION ALL BY NAME SELECT * FROM computed_decision_rows"
  )
}

rclinvarbitration_export_tidy_parquet <- function(
    con, path, release_sql, assembly_sql, profile_sql) {
  rclinvarbitration_tidy_select_sql(
    release_sql = release_sql,
    assembly_sql = assembly_sql,
    profile_sql = profile_sql
  )
}

#' Export ClinVarbitration decisions to Parquet
#'
#' `schema = "compatibility"` writes the seven columns in Centre for Population
#' Genomics ClinVarbitration's `clinvar_decisions.tsv`: `contig`, `position`,
#' `reference`, `alternate`, `clinical_significance`, `gold_stars`, and
#' `allele_id`.
#'
#' `schema = "tidy"` writes the canonical scalar `clinvar` relation.
#' `record_kind` distinguishes variations, alleles, assembly locations, source
#' assertions, conditions, genes, observations, citations, text, attributes,
#' and policy decisions. Every row has its own stable `record_key`; repeated
#' source elements are rows rather than lists or structs. `release_id` is kept
#' in the release receipt rather than copied into every Parquet row.
#'
#' The compatibility source is the allele-level policy view joined through
#' `clinvar_vcf`. Both GRCh37 and GRCh38 are supported, including distinct X/Y
#' locations for one AlleleID. Primary `NC_` placements take precedence when
#' present. An allele available only on alternate placements retains its exact
#' sequence accession and is not mislabeled as a primary-chromosome VCF record.
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
#'   or the canonical scalar evidence relation.
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
    schema = c("compatibility", "tidy")) {
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
  if (identical(schema, "tidy") && length(submitter_exclusions)) {
    stop(
      "`schema = \"tidy\"` requires a named policy profile; store ",
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
    rclinvarbitration_export_tidy_parquet(
      con = con,
      path = path,
      release_sql = release_sql,
      assembly_sql = assembly_sql,
      profile_sql = profile_sql
    )
  }
  DBI::dbExecute(
    con,
    paste0(
      "COPY (", select_sql,
      ") TO ", rclinvarbitration_sql_string(path),
      " (FORMAT PARQUET, COMPRESSION ZSTD)"
    )
  )
  n_rows <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS n FROM read_parquet(",
      rclinvarbitration_sql_string(path), ")"
    )
  )$n[[1L]]
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
