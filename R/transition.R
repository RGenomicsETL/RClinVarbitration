rclinvarbitration_transition_release_sql <- function(con, release_id, argument) {
  if (!is.character(release_id) || length(release_id) != 1L ||
      is.na(release_id) || !nzchar(release_id)) {
    stop("`", argument, "` must be a non-empty character scalar.", call. = FALSE)
  }
  release_sql <- rclinvarbitration_sql_string(release_id)
  imported <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS n FROM clinvar_releases WHERE release_id = ",
      release_sql
    )
  )$n[[1L]]
  if (imported != 1) {
    stop("`", argument, "` is not an imported ClinVar release.", call. = FALSE)
  }
  release_sql
}

#' Compare fixed-policy disease decisions between two ClinVar releases
#'
#' Returns the disease-level policy relation for two imported releases under one
#' configured ClinVarbitration profile. The profile and pinned policy version
#' are held fixed; this function does not calculate case rankings or evaluation
#' summaries. `transition_status` is `"inserted"`, `"withdrawn"`, `"changed"`,
#' or `"unchanged"`. `classification_changed` is true only for a retained
#' allele-and-disease key whose policy classification changed. A changed status
#' also covers changed gold-star evidence level or retained evaluation date.
#'
#' @param con A DuckDB DBI connection initialized with
#'   [rclinvarbitration_init()].
#' @param old_release_id Earlier imported ClinVar release label.
#' @param new_release_id Later imported ClinVar release label.
#' @param profile_id Configured policy profile identifier, normally
#'   `"default"`.
#' @return A data frame at the allele-and-disease decision grain, suitable for
#'   filtering temporal reclassification cases.
#' @export
rclinvarbitration_disease_release_transitions <- function(
    con, old_release_id, new_release_id, profile_id = "default") {
  rclinvarbitration_init(con)
  old_release_sql <- rclinvarbitration_transition_release_sql(
    con, old_release_id, "old_release_id"
  )
  new_release_sql <- rclinvarbitration_transition_release_sql(
    con, new_release_id, "new_release_id"
  )
  if (identical(old_release_id, new_release_id)) {
    stop("`old_release_id` and `new_release_id` must differ.", call. = FALSE)
  }
  if (!is.character(profile_id) || length(profile_id) != 1L ||
      is.na(profile_id) || !nzchar(profile_id)) {
    stop("`profile_id` must be a non-empty character scalar.", call. = FALSE)
  }
  rclinvarbitration_validate_profile(con, profile_id)
  profile_sql <- rclinvarbitration_sql_string(profile_id)
  policy_sql <- rclinvarbitration_sql_string(rclinvarbitration_policy_version())

  DBI::dbGetQuery(
    con,
    paste0(
      "WITH old_decisions AS (SELECT * FROM clinvar_policy_decisions WHERE ",
      "policy_version = ", policy_sql, " AND profile_id = ", profile_sql,
      " AND release_id = ", old_release_sql, "), ",
      "new_decisions AS (SELECT * FROM clinvar_policy_decisions WHERE ",
      "policy_version = ", policy_sql, " AND profile_id = ", profile_sql,
      " AND release_id = ", new_release_sql, ") ",
      "SELECT ", policy_sql, " AS policy_version, ", profile_sql,
      " AS profile_id, ", old_release_sql, " AS old_release_id, ",
      new_release_sql, " AS new_release_id, ",
      "coalesce(o.vcv_accession, n.vcv_accession) AS vcv_accession, ",
      "coalesce(o.variation_id, n.variation_id) AS variation_id, ",
      "coalesce(o.allele_id, n.allele_id) AS allele_id, ",
      "coalesce(o.disease_key, n.disease_key) AS disease_key, ",
      "o.disease_database AS old_disease_database, ",
      "n.disease_database AS new_disease_database, ",
      "o.disease_identifier AS old_disease_identifier, ",
      "n.disease_identifier AS new_disease_identifier, ",
      "o.disease_name AS old_disease_name, n.disease_name AS new_disease_name, ",
      "o.policy_classification AS old_classification, ",
      "n.policy_classification AS new_classification, ",
      "o.release_id IS NOT NULL AND n.release_id IS NOT NULL AND ",
      "o.policy_classification IS DISTINCT FROM n.policy_classification ",
      "AS classification_changed, ",
      "o.gold_stars AS old_gold_stars, n.gold_stars AS new_gold_stars, ",
      "o.latest_date_last_evaluated AS old_latest_date_last_evaluated, ",
      "n.latest_date_last_evaluated AS new_latest_date_last_evaluated, CASE ",
      "WHEN o.release_id IS NULL THEN 'inserted' ",
      "WHEN n.release_id IS NULL THEN 'withdrawn' ",
      "WHEN o.policy_classification IS DISTINCT FROM n.policy_classification ",
      "OR o.gold_stars IS DISTINCT FROM n.gold_stars ",
      "OR o.latest_date_last_evaluated IS DISTINCT FROM n.latest_date_last_evaluated ",
      "THEN 'changed' ELSE 'unchanged' END AS transition_status ",
      "FROM old_decisions o FULL OUTER JOIN new_decisions n ON ",
      "o.vcv_accession IS NOT DISTINCT FROM n.vcv_accession AND ",
      "o.allele_id IS NOT DISTINCT FROM n.allele_id AND ",
      "o.disease_key IS NOT DISTINCT FROM n.disease_key ",
      "ORDER BY vcv_accession, allele_id, disease_key"
    )
  )
}
