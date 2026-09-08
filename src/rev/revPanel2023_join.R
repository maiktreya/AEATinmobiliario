# ==============================================================================
# Script 2 - Diagnóstico, inferencia poblacional y discriminación residencial
# Archivo: src/rev/revPanel2023_join.R
# ==============================================================================

gc()
rm(list = ls())

library(data.table)
library(survey)

# 1. Cargar la tabla consolidada a nivel titular-inmueble
dt <- fread("out/2023/2023dt_panel_inmo.gz")

fmt_num <- function(x, dec = 0) {
  if (is.na(x) || !is.finite(x)) return("NA")
  formatC(x, format = "f", digits = dec, big.mark = ".", decimal.mark = ",")
}

# ==============================================================================
# 2. DIAGNÓSTICO DE REGISTROS Y COMPLETITUD CATASTRAL
# ==============================================================================
dt_sub <- dt[as.numeric(INGRESOS_INTEGROS) > 0 & !is.na(RC_ANONIMA)]

cat("------------------------------------------------------------------\n")
cat("AUDITORÍA DE REGISTROS MUESTRALES\n")
cat("------------------------------------------------------------------\n")
cat(sprintf("Total registros en panel (INM_PR consolidado):           %s\n", fmt_num(nrow(dt))))
cat(sprintf("Total registros con RC_ANONIMA:                          %s\n", fmt_num(nrow(dt[!is.na(RC_ANONIMA)]))))
cat(sprintf("Total registros con alquiler declarado (submuestra):     %s\n\n", fmt_num(nrow(dt_sub))))

cat(sprintf("Porcentaje sin VIVHAB en panel completo:                 %.2f\n", dt[is.na(URBACLAVES_HABITUAL), .N] / nrow(dt)))
cat(sprintf("Porcentaje sin VIVHAB en submuestra de alquiler:         %.2f\n", dt_sub[is.na(URBACLAVES_HABITUAL), .N] / nrow(dt_sub)))
cat(sprintf("Porcentaje sin RC_ANONIMA (extranjero/foral/no ref):     %.2f\n\n", dt[is.na(RC_ANONIMA), .N] / nrow(dt)))

# ==============================================================================
# 3. ESCALADO DE PESOS Y NORMALIZACIÓN DE VARIABLES
# ==============================================================================

# A. Factor de elevación (FACTORCAL)
fc_raw <- as.numeric(dt$FACTORCAL)
if (median(fc_raw, na.rm = TRUE) > 1000) {
  dt[, FACTORCAL_NUM := fc_raw / 1e10]
} else {
  dt[, FACTORCAL_NUM := fc_raw]
}

# B. Cuota de titularidad (share en escala 0.0 a 1.0)
porc <- as.numeric(dt$URBAPORBIN)
if (quantile(porc[porc > 0], 0.9, na.rm = TRUE) > 1) {
  dt[, share := pmin(pmax(porc / 100, 0), 1)]
} else {
  dt[, share := pmin(pmax(porc, 0), 1)]
}
dt[is.na(share) | share <= 0, share := 1.0]

# C. Importes monetarios corregidos
if (mean(as.numeric(dt_sub$INGRESOS_INTEGROS), na.rm = TRUE) < 200) {
  dt[, INGRESOS_REALES := as.numeric(INGRESOS_INTEGROS) * 100]
  dt[, REDUCCION_REAL  := as.numeric(REDUCCION_ALQUILER_VIVIENDA) * 100]
} else {
  dt[, INGRESOS_REALES := as.numeric(INGRESOS_INTEGROS)]
  dt[, REDUCCION_REAL  := as.numeric(REDUCCION_ALQUILER_VIVIENDA)]
}

# D. Elevación en viviendas equivalentes (GWSM)
dt[, veq := share * FACTORCAL_NUM]

# ==============================================================================
# 4. CLASIFICACIÓN RESIDENCIAL: BASE (20,9M) VS ALTERNATIVA FISCAL (18,07M)
# ==============================================================================

# Métricas físicas auxiliares
dt[, m2_por_viv := fifelse(!is.na(VIV) & as.numeric(VIV) > 0 & !is.na(VIV_METROS), 
                           as.numeric(VIV_METROS) / as.numeric(VIV), NA_real_)]

# ------------------------------------------------------------------------------
# 4.1 Criterio Base (es_vivienda): Parque Físico Residencial en manos de personas físicas
# ------------------------------------------------------------------------------
dt[, es_vivienda := (
  (!is.na(VIV) & as.numeric(VIV) >= 1) |
  (!is.na(URBACLAVES_HABITUAL) & grepl("V", URBACLAVES_HABITUAL)) |
  (!is.na(REDUCCION_REAL) & REDUCCION_REAL > 0)
)]

