sink("out_nested_anova.txt")

m1 <- lm(mpg ~ wt, data=mtcars)
m2 <- lm(mpg ~ wt + hp, data=mtcars)
a1 <- anova(m1, m2)

cat("Class of nested anova:\n")
print(class(a1))
cat("\nObject:\n")
print(a1)
cat("\nAs data frame:\n")
print(as.data.frame(a1))

cat("\n================\n")

# GLM version
m3 <- glm(am ~ wt, data=mtcars, family=binomial)
m4 <- glm(am ~ wt + hp, data=mtcars, family=binomial)
a2 <- anova(m3, m4, test="Chisq")
cat("Nested GLM anova:\n")
print(a2)
cat("\nAs data frame:\n")
print(as.data.frame(a2))

sink()
