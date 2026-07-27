if (!requireNamespace("ducklake", quietly = TRUE)) {
  exit_file("ducklake is not installed")
}

con <- DBI::dbConnect(duckdb::duckdb())
ducklake_available <- tryCatch(
  {
    DBI::dbExecute(con, "LOAD ducklake")
    TRUE
  },
  error = function(e) FALSE
)
if (!ducklake_available) {
  exit_file("the DuckLake extension is not available")
}

write_export <- function(rows, release_id) {
  if (!"release_id" %in% names(rows)) rows$release_id <- release_id
  DBI::dbWriteTable(
    con, "publication_rows", rows,
    temporary = TRUE, overwrite = TRUE
  )
  path <- tempfile("rclinvarbitration-publication-", fileext = ".parquet")
  DBI::dbExecute(
    con,
    paste0(
      "COPY publication_rows TO ",
      as.character(DBI::dbQuoteString(con, path)),
      " (FORMAT PARQUET)"
    )
  )
  list(
    path = path,
    rows = nrow(rows),
    release_id = release_id,
    assembly = "GRCh38",
    schema = "tidy",
    profile_id = "default",
    policy_version = rclinvarbitration_policy_version(),
    release_receipt = data.frame(release_id = release_id)
  )
}

rows_v1 <- data.frame(
  record_kind = "decision",
  record_key = c("key-a", "key-b", "key-d"),
  allele_key = c("allele-a", "allele-b", "allele-d"),
  assembly = "GRCh38",
  policy_version = rclinvarbitration_policy_version(),
  profile_id = "default",
  decision = c("unchanged", "old", "withdrawn")
)
export_v1 <- write_export(rows_v1, "ncbi-vcv-test-1")

lake_path <- tempfile("rclinvarbitration-lake-")
dir.create(lake_path)
lake_name <- paste0("clinvar_test_", sample.int(100000000L, 1L))
ducklake::set_ducklake_connection(con)
ducklake::attach_ducklake(lake_name, lake_path = lake_path)

publication_v1 <- rclinvarbitration_publish_ducklake(
  con, export_v1, ducklake_name = lake_name
)
expect_equal(publication_v1$input_rows, 3)
expect_equal(publication_v1$inserted, 3)
expect_equal(publication_v1$updated, 0)
expect_equal(publication_v1$deleted, 0)

rows_v2 <- data.frame(
  record_kind = "decision",
  record_key = c("key-a", "key-b", "key-c"),
  allele_key = c("allele-a", "allele-b", "allele-c"),
  assembly = "GRCh38",
  policy_version = rclinvarbitration_policy_version(),
  profile_id = "default",
  decision = c("unchanged", "new", "inserted")
)
export_v2 <- write_export(rows_v2, "ncbi-vcv-test-2")
publication_v2 <- rclinvarbitration_publish_ducklake(
  con, export_v2, ducklake_name = lake_name
)
expect_equal(publication_v2$input_rows, 3)
expect_equal(publication_v2$inserted, 1)
expect_equal(publication_v2$updated, 2)
expect_equal(publication_v2$deleted, 1)

published <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT record_key, decision FROM ",
    as.character(DBI::dbQuoteIdentifier(con, lake_name)),
    ".main.clinvar ORDER BY record_key"
  )
)
expect_equal(published$record_key, c("key-a", "key-b", "key-c"))
expect_equal(published$decision, c("unchanged", "new", "inserted"))
expect_equal(
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS n FROM ",
      as.character(DBI::dbQuoteIdentifier(con, lake_name)),
      ".main.clinvar_incoming"
    )
  )$n,
  0
)

changes <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT record_key, change_type FROM ",
    as.character(DBI::dbQuoteIdentifier(con, lake_name)),
    ".table_changes('clinvar', ",
    format(publication_v2$snapshot_id, scientific = FALSE), ", ",
    format(publication_v2$snapshot_id, scientific = FALSE),
    ") ORDER BY record_key, change_type"
  )
)
expect_true("key-a" %in% changes$record_key)
expect_equal(
  sort(changes$change_type),
  sort(c(
    "delete", "insert", "update_postimage", "update_postimage",
    "update_preimage", "update_preimage"
  ))
)
expect_equal(
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT DISTINCT release_id FROM ",
      as.character(DBI::dbQuoteIdentifier(con, lake_name)),
      ".main.clinvar"
    )
  )$release_id,
  "ncbi-vcv-test-2"
)

rows_duplicate <- rows_v2[c(1L, 1L), ]
export_duplicate <- write_export(rows_duplicate, "ncbi-vcv-test-duplicate")
expect_error(
  rclinvarbitration_publish_ducklake(
    con, export_duplicate, ducklake_name = lake_name
  ),
  "unique"
)
expect_equal(
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS n FROM ",
      as.character(DBI::dbQuoteIdentifier(con, lake_name)),
      ".main.clinvar"
    )
  )$n,
  3
)

rows_wrong_release <- rows_v2
rows_wrong_release$release_id <- "wrong-release"
export_wrong_release <- write_export(rows_wrong_release, "expected-release")
expect_error(
  rclinvarbitration_publish_ducklake(
    con, export_wrong_release, ducklake_name = lake_name
  ),
  "release identity"
)
unlink(export_wrong_release$path)

unlink(c(export_v1$path, export_v2$path, export_duplicate$path))
DBI::dbDisconnect(con, shutdown = TRUE)
unlink(lake_path, recursive = TRUE)