# Exclusión explícita de anexos no residenciales confirmados (garajes 'A', locales 'C')
dt[!is.na(URBACLAVES_HABITUAL) & !grepl("V", URBACLAVES_HABITUAL) & (is.na(VIV) | as.numeric(VIV) == 0), 
   es_vivienda := FALSE]

# ------------------------------------------------------------------------------
# 4.2 Criterio Alternativo (es_vivienda_alt): Réplica Fiscal Declarada (AEAT ~18M)
# ------------------------------------------------------------------------------
# A) Nuda Propiedad Pura: tiene derecho 'NP' pero NO tiene pleno dominio 'PR' ni usufructo 'US'.
#    El nudo propietario no declara la vivienda en IRPF (art. 22 y 85 LIRPF); imputa el usufructuario.
dt[, es_nuda_propiedad_pura := (
  !is.na(URBACODERE) & grepl("NP", URBACODERE) & !grepl("PR|US", URBACODERE)
)]

# B) Infravivienda / Trastero con VIV=1: superficie por vivienda < 25 m² sin contrato de alquiler de vivienda
dt[, es_anexo_o_trastero := (
  !is.na(m2_por_viv) & m2_por_viv < 25 & (is.na(REDUCCION_REAL) | REDUCCION_REAL <= 0)
)]

# Regla combinada: cumple criterio residencial, posee derecho con aprovechamiento fiscal y metraje habitable
dt[, es_vivienda_alt := es_vivienda & !es_nuda_propiedad_pura & !es_anexo_o_trastero]

# ==============================================================================
# 5. ESTIMACIÓN POBLACIONAL Y RECLASIFICACIÓN DE ALQUILER
# ==============================================================================

# 5.1 Totales de Parque Inmobiliario
tot_patrimonio_elevado     <- dt[, sum(veq, na.rm = TRUE)]
tot_residencial_elevado    <- dt[es_vivienda == TRUE, sum(veq, na.rm = TRUE)]
tot_residencial_alt_elevado <- dt[es_vivienda_alt == TRUE, sum(veq, na.rm = TRUE)]

# 5.2 Submuestra de alquiler
dt_sub <- dt[INGRESOS_REALES > 0 & !is.na(RC_ANONIMA)]

# Alquiler mensual básico al 100% de propiedad (flujo de caja anual / 12)
dt_sub[, alq_mes_flujo := (INGRESOS_REALES / share) / 12]

# Alquiler mensual equivalente AEAT (anualizado según días de ocupación)
if ("DIAS_101" %in% names(dt_sub)) {
  dt_sub[, dias_arr := fifelse(!is.na(DIAS_101) & DIAS_101 > 0, pmin(as.numeric(DIAS_101), 365), NA_real_)]
} else {
  dt_sub[, dias_arr := NA_real_]
}

# Reclasificación robusta de vivienda habitual: con reducción 23.2 O con inquilino 'V' en VIVHAB
dt_sub[, es_habitual_revisado := (
  (!is.na(REDUCCION_REAL) & REDUCCION_REAL > 0) |
  (!is.na(URBACLAVES_HABITUAL) & grepl("V", URBACLAVES_HABITUAL))
)]

# Imputación de días medios censales AEAT si no consta casilla 101 individualizada
dt_sub[is.na(dias_arr), dias_arr := fifelse(es_habitual_revisado == TRUE, 339, 271)]
dt_sub[, alq_mes_aeat := alq_mes_flujo * (365 / dias_arr)]

# 5.3 Segmentación de Mercado
tot_alq_bruto <- dt_sub[, sum(veq, na.rm = TRUE)]

# A. Alquiler Habitual (convergente con censo de domicilios)
dt_hab <- dt_sub[es_habitual_revisado == TRUE]
tot_alq_hab       <- dt_hab[, sum(veq, na.rm = TRUE)]
alq_mes_hab_flujo <- dt_hab[, sum(alq_mes_flujo * veq, na.rm = TRUE) / sum(veq, na.rm = TRUE)]
alq_mes_hab_aeat  <- dt_hab[, sum(alq_mes_aeat * veq, na.rm = TRUE) / sum(veq, na.rm = TRUE)]

tot_hab_con_reduccion <- dt_sub[!is.na(REDUCCION_REAL) & REDUCCION_REAL > 0, sum(veq, na.rm = TRUE)]
tot_hab_incorporadas  <- dt_sub[(is.na(REDUCCION_REAL) | REDUCCION_REAL <= 0) & grepl("V", URBACLAVES_HABITUAL), sum(veq, na.rm = TRUE)]

