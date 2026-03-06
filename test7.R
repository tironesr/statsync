devtools::load_all('C:/Users/Tyrone/Documents/statsync/statsync')
m1 <- lm(mpg ~ wt, data = mtcars)
e1 <- statsync:::sync_export(m1, file=tempfile())
d1 <- jsonlite::read_json(e1)
i1 <- d1$statistics[[1]]$id

m1 <- lm(mpg ~ wt + hp, data = mtcars)
e2 <- statsync:::sync_export(m1, file=tempfile())
d2 <- jsonlite::read_json(e2)
i2 <- d2$statistics[[1]]$id

cat("ID 1:", i1, "\n")
cat("ID 2:", i2, "\n")
