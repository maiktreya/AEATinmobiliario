library(magrittr)
library(readr)
library(data.table)

gc()
sel_year  <- 2023
data_path <- paste0("data/", sel_year, "/")

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

# ==============================================================================
# 1. RENTA & IDEN (Filer-level tax context)
# ==============================================================================
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

div_cols <- c("M3_ALQUILER_TOTAL", "M31_ALQUILER_PFISICAS", "M32_ALQUILER_ENTIDADES", "RB", "RBD")
renta[, (div_cols) := lapply(.SD, `/`, 100), .SDcols = div_cols]

start_iden <- c(1, 12, 35, 36)
end_iden   <- c(11, 22, 35, 55)
iden_cols  <- c("IDENPER", "IDENHOG", "TRAMO", "FACTORCAL")

iden <- read_dt_fwf(
  paste0(data_path, "_1_IDEN", sel_year, ".txt"),
  fwf_positions(start_iden, end_iden),
  "ddcc",
  iden_cols
)

panel_renta <- merge(iden, renta, by = c("IDENPER", "IDENHOG"))
panel_renta <- unique(panel_renta, by = "IDENPER")
rm(iden, renta); gc()

# ==============================================================================
# 2. MODULO 8 - IRPF_RRII (Declared rental yields per owner and property)
# ==============================================================================
start_rrii <- c(1, 12, 23, 154, 942, 962, 982, 1002, 1042)
end_rrii   <- c(11, 22, 33, 173, 961, 981, 1001, 1021, 1061)
rrii_cols  <- c("IDENPER", "IDENHOG", "RC_ANONIMA", "INGRESOS_INTEGROS", 
                "RENDIMIENTO_NETO", "REDUCCION_ALQUILER_VIVIENDA", 
                "REDUCCION_IRREGULAR", "RENDIMIENTO_MINIMO_PARENTESCO", 
                "RENDIMIENTO_NETO_REDUCIDO")

rrii <- read_dt_fwf(
  paste0(data_path, "_8_IRPF", sel_year, "_RRII.txt"),
  fwf_positions(start_rrii, end_rrii),
  "ddddddddd",
  rrii_cols
)

importes_rrii <- c("INGRESOS_INTEGROS", "RENDIMIENTO_NETO", "REDUCCION_ALQUILER_VIVIENDA",
                   "REDUCCION_IRREGULAR", "RENDIMIENTO_MINIMO_PARENTESCO", "RENDIMIENTO_NETO_REDUCIDO")
rrii[, (importes_rrii) := lapply(.SD, `/`, 100), .SDcols = importes_rrii]

# Consolidate multiple leasing periods within the same year for the same (IDENPER, RC)
rrii <- rrii[, .(
  N_PERIODOS_RRII               = .N,
  INGRESOS_INTEGROS             = sum(INGRESOS_INTEGROS, na.rm = TRUE),
  RENDIMIENTO_NETO              = sum(RENDIMIENTO_NETO, na.rm = TRUE),
  REDUCCION_ALQUILER_VIVIENDA   = sum(REDUCCION_ALQUILER_VIVIENDA, na.rm = TRUE),
  REDUCCION_IRREGULAR           = sum(REDUCCION_IRREGULAR, na.rm = TRUE),
  RENDIMIENTO_MINIMO_PARENTESCO = sum(RENDIMIENTO_MINIMO_PARENTESCO, na.rm = TRUE),
  RENDIMIENTO_NETO_REDUCIDO     = sum(RENDIMIENTO_NETO_REDUCIDO, na.rm = TRUE)
), by = .(IDENPER, RC_ANONIMA)]
rrii[, IN_RRII := TRUE]

# ==============================================================================
# 3. MODULO 1 - VIVIENDA HABITUAL (Occupancy aggregation to property grain)
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

# Aggregate occupants: captures household counts without multiplying rows
vivhab_agg <- vivhab[!is.na(RC_ANONIMA), .(
  N_OCUPANTES_VIVHAB  = .N,
  URBACLAVES_HABITUAL = paste(sort(unique(na.omit(URBACLAVE))), collapse = ";"),
  TIPOS_OCUPANTE      = paste(sort(unique(na.omit(TIPO_OCUPANTE))), collapse = ";"),
  IN_VIVHAB           = TRUE
), by = RC_ANONIMA]
rm(vivhab); gc()

