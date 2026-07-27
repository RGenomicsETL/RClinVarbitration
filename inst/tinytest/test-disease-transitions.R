con <- DBI::dbConnect(duckdb::duckdb())
rclinvarbitration_init(con)

policy_version <- rclinvarbitration_policy_version()
DBI::dbExecute(con, "
  INSERT INTO clinvar_releases (release_id, source_path) VALUES
    ('transition-old', 'old-fixture'), ('transition-new', 'new-fixture')
")

add_disease_decision <- function(release_id, vcv_accession, variation_id, allele_id,
                                 disease_id, disease_name, classification, evaluated) {
  prefix <- paste(release_id, vcv_accession, disease_id, sep = "|")
  DBI::dbAppendTable(con, "clinvar", data.frame(
    release_id = release_id,
    record_kind = c("variation", "allele", "scv_assertion", "condition"),
    record_key = paste(prefix, c("variation", "allele", "scv", "condition"), sep = "|"),
    record_ordinal = 1,
    source_ordinal = c(NA, NA, 1, NA),
    vcv_accession = vcv_accession,
    scv_entity_id = c(NA, NA, paste0(prefix, "|assertion"), paste0(prefix, "|assertion")),
    entity_id = c(
      paste0(prefix, "|variation"), paste0(prefix, "|allele"),
      paste0(prefix, "|assertion"), paste0(prefix, "|condition")
    ),
    parent_type = c(NA, NA, NA, "scv_assertion"),
    parent_id = c(NA, NA, NA, paste0(prefix, "|assertion")),
    variation_id = c(variation_id, NA, NA, NA),
    allele_id = c(NA, allele_id, NA, NA),
    accession = c(NA, NA, paste0("SCV", variation_id), NA),
    version = c(NA, NA, 1, NA),
    classification = c(NA, NA, classification, NA),
    review_status = c(NA, NA, "criteria provided, single submitter", NA),
    date_last_evaluated = as.Date(c(NA, NA, evaluated, NA)),
    context_type = c(NA, NA, NA, "scv_assertion"),
    context_id = c(NA, NA, NA, paste0(prefix, "|assertion")),
    database_name = c(NA, NA, NA, "OMIM"),
    database_id = c(NA, NA, NA, disease_id),
    preferred_name = c(NA, NA, NA, disease_name)
  ))
}

add_disease_decision(
  "transition-old", "VCV000001001", 1001, 2001, "1", "Shared disease",
  "Pathogenic", "2020-01-01"
)
add_disease_decision(
  "transition-new", "VCV000001001", 1001, 2001, "1", "Renamed shared disease",
  "Benign", "2024-01-01"
)
add_disease_decision(
  "transition-old", "VCV000001002", 1002, 2002, "2", "Withdrawn disease",
  "Pathogenic", "2020-01-01"
)
add_disease_decision(
  "transition-new", "VCV000001003", 1003, 2003, "3", "Inserted disease",
  "Pathogenic", "2024-01-01"
)
add_disease_decision(
  "transition-old", "VCV000001004", 1004, 2004, "4", "Stable disease",
  "Pathogenic", "2020-01-01"
)
add_disease_decision(
  "transition-new", "VCV000001004", 1004, 2004, "4", "Updated stable label",
  "Pathogenic", "2020-01-01"
)

transitions <- rclinvarbitration_disease_release_transitions(
  con, "transition-old", "transition-new"
)
expect_equal(transitions$policy_version, rep(policy_version, 4L))
expect_equal(transitions$profile_id, rep("default", 4L))
expect_equal(
  transitions$transition_status,
  c("changed", "withdrawn", "inserted", "unchanged")
)
shared <- transitions[transitions$disease_key == "omim:1", ]
expect_equal(shared$allele_id, 2001)
expect_equal(shared$old_disease_database, "OMIM")
expect_equal(shared$new_disease_database, "OMIM")
expect_equal(shared$old_disease_identifier, "1")
expect_equal(shared$new_disease_identifier, "1")
expect_equal(shared$old_disease_name, "Shared disease")
expect_equal(shared$new_disease_name, "Renamed shared disease")
expect_equal(shared$old_classification, "Pathogenic/Likely Pathogenic")
expect_equal(shared$new_classification, "Benign")
expect_true(shared$classification_changed)
expect_false(any(transitions$classification_changed[
  transitions$transition_status %in% c("inserted", "withdrawn", "unchanged")
]))
expect_equal(shared$old_gold_stars, 1)
expect_equal(shared$new_gold_stars, 1)
expect_equal(shared$old_latest_date_last_evaluated, as.Date("2020-01-01"))
expect_equal(shared$new_latest_date_last_evaluated, as.Date("2024-01-01"))
expect_error(
  rclinvarbitration_disease_release_transitions(
    con, "transition-old", "transition-new", profile_id = "not-configured"
  ),
  "not a configured"
)
expect_error(
  rclinvarbitration_disease_release_transitions(
    con, "transition-old'; DROP TABLE clinvar; --", "transition-new"
  ),
  "not an imported"
)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar")$n, 24)

DBI::dbDisconnect(con, shutdown = TRUE)
