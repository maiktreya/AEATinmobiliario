# Analyzing microdata structure

rm(list = ls())
library(data.table)


# dt <- fread("data/2023/panel_inmo_2023_full.gz")
dt <- fread("data/2023/panel_inmo_2023_linked.gz")
# dt <- fread("data/2023/vivhab_2023.gz")


print(summary(dt))
length(dt[URBACLAVE == "V"]$URBACLAVE) / length(dt$URBACLAVE)
