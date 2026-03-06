library(statsync)

# Check label passing
sync_export(
  sync_stats(iris, label = "Data Frame Explorer"),
  sync_stats(mtcars$disp),
  mtcars$wt,
  label = "Should Affect mtcars",
  file = "stats_export_direct_labels.json"
)
