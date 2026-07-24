rclinvarbitration_flat_tidy_sql <- function(
    submission_path, variant_path, release_id, assembly, profile_id,
    submitter_exclusions = character(), record_kind = NULL) {
  if (!is.null(record_kind) &&
      (!is.character(record_kind) || length(record_kind) != 1L ||
       is.na(record_kind) ||
       !record_kind %in% c(
         "variation", "allele", "location", "decision", "scv_assertion",
         "rcv_assertion", "gene"
       ))) {
    stop("Unknown flat-import `record_kind`.", call. = FALSE)
  }
  submission_sql <- rclinvarbitration_sql_string(
    normalizePath(submission_path, mustWork = TRUE)
  )
  variant_sql <- rclinvarbitration_sql_string(
    normalizePath(variant_path, mustWork = TRUE)
  )
  excluded <- rclinvarbitration_normalize_submitter_exclusions(
    submitter_exclusions
  )
  exclusion_predicate <- if (length(excluded)) {
    paste0(
      "submitter_normalized NOT IN (",
      paste(rclinvarbitration_sql_string(excluded), collapse = ", "), ")"
    )
  } else {
    "TRUE"
  }
  decision_sql <- rclinvarbitration_reproduction_sql(
    submission_sql = submission_sql,
    variant_sql = variant_sql,
    assembly = if ("GRCh38" %in% assembly) "GRCh38" else "GRCh37",
    submitter_exclusion_predicate = exclusion_predicate
  )
  contig <- paste(
    "CASE WHEN \"Assembly\" = 'GRCh38' THEN",
    "CASE WHEN \"Chromosome\" = 'MT' THEN 'chrM'",
    "ELSE 'chr' || \"Chromosome\" END ELSE",
    "CASE WHEN \"Chromosome\" = 'MT' THEN 'M' ELSE \"Chromosome\" END END"
  )
  assemblies_sql <- paste(
    rclinvarbitration_sql_string(assembly), collapse = ", "
  )
  policy_sql <- rclinvarbitration_sql_string(
    rclinvarbitration_policy_version()
  )
  profile_sql <- rclinvarbitration_sql_string(profile_id)
  release_sql <- rclinvarbitration_sql_string(release_id)
  output_columns <- paste(
    c(
      "release_id", "record_kind", "record_key", "record_ordinal",
      "entity_ordinal", "entity_id", "parent_type", "parent_id",
      "scv_entity_id", "variation_id", "allele_id", "variation_name",
      "variation_type", "allele_name", "variant_type", "assembly",
      "chromosome", "sequence_accession", "start", "stop", "position_vcf",
      "reference_allele_vcf", "alternate_allele_vcf", "accession", "version",
      "source_ordinal", "submitter_name", "classification", "review_status",
      "date_last_evaluated", "number_of_submitters", "origin", "description",
      "submitted_phenotype_info",
      "reported_phenotype_info", "collection_method", "origin_counts",
      "submitted_gene_symbol", "explanation",
      "contributes_to_aggregate_classification", "database_id",
      "preferred_name", "gene_id", "gene_symbol", "hgnc_id",
      "policy_version", "profile_id", "gold_stars"
    ),
    collapse = ", "
  )
  kind_predicate <- if (is.null(record_kind)) {
    ""
  } else {
    paste0(
      " WHERE record_kind = ",
      rclinvarbitration_sql_string(record_kind)
    )
  }
  paste0(
    "WITH variants_read AS (SELECT *, row_number() OVER () AS source_ordinal ",
    "FROM read_csv(", variant_sql,
    ", header = true, delim = '\\t', quote = '', all_varchar = true)), ",
    "location_candidates AS (SELECT try_cast(\"#AlleleID\" AS UBIGINT) AS allele_id, ",
    "try_cast(\"VariationID\" AS UBIGINT) AS variation_id, ",
    "\"Type\" AS variation_type, \"Name\" AS variation_name, ",
    "\"Assembly\" AS assembly, \"ChromosomeAccession\" AS sequence_accession, ",
    "\"Chromosome\" AS chromosome, ", contig,
    " AS contig, try_cast(\"Start\" AS UBIGINT) AS start, ",
    "try_cast(\"Stop\" AS UBIGINT) AS stop, ",
    "try_cast(\"PositionVCF\" AS UBIGINT) AS position_vcf, ",
    "\"ReferenceAlleleVCF\" AS reference_allele_vcf, ",
    "\"AlternateAlleleVCF\" AS alternate_allele_vcf, ",
    "\"ClinicalSignificance\" AS aggregate_classification, ",
    "\"ReviewStatus\" AS aggregate_review_status, ",
    "\"LastEvaluated\" AS aggregate_date_last_evaluated, ",
    "\"NumberSubmitters\" AS aggregate_submitter_count, ",
    "\"Origin\" AS aggregate_origin, ",
    "\"RCVaccession\" AS rcv_accessions, \"PhenotypeIDS\" AS phenotype_ids, ",
    "\"PhenotypeList\" AS phenotype_names, \"GeneID\" AS gene_ids, ",
    "\"GeneSymbol\" AS gene_symbols, \"HGNC_ID\" AS hgnc_ids, ",
    "source_ordinal FROM variants_read ",
    "WHERE \"Assembly\" IN (", assemblies_sql, ")",
    " AND try_cast(\"#AlleleID\" AS UBIGINT) IS NOT NULL ",
    "AND try_cast(\"VariationID\" AS UBIGINT) IS NOT NULL), ",
    "locations AS (SELECT *, 'variation:' || cast(variation_id AS VARCHAR) ",
    "AS variation_entity_id, 'allele:' || cast(allele_id AS VARCHAR) ",
    "AS allele_entity_id, concat_ws('|', assembly, ",
    "coalesce(sequence_accession, ''), coalesce(contig, ''), ",
    "coalesce(cast(start AS VARCHAR), ''), coalesce(cast(stop AS VARCHAR), ''), ",
    "coalesce(cast(position_vcf AS VARCHAR), ''), ",
    "coalesce(reference_allele_vcf, ''), coalesce(alternate_allele_vcf, ''), ",
    "cast(variation_id AS VARCHAR), ",
    "cast(allele_id AS VARCHAR)) AS coordinate_key ",
    "FROM location_candidates QUALIFY row_number() OVER (PARTITION BY assembly, ",
    "sequence_accession, chromosome, start, stop, position_vcf, reference_allele_vcf, ",
    "alternate_allele_vcf, variation_id, allele_id ",
    "ORDER BY source_ordinal DESC) = 1), ",
    "allele_sources AS (SELECT * FROM locations QUALIFY row_number() OVER ",
    "(PARTITION BY variation_id, allele_id ORDER BY source_ordinal DESC) = 1), ",
    "variation_sources AS (SELECT * FROM allele_sources QUALIFY row_number() ",
    "OVER (PARTITION BY variation_id ORDER BY source_ordinal DESC) = 1), ",
    "submissions_source AS (SELECT *, row_number() OVER () AS source_ordinal ",
    "FROM read_csv(",
    submission_sql,
    ", skip = 18, header = true, delim = '\\t', quote = '', all_varchar = true)), ",
    "submissions_read AS (SELECT *, ",
    "row_number() OVER (PARTITION BY try_cast(\"#VariationID\" AS UBIGINT), ",
    "\"SCV\" ORDER BY source_ordinal) AS scv_occurrence FROM submissions_source), ",
    "decision_source AS (", decision_sql, "), ",
    "variation_rows AS (SELECT ", release_sql, " AS release_id, ",
    "'variation' AS record_kind, 'variation|' || cast(variation_id AS VARCHAR) ",
    "AS record_key, source_ordinal AS record_ordinal, source_ordinal ",
    "AS entity_ordinal, variation_entity_id AS entity_id, variation_id, ",
    "variation_name, variation_type, aggregate_classification AS classification, ",
    "aggregate_review_status AS review_status, CASE WHEN ",
    "aggregate_date_last_evaluated IN ('', '-') THEN NULL ELSE ",
    "try_strptime(aggregate_date_last_evaluated, '%b %d, %Y')::DATE END ",
    "AS date_last_evaluated, try_cast(aggregate_submitter_count AS UINTEGER) ",
    "AS number_of_submitters, aggregate_origin AS origin FROM variation_sources), ",
    "allele_rows AS (SELECT ", release_sql, " AS release_id, ",
    "'allele' AS record_kind, 'allele|' || cast(allele_id AS VARCHAR) ",
    "AS record_key, source_ordinal AS record_ordinal, source_ordinal ",
    "AS entity_ordinal, allele_entity_id AS entity_id, 'variation' AS parent_type, ",
    "variation_entity_id AS parent_id, variation_id, allele_id, variation_name ",
    "AS allele_name, variation_type AS variant_type FROM allele_sources), ",
    "location_rows AS (SELECT ", release_sql, " AS release_id, ",
    "'location' AS record_kind, 'location|' || coordinate_key AS record_key, ",
    "source_ordinal AS record_ordinal, source_ordinal AS entity_ordinal, ",
    "allele_entity_id || '#location|' || coordinate_key AS entity_id, ",
    "'allele' AS parent_type, allele_entity_id AS parent_id, assembly, ",
    "variation_id, allele_id, chromosome, sequence_accession, start, stop, position_vcf, ",
    "reference_allele_vcf, alternate_allele_vcf ",
    "FROM locations), ",
    "decision_rows AS (SELECT ", release_sql, " AS release_id, ",
    "'decision' AS record_kind, 'decision|' || cast(l.allele_id AS VARCHAR) ",
    "|| '|' || ", profile_sql, " AS record_key, l.source_ordinal AS record_ordinal, ",
    "l.source_ordinal AS entity_ordinal, 'decision:' || cast(l.allele_id AS VARCHAR) ",
    "|| ':' || ", profile_sql, " AS entity_id, 'allele' AS parent_type, ",
    "l.allele_entity_id AS parent_id, l.variation_id, l.allele_id, ",
    "d.clinical_significance AS classification, d.gold_stars, ", policy_sql,
    " AS policy_version, ", profile_sql, " AS profile_id ",
    "FROM decision_source d JOIN allele_sources l USING (allele_id) ",
    "QUALIFY row_number() OVER (PARTITION BY l.allele_id ",
    "ORDER BY l.source_ordinal DESC) = 1), ",
    "scv_rows AS (SELECT ", release_sql, " AS release_id, ",
    "'scv_assertion' AS record_kind, 'scv_assertion|' || s.\"SCV\" || '|' || ",
    "cast(s.scv_occurrence AS VARCHAR) AS record_key, ",
    "s.source_ordinal AS record_ordinal, s.source_ordinal AS entity_ordinal, ",
    "split_part(s.\"SCV\", '.', 1) || '|' || cast(s.scv_occurrence AS VARCHAR) ",
    "AS entity_id, 'variation' AS parent_type, l.variation_entity_id AS parent_id, ",
    "split_part(s.\"SCV\", '.', 1) || '|' || ",
    "cast(s.scv_occurrence AS VARCHAR) AS scv_entity_id, ",
    "l.variation_id, split_part(s.\"SCV\", '.', 1) AS accession, ",
    "try_cast(nullif(split_part(s.\"SCV\", '.', 2), '') AS UINTEGER) AS version, ",
    "s.source_ordinal, ",
    "s.\"Submitter\" AS submitter_name, ",
    "s.\"ClinicalSignificance\" AS classification, ",
    "s.\"ReviewStatus\" AS review_status, ",
    "CASE WHEN s.\"DateLastEvaluated\" = '-' THEN NULL ",
    "ELSE try_strptime(s.\"DateLastEvaluated\", '%b %d, %Y')::DATE END ",
    "AS date_last_evaluated, s.\"Description\" AS description, ",
    "s.\"SubmittedPhenotypeInfo\" AS submitted_phenotype_info, ",
    "s.\"ReportedPhenotypeInfo\" AS reported_phenotype_info, ",
    "s.\"CollectionMethod\" AS collection_method, ",
    "s.\"OriginCounts\" AS origin_counts, ",
    "s.\"SubmittedGeneSymbol\" AS submitted_gene_symbol, ",
    "s.\"ExplanationOfInterpretation\" AS explanation, ",
    "try_cast(s.\"ContributesToAggregateClassification\" AS BOOLEAN) ",
    "AS contributes_to_aggregate_classification ",
    "FROM submissions_read s JOIN variation_sources l ",
    "ON l.variation_id = try_cast(s.\"#VariationID\" AS UBIGINT)), ",
    "rcv_rows AS (SELECT ", release_sql, " AS release_id, ",
    "'rcv_assertion' AS record_kind, 'rcv_assertion|' || ",
    "cast(variation_id AS VARCHAR) || '|' || accession AS record_key, ",
    "source_ordinal AS record_ordinal, source_ordinal AS entity_ordinal, ",
    "'variation:' || cast(variation_id AS VARCHAR) || '#rcv|' || accession ",
    "AS entity_id, 'variation' AS parent_type, variation_entity_id AS parent_id, ",
    "variation_id, accession, phenotype_ids AS database_id, ",
    "phenotype_name AS preferred_name ",
    "FROM (SELECT l.*, ",
    "unnest(string_split(nullif(l.rcv_accessions, '-'), '|')) AS accession, ",
    "unnest(string_split(nullif(l.phenotype_ids, '-'), '||')) AS phenotype_ids, ",
    "unnest(string_split(nullif(l.phenotype_names, '-'), '|')) AS phenotype_name ",
    "FROM allele_sources l) WHERE accession IS NOT NULL AND accession <> '' ",
    "QUALIFY row_number() OVER (PARTITION BY variation_id, accession ",
    "ORDER BY source_ordinal DESC) = 1), ",
    "gene_rows AS (SELECT ", release_sql, " AS release_id, ",
    "'gene' AS record_kind, 'gene|' || cast(allele_id AS VARCHAR) || '|' || coalesce(",
    "'ncbigene:' || cast(gene_id AS VARCHAR), ",
    "'hgnc:' || hgnc_id, 'symbol:' || upper(gene_symbol)) AS record_key, ",
    "source_ordinal AS record_ordinal, source_ordinal AS entity_ordinal, ",
    "allele_entity_id || '#gene|' || coalesce(",
    "'ncbigene:' || cast(gene_id AS VARCHAR), ",
    "'hgnc:' || hgnc_id, 'symbol:' || upper(gene_symbol)) AS entity_id, ",
    "'allele' AS parent_type, allele_entity_id AS parent_id, variation_id, ",
    "allele_id, gene_id, gene_symbol, hgnc_id FROM (SELECT l.* EXCLUDE ",
    "(gene_ids, gene_symbols, hgnc_ids), ",
    "try_cast(unnest(string_split(nullif(l.gene_ids, '-1'), ';')) AS UBIGINT) ",
    "AS gene_id, ",
    "unnest(string_split(nullif(l.gene_symbols, '-'), ';')) AS gene_symbol, ",
    "unnest(string_split(nullif(l.hgnc_ids, '-'), ';')) AS hgnc_id ",
    "FROM allele_sources l) WHERE gene_id IS NOT NULL OR gene_symbol IS NOT NULL ",
    "OR hgnc_id IS NOT NULL QUALIFY row_number() OVER (PARTITION BY allele_id, ",
    "coalesce('ncbigene:' || cast(gene_id AS VARCHAR), 'hgnc:' || hgnc_id, ",
    "'symbol:' || upper(gene_symbol)) ORDER BY source_ordinal DESC) = 1), ",
    "all_rows AS (SELECT * FROM variation_rows ",
    "UNION ALL BY NAME SELECT * FROM allele_rows ",
    "UNION ALL BY NAME SELECT * FROM location_rows ",
    "UNION ALL BY NAME SELECT * FROM decision_rows ",
    "UNION ALL BY NAME SELECT * FROM scv_rows ",
    "UNION ALL BY NAME SELECT * FROM rcv_rows ",
    "UNION ALL BY NAME SELECT * FROM gene_rows) ",
    "SELECT ", output_columns, " FROM all_rows", kind_predicate
  )
}

