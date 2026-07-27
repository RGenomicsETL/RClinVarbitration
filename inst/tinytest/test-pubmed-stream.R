baseline <- system.file(
  "extdata", "pubmed_baseline_fixture.xml", package = "RClinVarbitration",
  mustWork = TRUE
)
update <- system.file(
  "extdata", "pubmed_update_fixture.xml", package = "RClinVarbitration",
  mustWork = TRUE
)
deleted <- system.file(
  "extdata", "pubmed_delete_fixture.xml", package = "RClinVarbitration",
  mustWork = TRUE
)
book <- system.file(
  "extdata", "pubmed_book_fixture.xml", package = "RClinVarbitration",
  mustWork = TRUE
)

extension_directory <- tempfile("rclinvarbitration-pubmed-extensions-")
con <- DBI::dbConnect(duckdb::duckdb(config = list(
  allow_unsigned_extensions = "true",
  extension_directory = extension_directory
)))
rclinvarbitration_enable(con)

pubmed_rows <- function(con, path) {
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT * FROM rclinvarbitration_pubmed_xml_rows(",
      DBI::dbQuoteString(con, path), ") ORDER BY record_ordinal, entity_ordinal"
    )
  )
}

rows <- pubmed_rows(con, baseline)
expect_equal(sum(rows$entity_type == "article"), 1)
expect_equal(rows$pmid[rows$entity_type == "article"], "1001")
expect_equal(rows$article_title[rows$entity_type == "article"], "Baseline article title")
expect_equal(rows$publication_date[rows$entity_type == "article"], "2020-01-02")
expect_equal(rows$source_date[rows$entity_type == "article"], "2020-01-03")
expect_equal(
  rows$identifier[rows$entity_type == "cited_identifier"],
  c("2001", "10.1000/cited")
)
expect_equal(rows$citation_ordinal[rows$entity_type == "cited_identifier"], c(1, 1))
expect_false(any(rows$is_deleted))

delete_rows <- pubmed_rows(con, deleted)
expect_equal(delete_rows$entity_type, c("article", "article"))
expect_equal(delete_rows$pmid, c("1001", "1002"))
expect_true(all(delete_rows$is_deleted))

book_rows <- pubmed_rows(con, book)
expect_equal(book_rows$pmid[book_rows$entity_type == "article"], "3001")
expect_equal(book_rows$article_title[book_rows$entity_type == "article"], "PubMed book article")
expect_equal(
  book_rows$text_value[book_rows$entity_type == "abstract"], "Book abstract."
)

mismatch_path <- tempfile("pubmed-pmid-mismatch-", fileext = ".xml")
writeLines(c(
  "<PubmedArticleSet><PubmedArticle><MedlineCitation><PMID>1001</PMID>",
  "<Article><ArticleTitle>Mismatch</ArticleTitle></Article></MedlineCitation>",
  "<PubmedData><ArticleIdList><ArticleId IdType='pubmed'>1002</ArticleId>",
  "</ArticleIdList></PubmedData></PubmedArticle></PubmedArticleSet>"
), mismatch_path)
expect_error(pubmed_rows(con, mismatch_path), "does not match")
invalid_pmid_path <- tempfile("pubmed-invalid-pmid-", fileext = ".xml")
writeLines(c(
  "<PubmedArticleSet><PubmedArticle><MedlineCitation><PMID>not-a-pmid</PMID>",
  "</MedlineCitation></PubmedArticle></PubmedArticleSet>"
), invalid_pmid_path)
expect_error(pubmed_rows(con, invalid_pmid_path), "decimal identifier")
unlink(c(mismatch_path, invalid_pmid_path))

