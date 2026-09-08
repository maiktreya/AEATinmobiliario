# ==============================================================================
# Script 1 - Construccion del panel consolidado titular-inmueble
# Archivo: src/joint/getPanel2023_join.R
#
# Codificaciones VERIFICADAS empiricamente (doc/DiseñoRegistro_2023.xlsx esta
# desactualizado en los campos monetarios del M100):
#   * _1_IDEN:    FACTORCAL es decimal EXPLICITO de 20 posiciones (ej. "11.6906688868").
#   * _2_Renta:   importes en EUROS enteros (sin decimales implicitos).
#   * _8_RRII:    importes en EUROS enteros; PAR101 (pos 148-153) = dias de arrendamiento.
#   * INM_PR:     porcentajes y valores con decimal EXPLICITO (ej. "100.00", "16969.36").
#   * INM_CARACT: superficies y valores con decimal EXPLICITO (ej. "110.00", "11056.55").
# ==============================================================================

library(magrittr)
library(readr)
library(data.table)

gc()
sel_year  <- 2023
data_path <- paste0("data/", sel_year, "/")
out_path  <- paste0("out/", sel_year, "/")

dir.create(out_path, recursive = TRUE, showWarnings = FALSE)

# Fast loader helper: converts in-place to data.table without caching raw tibbles
read_dt_fwf <- function(file, positions, types, col_names) {
  dt <- setDT(read_fwf(
    file,
    col_positions = positions,
    col_types = types,
    na = c("", "NA", "."),
    show_col_types = FALSE
  ))
  setnames(dt, col_names)
  return(dt)
}

# ------------------------------------------------------------------------------
# Audit & assertion helpers
# ------------------------------------------------------------------------------
fmt_num <- function(x, dec = 0) {
  if (length(x) == 0 || is.na(x) || !is.finite(x)) return("NA")
  formatC(x, format = "f", digits = dec, big.mark = ".", decimal.mark = ",")
}

audit_log <- data.table(step = character(), metric = character(), value = character())

log_metric <- function(step, metric, value) {
  v <- if (is.numeric(value)) fmt_num(value) else as.character(value)
  audit_log <<- rbind(audit_log, data.table(step = step, metric = metric, value = v))
  cat(sprintf("[AUDIT] %-28s %-44s %s\n", step, metric, v))
}

# Assertion on the central mass of a distribution: fails loudly on scale errors
assert_center <- function(x, lo, hi, label, prob = 0.5) {
  q <- quantile(x, prob, na.rm = TRUE)
  if (is.na(q) || q < lo || q > hi) {
    stop(sprintf(
      "ASSERT FALLIDO (%s): %s = %.6g fuera de rango esperado [%.6g, %.6g]. Escala de ingest corrupta?",
      label, paste0("cuantil ", prob), q, lo, hi
    ))
  }
  invisible(TRUE)
}

# ==============================================================================
# 1. RENTA & IDEN (Filer-level tax context)
# ==============================================================================

# Renta: importes en EUROS enteros (verificado: RB mediana ~13.400 EUR)
start_positions <- c(1, 12, 233, 248, 263, 878, 893)
end_positions   <- c(11, 22, 247, 262, 277, 892, 907)
renta_cols <- c("IDENPER", "IDENHOG", "M3_ALQUILER_TOTAL", "M31_ALQUILER_PFISICAS",
                "M32_ALQUILER_ENTIDADES", "RB", "RBD")

renta <- read_dt_fwf(
  paste0(data_path, "_2_Renta", sel_year, ".txt"),
  fwf_positions(start_positions, end_positions),
  "ddddddd",
  renta_cols
)
assert_center(renta$RB[renta$RB > 0], 5000, 100000, "RB (euros, renta bruta)")
log_metric("1.renta", "registros leidos", nrow(renta))

# IDEN: FACTORCAL decimal explicito (verificado: mediana ~3,5; media ~13,7)
start_iden <- c(1, 12, 23, 35, 36)
end_iden   <- c(11, 22, 24, 35, 55)
iden_cols  <- c("IDENPER", "IDENHOG", "CCAA", "TRAMO", "FACTORCAL")

iden <- read_dt_fwf(
  paste0(data_path, "_1_IDEN", sel_year, ".txt"),
  fwf_positions(start_iden, end_iden),
  "ddccd",
  iden_cols
)
assert_center(iden$FACTORCAL, 0.5, 100, "FACTORCAL (decimal explicito)")
log_metric("1.iden", "registros leidos", nrow(iden))
log_metric("1.iden", "FACTORCAL NA", sum(is.na(iden$FACTORCAL)))
log_metric("1.iden", "estratos TRAMO", uniqueN(iden$TRAMO))

