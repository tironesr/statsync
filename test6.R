old_stats <- list(list(group=list('model1')))
get_g <- function(x) {
  v <- x$group; if (is.list(v)) v <- unlist(v);
  if (is.null(v) || length(v) == 0) '' else as.character(v[[1]])
}
new_groups <- c('model2')
old_stats_kept <- Filter(function(x) !(get_g(x) %in% new_groups), old_stats)
new_stats <- list(list(group=list('model2')))
merged <- c(old_stats_kept, new_stats)
cat(jsonlite::toJSON(merged, auto_unbox=TRUE))
