library(rlang)
sync_export <- function(...) {
    quos <- rlang::enquos(...)
    sapply(seq_along(quos), function(i) {
        expr <- rlang::quo_get_expr(quos[[i]])
        nm <- names(quos)[i]
        if (is.null(nm) || nm == "") {
            nm <- if (is.symbol(expr)) as.character(expr) else paste0("model_", i)
        }
        nm
    })
}
sync_serve <- function(...) { sync_export(...) }
update_fn <- function(...) { sync_export(...) }

cat("Serve:\n")
print(sync_serve(model1))

cat("Update:\n")
print(update_fn(model1))