# Union 1:1 por IDENPER (antes: inner join por (IDENPER, IDENHOG) que perdia
# filers silenciosamente y dejaba FACTORCAL = NA). Deduplicado explicito con diagnostico.
log_metric("1.renta", "duplicados por IDENPER", renta[duplicated(IDENPER), .N])
renta <- unique(renta, by = "IDENPER")
renta[, IDENHOG := NULL]  # evita colision IDENHOG.x/.y al unir por IDENPER
log_metric("1.iden", "duplicados por IDENPER", iden[duplicated(IDENPER), .N])
iden <- unique(iden, by = "IDENPER")

panel_renta <- merge(iden, renta, by = "IDENPER", all.x = TRUE)
log_metric("1.join_iden_renta", "filers en IDEN", nrow(iden))
log_metric("1.join_iden_renta", "filers sin Renta (todo NA)", panel_renta[is.na(RB) & is.na(RBD) & is.na(M3_ALQUILER_TOTAL), .N])
rm(iden, renta); gc()

# ==============================================================================
# 2. MODULO 8 - IRPF_RRII (Rendimientos por titular e inmueble, con dias)
# ==============================================================================

start_rrii <- c(1, 12, 23, 148, 154, 942, 962, 982, 1002, 1042)
end_rrii   <- c(11, 22, 33, 153, 173, 961, 981, 1001, 1021, 1061)
rrii_cols  <- c("IDENPER", "IDENHOG", "RC_ANONIMA", "DIAS_ARREND", "INGRESOS_INTEGROS",
                "RENDIMIENTO_NETO", "REDUCCION_ALQUILER_VIVIENDA",
                "REDUCCION_IRREGULAR", "RENDIMIENTO_MINIMO_PARENTESCO",
                "RENDIMIENTO_NETO_REDUCIDO")

rrii <- read_dt_fwf(
  paste0(data_path, "_8_IRPF", sel_year, "_RRII.txt"),
  fwf_positions(start_rrii, end_rrii),
  "dddddddddd",
  rrii_cols
)
# Importes en EUROS enteros y dias en [0, 366] (verificado empiricamente)
assert_center(rrii$INGRESOS_INTEGROS[rrii$INGRESOS_INTEGROS > 0], 2000, 30000,
              "INGRESOS_INTEGROS (euros)")
stopifnot(max(rrii$DIAS_ARREND, 0, na.rm = TRUE) <= 366)
log_metric("2.rrii", "registros leidos", nrow(rrii))
log_metric("2.rrii", "filas con alquiler (ingresos>0)", rrii[INGRESOS_INTEGROS > 0, .N])
log_metric("2.rrii", "masa bruta RRII (euros)", rrii[, sum(INGRESOS_INTEGROS, na.rm = TRUE)])

# Consolidar multiples periodos de arrendamiento del mismo (IDENPER, RC) dentro
# del ano: los importes se totalizan y los dias ocupados se acumulan (tope 365).
rrii <- rrii[, .(
  N_PERIODOS_RRII               = .N,
  DIAS_ARREND                   = pmin(sum(DIAS_ARREND, na.rm = TRUE), 365),
  INGRESOS_INTEGROS             = sum(INGRESOS_INTEGROS, na.rm = TRUE),
  RENDIMIENTO_NETO              = sum(RENDIMIENTO_NETO, na.rm = TRUE),
  REDUCCION_ALQUILER_VIVIENDA   = sum(REDUCCION_ALQUILER_VIVIENDA, na.rm = TRUE),
  REDUCCION_IRREGULAR           = sum(REDUCCION_IRREGULAR, na.rm = TRUE),
  RENDIMIENTO_MINIMO_PARENTESCO = sum(RENDIMIENTO_MINIMO_PARENTESCO, na.rm = TRUE),
  RENDIMIENTO_NETO_REDUCIDO     = sum(RENDIMIENTO_NETO_REDUCIDO, na.rm = TRUE)
), by = .(IDENPER, RC_ANONIMA)]
rrii[, IN_RRII := TRUE]
log_metric("2.rrii", "registros consolidados (IDENPER x RC)", nrow(rrii))
log_metric("2.rrii", "filas consolidadas con alquiler", rrii[INGRESOS_INTEGROS > 0, .N])
log_metric("2.rrii", "masa bruta consolidada (euros)", rrii[, sum(INGRESOS_INTEGROS, na.rm = TRUE)])

