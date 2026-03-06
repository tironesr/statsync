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
sync_serve <- function(...) {
    update_fn <- function(...) {
        sync_export(...)
    }
    assign("sync_update", update_fn, envir = .GlobalEnv)
}

sync_serve(model1)
cat("Names from sync_update:\n")
print(sync_update(model1))
