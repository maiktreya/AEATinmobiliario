# Fichero principal 2023 - panel de alquiler con identificacion correcta de inmuebles por RC_ANONIMA
library(magrittr)
library(readr)
library(data.table)
rm(list = ls()) # clean enviroment to avoid ram bottlenecks
sel_year <- 2023
data_path <- paste0("data/", sel_year, "/")
################################

# RENTA
start_positions <- c(1, 12, 707, 719, 191)
end_positions <- c(11, 22, 718, 730, 202)
col_positions <- fwf_positions(start = start_positions, end = end_positions) # Use fwf_positions to define column positions
renta_raw <- read_fwf(paste0(data_path, "_2_Renta", sel_year, ".txt"),
    col_positions = col_positions,
    col_types = "ddddd",
    na = c("", "NA", "."),
    show_col_types = FALSE
) # "." es el mismo marcador de ausencia que en PAR150
cat("--- problems(renta) ---\n")
problems(renta_raw) %>% print()
renta <- data.table(renta_raw)
colnames(renta) <- c("IDENPER", "IDENHOG", "RENTAB", "RENTAD", "RENTA_ALQ")

# IDENTIFICADORES Y PESOS
start_iden <- c(1, 12, 35, 36)
end_iden <- c(11, 22, 35, 55)
col_iden <- fwf_positions(start = start_iden, end = end_iden) # Use fwf_positions to define column positions
iden_raw <- read_fwf(paste0(data_path, "_1_IDEN", sel_year, ".txt"),
    col_positions = col_iden,
    col_types = "ddcc",
    show_col_types = FALSE
)
cat("--- problems(iden) ---\n")
problems(iden_raw) %>% print()
iden <- data.table(iden_raw)
colnames(iden) <- c("IDENPER", "IDENHOG", "TRAMO", "FACTORCAL")

# PAR150 REDUCCION ALQUILER VIVIENDA solo comprobado para 2023!
start_dt150 <- c(1, 12, 962)
end_dt150 <- c(11, 22, 981)
col_dt150 <- fwf_positions(start = start_dt150, end = end_dt150) # Use fwf_positions to define column positions
dt150_raw <- read_fwf(paste0(data_path, "_8_IRPF", sel_year, "_RRII.txt"),
    col_positions = col_dt150,
    col_types = "ddd", na = c("", "NA", "."), show_col_types = FALSE
)
cat("--- problems(dt150) ---\n")
problems(dt150_raw) %>% print()
dt150 <- data.table(dt150_raw)
colnames(dt150) <- c("IDENPER", "IDENHOG", "PAR150")

# Diagnostico: claves (IDENPER, IDENHOG) duplicadas en cada fichero, ANTES de mezclar nada.
# Si alguno de estos > 0, el merge por esa clave hara fan-out y el recuento final crecera.
cat("IDEN duplicate (IDENPER,IDENHOG):", iden[, .N, by = .(IDENPER, IDENHOG)][N > 1, .N], "\n")
cat("IDEN duplicate IDENPER solo (persona en mas de un hogar):", iden[, .N, by = IDENPER][N > 1, .N], "\n")
cat("RENTA duplicate (IDENPER,IDENHOG):", renta[, .N, by = .(IDENPER, IDENHOG)][N > 1, .N], "\n")
cat("PAR150 duplicate (IDENPER,IDENHOG):", dt150[, .N, by = .(IDENPER, IDENHOG)][N > 1, .N], "\n")

# PAR150 es un importe (euros/centimos), no un flag: "." = no aplica, "0" = solicitada
# con importe cero, y el resto son importes reales de la reduccion. Con varios registros
# para la misma (IDENPER,IDENHOG), sumamos el importe total reclamado en lugar de listar
# valores unicos como antes (mas correcto semanticamente, y mucho mas rapido de calcular).
# ASUNCION a confirmar: si el campo lleva 2 decimales implicitos (como el resto de importes
# AEAT vistos hasta ahora), descomentar la siguiente linea antes de agregar:
# dt150[, PAR150 := PAR150 / 100]
dt150 <- dt150[, .(N_PAR150 = .N, PAR150 = sum(PAR150, na.rm = TRUE)), by = .(IDENPER, IDENHOG)]

# Panel de renta a nivel persona/hogar
panel_renta <- merge(iden, renta, by = c("IDENPER", "IDENHOG"))
panel_renta <- merge(panel_renta, dt150, by = c("IDENPER", "IDENHOG"))
nrow(panel_renta) %>% print()

# Con PAR150 ya agregado, esto deberia ser 0 (o cercano); si no lo es, hay verdaderos
# casos de una misma persona en mas de un hogar el mismo anyo y hay que decidir un criterio.
cat(
    "panel_renta IDENPER duplicados tras agregar PAR150:",
    panel_renta[, .N, by = IDENPER][N > 1, .N], "\n"
)
panel_renta <- unique(panel_renta, by = "IDENPER")
nrow(panel_renta) %>% print()

