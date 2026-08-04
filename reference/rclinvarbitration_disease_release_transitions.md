# Compare fixed-policy disease decisions between two ClinVar releases

Returns the disease-level policy relation for two imported releases
under one configured ClinVarbitration profile. The profile and pinned
policy version are held fixed; this function does not calculate case
rankings or evaluation summaries. `transition_status` is `"inserted"`,
`"withdrawn"`, `"changed"`, or `"unchanged"`. `classification_changed`
is true only for a retained allele-and-disease key whose policy
classification changed. A changed status also covers changed gold-star
evidence level or retained evaluation date.

## Usage

``` r
rclinvarbitration_disease_release_transitions(
  con,
  old_release_id,
  new_release_id,
  profile_id = "default"
)
```

## Arguments

- con:

  A DuckDB DBI connection initialized with
  [`rclinvarbitration_init()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_init.md).

- old_release_id:

  Earlier imported ClinVar release label.

- new_release_id:

  Later imported ClinVar release label.

- profile_id:

  Configured policy profile identifier, normally `"default"`.

## Value

A data frame at the allele-and-disease decision grain, suitable for
filtering temporal reclassification cases.