#' Import the official ClinVar flat reports as one tidy table
#'
#' Joins `variant_summary` and `submission_summary` directly in DuckDB. The
#' resulting `clinvar` table has one scalar row per variation, allele, assembly
#' location, decision, SCV submission, RCV accession, or allele-gene link,
#' identified by `record_kind`. It is the same canonical table used by
#' [rclinvarbitration_import_xml()].
#' Location rows retain source coordinates even when ClinVar does not provide a
#' complete VCF tuple (for example some CNVs). `clinvar_vcf` contains only
#' locations with a usable one-based position and non-missing REF/ALT.
#'
#' This is the compact default substrate for ClinVarbitration and temporal
#' analysis. XML import remains available for evidence absent from the flat
#' reports, including richer attributable observations and XML-only text.
#'
#' @param con A DuckDB DBI connection.
#' @param submission_path Official `submission_summary*.txt.gz`.
#' @param variant_path Official `variant_summary*.txt.gz`.
#' @param release_id Immutable source-release label stored with the imported
#'   rows and returned in the import receipt.
#' @param parquet_path Optional new Parquet path for the same tidy table. The
#'   returned import receipt can be passed directly to
#'   [rclinvarbitration_publish_ducklake()].
#' @param assembly One or both of `"GRCh38"` and `"GRCh37"`. Both are imported
#'   by default; policy decisions are computed once, preferring GRCh38 as the
#'   coordinate source when both are present.
#' @param profile_id Policy profile recorded on decision rows.
#' @param submitter_exclusions Submitters excluded from the policy decision.
#' @return Invisibly returns the table name, release identity, source paths and
#'   byte sizes, and row counts by record kind.
#' @export
rclinvarbitration_import_flat <- function(
    con, submission_path, variant_path, release_id,
    parquet_path = NULL, assembly = c("GRCh38", "GRCh37"),
    profile_id = "default", submitter_exclusions = character()) {
  for (path in list(submission_path, variant_path)) {
    if (!is.character(path) || length(path) != 1L || is.na(path) ||
        !file.exists(path)) {
      stop(
        "`submission_path` and `variant_path` must name existing files.",
        call. = FALSE
      )
    }
  }
  if (!is.character(release_id) || length(release_id) != 1L ||
      is.na(release_id) || !nzchar(release_id)) {
    stop("`release_id` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.character(profile_id) || length(profile_id) != 1L ||
      is.na(profile_id) || !nzchar(profile_id)) {
    stop("`profile_id` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.null(parquet_path)) {
    if (!is.character(parquet_path) || length(parquet_path) != 1L ||
        is.na(parquet_path) || !nzchar(parquet_path)) {
      stop("`parquet_path` must be NULL or a non-empty path.", call. = FALSE)
    }
    parquet_path <- normalizePath(parquet_path, mustWork = FALSE)
    if (!dir.exists(dirname(parquet_path))) {
      stop("The parent directory of `parquet_path` does not exist.", call. = FALSE)
    }
    if (file.exists(parquet_path)) {
      stop("`parquet_path` already exists; refuse to overwrite it.", call. = FALSE)
    }
  }
  if (!is.character(assembly) || !length(assembly) || anyNA(assembly) ||
      any(!assembly %in% c("GRCh38", "GRCh37"))) {
    stop(
      "`assembly` must contain one or both of \"GRCh38\" and \"GRCh37\".",
      call. = FALSE
    )
  }
  assembly <- unique(assembly)
  rclinvarbitration_init(con)
  release_sql <- rclinvarbitration_sql_string(release_id)
  if (DBI::dbGetQuery(
      con,
      paste0(
        "SELECT count(*) AS n FROM clinvar_releases WHERE release_id = ",
        release_sql
      )
    )$n[[1L]] > 0) {
    stop("`release_id` already exists.", call. = FALSE)
  }
  import_complete <- FALSE
  on.exit({
    if (!import_complete) {
      try(
        DBI::dbExecute(
          con, paste0("DELETE FROM clinvar WHERE release_id = ", release_sql)
        ),
        silent = TRUE
      )
    }
  }, add = TRUE)
  DBI::dbExecute(con, paste0("DELETE FROM clinvar WHERE release_id = ", release_sql))
  for (record_kind in c(
      "variation", "allele", "location", "scv_assertion", "rcv_assertion",
      "gene", "decision")) {
    select_sql <- rclinvarbitration_flat_tidy_sql(
      submission_path = submission_path,
      variant_path = variant_path,
      release_id = release_id,
      assembly = assembly,
      profile_id = profile_id,
      submitter_exclusions = submitter_exclusions,
      record_kind = record_kind
    )
    DBI::dbExecute(con, paste0("INSERT INTO clinvar BY NAME ", select_sql))
  }
  submission_path <- normalizePath(submission_path, mustWork = TRUE)
  variant_path <- normalizePath(variant_path, mustWork = TRUE)
  source_bytes <- unname(
    file.info(submission_path)$size + file.info(variant_path)$size
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO clinvar_releases ",
      "(release_id, source_path, source_bytes, source_kind, submission_path, ",
      "variant_path) VALUES (", release_sql, ", ",
      rclinvarbitration_sql_string(variant_path), ", ",
      sprintf("%.0f", source_bytes), ", 'flat_reports', ",
      rclinvarbitration_sql_string(submission_path), ", ",
      rclinvarbitration_sql_string(variant_path), ")"
    )
  )
  import_complete <- TRUE
  counts <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT record_kind, count(*) AS rows FROM clinvar WHERE release_id = ",
      release_sql, " GROUP BY record_kind ORDER BY record_kind"
    )
  )
  if (!is.null(parquet_path)) {
    DBI::dbExecute(
      con,
      paste0(
        "COPY (SELECT * EXCLUDE (release_id) FROM clinvar WHERE release_id = ",
        release_sql, ") TO ",
        rclinvarbitration_sql_string(parquet_path),
        " (FORMAT PARQUET, COMPRESSION ZSTD)"
      )
    )
  }
  release_receipt <- data.frame(
    release_id = release_id,
    submission_path = submission_path,
    submission_bytes = unname(file.info(submission_path)$size),
    variant_path = variant_path,
    variant_bytes = unname(file.info(variant_path)$size),
    stringsAsFactors = FALSE
  )
  invisible(list(
    table_name = "clinvar",
    path = parquet_path,
    rows = sum(counts$rows),
    release_id = release_id,
    assembly = assembly,
    schema = "tidy",
    profile_id = profile_id,
    policy_version = rclinvarbitration_policy_version(),
    release_receipt = release_receipt,
    counts = counts
  ))
}
