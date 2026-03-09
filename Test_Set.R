# ==============================================================================
# StatSync Comprehensive Test Set
# 
# Run this script to start a StatSync server and populate it with a variety
# of statistical models covering all available features. This allows for
# manual verification in the StatSync Word Add-in.
# ==============================================================================

# Load required libraries
if (!requireNamespace("statsync", quietly = TRUE)) {
  stop("The 'statsync' package is not installed. Please install it first.")
}
if (!requireNamespace("lmerTest", quietly = TRUE)) {
  install.packages("lmerTest")
}
if (!requireNamespace("car", quietly = TRUE)) {
  install.packages("car")
}

library(statsync)
library(lmerTest)
library(car)

# Start the server. The Word Add-in can now connect to this instance.
sync_serve(project_name = "StatSync Test w/ Cat")

# Pause briefly to ensure server starts up
Sys.sleep(1)

cat("\nGenerating and syncing models to the add-in...\n")

# ------------------------------------------------------------------------------
# 1. Descriptive Statistics
# ------------------------------------------------------------------------------
cat("-> Syncing: Descriptive Statistics\n")
sync_update(iris)

stop# ------------------------------------------------------------------------------
# 2. Linear Models (OLS Regression)
# ------------------------------------------------------------------------------
cat("-> Syncing: Linear Model\n")
lm_mod <- lm(mpg ~ wt, data = mtcars)
sync_update(lm_mod)

# ------------------------------------------------------------------------------
# 3. Nested Model Comparisons (Linear Models / F-test)
# ------------------------------------------------------------------------------
cat("-> Syncing: Nested Linear Model Comparison (ANOVA)\n")
lm_mod_reduced <- lm(mpg ~ wt, data = mtcars)
nested_lm_comp <- anova(lm_mod_reduced, lm_mod)
sync_update(nested_lm_comp, label = "Nested Model Comp: LM (F-Test)")

# ------------------------------------------------------------------------------
# 4. Generalized Linear Models (Logistic Regression / Odds Ratios)
# ------------------------------------------------------------------------------
cat("-> Syncing: Logistic Regression\n")
glm_mod <- glm(vs ~ wt + hp, data = mtcars, family = "binomial")
sync_update(glm_mod)

# ------------------------------------------------------------------------------
# 5. Nested Model Comparisons (GLM / Chi-Square)
# ------------------------------------------------------------------------------
cat("-> Syncing: Nested GLM Comparison (Chi-Square)\n")
glm_mod_reduced <- glm(vs ~ gp, data = mtcars, family = "binomial")
nested_glm_comp <- anova(glm_mod_reduced, glm_mod, test = "Chisq")


sync_update(glm_mod,glm_mod_reduced)

# ------------------------------------------------------------------------------
# 6. Mixed-Effects Models (lmerTest)
# ------------------------------------------------------------------------------
cat("-> Syncing: Mixed-Effects Model\n")
lmer_mod <- lmer(Reaction ~ Days + (Days | Subject), data = sleepstudy)
sync_update(lmer_mod)

# ------------------------------------------------------------------------------
# 7. Analysis of Variance (Generic ANOVA)
# ------------------------------------------------------------------------------
cat("-> Syncing: Standard Analysis of Variance\n")
aov_mod <- aov(yield ~ block + N * P + K, data = npk)
sync_update(aov_mod, label = "ANOVA: Crop Yield")

# ------------------------------------------------------------------------------
# 8. car::Anova (Type II / III Tests)
# ------------------------------------------------------------------------------
cat("-> Syncing: car::Anova Type II Test\n")
car_anova_mod <- car::Anova(lm_mod, type = 2)
sync_update(car_anova_mod, label = "car::Anova Type II")

# ------------------------------------------------------------------------------
# 9. T-Tests (Independent & Paired)
# ------------------------------------------------------------------------------
cat("-> Syncing: Independent Samples T-Test\n")
t_test_indep <- t.test(mpg ~ am, data = mtcars)
sync_update(t_test_indep, label = "T-Test (Independent): MPG by Auto/Manual")

cat("-> Syncing: Paired Samples T-Test\n")
# Create some dummy paired data
pre_test <- c(80, 85, 90, 75, 88)
post_test <- c(85, 88, 95, 80, 92)
t_test_paired <- t.test(pre_test, post_test, paired = TRUE)
sync_update(t_test_paired, label = "T-Test (Paired): Pre vs Post")

# ------------------------------------------------------------------------------
# 10. Chi-Square Tests
# ------------------------------------------------------------------------------
cat("-> Syncing: Pearson's Chi-Square Test\n")
chi_sq_test <- chisq.test(table(mtcars$cyl, mtcars$gear))
sync_update(chi_sq_test, label = "Chi-Square Test: Cylinders by Gears")

# ------------------------------------------------------------------------------
# 11. Correlation Tests
# ------------------------------------------------------------------------------
cat("-> Syncing: Pearson Correlation Test\n")
cor_test <- cor.test(mtcars$mpg, mtcars$wt)
sync_update(cor_test)

# ------------------------------------------------------------------------------
# 12. Single Atomic Vectors
# ------------------------------------------------------------------------------
cat("-> Syncing: Atomic Vector\n")
sync_update(mtcars$disp)

cat("\n==============================================================================\n")
cat("SUCCESS: All models have been generated and synced to the StatSync server!\n")
cat("You can now open the StatSync Word Add-in and refresh to verify the outputs.\n")
cat("Remember to leave this R session running while you test in Word.\n")
cat("Run `sync_stop()` when you are finished testing to shut down the server.\n")
cat("==============================================================================\n")


#Add manual sync button when autosync is turned off
#StatSync should check for updates on models already inserted into the text when a live connection is established (e.g., you close Word, make updates to your code push your updates, re-open word... you want those updates to be reflected)
#There needs to be an offline mode