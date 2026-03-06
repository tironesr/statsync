library(jsonlite)
state <- new.env()
state$data <- list(statistics = list(list(id="model1.result", group="model1")), tables = list())

new_data <- list(statistics = list(list(id="model1.result", group="model1")))

get_g <- function(x) {
  v <- x$group; if (is.list(v)) v <- unlist(v)
  if (is.null(v) || length(v) == 0) "" else as.character(v[[1]])
}
# Merge new data into existing data, overwriting those with the same group/label
new_groups <- unique(vapply(new_data$statistics, get_g, character(1)))
old_stats <- state$data$statistics
old_stats_kept <- Filter(function(x) !(get_g(x) %in% new_groups), old_stats)
state$data$statistics <- c(old_stats_kept, new_data$statistics)

cat(toJSON(state$data, auto_unbox=TRUE))