# ==============================================================================
# 3. MODULO 1 - VIVIENDA HABITUAL (agregacion de ocupantes a nivel de inmueble)
# ==============================================================================

start_vivhab <- c(1, 12, 14, 15, 26)
end_vivhab   <- c(11, 13, 14, 25, 29)
vivhab_cols  <- c("IDENPER_OCUPANTE", "TIPO_OCUPANTE", "URBACLAVE", "RC_ANONIMA", "MARCA_VIVHAB")

vivhab <- read_dt_fwf(
  paste0(data_path, "VIVHAB", sel_year, ".txt"),
  fwf_positions(start_vivhab, end_vivhab),
  "dccdc",
  vivhab_cols
)
log_metric("3.vivhab", "registros leidos", nrow(vivhab))
log_metric("3.vivhab", "sin RC_ANONIMA", vivhab[is.na(RC_ANONIMA), .N])

# Aggregate occupants: captures household counts without multiplying rows
vivhab_agg <- vivhab[!is.na(RC_ANONIMA), .(
  N_OCUPANTES_VIVHAB  = .N,
  URBACLAVES_HABITUAL = paste(sort(unique(na.omit(URBACLAVE))), collapse = ";"),
  TIPOS_OCUPANTE      = paste(sort(unique(na.omit(TIPO_OCUPANTE))), collapse = ";"),
  IN_VIVHAB           = TRUE
), by = RC_ANONIMA]
rm(vivhab); gc()
log_metric("3.vivhab", "referencias catastrales unicas", nrow(vivhab_agg))

# ==============================================================================
# 4. MODULO 3 - CARACTERISTICAS (deduplicacion con verificacion de conflictos)
# ==============================================================================

start_inmcar <- c(1, 3, 5, 8, 10, 13, 18, 33, 38, 53, 57, 68)
end_inmcar   <- c(2, 4, 7, 9, 12, 17, 32, 37, 52, 56, 67, 82)
inmcar_cols  <- c("CA", "PROV", "MUN", "DIST", "SECC", "VIVLOC", "VIVLOC_METROS",
                  "VIV", "VIV_METROS", "ANCONS", "RC_ANONIMA", "VALCAT")

inm_car <- read_dt_fwf(
  paste0(data_path, "INM_CARACT", sel_year, ".txt"),
  fwf_positions(start_inmcar, end_inmcar),
  "cccccddddddd",
  inmcar_cols
)
# Superficies y valor catastral con decimal EXPLICITO (verificado: m2 mediana ~110)
assert_center(inm_car$VIV_METROS[inm_car$VIV_METROS > 0], 20, 1000, "VIV_METROS (m2)")
assert_center(inm_car$VALCAT[inm_car$VALCAT > 0], 1000, 500000, "VALCAT (euros)")
log_metric("4.inm_caract", "registros leidos", nrow(inm_car))

# Verificar que los duplicados por RC son exactos ANTES de deduplicar
dup_rc <- inm_car[!is.na(RC_ANONIMA), .N, by = RC_ANONIMA][N > 1, RC_ANONIMA]
if (length(dup_rc) > 0) {
  conflicts <- inm_car[RC_ANONIMA %in% dup_rc, .(
    u_m2   = uniqueN(VIV_METROS),
    u_vc   = uniqueN(VALCAT),
    u_viv  = uniqueN(VIV),
    u_an   = uniqueN(ANCONS)
  ), by = RC_ANONIMA]
  if (conflicts[, max(u_m2)] > 1 || conflicts[, max(u_vc)] > 1 ||
      conflicts[, max(u_viv)] > 1 || conflicts[, max(u_an)] > 1) {
    stop("ASSERT FALLIDO: INM_CARACT contiene duplicados por RC con valores contradictorios.")
  }
}
log_metric("4.inm_caract", "RC duplicadas verificadas sin conflicto", length(dup_rc))

inm_car_agg <- unique(inm_car[!is.na(RC_ANONIMA)], by = "RC_ANONIMA")
inm_car_agg[, IN_CARACT := TRUE]
rm(inm_car); gc()
log_metric("4.inm_caract", "referencias catastrales unicas", nrow(inm_car_agg))

