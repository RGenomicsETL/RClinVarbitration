#' Import a PubMed baseline or update XML source
#'
#' Streams concrete PubMed baseline or update XML through the package-owned
#' libxml2 DuckDB extension. PMID is the article authority; DOI and PMCID are
#' retained as ordinary article identifiers when supplied. Each import appends
#' immutable source-versioned rows. `DeleteCitation` appends an explicit deleted
#' article event; it does not erase earlier article or child facts.
#'
#' The caller's current DuckDB or DuckLake catalog owns the resulting
#' `pubmed_*` relations. `pubmed_current_*` selects the latest non-deleted event
#' per PMID, while `pubmed_*_as_of(source_id)` table macros select a historical
#' cutoff. This importer does not fetch Europe PMC or perform semantic screening.
#'
#' @param con A DuckDB DBI connection with [rclinvarbitration_enable()] loaded.
#' @param path Path to a PubMed baseline or update XML or XML.GZ file.
#' @param source_id Immutable source snapshot or update label.
#' @param source_kind Whether `path` is a `"baseline"` or `"update"` source.
#' @return Invisibly returns source identity, typed source ordinal, and scalar
#'   row counts.
#' @export
rclinvarbitration_import_pubmed <- function(
    con, path, source_id, source_kind = c("baseline", "update")) {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !file.exists(path)) {
    stop("`path` must name an existing PubMed XML file.", call. = FALSE)
  }
  if (!is.character(source_id) || length(source_id) != 1L ||
      is.na(source_id) || !nzchar(source_id)) {
    stop("`source_id` must be a non-empty character scalar.", call. = FALSE)
  }
  source_kind <- match.arg(source_kind)
  rclinvarbitration_init(con)

  source_id_sql <- rclinvarbitration_sql_string(source_id)
  if (DBI::dbGetQuery(
      con,
      paste0("SELECT count(*) AS n FROM pubmed_sources WHERE source_id = ", source_id_sql)
    )$n[[1L]] > 0) {
    stop("`source_id` already exists.", call. = FALSE)
  }

  source_path <- normalizePath(path, mustWork = TRUE)
  source_path_sql <- rclinvarbitration_sql_string(source_path)
  source_kind_sql <- rclinvarbitration_sql_string(source_kind)
  staging_table <- "rclinvarbitration_pubmed_import_rows"
  transaction_open <- FALSE
  import_complete <- FALSE
  on.exit({
    if (transaction_open && !import_complete) {
      try(DBI::dbRollback(con), silent = TRUE)
    }
    try(DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", staging_table)), silent = TRUE)
  }, add = TRUE)

  # The native scanner materializes only the source records being imported;
  # durable PubMed relations change only after the complete XML stream parses.
  DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", staging_table))
  DBI::dbExecute(
    con,
    paste0(
      "CREATE TEMP TABLE ", staging_table,
      " AS SELECT * FROM rclinvarbitration_pubmed_xml_rows(", source_path_sql, ")"
    )
  )
  summary <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) FILTER (WHERE entity_type = 'article') AS article_rows, ",
      "count(DISTINCT pmid) FILTER (WHERE entity_type = 'article') AS article_pmids, ",
      "count(*) FILTER (WHERE entity_type = 'article' AND is_deleted) AS deleted, ",
      "count(*) FILTER (WHERE entity_type = 'abstract') AS abstracts, ",
      "count(*) FILTER (WHERE entity_type IN ('identifier', 'cited_identifier')) AS identifiers, ",
      "count(*) FILTER (WHERE entity_type = 'mesh') AS mesh_terms, ",
      "count(*) FILTER (WHERE entity_type = 'keyword') AS keywords FROM ", staging_table
    )
  )
  if (summary$article_rows[[1L]] == 0 ||
      summary$article_rows[[1L]] != summary$article_pmids[[1L]]) {
    stop(
      "PubMed XML must contain one PMID-authoritative article row per source record.",
      call. = FALSE
    )
  }

  DBI::dbBegin(con)
  transaction_open <- TRUE
  source_ordinal <- DBI::dbGetQuery(
    con,
    "SELECT coalesce(max(source_ordinal), 0) + 1 AS source_ordinal FROM pubmed_sources"
  )$source_ordinal[[1L]]
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO pubmed_sources ",
      "(source_id, source_ordinal, source_provider, source_path, source_kind, source_bytes) VALUES (",
      source_id_sql, ", ", sprintf("%.0f", source_ordinal), ", 'pubmed', ",
      source_path_sql, ", ", source_kind_sql, ", ",
      sprintf("%.0f", unname(file.info(source_path)$size)), ")"
    )
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO pubmed_articles ",
      "(source_id, pmid, source_kind, source_record_ordinal, article_title, ",
      "publication_date, source_date, is_deleted) SELECT ", source_id_sql,
      ", pmid, ", source_kind_sql,
      ", record_ordinal, article_title, publication_date, source_date, is_deleted FROM ",
      staging_table, " WHERE entity_type = 'article'"
    )
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO pubmed_abstracts ",
      "(source_id, pmid, source_record_ordinal, source_entity_ordinal, section, text) ",
      "SELECT ", source_id_sql, ", pmid, record_ordinal, entity_ordinal, section, text_value ",
      "FROM ", staging_table, " WHERE entity_type = 'abstract'"
    )
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO pubmed_article_identifiers ",
      "(source_id, pmid, source_record_ordinal, source_entity_ordinal, identifier_role, ",
      "identifier_source, identifier, citation_ordinal) SELECT ", source_id_sql,
      ", pmid, record_ordinal, entity_ordinal, CASE entity_type WHEN 'identifier' ",
      "THEN 'article_identifier' ELSE 'cited_identifier' END, identifier_source, identifier, ",
      "nullif(citation_ordinal, 0) ",
      "FROM ", staging_table,
      " WHERE entity_type IN ('identifier', 'cited_identifier')"
    )
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO pubmed_mesh_terms ",
      "(source_id, pmid, source_record_ordinal, source_entity_ordinal, mesh_type, mesh_ui, term) ",
      "SELECT ", source_id_sql, ", pmid, record_ordinal, entity_ordinal, identifier_source, identifier, text_value ",
      "FROM ", staging_table, " WHERE entity_type = 'mesh'"
    )
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO pubmed_keywords ",
      "(source_id, pmid, source_record_ordinal, source_entity_ordinal, keyword) ",
      "SELECT ", source_id_sql, ", pmid, record_ordinal, entity_ordinal, text_value FROM ", staging_table,
      " WHERE entity_type = 'keyword'"
    )
  )
  DBI::dbCommit(con)
  transaction_open <- FALSE
  import_complete <- TRUE
  DBI::dbExecute(con, paste("DROP TABLE", staging_table))

  invisible(list(
    source_id = source_id,
    source_kind = source_kind,
    source_ordinal = unname(source_ordinal),
    articles = unname(summary$article_rows[[1L]]),
    deleted = unname(summary$deleted[[1L]]),
    abstracts = unname(summary$abstracts[[1L]]),
    identifiers = unname(summary$identifiers[[1L]]),
    mesh_terms = unname(summary$mesh_terms[[1L]]),
    keywords = unname(summary$keywords[[1L]])
  ))
}
