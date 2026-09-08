# ==============================================================================
# Script 2 (dev) - Diagnostico, inferencia poblacional y conciliacion del parque
# Archivo: src/rev/revPanel2023_join_dev.R
#
# Variante de desarrollo de revPanel2023_join.R que anade la seccion 5.3:
# conciliacion del parque residencial fisico con el censo de viviendas declaradas
# en IRPF (Tabla AEAT 18.069.370), aislando la nuda propiedad pura y forzando un
# maximo de una vivienda habitual por declarante.
#
# Requiere el panel regenerado por src/joint/getPanel2023_join.R:
#   * importes ya en euros reales y FACTORCAL con decimal explicito (asserts lo verifican)
#   * placeholders (declarantes sin inmuebles) excluidos del panel
#   * DIAS_ARREND (dias de contrato del Modulo 8, campo PAR101) disponible
#
# Inferencia: veq = share x FACTORCAL (GWSM); EE por linealizacion de Taylor
# sobre el diseño estratificado AEAT (estratos TRAMO, conglomerados IDENHOG).
# ==============================================================================

gc()
rm(list = ls())

library(data.table)
library(survey)

options(survey.lonely.psu = "adjust")

# ------------------------------------------------------------------------------
# Parametros
# ------------------------------------------------------------------------------
panel_path             <- "out/2023/2023dt_panel_inmo.gz"
umbral_residencial_eur <- 2400
dias_aeat_habitual     <- 339
dias_aeat_no_habitual  <- 271

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
fmt_num <- function(x, dec = 0) {
  if (is.na(x) || !is.finite(x)) return("NA")
  formatC(x, format = "f", digits = dec, big.mark = ".", decimal.mark = ",")
}

assert_center <- function(x, lo, hi, label, prob = 0.5) {
  q <- quantile(x, prob, na.rm = TRUE)
  if (is.na(q) || q < lo || q > hi) {
    stop(sprintf("ASSERT FALLIDO (%s): cuantil %.0f%% = %.6g fuera de [%.6g, %.6g]. Regenere el panel con src/joint/getPanel2023_join.R",
                 label, 100 * prob, q, lo, hi))
  }
  invisible(TRUE)
}

fmt_est <- function(est, se, dec = 0) {
  if (is.na(est) || is.na(se)) return("NA")
  cv <- if (est != 0) 100 * se / est else NA_real_
  sprintf("%s (EE %s; CV %.2f%%)", fmt_num(est, dec), fmt_num(se, dec), cv)
}

# ==============================================================================
# 1. CARGA Y VERIFICACION DE ESCALAS
# ==============================================================================
dt <- fread(panel_path)

cols_req <- c("FACTORCAL", "URBAPORBIN", "DIAS_ARREND", "IDENHOG", "TRAMO",
              "INGRESOS_INTEGROS", "REDUCCION_ALQUILER_VIVIENDA",
              "URBACLAVES_HABITUAL", "VIV", "URBACODERE", "RC_ANONIMA")
faltan <- setdiff(cols_req, names(dt))
if (length(faltan) > 0) {
  stop("Panel desactualizado, faltan columnas: ", paste(faltan, collapse = ", "),
       ". Regenere con src/joint/getPanel2023_join.R")
}

assert_center(dt$FACTORCAL, 0.5, 100, "FACTORCAL (decimal explicito)")
assert_center(dt[INGRESOS_INTEGROS > 0, INGRESOS_INTEGROS], 2000, 30000,
              "INGRESOS_INTEGROS (euros)")
assert_center(dt[URBAPORBIN > 0, URBAPORBIN], 1, 100, "URBAPORBIN (escala 0-100)")

dt[, INGRESOS_REALES := as.numeric(INGRESOS_INTEGROS)]
dt[, REDUCCION_REAL  := as.numeric(REDUCCION_ALQUILER_VIVIENDA)]

