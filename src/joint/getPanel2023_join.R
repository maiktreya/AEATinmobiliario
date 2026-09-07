library(magrittr)
library(readr)
library(data.table)

# Ensure garbage collection runs aggressively
gc()
sel_year <- 2023
data_path <- paste0("data/", sel_year, "/")

# Helper to read directly into data.table without storing intermediate raw tibbles
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

# 1. RENTA
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

# 2. IDENTIFICADORES Y PESOS
start_iden <- c(1, 12, 35, 36)
end_iden   <- c(11, 22, 35, 55)
iden_cols  <- c("IDENPER", "IDENHOG", "TRAMO", "FACTORCAL")

iden <- read_dt_fwf(
  paste0(data_path, "_1_IDEN", sel_year, ".txt"),
  fwf_positions(start_iden, end_iden),
  "ddcc",
  iden_cols
)

# 3. PANEL RENTA & CLEANUP
panel_renta <- merge(iden, renta, by = c("IDENPER", "IDENHOG"))
panel_renta <- unique(panel_renta, by = "IDENPER")
rm(iden, renta) # Release source tables immediately
gc()

# 4. MODULO 8 - IRPF_RRII
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

# Agregación previa para garantizar 1 fila por (IDENPER, RC_ANONIMA)
rrii <- rrii[, .(
  N_PERIODOS_RRII = .N,
  INGRESOS_INTEGROS = sum(INGRESOS_INTEGROS, na.rm = TRUE),
  RENDIMIENTO_NETO = sum(RENDIMIENTO_NETO, na.rm = TRUE),
  REDUCCION_ALQUILER_VIVIENDA = sum(REDUCCION_ALQUILER_VIVIENDA, na.rm = TRUE),
  REDUCCION_IRREGULAR = sum(REDUCCION_IRREGULAR, na.rm = TRUE),
  RENDIMIENTO_MINIMO_PARENTESCO = sum(RENDIMIENTO_MINIMO_PARENTESCO, na.rm = TRUE),
  RENDIMIENTO_NETO_REDUCIDO = sum(RENDIMIENTO_NETO_REDUCIDO, na.rm = TRUE)
), by = .(IDENPER, RC_ANONIMA)]
rrii[, IN_RRII := TRUE]

# 5. MODULO 2 - PATRIMONIO INMOBILIARIO
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

# 6. MODULO 1 - VIVIENDA HABITUAL
start_vivhab <- c(1, 12, 14, 15, 26)
end_vivhab   <- c(11, 13, 14, 25, 29)
vivhab_cols  <- c("IDENPER_OCUPANTE", "TIPO_OCUPANTE", "URBACLAVE", "RC_ANONIMA", "MARCA_VIVHAB")

vivhab <- read_dt_fwf(
  paste0(data_path, "VIVHAB", sel_year, ".txt"),
  fwf_positions(start_vivhab, end_vivhab),
  "dccdc",
  vivhab_cols
)
vivhab[, IN_VIVHAB := TRUE]

# DEDUPLICAR VIVHAB por RC_ANONIMA para evitar el producto cartesiano
# Si hay multiples ocupantes, preservamos la primera observacion o un registro unico
vivhab <- unique(vivhab, by = "RC_ANONIMA")

# 7. MODULO 3 - CARACTERISTICAS
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
inm_car[, IN_CARACT := TRUE]

# DEDUPLICAR INM_CAR por RC_ANONIMA para evitar duplicaciones
inm_car <- unique(inm_car, by = "RC_ANONIMA")

# 8. GESTION DE VALORES NA EN REFERENCIA CATASTRAL
inm_pr[is.na(RC_ANONIMA),  RC_ANONIMA := -.I]
vivhab[is.na(RC_ANONIMA),  RC_ANONIMA := -(.I + 1e8)]
inm_car[is.na(RC_ANONIMA), RC_ANONIMA := -(.I + 2e8)]
rrii[is.na(RC_ANONIMA),    RC_ANONIMA := -(.I + 3e8)]

# 9. UNIONES SECUENCIALES CON LIBERACION DE MEMORIA
# Ya no es necesario allow.cartesian = TRUE porque vivhab e inm_car estan deduplicados
property_level <- merge(inm_pr, vivhab, by = "RC_ANONIMA", all.x = TRUE)
rm(inm_pr, vivhab); gc()

property_level[is.na(IN_VIVHAB), IN_VIVHAB := FALSE]

property_level <- merge(property_level, inm_car, by = "RC_ANONIMA", all.x = TRUE)
rm(inm_car); gc()

property_level[is.na(IN_CARACT), IN_CARACT := FALSE]

property_level <- merge(property_level, rrii, by = c("IDENPER", "RC_ANONIMA"), all.x = TRUE)
rm(rrii); gc()

property_level[is.na(IN_RRII), IN_RRII := FALSE]
property_level[RC_ANONIMA < 0, RC_ANONIMA := NA]

property_level[, N_PROPIEDADES := uniqueN(RC_ANONIMA), by = IDENPER]

# 10. MERGE FINAL Y EXPORTACION
dt <- merge(property_level, panel_renta, by = "IDENPER")
rm(property_level, panel_renta); gc()

dir.create(paste0("out/", sel_year), recursive = TRUE, showWarnings = FALSE)
fwrite(dt, paste0("out/", sel_year, "/", sel_year, "dt_panel_inmo.gz"), na = "NA")
rm(dt); gc()