baseline_import <- rclinvarbitration_import_pubmed(
  con, baseline, source_id = "pubmed-baseline", source_kind = "baseline"
)
expect_equal(baseline_import$source_ordinal, 1)
expect_equal(baseline_import$articles, 1)
expect_equal(baseline_import$deleted, 0)
expect_equal(baseline_import$abstracts, 2)
article <- DBI::dbGetQuery(
  con, "SELECT * FROM pubmed_articles WHERE source_id = 'pubmed-baseline'"
)
expect_equal(article$pmid, "1001")
expect_equal(article$article_title, "Baseline article title")
expect_equal(article$publication_date, "2020-01-02")
expect_equal(article$source_date, "2020-01-03")
expect_false(article$is_deleted)
expect_equal(
  DBI::dbGetQuery(
    con,
    "SELECT section, text FROM pubmed_abstracts WHERE source_id = 'pubmed-baseline'
     ORDER BY source_entity_ordinal"
  )$section,
  c("BACKGROUND", "METHODS")
)
expect_equal(
  DBI::dbGetQuery(con, "
    SELECT identifier_source, identifier
    FROM pubmed_article_identifiers
    WHERE source_id = 'pubmed-baseline' AND identifier_role = 'article_identifier'
    ORDER BY identifier_source
  ")$identifier,
  c("10.1000/baseline", "PMC1001", "1001")
)
expect_equal(
  DBI::dbGetQuery(con, "
    SELECT identifier, citation_ordinal FROM pubmed_article_identifiers
    WHERE source_id = 'pubmed-baseline' AND identifier_role = 'cited_identifier'
    ORDER BY source_entity_ordinal
  ")$citation_ordinal,
  c(1, 1)
)
expect_equal(
  DBI::dbGetQuery(
    con, "SELECT term FROM pubmed_mesh_terms WHERE source_id = 'pubmed-baseline'"
  )$term,
  "Calcimycin"
)
expect_equal(
  DBI::dbGetQuery(
    con, "SELECT keyword FROM pubmed_keywords WHERE source_id = 'pubmed-baseline'"
  )$keyword,
  "baseline keyword"
)

update_import <- rclinvarbitration_import_pubmed(
  con, update, source_id = "pubmed-update", source_kind = "update"
)
expect_equal(update_import$source_ordinal, 2)
expect_equal(update_import$articles, 1)
updated <- DBI::dbGetQuery(con, "SELECT * FROM pubmed_current_articles")
expect_equal(updated$source_id, "pubmed-update")
expect_equal(updated$article_title, "Updated article title")
expect_equal(updated$publication_date, "2021-02-04")
expect_equal(updated$source_date, "2021-02-05")
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM pubmed_abstracts")$n, 3)
expect_equal(
  DBI::dbGetQuery(con, "SELECT text FROM pubmed_current_abstracts")$text,
  "Updated results."
)
expect_equal(
  DBI::dbGetQuery(con, "
    SELECT count(*) AS n FROM pubmed_current_article_identifiers
    WHERE identifier_source = 'doi'
  ")$n,
  0
)

remove_import <- rclinvarbitration_import_pubmed(
  con, deleted, source_id = "pubmed-delete", source_kind = "update"
)
expect_equal(remove_import$source_ordinal, 3)
expect_equal(remove_import$articles, 2)
expect_equal(remove_import$deleted, 2)
removed <- DBI::dbGetQuery(
  con, "SELECT * FROM pubmed_articles WHERE source_id = 'pubmed-delete' ORDER BY pmid"
)
expect_equal(removed$pmid, c("1001", "1002"))
expect_true(all(removed$is_deleted))
expect_true(all(is.na(removed$article_title)))
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM pubmed_current_articles")$n, 0)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM pubmed_current_abstracts")$n, 0)
expect_equal(
  DBI::dbGetQuery(con, "SELECT count(*) AS n FROM pubmed_current_article_identifiers")$n,
  0
)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM pubmed_articles")$n, 4)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM pubmed_article_events")$n, 4)