# ==============================================================================
# 2. AUDITORIA DE REGISTROS Y COMPLETITUD
# ==============================================================================
cat("------------------------------------------------------------------\n")
cat("AUDITORIA DE REGISTROS MUESTRALES\n")
cat("------------------------------------------------------------------\n")
cat(sprintf("Total registros en panel (titulos reales INM_PR):        %s\n", fmt_num(nrow(dt))))
cat(sprintf("Total declarantes con titulos:                          %s\n", fmt_num(uniqueN(dt$IDENPER))))
cat(sprintf("Total registros con RC_ANONIMA:                        %s\n", fmt_num(dt[!is.na(RC_ANONIMA), .N])))
cat(sprintf("Total registros con alquiler declarado (submuestra):    %s\n\n", fmt_num(dt[INGRESOS_REALES > 0 & !is.na(RC_ANONIMA), .N])))
cat(sprintf("Porcentaje con VIVHAB en panel completo:                 %.2f\n",
            dt[IN_VIVHAB == TRUE, .N] / nrow(dt)))
cat(sprintf("Porcentaje con VIVHAB en submuestra de alquiler:        %.2f\n",
            dt[INGRESOS_REALES > 0 & IN_VIVHAB == TRUE, .N] / dt[INGRESOS_REALES > 0, .N]))
cat(sprintf("Porcentaje con INM_CARACT en submuestra de alquiler:    %.2f\n\n",
            dt[INGRESOS_REALES > 0 & IN_CARACT == TRUE, .N] / dt[INGRESOS_REALES > 0, .N]))
cat(sprintf("Filas sin FACTORCAL (excluidas del diseño muestral):   %s\n\n",
            fmt_num(dt[is.na(FACTORCAL), .N])))

# ==============================================================================
# 3. PESOS GWSM CON IMPUTACION DE share AUDITADA
# ==============================================================================
dt[, share_imputado := (is.na(URBAPORBIN) | URBAPORBIN <= 0)]
dt[, share := fifelse(share_imputado, 1, pmin(pmax(URBAPORBIN / 100, 0), 1))]

cat(sprintf("Cuotas imputadas a share=1 (NA o <=0%%):                %s filas (veq: %s)\n",
            fmt_num(dt[share_imputado == TRUE, .N]),
            fmt_num(dt[share_imputado == TRUE, sum(share * FACTORCAL, na.rm = TRUE)])))

dt[, veq := share * FACTORCAL]

# ==============================================================================
# 4. CLASIFICACION RESIDENCIAL FISICA Y DERECHOS REALES
# ==============================================================================
# 4.1 Naturaleza residencial fisica
dt[, es_vivienda := (
  (!is.na(VIV) & VIV >= 1) |
  (!is.na(URBACLAVES_HABITUAL) & grepl("V", URBACLAVES_HABITUAL)) |
  (!is.na(REDUCCION_REAL) & REDUCCION_REAL > 0)
)]
dt[!is.na(URBACLAVES_HABITUAL) & !grepl("V", URBACLAVES_HABITUAL) & (is.na(VIV) | VIV == 0),
   es_vivienda := FALSE]

# 4.2 Nuda propiedad pura ('NP' sin 'PR' ni 'US'): el nudo propietario no imputa
# rentas ni declara alquiler en IRPF (art. 85 LIRPF); tributa el usufructuario
dt[, es_nuda_pura := (
  !is.na(URBACODERE) & grepl("NP", URBACODERE) & !grepl("PR|US", URBACODERE)
)]
cat(sprintf("Titulos de nuda propiedad pura:                         %s (veq: %s)\n\n",
            fmt_num(dt[es_nuda_pura == TRUE, .N]),
            fmt_num(dt[es_nuda_pura == TRUE, sum(veq, na.rm = TRUE)])))

# ==============================================================================
# 5. SUBMUESTRA DE ALQUILER: DIAS REALES DE CONTRATO Y SEGMENTACION
# ==============================================================================
dt[, es_alquiler := (INGRESOS_REALES > 0 & !is.na(RC_ANONIMA))]
dt[, ing_anual_pleno := INGRESOS_REALES / share]
dt[, alq_mes_flujo := fifelse(es_alquiler, ing_anual_pleno / 12, NA_real_)]

