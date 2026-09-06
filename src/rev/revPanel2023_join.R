# Analyzing microdata structure for subsample INMUEBLES DE ALQUILER

rm(list = ls())

library(data.table)
library(survey)

# leemos la tabla con outer join entre panel2023 y el fichero
dt <- fread("out/2023/2023dt_panel_inmo.gz")

# subset de inmuebles en alquiler
dt_sub <- subset(dt, as.numeric(RENTA_ALQ) > 0)

# testando completeness of set and subset
ratio_a <- dt[is.na(RC_ANONIMA), .N] / nrow(dt)
ratio_b <- dt_sub[is.na(URBACLAVE), .N] / nrow(dt_sub)
ratio_c <- dt_sub[URBACLAVE == "", .N] / nrow(dt_sub)
print(paste("Porcentaje de NAs sobre muestra de inmuebles:", round(ratio_a, 2)))
print(paste("Porcentaje de NAs sobre submuestra inmuebles alquilados:", round(ratio_b, 2)))
print(paste("Porcentaje de inmuebles con URBACLAVE vacia sobre total alquiler:", round(ratio_c, 2)))


ratio_d <- dt[IN_VIVHAB == FALSE, .N] / nrow(dt) # no aparece en VIVHAB en absoluto
ratio_e <- dt[IN_VIVHAB == TRUE & URBACLAVE == "", .N] / nrow(dt) # aparece, pero URBACLAVE viene en blanco
ratio_f <- dt[IN_VIVHAB == TRUE & URBACLAVE != "", .N] / nrow(dt) # aparece con codigo de uso valido

print(paste("no aparece en VIVHAB en absoluto:", round(ratio_d, 2)))
print(paste("aparece, pero URBACLAVE viene en blanco", round(ratio_e, 2)))
print(paste("aparece con codigo de uso valido", round(ratio_f, 2)))