article_as_of <- function(con, source_id) {
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT source_id, pmid, article_title FROM pubmed_articles_as_of(",
      DBI::dbQuoteString(con, source_id), ") ORDER BY pmid"
    )
  )
}
expect_equal(article_as_of(con, "pubmed-baseline")$article_title, "Baseline article title")
expect_equal(article_as_of(con, "pubmed-update")$article_title, "Updated article title")
expect_equal(nrow(article_as_of(con, "pubmed-delete")), 0L)
expect_equal(
  DBI::dbGetQuery(con, "
    SELECT text FROM pubmed_abstracts_as_of('pubmed-baseline')
    ORDER BY source_entity_ordinal
  ")$text,
  c("Baseline background.", "Baseline methods.")
)
expect_equal(
  DBI::dbGetQuery(con, "SELECT text FROM pubmed_abstracts_as_of('pubmed-update')")$text,
  "Updated results."
)
expect_equal(
  DBI::dbGetQuery(con, "SELECT count(*) AS n FROM pubmed_abstracts_as_of('pubmed-delete')")$n,
  0
)
sources <- DBI::dbGetQuery(
  con, "SELECT source_id, source_ordinal, source_provider FROM pubmed_sources ORDER BY source_ordinal"
)
expect_equal(
  sources$source_id,
  c("pubmed-baseline", "pubmed-update", "pubmed-delete")
)
expect_equal(sources$source_ordinal, c(1, 2, 3))
expect_equal(sources$source_provider, rep("pubmed", 3L))

# Canonical read-only projections retain all events; semantic consumers do not
# need to reconstruct temporal visibility or copy source facts.
literature_snapshots <- DBI::dbGetQuery(con, "
  SELECT provider_id, snapshot_id, high_water_ordinal, effective_at
  FROM pubmed_literature_snapshots
  ORDER BY high_water_ordinal
")
expect_equal(literature_snapshots$provider_id, rep("pubmed", 3L))
expect_equal(
  literature_snapshots$snapshot_id,
  c("pubmed-baseline", "pubmed-update", "pubmed-delete")
)
expect_equal(literature_snapshots$high_water_ordinal, c(1, 2, 3))
expect_false(any(is.na(literature_snapshots$effective_at)))

literature_versions <- DBI::dbGetQuery(con, "
  SELECT provider_id, article_id, pmid, version_id, source_ordinal, is_deleted,
         article_title, publication_date, source_date
  FROM pubmed_literature_article_versions
  WHERE pmid = '1001'
  ORDER BY source_ordinal
")
expect_equal(literature_versions$provider_id, rep("pubmed", 3L))
expect_equal(literature_versions$article_id, rep("1001", 3L))
expect_equal(
  literature_versions$version_id,
  c("pubmed-baseline", "pubmed-update", "pubmed-delete")
)
expect_equal(literature_versions$source_ordinal, c(1, 2, 3))
expect_equal(literature_versions$is_deleted, c(FALSE, FALSE, TRUE))
expect_equal(
  literature_versions$article_title,
  c("Baseline article title", "Updated article title", NA_character_)
)
expect_equal(
  literature_versions$publication_date,
  c("2020-01-02", "2021-02-04", NA_character_)
)
expect_equal(
  literature_versions$source_date,
  c("2020-01-03", "2021-02-05", NA_character_)
)

version_sections <- DBI::dbGetQuery(con, "
  SELECT v.version_id, s.snapshot_id, v.source_ordinal, s.high_water_ordinal,
         count(x.text) AS section_rows
  FROM pubmed_literature_article_versions v
  JOIN pubmed_literature_snapshots s
    ON s.provider_id = v.provider_id AND s.snapshot_id = v.version_id
  LEFT JOIN pubmed_literature_sections x
    ON x.provider_id = v.provider_id AND x.article_id = v.article_id
   AND x.version_id = v.version_id
  WHERE v.pmid = '1001'
  GROUP BY v.version_id, s.snapshot_id, v.source_ordinal, s.high_water_ordinal
  ORDER BY v.source_ordinal
")
expect_equal(
  version_sections$version_id,
  c("pubmed-baseline", "pubmed-update", "pubmed-delete")
)
expect_equal(version_sections$snapshot_id, version_sections$version_id)
expect_equal(version_sections$source_ordinal, version_sections$high_water_ordinal)
expect_equal(version_sections$section_rows, c(3, 2, 0))
literature_sections <- DBI::dbGetQuery(con, "
  SELECT version_id, source_ordinal, section, subsection, text
  FROM pubmed_literature_sections
  WHERE pmid = '1001'
  ORDER BY source_ordinal, CASE section WHEN 'title' THEN 0 ELSE 1 END, subsection
")
expect_equal(literature_sections$version_id,
             c("pubmed-baseline", "pubmed-baseline", "pubmed-baseline",
               "pubmed-update", "pubmed-update"))
expect_equal(literature_sections$source_ordinal, c(1, 1, 1, 2, 2))
expect_equal(
  literature_sections$section,
  c("title", "abstract", "abstract", "title", "abstract")
)
expect_equal(
  literature_sections$subsection,
  c(NA_character_, "BACKGROUND", "METHODS", NA_character_, "RESULTS")
)
expect_equal(
  literature_sections$text,
  c(
    "Baseline article title", "Baseline background.", "Baseline methods.",
    "Updated article title", "Updated results."
  )
)
expect_error(
  rclinvarbitration_import_pubmed(con, baseline, source_id = "pubmed-baseline"),
  "already exists"
)

DBI::dbDisconnect(con, shutdown = TRUE)

# The same typed source cutoffs work in the selected DuckLake catalog when its
# extension and R binding are available.
if (requireNamespace("ducklake", quietly = TRUE)) {
  lake_con <- DBI::dbConnect(duckdb::duckdb(config = list(
    allow_unsigned_extensions = "true",
    extension_directory = tempfile("rclinvarbitration-pubmed-lake-extensions-")
  )))
  lake_available <- tryCatch({
    DBI::dbExecute(lake_con, "LOAD ducklake")
    TRUE
  }, error = function(e) FALSE)
  if (lake_available) {
    lake_path <- tempfile("rclinvarbitration-pubmed-lake-")
    dir.create(lake_path)
    lake_name <- paste0("pubmed_test_", sample.int(100000000L, 1L))
    ducklake::set_ducklake_connection(lake_con)
    ducklake::attach_ducklake(lake_name, lake_path = lake_path)
    rclinvarbitration_enable(lake_con)
    rclinvarbitration_import_pubmed(lake_con, baseline, "pubmed-baseline", "baseline")
    rclinvarbitration_import_pubmed(lake_con, update, "pubmed-update", "update")
    rclinvarbitration_import_pubmed(lake_con, deleted, "pubmed-delete", "update")
    expect_equal(
      article_as_of(lake_con, "pubmed-baseline")$article_title,
      "Baseline article title"
    )
    expect_equal(
      article_as_of(lake_con, "pubmed-update")$article_title,
      "Updated article title"
    )
    expect_equal(nrow(article_as_of(lake_con, "pubmed-delete")), 0L)
    DBI::dbDisconnect(lake_con, shutdown = TRUE)
    unlink(lake_path, recursive = TRUE)
  } else {
    DBI::dbDisconnect(lake_con, shutdown = TRUE)
  }
}
