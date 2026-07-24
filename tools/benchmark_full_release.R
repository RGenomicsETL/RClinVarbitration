#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L || length(args) > 4L) {
  stop(
    "Usage: Rscript tools/benchmark_full_release.R XML_PATH DATABASE_PATH RELEASE_ID [RESULT_DCF]",
    call. = FALSE
  )
}

xml <- normalizePath(args[[1L]], mustWork = TRUE)
database <- normalizePath(args[[2L]], mustWork = FALSE)
release_id <- args[[3L]]
result <- if (length(args) == 4L) args[[4L]] else paste0(database, ".benchmark.dcf")
memory_limit <- Sys.getenv("CLINVAR_DUCKDB_MEMORY_LIMIT", "2GB")
threads <- Sys.getenv("CLINVAR_DUCKDB_THREADS", "2")
if (!grepl("^[1-9][0-9]*$", threads)) stop("CLINVAR_DUCKDB_THREADS must be a positive integer.")
if (file.exists(database) || file.exists(result)) {
  stop("Database and result paths must not already exist.", call. = FALSE)
}
if (!dir.exists(dirname(database)) || !dir.exists(dirname(result))) {
  stop("Database and result parent directories must exist.", call. = FALSE)
}

temporary_directory <- paste0(database, ".tmp")
dir.create(temporary_directory, recursive = TRUE, showWarnings = FALSE)

library(DBI)
library(duckdb)
library(RClinVarbitration)

con <- dbConnect(duckdb(
  dbdir = database,
  config = list(
    allow_unsigned_extensions = "true",
    memory_limit = memory_limit,
    preserve_insertion_order = "false",
    temp_directory = temporary_directory,
    threads = threads
  )
))
connected <- TRUE
on.exit({
  if (connected) try(dbDisconnect(con, shutdown = TRUE), silent = TRUE)
}, add = TRUE)
rclinvarbitration_enable(con)
rclinvarbitration_init(con)
source_url <- Sys.getenv("CLINVAR_SOURCE_URL", unset = "")
source_md5 <- Sys.getenv("CLINVAR_SOURCE_MD5", unset = "")
if (!nzchar(source_url)) source_url <- NULL
if (!nzchar(source_md5)) source_md5 <- NULL

started_at <- Sys.time()
timing <- system.time({
  counts <- rclinvarbitration_import_xml(
    con, xml, release_id,
    source_url = source_url,
    source_md5 = source_md5
  )
})
record_counts <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT record_kind, count(*) AS rows FROM clinvar WHERE release_id = ",
    DBI::dbQuoteString(con, release_id),
    " GROUP BY record_kind ORDER BY record_kind"
  )
)
key_counts <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT count(*) AS rows, count(DISTINCT record_key) AS keys ",
    "FROM clinvar WHERE release_id = ",
    DBI::dbQuoteString(con, release_id)
  )
)
coordinate_counts <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT assembly, count(*) AS rows FROM clinvar_vcf WHERE release_id = ",
    DBI::dbQuoteString(con, release_id),
    " GROUP BY assembly ORDER BY assembly"
  )
)
placement_counts <- DBI::dbGetQuery(
  con,
  paste0(
    "WITH xy AS (SELECT assembly, vcv_accession, allele_id, ",
    "bool_or(chromosome = 'X') AS has_x, bool_or(chromosome = 'Y') AS has_y ",
    "FROM clinvar_vcf WHERE release_id = ",
    DBI::dbQuoteString(con, release_id),
    " GROUP BY assembly, vcv_accession, allele_id) ",
    "SELECT (SELECT count(*) FROM clinvar_vcf WHERE release_id = ",
    DBI::dbQuoteString(con, release_id),
    " AND sequence_accession IS NOT NULL ",
    "AND NOT starts_with(sequence_accession, 'NC_')) AS alternate_rows, ",
    "count(*) FILTER (WHERE has_x AND has_y) AS xy_dual_alleles FROM xy"
  )
)
layout <- DBI::dbGetQuery(con, "DESCRIBE clinvar")
DBI::dbExecute(con, "CHECKPOINT")
finished_at <- Sys.time()
database_size <- DBI::dbGetQuery(con, "PRAGMA database_size")
dbDisconnect(con, shutdown = TRUE)
connected <- FALSE
unlink(temporary_directory, recursive = TRUE, force = TRUE)

optional_env <- function(name) {
  value <- Sys.getenv(name, unset = NA_character_)
  if (identical(value, "")) NA_character_ else value
}
values <- c(
  release_id = release_id,
  source_path = xml,
  source_url = optional_env("CLINVAR_SOURCE_URL"),
  source_md5 = optional_env("CLINVAR_SOURCE_MD5"),
  source_bytes = unname(file.info(xml)$size),
  database_path = database,
  database_bytes = unname(file.info(database)$size),
  database_total_blocks = database_size$total_blocks[[1L]],
  database_used_blocks = database_size$used_blocks[[1L]],
  database_free_blocks = database_size$free_blocks[[1L]],
  database_block_size = database_size$block_size[[1L]],
  started_at = format(started_at, "%Y-%m-%dT%H:%M:%S%z"),
  finished_at = format(finished_at, "%Y-%m-%dT%H:%M:%S%z"),
  elapsed_seconds = unname(timing[["elapsed"]]),
  user_seconds = unname(timing[["user.self"]]),
  system_seconds = unname(timing[["sys.self"]]),
  memory_limit = memory_limit,
  threads = threads,
  preserve_insertion_order = "false",
  rclinvarbitration_version = as.character(packageVersion("RClinVarbitration")),
  duckdb_version = as.character(packageVersion("duckdb")),
  r_version = as.character(getRversion()),
  sysname = unname(Sys.info()[["sysname"]]),
  release = unname(Sys.info()[["release"]]),
  machine = unname(Sys.info()[["machine"]]),
  total_rows = unname(key_counts$rows[[1L]]),
  distinct_record_keys = unname(key_counts$keys[[1L]]),
  duplicate_record_keys = unname(
    key_counts$rows[[1L]] - key_counts$keys[[1L]]
  ),
  scalar_columns = nrow(layout),
  nested_columns = sum(grepl("STRUCT|\\[\\]$", layout$column_type)),
  vcf_alternate_accession_rows = placement_counts$alternate_rows[[1L]],
  vcf_xy_dual_alleles = placement_counts$xy_dual_alleles[[1L]],
  setNames(
    record_counts$rows,
    paste0("rows_", gsub("[^a-z0-9]+", "_", record_counts$record_kind))
  ),
  setNames(
    coordinate_counts$rows,
    paste0("vcf_rows_", tolower(coordinate_counts$assembly))
  )
)
write.dcf(as.data.frame(as.list(values), optional = TRUE), file = result)
print(values)
