# ==============================================================================
# Script 2 - Diagnostico de completeness: uso catastral (URBACLAVES_HABITUAL) en el panel
# de inmuebles en alquiler 2023
# ==============================================================================
# Este script NO construye ni modifica la tabla (eso lo hace revPanel2023_join.R,
# script 1); unicamente la lee y calcula ratios para evaluar cuanta informacion
# de uso catastral (URBACLAVES_HABITUAL, Modulo 1 - VIVHAB) esta realmente disponible,
# tanto para el universo completo de inmuebles del panel como para el
# subconjunto que genera alquiler realmente declarado por ESE inmueble concreto
# (INGRESOS_INTEGROS > 0, de RRII - ver README).
#
# Ver README_panel2023_join.md para el detalle de como se construyo "dt" y por
# que existen las columnas IN_VIVHAB / URBACLAVES_HABITUAL / INGRESOS_INTEGROS con los
# valores que tienen.

rm(list = ls()) # limpiar el entorno antes de cargar la tabla evita mezclar objetos de sesiones anteriores

library(data.table)
library(survey) # cargado para analisis posteriores con diseno muestral (FACTORCAL); no se usa todavia en este script

# Leemos la tabla ya unida y exportada por el script 1 (nivel inmueble-arrendador)
dt <- fread("out/2023/2023dt_panel_inmo2.gz")

# ------------------------------------------------------------------------------
# Subconjunto: inmuebles con alquiler realmente declarado por ese inmueble
# ------------------------------------------------------------------------------
# INGRESOS_INTEGROS viene de RRII y esta ya a nivel inmueble (ver README, seccion
# "RRII"): a diferencia del antiguo RENTA_ALQ (persona/hogar, y ademas con
# posiciones incorrectas), aqui cada fila solo entra si ESE arrendador declaro
# alquiler por ESE RC_ANONIMA concreto.
dt_sub <- subset(dt, as.numeric(INGRESOS_INTEGROS) > 0 & !is.na(RC_ANONIMA))

# Total propiedades inmobiliarias en la muestra
print(paste("total prop. inmobiliarias panel: ", nrow(dt)))
print(paste("total prop. inmobiliarias panel CON RC_ANONIMA: ", nrow(dt[!is.na(RC_ANONIMA)])))

# Total propiedades inmobiliarias en la submuestra de inmuebles alquilados
print(paste("total prop. inmobiliarias submuestra inmuebles alquilados: ", nrow(dt_sub)))

# ------------------------------------------------------------------------------
# Completeness de URBACLAVES_HABITUAL: universo completo (dt) vs. subconjunto de alquiler (dt_sub)
# ------------------------------------------------------------------------------
# is.na(URBACLAVES_HABITUAL): tras el fix de fwrite/fread (na = "NA", ver README punto 8),
# esto identifica de forma fiable los inmuebles que NO aparecen en VIVHAB2023.txt
# en absoluto (nadie -ni arrendador ni inquilino- lo declaro como vivienda
# habitual ese anyo).
ratio_a <- dt[is.na(URBACLAVES_HABITUAL), .N] / nrow(dt)
ratio_b <- dt_sub[is.na(URBACLAVES_HABITUAL), .N] / nrow(dt_sub)
ratio_c <- dt[is.na(RC_ANONIMA), .N] / nrow(dt)

print(paste("Porcentaje de NAs sobre muestra de inmuebles:", round(ratio_a, 2)))
print(paste("Porcentaje de NAs sobre submuestra inmuebles alquilados:", round(ratio_b, 2)))
print(paste("Porcentaje de NAs sobre RC_ANONIMA:", round(ratio_c, 2)))

# ------------------------------------------------------------------------------
# Mismo desglose usando el flag booleano IN_VIVHAB en lugar de NA en texto.
# IN_VIVHAB es mas robusto frente a futuras exportaciones (no depende de como
# fwrite/fread manejen los valores ausentes, ver README punto 8).
#
# Calculado sobre dt_sub (no sobre dt completo) para que sea directamente
# comparable con ratio_b de arriba: IN_VIVHAB == FALSE deberia coincidir
# exactamente con is.na(URBACLAVES_HABITUAL) dentro del mismo subconjunto.
# ------------------------------------------------------------------------------
ratio_d <- dt_sub[IN_VIVHAB == FALSE, .N] / nrow(dt_sub) # no aparece en VIVHAB en absoluto
ratio_e <- dt_sub[!is.na(URBACLAVES_HABITUAL), .N] / nrow(dt_sub) # aparece en VIVHAB con RC_ANONIMA válida
ratio_f <- dt_sub[IN_VIVHAB == TRUE & URBACLAVES_HABITUAL != "", .N] / nrow(dt_sub) # aparece con codigo de uso valido

print(paste("no aparece en VIVHAB en absoluto:", round(ratio_d, 2)))
print(paste("aparece en VIVHAB con RC_ANONIMA válida:", round(ratio_e, 2)))
print(paste("aparece con codigo de uso valido", round(ratio_f, 2)))
# Nota: ratio_d + ratio_f no tiene por que sumar 1 -- falta el caso intermedio
# (aparece en VIVHAB pero URBACLAVES_HABITUAL viene vacio: IN_VIVHAB==TRUE & URBACLAVES_HABITUAL==""),
# que se omitio aqui. Si hace falta comprobar que los tres casos cuadran, anyadir
# esa tercera linea con el mismo patron.

# ------------------------------------------------------------------------------
# Nota sobre los codigos de URBACLAVES_HABITUAL distintos de "V" (p.ej. "A"): no indican
# un error de union. El Real Decreto 1020/1993 (normas tecnicas de valoracion
# catastral) clasifica garajes, trasteros y locales en estructura como
# modalidades DENTRO del uso residencial (normas 20.1.1.3, 20.1.2.3 y 20.1.3.2),
# por lo que es esperable que una misma persona tenga varias filas en VIVHAB:
# una con "V" (la vivienda) y otra con el codigo del anexo (garaje/trastero).
# Ver README para el detalle y la comprobacion empirica realizada.
# ------------------------------------------------------------------------------

