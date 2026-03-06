library(lmerTest)
library(car)

# 0. Start server (required for sync_update to exist)
cat("Starting server...\n")
sync_serve()

# 1. Descriptive stats (Consolidated)
cat("\nTesting Descriptives...\n")
sync_update(iris, label = "Iris Explorer")

# 2. Nested LM
cat("\nTesting Nested LM...\n")
m1 <- lm(mpg ~ wt, data = mtcars)
m2 <- lm(mpg ~ wt + hp, data = mtcars)
a_nested <- anova(m1, m2)
sync_update(a_nested, label = "Nested Model Comparison")

# 3. Model with AIC/BIC
cat("\nTesting AIC/BIC...\n")
sync_update(m2)

# 4. Vector naming
cat("\nTesting Vector Naming...\n")
v <- iris$Sepal.Length
sync_update(v)

# 5. car::Anova
cat("\nTesting car::Anova...\n")
a_car <- car::Anova(m2, type = 2)
sync_update(a_car)

# Clean up
sync_stop()