# MODULO2 - PATRIMONIO INMOBILIARIO: que inmuebles concretos posee cada IDENPER (arrendador)
start_inmpr <- c(1, 12, 14, 20, 35, 43, 51)
end_inmpr <- c(11, 13, 19, 34, 42, 50, 61)
col_inmpr <- fwf_positions(start = start_inmpr, end = end_inmpr) # Use fwf_positions to define column positions
inm_pr_raw <- read_fwf(paste0(data_path, "INM_PR", sel_year, ".txt"),
    col_positions = col_inmpr,
    col_types = "dcddddd", show_col_types = FALSE
)
cat("--- problems(inm_pr) ---\n")
problems(inm_pr_raw) %>% print()
inm_pr <- data.table(inm_pr_raw)
colnames(inm_pr) <- c(
    "IDENPER", "URBACODERE", "URBAPORBIN", "URBAVALORC",
    "URBAFECHIN", "URBAFECHFI", "RC_ANONIMA"
)
inm_pr[, c("URBAPORBIN", "URBAVALORC") := lapply(.SD, `/`, 100),
    .SDcols = c("URBAPORBIN", "URBAVALORC")
] # aplicar los 2 decimales implicitos
nrow(inm_pr) %>% print()

# MODULO1 - VIVIENDA HABITUAL: clasificacion de uso del inmueble (URBACLAVE), segun quien lo declare como su vivienda habitual
start_vivhab <- c(1, 12, 14, 15, 26)
end_vivhab <- c(11, 13, 14, 25, 29)
col_vivhab <- fwf_positions(start = start_vivhab, end = end_vivhab) # Use fwf_positions to define column positions
vivhab_raw <- read_fwf(paste0(data_path, "VIVHAB", sel_year, ".txt"),
    col_positions = col_vivhab,
    col_types = "dccdc", show_col_types = FALSE
)
cat("--- problems(vivhab) ---\n")
problems(vivhab_raw) %>% print()
vivhab <- data.table(vivhab_raw)
# Renombramos: estos campos describen al OCUPANTE que declara el inmueble como habitual,
# no al arrendador propietario del modulo de patrimonio.
colnames(vivhab) <- c("IDENPER_OCUPANTE", "TIPO_OCUPANTE", "URBACLAVE", "RC_ANONIMA", "MARCA_VIVHAB")
vivhab[, IN_VIVHAB := TRUE] # flag explicito: mas robusto que distinguir NA de "" tras un fwrite/fread
nrow(vivhab) %>% print()

# MODULO3 - CARACTERISTICAS DE LOS INMUEBLES
start_inmcar <- c(1, 3, 5, 8, 10, 13, 18, 33, 38, 53, 57, 68)
end_inmcar <- c(2, 4, 7, 9, 12, 17, 32, 37, 52, 56, 67, 82)
col_inmcar <- fwf_positions(start = start_inmcar, end = end_inmcar) # Use fwf_positions to define column positions
inm_car_raw <- read_fwf(paste0(data_path, "INM_CARACT", sel_year, ".txt"),
    col_positions = col_inmcar,
    col_types = "cccccddddddd", show_col_types = FALSE
)
cat("--- problems(inm_car) ---\n")
problems(inm_car_raw) %>% print()
inm_car <- data.table(inm_car_raw)
colnames(inm_car) <- c(
    "CA", "PROV", "MUN", "DIST", "SECC", "VIVLOC", "VIVLOC_METROS",
    "VIV", "VIV_METROS", "ANCONS", "RC_ANONIMA", "VALCAT"
)
inm_car[, c("VIVLOC_METROS", "VIV_METROS", "VALCAT") := lapply(.SD, `/`, 100),
    .SDcols = c("VIVLOC_METROS", "VIV_METROS", "VALCAT")
] # aplicar los 2 decimales implicitos
nrow(inm_car) %>% print()

# merge() matches NA == NA on the join key, which would wrongly link unrelated records
# that simply lack a catastral reference. Sentinel each NA so it can never falsely match.
inm_pr[is.na(RC_ANONIMA), RC_ANONIMA := -.I]
vivhab[is.na(RC_ANONIMA), RC_ANONIMA := -(.I + 1e8)]
inm_car[is.na(RC_ANONIMA), RC_ANONIMA := -(.I + 2e8)]

# Nivel-propiedad: cada inmueble del arrendador (INM_PR), enriquecido con su uso (VIVHAB)
# y sus caracteristicas fisicas (INM_CARACT), todo identificado por RC_ANONIMA.
property_level <- merge(inm_pr, vivhab, by = "RC_ANONIMA", all.x = TRUE, allow.cartesian = TRUE)
property_level[is.na(IN_VIVHAB), IN_VIVHAB := FALSE] # RC no presente en VIVHAB2023.txt en absoluto
property_level <- merge(property_level, inm_car, by = "RC_ANONIMA", all.x = TRUE, allow.cartesian = TRUE)
property_level[RC_ANONIMA < 0, RC_ANONIMA := NA] # restaurar la ausencia real

# Cuantas propiedades declara cada arrendador: RENTA_ALQ es un importe a nivel IDENPER,
# no por inmueble, asi que si N_PROPIEDADES > 1 ese mismo importe se repetira en cada fila
# de ese arrendador; no es posible desagregarlo por inmueble con esta informacion.
property_level[, N_PROPIEDADES := .N, by = IDENPER]
nrow(property_level) %>% print()

# Adjuntamos la renta/PAR150 del arrendador (nivel persona) a cada uno de sus inmuebles
dt <- merge(property_level, panel_renta, by = "IDENPER")
nrow(dt) %>% print()

fwrite(dt, paste0("out/", sel_year, "/", sel_year, "dt_panel_inmo.gz"), na = "NA")
