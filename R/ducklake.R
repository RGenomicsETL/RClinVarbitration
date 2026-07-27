rclinvarbitration_ducklake_identifier <- function(value, name) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !grepl("^[A-Za-z_][A-Za-z0-9_]*$", value)) {
    stop("`", name, "` must be one unquoted SQL identifier.", call. = FALSE)
  }
  value
}

rclinvarbitration_ducklake_export <- function(export) {
  required <- c(
    "path", "rows", "release_id", "assembly", "schema", "profile_id",
    "policy_version", "release_receipt"
  )
  if (!is.list(export) || !all(required %in% names(export))) {
    stop(
      "`export` must be the result of ",
      "`rclinvarbitration_export_clinvarbitration_parquet()`.",
      call. = FALSE
    )
  }
  if (!identical(export$schema, "tidy")) {
    stop("Only `schema = \"tidy\"` exports can be published.", call. = FALSE)
  }
  if (!is.character(export$release_id) || length(export$release_id) != 1L ||
      is.na(export$release_id) || !nzchar(export$release_id)) {
    stop("`export$release_id` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.character(export$path) || length(export$path) != 1L ||
      is.na(export$path) || !file.exists(export$path)) {
    stop("The tidy Parquet file recorded by `export` does not exist.", call. = FALSE)
  }
  export$path <- normalizePath(export$path, mustWork = TRUE)
  export
}

rclinvarbitration_ducklake_validate_parquet <- function(con, export) {
  path_sql <- as.character(DBI::dbQuoteString(con, export$path))
  columns <- DBI::dbGetQuery(
    con,
    paste0("DESCRIBE SELECT * FROM read_parquet(", path_sql, ")")
  )$column_name
  required <- c(
    "release_id", "record_kind", "record_key", "assembly", "policy_version",
    "profile_id"
  )
  missing <- setdiff(required, columns)
  if (length(missing)) {
    stop(
      "The tidy Parquet file is missing required columns: ",
      paste(missing, collapse = ", "), ".",
      call. = FALSE
    )
  }

  summary <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS row_count, ",
      "count(DISTINCT record_key) AS key_count, ",
      "count(*) FILTER (WHERE record_key IS NULL OR record_key = '') AS bad_keys, ",
      "count(*) FILTER (WHERE release_id IS DISTINCT FROM ",
      rclinvarbitration_sql_string(export$release_id), ") AS wrong_release, ",
      "count(*) FILTER (WHERE assembly IS NOT NULL AND assembly NOT IN (",
      paste(
        rclinvarbitration_sql_string(export$assembly), collapse = ", "
      ),
      ")) AS wrong_assembly, ",
      "count(*) FILTER (WHERE record_kind = 'decision' AND ",
      "policy_version IS DISTINCT FROM ",
      rclinvarbitration_sql_string(export$policy_version), ") AS wrong_policy, ",
      "count(*) FILTER (WHERE record_kind = 'decision' AND ",
      "profile_id IS DISTINCT FROM ",
      rclinvarbitration_sql_string(export$profile_id), ") AS wrong_profile ",
      "FROM read_parquet(", path_sql, ")"
    )
  )
  if (summary$row_count[[1L]] == 0) {
    stop("Refuse to replace the published table with an empty export.", call. = FALSE)
  }
  if (summary$key_count[[1L]] != summary$row_count[[1L]] ||
      summary$bad_keys[[1L]] != 0) {
    stop("Every tidy row must have one unique, non-empty `record_key`.", call. = FALSE)
  }
  if (summary$wrong_release[[1L]] != 0 || summary$wrong_assembly[[1L]] != 0 ||
      summary$wrong_policy[[1L]] != 0 ||
      summary$wrong_profile[[1L]] != 0) {
    stop(
      "Parquet release identity, assembly, policy version, or profile does not match `export`.",
      call. = FALSE
    )
  }
  list(rows = unname(summary$row_count[[1L]]), columns = columns)
}

rclinvarbitration_ducklake_table_exists <- function(
    con, ducklake_name, table_name) {
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS n FROM information_schema.tables ",
      "WHERE table_catalog = ", rclinvarbitration_sql_string(ducklake_name),
      " AND table_schema = 'main' AND table_name = ",
      rclinvarbitration_sql_string(table_name)
    )
  )$n[[1L]] == 1
}

