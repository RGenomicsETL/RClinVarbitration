expect_equal(
  rclinvarbitration_policy_version(),
  "cpg-clinvarbitration-2.2.11"
)
expect_error(rclinvarbitration_policy_sql("unknown"), "Unsupported")

con <- DBI::dbConnect(duckdb::duckdb())
rclinvarbitration_init(con)
rclinvarbitration_init(con)
expect_equal(
  DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_policy_profiles WHERE profile_id = 'default'")$n,
  1
)

DBI::dbExecute(con, "
  INSERT INTO clinvar
    (release_id, record_kind, record_key, record_ordinal, vcv_accession,
     scv_entity_id, entity_id, parent_type, parent_id, allele_id,
     context_type, context_id, preferred_name, database_name, database_id)
  VALUES
    ('xref', 'variation', 'variation|x', 1, 'VCVX',
     NULL, 'variation-x', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('xref', 'allele', 'allele|x', 1, 'VCVX',
     NULL, 'allele-x', NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL),
    ('xref', 'scv_assertion', 'scv|x', 1, 'VCVX',
     'assertion-x', 'assertion-x', NULL, NULL, NULL,
     NULL, NULL, NULL, NULL, NULL),
    ('xref', 'condition', 'condition|x', 1, 'VCVX',
     'assertion-x', 'condition-x', 'scv_assertion', 'assertion-x', NULL,
     'scv_assertion', 'assertion-x', 'Disease X', NULL, NULL),
    ('xref', 'xref', 'xref|hp', 1, 'VCVX',
     'assertion-x', 'xref-hp', 'condition', 'condition-x', NULL,
     'condition', 'condition-x', NULL, 'HP', 'HP:0000001'),
    ('xref', 'xref', 'xref|omim', 1, 'VCVX',
     'assertion-x', 'xref-omim', 'condition', 'condition-x', NULL,
     'condition', 'condition-x', NULL, 'OMIM', '123')
")
canonical <- DBI::dbGetQuery(con, "SELECT disease_database, disease_identifier, disease_key FROM clinvar_disease_submissions")
expect_equal(canonical$disease_database, "OMIM")
expect_equal(canonical$disease_identifier, "123")
expect_equal(canonical$disease_key, "omim:123")
hpo <- DBI::dbGetQuery(con, "
  SELECT vcv_accession, scv_entity_id, context_type, context_id, xref_id, hpo_id
  FROM clinvar_hpo_terms
")
expect_equal(hpo$hpo_id, "HP:0000001")
expect_equal(hpo$vcv_accession, "VCVX")
expect_equal(hpo$scv_entity_id, "assertion-x")
expect_equal(hpo$context_type, "condition")
expect_equal(hpo$context_id, "condition-x")
expect_equal(hpo$xref_id, "xref-hp")

DBI::dbExecute(con, "DROP VIEW clinvar_policy_pathogenic_alleles")
DBI::dbExecute(con, "DROP VIEW clinvar_policy_decisions")
DBI::dbExecute(con, "DROP VIEW clinvar_disease_submissions")

rows <- character()
add_submission <- function(group, classification,
                           review_status = "criteria provided, single submitter",
                           date_last_evaluated = "2022-01-01", submitter = NULL) {
  id <- length(rows) + 1L
  if (is.null(submitter)) submitter <- paste0("lab-", group, "-", id)
  group_number <- match(group, LETTERS)
  values <- c(
    "release", paste0("VCV", group), 1000L + group_number, 2000L + group_number,
    paste0("assertion-", id), paste0("SCV", id), 1L, id, submitter,
    classification, review_status, date_last_evaluated, paste0("condition-", group),
    "MedGen", paste0("D", group), paste("Disease", group), paste0("medgen:D", group)
  )
  quote_sql <- function(x) paste0("'", gsub("'", "''", as.character(x), fixed = TRUE), "'")
  rows <<- c(rows, paste0("(", paste(quote_sql(values), collapse = ","), ")"))
  invisible(NULL)
}

add_submission("A", "Pathogenic")
add_submission("A", "Benign", "reviewed by expert panel")
for (i in seq_len(6L)) add_submission("B", "Pathogenic")
for (i in seq_len(2L)) add_submission("B", "Benign")
for (i in seq_len(2L)) add_submission("B", "Uncertain significance")
for (i in seq_len(5L)) add_submission("C", "Pathogenic")
for (i in seq_len(2L)) add_submission("C", "Benign")
for (i in seq_len(3L)) add_submission("C", "Uncertain significance")
add_submission("D", "Uncertain significance")
add_submission("D", "Uncertain significance")
add_submission("D", "drug response")
add_submission("E", "Pathogenic")
add_submission("E", "Uncertain significance")
add_submission("F", "Benign")
add_submission("F", "Uncertain significance")
add_submission("G", "Pathogenic", date_last_evaluated = "2010-01-01")
add_submission("G", "Benign", date_last_evaluated = "2020-01-01")
add_submission("H", "Pathogenic", date_last_evaluated = "2010-01-01")
add_submission("H", "Uncertain significance", date_last_evaluated = "2010-01-01")
add_submission("I", "Pathogenic", "practice guideline")
add_submission("I", "Benign", "reviewed by expert panel")
add_submission("J", "Benign", submitter = "Illumina Laboratory Services; Illumina")
add_submission("J", "Pathogenic")
add_submission("K", "drug response")
add_submission("L", "Pathogenic, low penetrance")
add_submission("M", "Pathogenic", submitter = "blind-me")
add_submission("M", "Benign", submitter = "independent-lab")
add_submission("N", "Benign", "reviewed by expert panel")
add_submission("N", "Pathogenic", "practice guideline")

DBI::dbExecute(con, paste0(
  "CREATE VIEW clinvar_disease_submissions AS SELECT ",
  "col0 AS release_id, col1 AS vcv_accession, cast(col2 AS UBIGINT) AS variation_id, ",
  "cast(col3 AS UBIGINT) AS allele_id, col4 AS assertion_entity_id, col5 AS scv_accession, ",
  "cast(col6 AS UINTEGER) AS scv_version, cast(col7 AS UBIGINT) AS assertion_id, ",
  "cast(col7 AS UBIGINT) AS source_ordinal, col8 AS submitter_name, ",
  "col9 AS classification, col10 AS review_status, ",
  "cast(col11 AS DATE) AS date_last_evaluated, col12 AS condition_id, ",
  "col13 AS disease_database, col14 AS disease_identifier, col15 AS disease_name, ",
  "col16 AS disease_key FROM (VALUES ", paste(rows, collapse = ","), ")"
))

version_sql <- as.character(DBI::dbQuoteString(con, rclinvarbitration_policy_version()))
DBI::dbExecute(con, paste0(
  "INSERT INTO clinvar_policy_profiles VALUES (", version_sql,
  ", 'blind', 'test profile')"
))
DBI::dbExecute(con, paste0(
  "INSERT INTO clinvar_policy_submitter_exclusions VALUES (", version_sql,
  ", 'blind', 'blind-me', NULL, 'blinded test submitter')"
))
for (statement in rclinvarbitration_policy_sql()) DBI::dbExecute(con, statement)

default <- DBI::dbGetQuery(con, "
  SELECT right(vcv_accession, 1) AS group_id, policy_classification,
         gold_stars, modern_filter_applied,
         eligible_submission_count, retained_submission_count
  FROM clinvar_policy_decisions
  WHERE profile_id = 'default'
  ORDER BY group_id
")
expect_equal(default$group_id, c(LETTERS[1:10], "L", "M", "N"))
expect_equal(
  default$policy_classification,
  c(
    "Benign", "Pathogenic/Likely Pathogenic", "Conflicting", "VUS",
    "Pathogenic/Likely Pathogenic", "Benign", "Benign",
    "Pathogenic/Likely Pathogenic", "Pathogenic/Likely Pathogenic",
    "Pathogenic/Likely Pathogenic", "Pathogenic/Likely Pathogenic", "Conflicting", "Benign"
  )
)
expect_equal(default$gold_stars[c(1L, 9L, 13L)], c(3L, 4L, 4L))
expect_true(default$modern_filter_applied[7L])
expect_false(default$modern_filter_applied[8L])
expect_equal(default$eligible_submission_count[7L], 2)
expect_equal(default$retained_submission_count[7L], 1)
expect_false("K" %in% default$group_id)

blinded <- DBI::dbGetQuery(con, "
  SELECT policy_classification, pathogenic_count, benign_count
  FROM clinvar_policy_decisions
  WHERE profile_id = 'blind' AND vcv_accession = 'VCVM'
")
expect_equal(blinded$policy_classification, "Benign")
expect_equal(blinded$pathogenic_count, 0)
expect_equal(blinded$benign_count, 1)

DBI::dbDisconnect(con, shutdown = TRUE)
