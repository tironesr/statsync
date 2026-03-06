library(statsync)
library(lmerTest)
library(car)
library(jsonlite)

# Start server briefly just so sync_update initializes the collection
sync_serve(port = 8765, daemon = TRUE)
Sys.sleep(1) # wait for server to start

cat("Generating comprehensive tests...\n")

# 1. Descriptive stats
cat("-> Descriptives\n")
sync_update(iris, label = "Iris Explorer")

# 2. Linear Model
cat("-> LM\n")
m1 <- lm(mpg ~ wt, data = mtcars)
sync_update(m1, label = "Linear Model")

# 3. Nested LM (ANOVA F-test)
cat("-> Nested LM\n")
m2 <- lm(mpg ~ wt + hp, data = mtcars)
a_nested <- anova(m1, m2)
sync_update(a_nested, label = "Nested Model Comparison")

# 4. Mixed Model
cat("-> LMEM\n")
lmer_mod <- lmer(Reaction ~ Days + (Days | Subject), data = sleepstudy)
sync_update(lmer_mod, label = "Mixed Model")

# 5. Generic ANOVA
cat("-> Generic ANOVA\n")
aov_mod <- aov(yield ~ block, npk)
sync_update(aov_mod, label = "ANOVA Model")

# 6. GLM (Logistic)
cat("-> GLM (Logistic)\n")
glm_mod <- glm(vs ~ wt, data = mtcars, family = "binomial")
sync_update(glm_mod, label = "Logistic Regression")

# 7. Nested GLM (Chisq test)
cat("-> Nested GLM Comparison\n")
glm_mod1 <- glm(vs ~ 1, data = mtcars, family = "binomial")
a_nested_glm <- anova(glm_mod1, glm_mod, test="Chisq")
sync_update(a_nested_glm, label = "Nested Logistic Comparison")

# 8. T-test
cat("-> T-Test\n")
tt <- t.test(1:10, y = c(7:20))
sync_update(tt, label = "T-Test")

# 9. Chi-square test
cat("-> Chi-Square\n")
ct <- chisq.test(table(mtcars$cyl, mtcars$gear))
sync_update(ct, label = "Chi-Square Test")

# 10. Correlation
cat("-> Correlation\n")
cor_test <- cor.test(mtcars$mpg, mtcars$wt)
sync_update(cor_test, label = "Correlation Test")

# 11. Vector naming
cat("-> Vector Naming\n")
v <- iris$Sepal.Length
sync_update(v)

# 12. car::Anova
cat("-> car::Anova\n")
a_car <- car::Anova(m2, type = 2)
sync_update(a_car, label = "car::Anova")

cat("\nDone!\n")

# Wait a moment to ensure all updates were processed
Sys.sleep(2)
sync_stop()