#' Publish a tidy ClinVar evidence export to DuckLake
#'
#' Registers one tidy Parquet export in a persistent staging table, then
#' replaces the current evidence set by key in one DuckLake transaction.
#' New keys are inserted, absent keys are deleted, changed content is updated,
#' and byte-identical records are left untouched. DuckLake's native data-change
#' feed is the release-delta authority.
#'
#' The staging and target tables are initialized once from the Parquet schema.
#' The staging table is retained because current DuckLake releases cannot
#' create, register, and drop that table safely in the same transaction. It is
#' empty before and after every successful publication.
#'
#' @param con A DuckDB DBI connection whose current database is the writable
#'   DuckLake catalog.
#' @param export The returned value from
#'   [rclinvarbitration_export_clinvarbitration_parquet()] with
#'   `schema = "tidy"`, or the returned value from
#'   [rclinvarbitration_import_flat()] when `parquet_path` was supplied.
#' @param table_name Persistent current-decision table.
#' @param staging_table Persistent empty staging table.
#' @param ducklake_name Attached DuckLake catalog. `NULL` uses the current
#'   database.
#' @param author Snapshot author.
#' @param commit_message Snapshot message. `NULL` derives one from the export.
#' @return Invisibly returns the publication snapshot, source identity, input
#'   row count, and DuckLake change counts.
#' @export
rclinvarbitration_publish_ducklake <- function(
    con, export, table_name = "clinvar",
    staging_table = "clinvar_incoming", ducklake_name = NULL,
    author = "RClinVarbitration", commit_message = NULL) {
  if (!requireNamespace("ducklake", quietly = TRUE)) {
    stop(
      "Install RGenomicsETL/ducklake-r to publish tidy exports.",
      call. = FALSE
    )
  }
  export <- rclinvarbitration_ducklake_export(export)
  table_name <- rclinvarbitration_ducklake_identifier(
    table_name, "table_name"
  )
  staging_table <- rclinvarbitration_ducklake_identifier(
    staging_table, "staging_table"
  )
  if (identical(table_name, staging_table)) {
    stop("`table_name` and `staging_table` must differ.", call. = FALSE)
  }
  if (!DBI::dbIsValid(con)) {
    stop("`con` must be an open DBI connection.", call. = FALSE)
  }
  current_database <- DBI::dbGetQuery(
    con, "SELECT current_database() AS database_name"
  )$database_name[[1L]]
  if (is.null(ducklake_name)) ducklake_name <- current_database
  ducklake_name <- rclinvarbitration_ducklake_identifier(
    ducklake_name, "ducklake_name"
  )
  if (!identical(current_database, ducklake_name)) {
    stop(
      "`con` must currently USE the selected DuckLake catalog.",
      call. = FALSE
    )
  }
  if (!is.character(author) || length(author) != 1L || is.na(author) ||
      !nzchar(author)) {
    stop("`author` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.null(commit_message) &&
      (!is.character(commit_message) || length(commit_message) != 1L ||
       is.na(commit_message) || !nzchar(commit_message))) {
    stop("`commit_message` must be NULL or non-empty text.", call. = FALSE)
  }

  input <- rclinvarbitration_ducklake_validate_parquet(con, export)
  ducklake::set_ducklake_connection(con)
  target <- paste0(
    as.character(DBI::dbQuoteIdentifier(con, ducklake_name)), ".main.",
    as.character(DBI::dbQuoteIdentifier(con, table_name))
  )
  staging <- paste0(
    as.character(DBI::dbQuoteIdentifier(con, ducklake_name)), ".main.",
    as.character(DBI::dbQuoteIdentifier(con, staging_table))
  )
  path_sql <- as.character(DBI::dbQuoteString(con, export$path))
  missing_tables <- c(
    target = !rclinvarbitration_ducklake_table_exists(
      con, ducklake_name, table_name
    ),
    staging = !rclinvarbitration_ducklake_table_exists(
      con, ducklake_name, staging_table
    )
  )
  if (any(missing_tables)) {
    ducklake::with_transaction(
      {
        if (missing_tables[["target"]]) {
          DBI::dbExecute(
            con,
            paste0(
              "CREATE TABLE ", target,
              " AS SELECT * FROM read_parquet(", path_sql, ") LIMIT 0"
            )
          )
        }
        if (missing_tables[["staging"]]) {
          DBI::dbExecute(
            con,
            paste0(
              "CREATE TABLE ", staging,
              " AS SELECT * FROM read_parquet(", path_sql, ") LIMIT 0"
            )
          )
        }
      },
      author = author,
      commit_message = "Initialize ClinVar publication tables",
      conn = con
    )
  }
  if (DBI::dbGetQuery(
      con, paste0("SELECT count(*) AS n FROM ", staging)
    )$n[[1L]] != 0) {
    stop(
      "The persistent DuckLake staging table is not empty; inspect it before ",
      "publishing another release.",
      call. = FALSE
    )
  }

  if (is.null(commit_message)) {
    commit_message <- paste(
      "Publish", export$release_id, paste(export$assembly, collapse = ","),
      export$profile_id
    )
  }
  extra_info <- paste(
    paste0("release_id=", export$release_id),
    paste0("assembly=", paste(export$assembly, collapse = ",")),
    paste0("policy_version=", export$policy_version),
    paste0("profile_id=", export$profile_id),
    sep = ";"
  )
  compare_columns <- setdiff(input$columns, "record_key")
  quote_column <- function(column, alias) {
    paste0(alias, ".", as.character(DBI::dbQuoteIdentifier(con, column)))
  }
  current_row <- paste0(
    "row(", paste(
      vapply(compare_columns, quote_column, character(1), alias = "current"),
      collapse = ", "
    ), ")"
  )
  incoming_row <- paste0(
    "row(", paste(
      vapply(compare_columns, quote_column, character(1), alias = "incoming"),
      collapse = ", "
    ), ")"
  )
  ducklake::with_transaction(
    {
      ducklake::add_data_files(
        staging_table, export$path, ducklake_name = ducklake_name
      )
      DBI::dbExecute(
        con,
        paste0(
          "DELETE FROM ", target, " AS current WHERE NOT EXISTS (",
          "SELECT 1 FROM ", staging, " AS incoming ",
          "WHERE incoming.record_key = current.record_key)"
        )
      )
      DBI::dbExecute(
        con,
        paste0(
          "MERGE INTO ", target, " AS current USING ", staging,
          " AS incoming USING (record_key) ",
          "WHEN MATCHED AND ", current_row, " IS DISTINCT FROM ",
          incoming_row, " THEN UPDATE ",
          "WHEN NOT MATCHED THEN INSERT"
        )
      )
      DBI::dbExecute(con, paste0("DELETE FROM ", staging))
    },
    author = author,
    commit_message = commit_message,
    commit_extra_info = extra_info,
    conn = con
  )

  catalog <- as.character(DBI::dbQuoteIdentifier(con, ducklake_name))
  snapshot_id <- DBI::dbGetQuery(
    con,
    paste0("SELECT max(snapshot_id) AS snapshot_id FROM ", catalog, ".snapshots()")
  )$snapshot_id[[1L]]
  changes <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT change_type, count(*) AS rows FROM ", catalog,
      ".table_changes(", rclinvarbitration_sql_string(table_name), ", ",
      format(snapshot_id, scientific = FALSE), ", ",
      format(snapshot_id, scientific = FALSE),
      ") GROUP BY change_type ORDER BY change_type"
    )
  )
  change_count <- function(type) {
    value <- changes$rows[changes$change_type == type]
    if (length(value)) unname(value[[1L]]) else 0
  }
  invisible(list(
    snapshot_id = snapshot_id,
    table_name = table_name,
    staging_table = staging_table,
    release_id = export$release_id,
    assembly = export$assembly,
    policy_version = export$policy_version,
    profile_id = export$profile_id,
    input_rows = input$rows,
    inserted = change_count("insert"),
    deleted = change_count("delete"),
    updated = change_count("update_postimage")
  ))
}
