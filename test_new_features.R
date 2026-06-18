detach("package:statsync", unload=TRUE)
install.packages("C:/Users/Tyrone/Documents/statsync/statsync", repos = NULL, type = "source")
# StatSync: Test New Features Script
# This script generates sample data and exports statistics for the new tests:
# Repeated Measures ANOVA (afex), Post-Hoc Tests (emmeans), and SEM (lavaan).

# Install required packages if missing
if (!requireNamespace("afex", quietly = TRUE)) install.packages("afex")
if (!requireNamespace("emmeans", quietly = TRUE)) install.packages("emmeans")
if (!requireNamespace("lavaan", quietly = TRUE)) install.packages("lavaan")

library(afex)
library(emmeans)
library(lavaan)

# Load the StatSync package natively
library(statsync)

# Clear any previous tracking
sync_clear()

cat("\n[1/3] Running Repeated Measures ANOVA...\n")
# Using the obk.long dataset built into afex
data(obk.long, package = "afex")
# Build a repeated measures ANOVA model
rm_aov <- afex::aov_ez("id", "value", obk.long, 
                       between = c("treatment", "gender"), 
                       within = c("phase", "hour"))
# Export the overall RM ANOVA model
sync_export(rm_aov, label = "ANOVA: Phase and Treatment")

cat("[2/3] Running Post-Hoc Tests (emmeans)...\n")
# Calculate pairwise contrasts for the 'treatment' factor
post_hoc <- emmeans::emmeans(rm_aov, pairwise ~ treatment)
# Export the contrasts (post-hoc t-tests)
sync_update(post_hoc$contrasts, label = "Post-Hoc: Treatment Contrasts")

cat("[3/3] Running Structural Equation Model (lavaan)...\n")
# Build a classic SEM model using the PoliticalDemocracy dataset
sem_model <- '
  # latent variable definitions
     ind60 =~ x1 + x2 + x3
     dem60 =~ y1 + a*y2 + b*y3 + c*y4
     dem65 =~ y5 + a*y6 + b*y7 + c*y8

  # regressions
    dem60 ~ ind60
    dem65 ~ ind60 + dem60

  # residual correlations
    y1 ~~ y5
    y2 ~~ y4 + y6
    y3 ~~ y7
    y4 ~~ y8
    y6 ~~ y8
'
sem_fit <- lavaan::sem(sem_model, data = lavaan::PoliticalDemocracy)
# Export the SEM model (extracts fit indices and paths)
sync_update(sem_fit, label = "SEM: Political Democracy Model")

cat("\n[4/4] Generating a Regression Table...\n")
# Create a multiple regression model
lm_model213 <- lm(mpg ~ wt + qsec, data = mtcars)
# Generate a formatted, publication-ready APA table
# Export the table alongside the other stats
sync_export(lm_model213)

cat("\n======================================================\n")
cat("Starting StatSync server... Open the Word Add-in to test!\n")
cat("Press Esc or Ctrl+C to stop the server when finished.\n")
cat("======================================================\n")

# Start the server synchronously (foreground) so you can test it live in Word
sync_serve("V1Test")