dt[, dias_arr := fifelse(es_alquiler & !is.na(DIAS_ARREND) & DIAS_ARREND > 0,
                         pmin(as.numeric(DIAS_ARREND), 365), NA_real_)]
dt[, es_habitual_revisado := (
  (!is.na(REDUCCION_REAL) & REDUCCION_REAL > 0) |
  (!is.na(URBACLAVES_HABITUAL) & grepl("V", URBACLAVES_HABITUAL))
)]
dt[es_alquiler == TRUE & is.na(dias_arr),
   dias_arr := fifelse(es_habitual_revisado == TRUE, dias_aeat_habitual, dias_aeat_no_habitual)]
dt[, alq_mes_aeat := alq_mes_flujo * (365 / dias_arr)]

dt[, alq_veq_flujo := share * alq_mes_flujo]
dt[, alq_veq_aeat  := share * alq_mes_aeat]

n_alq  <- dt[es_alquiler == TRUE, .N]
n_dias <- dt[es_alquiler == TRUE & !is.na(DIAS_ARREND) & DIAS_ARREND > 0, .N]
cat(sprintf("Dias de contrato observados en submuestra de alquiler:  %s de %s (%.2f%%)\n",
            fmt_num(n_dias), fmt_num(n_alq), 100 * n_dias / n_alq))

# ==============================================================================
# 6. CONCILIACION DEL PARQUE RESIDENCIAL (habitual / arrendada / a disposicion)
# ==============================================================================
dt[, es_alquiler_residencial := (es_vivienda == TRUE & es_alquiler == TRUE)]

# A) Vivienda habitual en propiedad censada (VIVHAB)
dt[, es_hab_prop_catastro := (
  es_vivienda == TRUE & !es_alquiler_residencial &
  IN_VIVHAB == TRUE & !is.na(URBACLAVES_HABITUAL) & grepl("V", URBACLAVES_HABITUAL)
)]

# Vivienda habitual declarada en IRPF: maximo 1 por declarante, priorizando la
# cuota mas alta; sin nuda propiedad pura
setorder(dt, IDENPER, -share, -veq)
dt[, es_hab_prop_irpf := FALSE]
dt[es_hab_prop_catastro == TRUE & es_nuda_pura == FALSE,
   es_hab_prop_irpf := (seq_len(.N) == 1L), by = IDENPER]

# B) Viviendas arrendadas (habitual + no habitual residencial al umbral)
dt[, es_arrendada_irpf := (
  es_alquiler == TRUE & (
    es_habitual_revisado == TRUE |
    (es_vivienda == TRUE & ing_anual_pleno >= umbral_residencial_eur)
  )
)]

# C) Segundas residencias / a disposicion declaradas IRPF: residencial no
# alquilado, no habitual y sin nuda propiedad pura
dt[, es_a_disp_fiscal := (
  es_vivienda == TRUE & !es_alquiler_residencial & !es_hab_prop_irpf & es_nuda_pura == FALSE
)]

# ==============================================================================
# 7. DISEÑO MUESTRAL (estratos TRAMO, conglomerados IDENPER, pesos FACTORCAL)
# ==============================================================================
dt_design <- dt[!is.na(FACTORCAL) & !is.na(IDENPER) & !is.na(TRAMO)]
des <- svydesign(ids = ~IDENPER, strata = ~TRAMO, weights = ~FACTORCAL,
                 data = dt_design, nest = TRUE)

tot_se <- function(dom_expr, v = "share") {
  d <- if (isTRUE(dom_expr)) des else subset(des, dom_expr)
  e <- svytotal(as.formula(paste0("~", v)), d)
  c(est = as.numeric(coef(e)), se = as.numeric(SE(e)))
}
ratio_se <- function(dom_expr, num, den = "share") {
  d <- if (isTRUE(dom_expr)) des else subset(des, dom_expr)
  e <- svyratio(as.formula(paste0("~", num)), as.formula(paste0("~", den)), d)
  c(est = as.numeric(coef(e)), se = as.numeric(SE(e)))
}
D <- function(col) dt_design[[col]]

