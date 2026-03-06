# ============================================================
# StatSync Example Analysis
# ============================================================

library(statsync)

# Set working directory
setwd("C:/Users/Tyrone/Documents/statsync/example")


out <- lm(Sepal.Length ~ Sepal.Width + Petal.Length, data = iris);out

sync_export(sync_stats(out, label = "iris1"),
            project_name = "Iris Test")



# ============================================================
# 6. EXPORT TO JSON
# ============================================================

sync_export(
  sync_ttest,
  sync_cor1,
  sync_cor2,
  sync_simple,
  sync_full,
  sync_anova,
  sync_chisq,
  sync_logistic,
  sync_desc,
  reg_table,
  cor_table,
  project_name = "MPG Analysis"
)


