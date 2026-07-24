#' RClinVarbitration: relational ClinVar evidence in DuckDB
#'
#' A DuckDB-native tidy ClinVar store. Flat reports and optional VCV XML both
#' feed one scalar `clinvar` table. The default flat path creates variation,
#' allele, GRCh37/GRCh38 location, decision, SCV, RCV, and gene rows. The
#' package-owned native extension adds XML-only observations, conditions,
#' citations, attributes, and attributable text to the same contract.
#'
#' @keywords internal
"_PACKAGE"
