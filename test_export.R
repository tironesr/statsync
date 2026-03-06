library(statsync)
library(lmerTest)
library(car)
library(jsonlite)

cat("Generating comprehensive tests...\n")

# Assign models
m1 <- lm(mpg ~ wt, data = mtcars)
m2 <- lm(mpg ~ wt + hp, data = mtcars)
a_nested <- anova(m1, m2)
lmer_mod <- lmer(Reaction ~ Days + (Days | Subject), data = sleepstudy)
aov_mod <- aov(yield ~ block, npk)
glm_mod <- glm(vs ~ wt, data = mtcars, family = "binomial")
glm_mod1 <- glm(vs ~ 1, data = mtcars, family = "binomial")
a_nested_glm <- anova(glm_mod1, glm_mod, test="Chisq")
tt <- t.test(1:10, y = c(7:20))
ct <- chisq.test(table(mtcars$cyl, mtcars$gear))
cor_test <- cor.test(mtcars$mpg, mtcars$wt)
v <- iris$Sepal.Length
a_car <- car::Anova(m2, type = 2)

sync_export(
  sync_stats(iris, label = "Iris Explorer"),
  sync_stats(m1, label = "Linear Model"),
  sync_stats(a_nested, label = "Nested Model Comparison"),
  sync_stats(lmer_mod, label = "Mixed Model"),
  sync_stats(aov_mod, label = "ANOVA Model"),
  sync_stats(glm_mod, label = "Logistic Regression"),
  sync_stats(a_nested_glm, label = "Nested Logistic Comparison"),
  sync_stats(tt, label = "T-Test"),
  sync_stats(ct, label = "Chi-Square Test"),
  sync_stats(cor_test, label = "Correlation Test"),
  sync_stats(v, label = "Vector Naming"),
  sync_stats(a_car, label = "car::Anova"),
  file = "stats_export_direct.json"
)

cat("\nDone exporting!\n")
