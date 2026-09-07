# ==============================================================================
# Script 2 - Diagnóstico, inferencia poblacional y discriminación residencial
# ==============================================================================

gc()
rm(list = ls())

library(data.table)
library(survey)

# 1. Cargar la tabla consolidada a nivel titular-inmueble
dt <- fread("out/2023/2023dt_panel_inmo2.gz")

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
# 4. CLASIFICACIÓN DE USO RESIDENCIAL (VIVIENDA VS GARAJE/LOCAL/OTROS)
# ==============================================================================

# Identificación de naturaleza residencial:
# 1. Catastro acredita viviendas en la parcela: VIV >= 1
# 2. Ocupante la declara como vivienda habitual: URBACLAVE contiene 'V'
# 3. Arrendador declara reducción por vivienda habitual: REDUCCION_REAL > 0
dt[, es_vivienda := (
  (!is.na(VIV) & as.numeric(VIV) >= 1) |
  (!is.na(URBACLAVES_HABITUAL) & grepl("V", URBACLAVES_HABITUAL)) |
  (!is.na(REDUCCION_REAL) & REDUCCION_REAL > 0)
)]

# Exclusión explícita de anexos no residenciales confirmados (garajes 'A', locales 'C')
dt[!is.na(URBACLAVES_HABITUAL) & !grepl("V", URBACLAVES_HABITUAL) & (is.na(VIV) | as.numeric(VIV) == 0), 
   es_vivienda := FALSE]

# ==============================================================================
# 5. ESTIMACIÓN POBLACIONAL
# ==============================================================================

# 5.1 Parque Total vs Parque Residencial
tot_patrimonio_elevado <- dt[, sum(veq, na.rm = TRUE)]
tot_residencial_elevado <- dt[es_vivienda == TRUE, sum(veq, na.rm = TRUE)]

# 5.2 Submuestra de alquiler
dt_sub <- dt[INGRESOS_REALES > 0 & !is.na(RC_ANONIMA)]
dt_sub[, alq_mes_viv_completa := (INGRESOS_REALES / share) / 12]

tot_alq_bruto <- dt_sub[, sum(veq, na.rm = TRUE)]

# Habitual: contrato con reducción art. 23.2 LIRPF
tot_alq_hab <- dt_sub[REDUCCION_REAL > 0, sum(veq, na.rm = TRUE)]
alq_mes_hab <- dt_sub[REDUCCION_REAL > 0, sum(alq_mes_viv_completa * veq, na.rm = TRUE) / sum(veq, na.rm = TRUE)]

# Resto sin reducción: se descompone en vivienda no habitual y no residencial (garajes/locales)
dt_nh <- dt_sub[is.na(REDUCCION_REAL) | REDUCCION_REAL <= 0]
tot_nh_bruto <- dt_nh[, sum(veq, na.rm = TRUE)]

# No habitual residencial depurado (vivienda acreditada y renta anual >= 2.400 €)
dt_nh_residencial <- dt_nh[es_vivienda == TRUE & (INGRESOS_REALES / share) >= 2400]
tot_nh_residencial <- dt_nh_residencial[, sum(veq, na.rm = TRUE)]
alq_mes_nh <- dt_nh_residencial[, sum(alq_mes_viv_completa * veq, na.rm = TRUE) / sum(veq, na.rm = TRUE)]

# Subconjunto estricto con clave 'V' confirmada en VIVHAB
dt_nh_v_pura <- dt_nh[grepl("V", URBACLAVES_HABITUAL) & (INGRESOS_REALES / share) >= 2400]
tot_nh_v_pura <- dt_nh_v_pura[, sum(veq, na.rm = TRUE)]
alq_mes_nh_v <- dt_nh_v_pura[, sum(alq_mes_viv_completa * veq, na.rm = TRUE) / sum(veq, na.rm = TRUE)]

# Anexos y alquiler no residencial (garajes sueltos, trasteros, locales comerciales)
tot_alq_no_residencial <- dt_nh[es_vivienda == FALSE | (INGRESOS_REALES / share) < 2400, sum(veq, na.rm = TRUE)]

# Masa dineraria total declarada (Horvitz-Thompson)
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
cat(sprintf("  * Parque RESIDENCIAL estimado (solo viviendas):              %s viviendas\n\n", fmt_num(tot_residencial_elevado)))

cat("2. MERCADO DEL ALQUILER DECLARADO (Módulo 8 - IRPF)\n")
cat(sprintf("  * Total contratos / inmuebles con alquiler declarado:        %s unidades\n", fmt_num(tot_alq_bruto)))
cat(sprintf("    - Alquiler Habitual (con red. 23.2):                      %s viviendas (Ref. AEAT: ~2.409.689)\n", fmt_num(tot_alq_hab)))
cat(sprintf("      Alquiler medio mensual habitual:                        %s €/mes (Ref. AEAT: 657 €)\n", fmt_num(alq_mes_hab, dec = 2)))
cat(sprintf("    - Alquiler No Habitual RESIDENCIAL (temporada/turismo):    %s viviendas (Ref. AEAT:   ~309.479)\n", fmt_num(tot_nh_residencial)))
cat(sprintf("      Alquiler medio mensual no habitual:                     %s €/mes (Ref. AEAT: 1.361 €)\n", fmt_num(alq_mes_nh, dec = 2)))
cat(sprintf("    - Alquiler NO Residencial (plazas de garaje, trasteros):   %s unidades\n\n", fmt_num(tot_alq_no_residencial)))

cat("3. SENSIBILIDAD: NO HABITUAL CON CLAVE 'V' CONFIRMADA EN VIVHAB\n")
cat(sprintf("  * No habitual con inquilino censado en VIVHAB ('V'):        %s viviendas\n", fmt_num(tot_nh_v_pura)))
cat(sprintf("  * Alquiler medio mensual:                                   %s €/mes\n", fmt_num(alq_mes_nh_v, dec = 2)))
cat("==================================================================\n")