# ==============================================================================
# 4. MODULO 3 - CARACTERISTICAS (Lossless deduplication confirmed by diagnostic)
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
inm_car[, c("VIVLOC_METROS", "VIV_METROS", "VALCAT") := lapply(.SD, `/`, 100), 
        .SDcols = c("VIVLOC_METROS", "VIV_METROS", "VALCAT")]

# Diagnostic verified 0 conflicting values: strictly exact duplicates
inm_car_agg <- unique(inm_car[!is.na(RC_ANONIMA)], by = "RC_ANONIMA")
inm_car_agg[, IN_CARACT := TRUE]
rm(inm_car); gc()

# ==============================================================================
# 5. MODULO 2 - PATRIMONIO INMOBILIARIO & CO-OWNERSHIP METRICS
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
inm_pr[, c("URBAPORBIN", "URBAVALORC") := lapply(.SD, `/`, 100), .SDcols = c("URBAPORBIN", "URBAVALORC")]

# Consolidate rare cases where a single taxpayer holds multiple rights/periods for the same RC
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
  # Flag exactly one owner row per property to isolate physical stock
  FLAG_INMUEBLE_UNICO      = (seq_len(.N) == 1L)
), by = RC_ANONIMA]

# Single-owner fallback for missing cadastral references
inm_pr[is.na(RC_ANONIMA), `:=`(
  N_COPROPIETARIOS_MUESTRA = 1L,
  PORC_PROPIEDAD_MUESTRA   = URBAPORBIN,
  FLAG_INMUEBLE_UNICO      = TRUE
)]

# ==============================================================================
# 6. RELATIONAL MERGES (Protected NA sentinels)
# ==============================================================================
inm_pr[is.na(RC_ANONIMA),      RC_ANONIMA := -.I]
vivhab_agg[is.na(RC_ANONIMA),  RC_ANONIMA := -(.I + 1e8)]
inm_car_agg[is.na(RC_ANONIMA), RC_ANONIMA := -(.I + 2e8)]
rrii[is.na(RC_ANONIMA),        RC_ANONIMA := -(.I + 3e8)]

# Enrich property ownership with occupant profile
property_level <- merge(inm_pr, vivhab_agg, by = "RC_ANONIMA", all.x = TRUE)
rm(inm_pr, vivhab_agg); gc()
property_level[is.na(IN_VIVHAB), IN_VIVHAB := FALSE]
property_level[is.na(N_OCUPANTES_VIVHAB), N_OCUPANTES_VIVHAB := 0L]

# Enrich with physical characteristics
property_level <- merge(property_level, inm_car_agg, by = "RC_ANONIMA", all.x = TRUE)
rm(inm_car_agg); gc()
property_level[is.na(IN_CARACT), IN_CARACT := FALSE]

# Match individual rental income declarations
property_level <- merge(property_level, rrii, by = c("IDENPER", "RC_ANONIMA"), all.x = TRUE)
rm(rrii); gc()
property_level[is.na(IN_RRII), IN_RRII := FALSE]

# Restore original NA values
property_level[RC_ANONIMA < 0, RC_ANONIMA := NA]

# ==============================================================================
# 7. METRIC ATTRIBUTION & SAMPLE AGGREGATION
# ==============================================================================
# Attributed metrics for landlord-level portfolio analysis
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

# Distinct properties held per landlord
property_level[, N_PROPIEDADES_TITULAR := uniqueN(RC_ANONIMA), by = IDENPER]

# ==============================================================================
# 8. FINAL MERGE & EXPORT
# ==============================================================================
dt <- merge(property_level, panel_renta, by = "IDENPER", all.x = TRUE)
rm(property_level, panel_renta); gc()

dir.create(paste0("out/", sel_year), recursive = TRUE, showWarnings = FALSE)
fwrite(dt, paste0("out/", sel_year, "/", sel_year, "dt_panel_inmo2.gz"), na = "NA")
rm(dt); gc()