# ==============================================================================
# 5. MODULO 2 - PATRIMONIO INMOBILIARIO & COPROPIEDAD
# ==============================================================================

start_inmpr <- c(1, 12, 14, 20, 35, 43, 51)
end_inmpr   <- c(11, 13, 19, 34, 42, 50, 61)
inmpr_cols  <- c("IDENPER", "URBACODERE", "URBAPORBIN", "URBAVALORC", "URBAFECHIN", "URBAFECHFI", "RC_ANONIMA")

inm_pr <- read_dt_fwf(
  paste0(data_path, "INM_PR", sel_year, ".txt"),
  fwf_positions(start_inmpr, end_inmpr),
  "dcddddd",
  inmpr_cols
)
# URBAPORBIN en escala 0-100 con decimal explicito (verificado: "100.00" = pleno dominio)
assert_center(inm_pr$URBAPORBIN[inm_pr$URBAPORBIN > 0], 1, 100, "URBAPORBIN (0-100)")
stopifnot(quantile(inm_pr$URBAPORBIN, 0.999, na.rm = TRUE) <= 100.01)
log_metric("5.inm_pr", "registros leidos", nrow(inm_pr))

# Excluir filas PLACEHOLDER (una por declarante sin inmuebles: todo en blanco).
# Antes se imputaban como propiedades plenas (share=1) e inflaban el parque en
# ~24 millones de unidades fantasma (43% del total).
inm_pr[, es_placeholder := (is.na(RC_ANONIMA) & is.na(URBACODERE) & is.na(URBAPORBIN))]
log_metric("5.inm_pr", "placeholders excluidos (filers sin inmuebles)", inm_pr[es_placeholder == TRUE, .N])
log_metric("5.inm_pr", "filers solo-placeholder", inm_pr[es_placeholder == TRUE, uniqueN(IDENPER)])
inm_pr <- inm_pr[es_placeholder == FALSE]
inm_pr[, es_placeholder := NULL]
log_metric("5.inm_pr", "titulos reales", nrow(inm_pr))
log_metric("5.inm_pr", "filers con titulos reales", uniqueN(inm_pr$IDENPER))
log_metric("5.inm_pr", "titulos sin RC (extranjero/foral)", inm_pr[is.na(RC_ANONIMA), .N])

# Consolidar derechos/subperiodos del mismo titular sobre la misma finca
inm_pr <- inm_pr[, .(
  N_TITULOS_IDENPER = .N,
  URBAPORBIN        = sum(URBAPORBIN, na.rm = TRUE),
  URBAVALORC        = sum(URBAVALORC, na.rm = TRUE),
  URBACODERE        = paste(sort(unique(na.omit(URBACODERE))), collapse = ";")
), by = .(IDENPER, RC_ANONIMA)]

# Co-ownership structure across distinct taxpayers declaring the same property
inm_pr[!is.na(RC_ANONIMA), `:=`(
  N_COPROPIETARIOS_MUESTRA = uniqueN(IDENPER),
  PORC_PROPIEDAD_MUESTRA   = sum(URBAPORBIN, na.rm = TRUE),
  FLAG_INMUEBLE_UNICO      = (seq_len(.N) == 1L)
), by = RC_ANONIMA]

# Single-owner fallback for missing cadastral references
inm_pr[is.na(RC_ANONIMA), `:=`(
  N_COPROPIETARIOS_MUESTRA = 1L,
  PORC_PROPIEDAD_MUESTRA   = URBAPORBIN,
  FLAG_INMUEBLE_UNICO      = TRUE
)]
log_metric("5.inm_pr", "observaciones titular-inmueble", nrow(inm_pr))

# ==============================================================================
# 6. UNIONES RELACIONALES (centinelas NA protegidos)
# ==============================================================================

# Cobertura RRII pre-union (para auditar la attrition del alquiler declarado)
rrii_rental_pre <- rrii[INGRESOS_INTEGROS > 0, .N]
rrii_rental_mass_pre <- rrii[INGRESOS_INTEGROS > 0, sum(INGRESOS_INTEGROS, na.rm = TRUE)]

# NA sentinels: enteros negativos unicos por fila, imposible NA == NA
inm_pr[is.na(RC_ANONIMA),      RC_ANONIMA := -.I]
vivhab_agg[is.na(RC_ANONIMA),  RC_ANONIMA := -(.I + 1e8)]
inm_car_agg[is.na(RC_ANONIMA), RC_ANONIMA := -(.I + 2e8)]
rrii[is.na(RC_ANONIMA),        RC_ANONIMA := -(.I + 3e8)]