# ==============================================================================
# 8. ESTIMACIONES
# ==============================================================================
parque_total       <- tot_se(TRUE)
parque_residencial <- tot_se(D("es_vivienda"))

dom_hab  <- D("es_alquiler") & D("es_habitual_revisado")
dom_nh   <- D("es_alquiler") & !D("es_habitual_revisado") &
            D("es_vivienda") & D("ing_anual_pleno") >= umbral_residencial_eur
dom_nores <- D("es_alquiler") & !D("es_habitual_revisado") &
             (!D("es_vivienda") | D("ing_anual_pleno") < umbral_residencial_eur)

alq_bruto   <- tot_se(D("es_alquiler"))
alq_hab     <- tot_se(dom_hab)
alq_hab_red <- tot_se(D("es_alquiler") & !is.na(D("REDUCCION_REAL")) & D("REDUCCION_REAL") > 0)
alq_hab_vivh <- tot_se(D("es_alquiler") & (is.na(D("REDUCCION_REAL")) | D("REDUCCION_REAL") <= 0) &
                        !is.na(D("URBACLAVES_HABITUAL")) & grepl("V", D("URBACLAVES_HABITUAL")))
alq_nh      <- tot_se(dom_nh)
alq_nores   <- tot_se(dom_nores)

alq_hab_flujo <- ratio_se(dom_hab, "alq_veq_flujo")
alq_hab_aeat  <- ratio_se(dom_hab, "alq_veq_aeat")
alq_nh_flujo  <- ratio_se(dom_nh, "alq_veq_flujo")
alq_nh_aeat   <- ratio_se(dom_nh, "alq_veq_aeat")

masa_e <- svytotal(~INGRESOS_REALES,
                   subset(des, !is.na(D("INGRESOS_REALES")) & D("INGRESOS_REALES") > 0))

# Conciliacion A / B / C
hab_prop_catastro <- tot_se(D("es_hab_prop_catastro"))
hab_prop_irpf     <- tot_se(D("es_hab_prop_irpf"))
arrendada_irpf    <- tot_se(D("es_arrendada_irpf"))
a_disp_fiscal     <- tot_se(D("es_a_disp_fiscal"))
a_disp_catastro   <- tot_se(D("es_vivienda") & !D("es_alquiler_residencial") & !D("es_hab_prop_irpf"))
dom_total_decl <- D("es_hab_prop_irpf") | D("es_arrendada_irpf") | D("es_a_disp_fiscal")
total_decl      <- tot_se(dom_total_decl)

# ==============================================================================
# 9. RESULTADOS FORMATEADOS
# ==============================================================================
cat("==================================================================\n")
cat("RESULTADOS DE INFERENCIA POBLACIONAL (GWSM: share x FACTORCAL)\n")
cat("EE por linealizacion de Taylor (estratos TRAMO, conglomerados IDENPER)\n")
cat("==================================================================\n")
cat(sprintf("Factor de elevacion medio (filas del panel):           %s\n",
            fmt_num(mean(dt$FACTORCAL, na.rm = TRUE), dec = 2)))
cat(sprintf("Masa de ingresos por alquiler unida al panel:          %s EUR\n",
            fmt_est(as.numeric(coef(masa_e)), as.numeric(SE(masa_e)))))
cat("(Cobertura de la masa declarada del Modulo 8: ver auditoria de uniones del script 1)\n\n")

cat("1. PARQUE RESIDENCIAL FISICO CATASTRAL (INM_PR - Escala INE)\n")
cat(sprintf("  * Parque Inmobiliario TOTAL (viviendas + garajes + locales): %s unidades\n",
            fmt_est(parque_total[1], parque_total[2])))
cat(sprintf("  * Parque RESIDENCIAL FISICO (viviendas Catastro declarantes): %s viviendas\n",
            fmt_est(parque_residencial[1], parque_residencial[2])))
