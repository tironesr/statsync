sink("out_anova.txt")

library(lmerTest)
library(car)
library(broom.mixed)

m1 <- lmerTest::lmer(mpg ~ wt + (1|cyl), data=mtcars)
cat("Class of lmer:\n")
print(class(m1))
t1 <- tidy(m1, effects='fixed', conf.int=TRUE)
print(as.data.frame(t1))

cat("\n================\n")

m2 <- lm(mpg ~ wt + hp, data=mtcars)
a1 <- car::Anova(m2, type=2)
cat("Class of car::Anova:\n")
print(class(a1))
print(a1)
print(as.data.frame(broom::tidy(a1)))

sink()