# Enrich property ownership with occupant profile
property_level <- merge(inm_pr, vivhab_agg, by = "RC_ANONIMA", all.x = TRUE)
rm(inm_pr, vivhab_agg); gc()
property_level[is.na(IN_VIVHAB), IN_VIVHAB := FALSE]
property_level[is.na(N_OCUPANTES_VIVHAB), N_OCUPANTES_VIVHAB := 0L]
log_metric("6.merge_vivhab", "filas panel", nrow(property_level))
log_metric("6.merge_vivhab", "con VIVHAB", property_level[IN_VIVHAB == TRUE, .N])

# Enrich with physical characteristics
property_level <- merge(property_level, inm_car_agg, by = "RC_ANONIMA", all.x = TRUE)
rm(inm_car_agg); gc()
property_level[is.na(IN_CARACT), IN_CARACT := FALSE]
log_metric("6.merge_caract", "con INM_CARACT", property_level[IN_CARACT == TRUE, .N])

# Match individual rental income declarations
property_level <- merge(property_level, rrii, by = c("IDENPER", "RC_ANONIMA"), all.x = TRUE)
rm(rrii); gc()
property_level[is.na(IN_RRII), IN_RRII := FALSE]
log_metric("6.merge_rrii", "con RRII", property_level[IN_RRII == TRUE, .N])
log_metric("6.merge_rrii", "filas con alquiler (ingresos>0)", property_level[INGRESOS_INTEGROS > 0, .N])
log_metric("6.merge_rrii", "masa alquiler unida (euros)", property_level[INGRESOS_INTEGROS > 0, sum(INGRESOS_INTEGROS, na.rm = TRUE)])
log_metric("6.merge_rrii", "cobertura masa RRII (%)",
           100 * property_level[INGRESOS_INTEGROS > 0, sum(INGRESOS_INTEGROS, na.rm = TRUE)] / rrii_rental_mass_pre)

# Restore original NA values
property_level[RC_ANONIMA < 0, RC_ANONIMA := NA]

# ==============================================================================
# 7. ATRIBUCION POR CUOTA Y AGREGADOS POR INMUEBLE
# ==============================================================================

# Metricas atribuidas por cuota (URBAPORBIN en escala 0-100)
property_level[, `:=`(
  VALCAT_CUOTA     = VALCAT * (URBAPORBIN / 100),
  VIV_METROS_CUOTA = VIV_METROS * (URBAPORBIN / 100)
)]

# Property-level totals across all sample co-owners
property_level[!is.na(RC_ANONIMA), `:=`(
  INGRESOS_INTEGROS_TOTAL_INMUEBLE = sum(INGRESOS_INTEGROS, na.rm = TRUE),
  RENDIMIENTO_NETO_TOTAL_INMUEBLE  = sum(RENDIMIENTO_NETO, na.rm = TRUE)
), by = RC_ANONIMA]

property_level[is.na(RC_ANONIMA), `:=`(
  INGRESOS_INTEGROS_TOTAL_INMUEBLE = INGRESOS_INTEGROS,
  RENDIMIENTO_NETO_TOTAL_INMUEBLE  = RENDIMIENTO_NETO
)]

# Distinct properties held per landlord (solo filers con al menos un titulo real)
property_level[, N_PROPIEDADES_TITULAR := uniqueN(RC_ANONIMA), by = IDENPER]

# ==============================================================================
# 8. UNION FINAL Y EXPORT
# ==============================================================================

dt <- merge(property_level, panel_renta, by = "IDENPER", all.x = TRUE)
rm(property_level, panel_renta); gc()

log_metric("8.final", "filas panel", nrow(dt))
log_metric("8.final", "filers unicos", uniqueN(dt$IDENPER))
log_metric("8.final", "filas con RC_ANONIMA", dt[!is.na(RC_ANONIMA), .N])
log_metric("8.final", "filas sin FACTORCAL", dt[is.na(FACTORCAL), .N])

fwrite(dt, paste0(out_path, sel_year, "dt_panel_inmo.gz"), na = "NA")
fwrite(audit_log, paste0(out_path, sel_year, "dt_panel_audit.txt"), sep = "\t")
rm(dt); gc()
cat("\nPanel y auditoria exportados en: ", out_path, "\n", sep = "")