cat("    (Nota: concuerda con los 26,6M del Censo INE deduciendo Pais Vasco, Navarra, sociedades y no residentes)\n\n")

cat("2. CONCILIACION CON EL CENSO DE VIVIENDAS DECLARADAS EN IRPF (Tabla AEAT 18.069.370)\n")
cat(sprintf("  * A. Vivienda habitual en propiedad declarada en IRPF:  %s viviendas (Ref. AEAT: 10.460.700)\n",
            fmt_est(hab_prop_irpf[1], hab_prop_irpf[2])))
cat(sprintf("       (Censadas en Catastro VIVHAB: %s viv; exceso = no declarantes IRPF)\n",
            fmt_num(hab_prop_catastro[1])))
cat(sprintf("  * B. Viviendas arrendadas (Habitual + No habitual):    %s viviendas (Ref. AEAT:  2.738.472)\n",
            fmt_est(arrendada_irpf[1], arrendada_irpf[2])))
cat(sprintf("  * C. Segundas residencias / A disposicion IRPF:         %s viviendas (Ref. AEAT:  4.870.198)\n",
            fmt_est(a_disp_fiscal[1], a_disp_fiscal[2])))
cat(sprintf("       (Total censadas en Catastro: %s viv; diferencia = nuda propiedad pura)\n",
            fmt_num(a_disp_catastro[1])))
cat("  ----------------------------------------------------------------------------------------------\n")
cat(sprintf("  * TOTAL VIVIENDAS DECLARADAS IRPF ESTIMADAS:            %s viviendas (Ref. AEAT: 18.069.370)\n\n",
            fmt_est(total_decl[1], total_decl[2])))

cat("3. MERCADO DEL ALQUILER DECLARADO (Modulo 8 - IRPF)\n")
cat(sprintf("  * Submuestra con alquiler (n crudo):                  %s unidades\n", fmt_num(n_alq)))
cat(sprintf("  * Total contratos / inmuebles con alquiler declarado:  %s unidades\n",
            fmt_est(alq_bruto[1], alq_bruto[2])))

cat(sprintf("\n    - Alquiler Habitual CONVERGENTE:                     %s viviendas (Ref. AEAT: 2.409.689)\n",
            fmt_est(alq_hab[1], alq_hab[2])))
cat(sprintf("        . Declaradas con reduccion art. 23.2:            %s viviendas\n",
            fmt_est(alq_hab_red[1], alq_hab_red[2])))
cat(sprintf("        . Reclasificadas con inquilino en VIVHAB ('V'):   %s viviendas\n",
            fmt_est(alq_hab_vivh[1], alq_hab_vivh[2])))
cat(sprintf("      Renta media mensual habitual (flujo anual / 12):    %s EUR/mes\n",
            fmt_est(alq_hab_flujo[1], alq_hab_flujo[2], 2)))
cat(sprintf("      Renta media mensual habitual (anualizada AEAT):     %s EUR/mes (Ref. AEAT: 657 EUR)\n",
            fmt_est(alq_hab_aeat[1], alq_hab_aeat[2], 2)))

cat(sprintf("\n    - Alquiler No Habitual RESIDENCIAL (umbral %s EUR/anual):\n", fmt_num(umbral_residencial_eur)))
cat(sprintf("      Total:                                             %s viviendas (Ref. AEAT:   309.479)\n",
            fmt_est(alq_nh[1], alq_nh[2])))
cat(sprintf("      Renta media mensual no habitual (flujo anual / 12): %s EUR/mes\n",
            fmt_est(alq_nh_flujo[1], alq_nh_flujo[2], 2)))
cat(sprintf("      Renta media mensual no habitual (anualizada AEAT):   %s EUR/mes (Ref. AEAT: 1.361 EUR)\n",
            fmt_est(alq_nh_aeat[1], alq_nh_aeat[2], 2)))

cat(sprintf("\n    - Alquiler NO Residencial (garajes, trasteros, locales): %s unidades\n",
            fmt_est(alq_nores[1], alq_nores[2])))
cat("==================================================================\n")