# B. Alquiler No Habitual Residencial Depurado (>= 2.400 € y naturaleza residencial)
dt_nh_residencial <- dt_sub[es_habitual_revisado == FALSE & es_vivienda_alt == TRUE & (INGRESOS_REALES / share) >= 2400]
tot_nh_residencial <- dt_nh_residencial[, sum(veq, na.rm = TRUE)]
alq_mes_nh_flujo  <- dt_nh_residencial[, sum(alq_mes_flujo * veq, na.rm = TRUE) / sum(veq, na.rm = TRUE)]
alq_mes_nh_aeat   <- dt_nh_residencial[, sum(alq_mes_aeat * veq, na.rm = TRUE) / sum(veq, na.rm = TRUE)]

# C. Alquiler No Residencial (garajes, trasteros, locales)
tot_alq_no_residencial <- dt_sub[es_habitual_revisado == FALSE & (es_vivienda_alt == FALSE | (INGRESOS_REALES / share) < 2400), sum(veq, na.rm = TRUE)]

# Masa dineraria total declarada
masa_alquiler_total <- dt[, sum(INGRESOS_REALES * FACTORCAL_NUM, na.rm = TRUE)]

# ==============================================================================
# 6. RESULTADOS FORMATEADOS
# ==============================================================================
cat("==================================================================\n")
cat("RESULTADOS DE INFERENCIA POBLACIONAL (FACTORCAL x cuota)\n")
cat("==================================================================\n")
cat(sprintf("Factor de elevación medio:                                %s\n", fmt_num(mean(dt$FACTORCAL_NUM, na.rm = TRUE), dec = 2)))
cat(sprintf("Masa total de ingresos por alquiler declarada:            %s €\n\n", fmt_num(masa_alquiler_total)))

cat("1. PARQUE INMOBILIARIO EN MANOS DE DECLARANTES IRPF\n")
cat(sprintf("  * Parque Inmobiliario TOTAL (viviendas + garajes + locales): %s unidades\n", fmt_num(tot_patrimonio_elevado)))
cat(sprintf("  * Parque RESIDENCIAL FÍSICO (es_vivienda - Escala INE):      %s viviendas\n", fmt_num(tot_residencial_elevado)))
cat(sprintf("  * Parque RESIDENCIAL DECLARADO (es_vivienda_alt - Ref AEAT): %s viviendas (Ref. AEAT: 18.069.370)\n\n", fmt_num(tot_residencial_alt_elevado)))

cat("2. MERCADO DEL ALQUILER DECLARADO (Módulo 8 - IRPF)\n")
cat(sprintf("  * Total contratos / inmuebles con alquiler declarado:        %s unidades\n", fmt_num(tot_alq_bruto)))

cat(sprintf("    - Alquiler Habitual CONVERGENTE:                          %s viviendas (Ref. AEAT: 2.409.689)\n", fmt_num(tot_alq_hab)))
cat(sprintf("        · Declaradas con reducción art. 23.2:                 %s viviendas\n", fmt_num(tot_hab_con_reduccion)))
cat(sprintf("        · Reclasificadas con inquilino en VIVHAB ('V'):         %s viviendas\n", fmt_num(tot_hab_incorporadas)))
cat(sprintf("      Alquiler medio mensual habitual (flujo anual / 12):       %s €/mes\n", fmt_num(alq_mes_hab_flujo, dec = 2)))
cat(sprintf("      Alquiler medio mensual habitual (anualizado AEAT):        %s €/mes (Ref. AEAT: 657 €)\n\n", fmt_num(alq_mes_hab_aeat, dec = 2)))

cat(sprintf("    - Alquiler No Habitual RESIDENCIAL CONVERGENTE:             %s viviendas (Ref. AEAT:   309.479)\n", fmt_num(tot_nh_residencial)))
cat(sprintf("      Alquiler medio mensual no habitual (flujo anual / 12):    %s €/mes\n", fmt_num(alq_mes_nh_flujo, dec = 2)))
cat(sprintf("      Alquiler medio mensual no habitual (anualizado AEAT):    %s €/mes (Ref. AEAT: 1.361 €)\n\n", fmt_num(alq_mes_nh_aeat, dec = 2)))

cat(sprintf("    - Alquiler NO Residencial (plazas de garaje, trasteros):    %s unidades\n", fmt_num(tot_alq_no_residencial)))
cat("==================================================================\n")
