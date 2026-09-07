# Fichero principal 2023 - panel de alquiler con identificacion correcta de inmuebles por RC_ANONIMA
library(magrittr)
library(readr)
library(data.table)
rm(list = ls()) # clean enviroment to avoid ram bottlenecks
sel_year <- 2023
data_path <- paste0("data/", sel_year, "/")
################################

# RENTA
# POSICIONES CORREGIDAS contra Dise<U+00F1>oRegistro_2023.xlsx (hoja "2_Renta"): las posiciones
# usadas anteriormente (707/719/191) no correspondian a ningun campo real de este fichero
# y leian fragmentos de Dividendos (M22) y de Cuota resultante/Cotizaciones (M711/M72) sin
# dar ningun error. M31 mezcla alquiler de LOCALES y VIVIENDAS de personas fisicas (no separa
# uso residencial); para el alquiler realmente identificado por vivienda, ver RRII mas abajo.
start_positions <- c(1, 12, 233, 248, 263, 878, 893)
end_positions <- c(11, 22, 247, 262, 277, 892, 907)
col_positions <- fwf_positions(start = start_positions, end = end_positions) # Use fwf_positions to define column positions
renta_raw <- read_fwf(paste0(data_path, "_2_Renta", sel_year, ".txt"),
    col_positions = col_positions,
    col_types = "ddddddd",
    na = c("", "NA", "."),
    show_col_types = FALSE
)
cat("--- problems(renta) ---\n")
problems(renta_raw) %>% print()
renta <- data.table(renta_raw)
colnames(renta) <- c(
    "IDENPER", "IDENHOG", "M3_ALQUILER_TOTAL", "M31_ALQUILER_PFISICAS",
    "M32_ALQUILER_ENTIDADES", "RB", "RBD"
)
renta[, c("M3_ALQUILER_TOTAL", "M31_ALQUILER_PFISICAS", "M32_ALQUILER_ENTIDADES", "RB", "RBD") :=
    lapply(.SD, `/`, 100),
.SDcols = c("M3_ALQUILER_TOTAL", "M31_ALQUILER_PFISICAS", "M32_ALQUILER_ENTIDADES", "RB", "RBD")
]

# IDENTIFICADORES Y PESOS (posiciones verificadas contra Dise<U+00F1>oRegistro_2023.xlsx, hoja "1_IDEN")
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
# Nota: FACTORCAL lleva 10 decimales implicitos segun el diseno de registro (no 2). Se deja
# como texto ("c") porque no se usa numericamente en este script; si se necesita como peso
# de calibracion mas adelante, leer con col_types "d" y dividir entre 1e10.

# MODULO 8 - IRPF_RRII: desglose de rendimientos de capital inmobiliario POR INMUEBLE.
# Sustituye a la version anterior que solo leia PAR150 a nivel persona/hogar: este fichero
# incluye RefCatastral (aqui RC_ANONIMA), por lo que el alquiler se puede enlazar al inmueble
# concreto en vez de repetirse en todas las propiedades del arrendador. Campos (posiciones
# verificadas contra Dise<U+00F1>oRegistro_2023.xlsx hoja "8_IRPF_RRII" y el manual metodologico
# 2025_04.pdf, Documentos de Trabajo del IEF 4/2025):
#   PAR102 Ingresos integros computables (alquiler bruto de ESE inmueble)
#   PAR149 Rendimiento neto (bruto menos gastos deducibles)
#   PAR150 Reduccion por arrendamiento de vivienda (art. 23.2 Ley IRPF) - solo aplica si es vivienda
#   PAR151 Reduccion por rendimientos irregulares
#   PAR152 Rendimiento minimo computable en caso de parentesco
#   PAR154 Rendimiento neto reducido (cifra final, la que tributa)
start_rrii <- c(1, 12, 23, 154, 942, 962, 982, 1002, 1042)
end_rrii <- c(11, 22, 33, 173, 961, 981, 1001, 1021, 1061)
col_rrii <- fwf_positions(start = start_rrii, end = end_rrii) # Use fwf_positions to define column positions
rrii_raw <- read_fwf(paste0(data_path, "_8_IRPF", sel_year, "_RRII.txt"),
    col_positions = col_rrii,
    col_types = "ddddddddd", na = c("", "NA", "."), show_col_types = FALSE
)
cat("--- problems(rrii) ---\n")
problems(rrii_raw) %>% print()
rrii <- data.table(rrii_raw)
colnames(rrii) <- c(
    "IDENPER", "IDENHOG", "RC_ANONIMA", "INGRESOS_INTEGROS", "RENDIMIENTO_NETO",
    "REDUCCION_ALQUILER_VIVIENDA", "REDUCCION_IRREGULAR",
    "RENDIMIENTO_MINIMO_PARENTESCO", "RENDIMIENTO_NETO_REDUCIDO"
)
importes_rrii <- c(
    "INGRESOS_INTEGROS", "RENDIMIENTO_NETO", "REDUCCION_ALQUILER_VIVIENDA",
    "REDUCCION_IRREGULAR", "RENDIMIENTO_MINIMO_PARENTESCO", "RENDIMIENTO_NETO_REDUCIDO"
)
rrii[, (importes_rrii) := lapply(.SD, `/`, 100), .SDcols = importes_rrii] # 2 decimales implicitos, confirmado en el diseno de registro
nrow(rrii) %>% print()

# Diagnostico: claves duplicadas ANTES de mezclar nada.
cat("IDEN duplicate (IDENPER,IDENHOG):", iden[, .N, by = .(IDENPER, IDENHOG)][N > 1, .N], "\n")
cat("IDEN duplicate IDENPER solo (persona en mas de un hogar):", iden[, .N, by = IDENPER][N > 1, .N], "\n")
cat("RENTA duplicate (IDENPER,IDENHOG):", renta[, .N, by = .(IDENPER, IDENHOG)][N > 1, .N], "\n")
# Con RC_ANONIMA presente, RRII deberia tener como mucho una fila por inmueble declarado;
# si aqui aparecen duplicados reales (misma persona+hogar+inmueble varias veces), investigar
# antes de continuar en vez de agregarlos a ciegas como se hacia antes con PAR150.
cat("RRII duplicate (IDENPER,IDENHOG,RC_ANONIMA):", rrii[!is.na(RC_ANONIMA), .N, by = .(IDENPER, IDENHOG, RC_ANONIMA)][N > 1, .N], "\n")
cat("RRII duplicate (IDENPER,RC_ANONIMA), ignorando IDENHOG:", rrii[!is.na(RC_ANONIMA), .N, by = .(IDENPER, RC_ANONIMA)][N > 1, .N], "\n")

# Los duplicados de (IDENPER,RC_ANONIMA) son reales: muy probablemente distintos periodos
# de arrendamiento del MISMO inmueble dentro del mismo anyo (p.ej. cambio de inquilino a
# mitad de anyo, ver los pares de fechas PAR120/121 y PAR135/136 del diseno de registro).
# Sumamos ANTES de unir para mantener una fila por inmueble en property_level, igual que se
# hizo antes con PAR150 a nivel persona (N_PERIODOS_RRII deja constancia de cuantas filas
# originales se han combinado). Nota: si RC_ANONIMA es NA, esto agrupa entre si los distintos
# alquileres "sin referencia catastral" de una misma persona, que ya eran indistinguibles.
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

# Panel de renta a nivel persona/hogar (contexto/agregados; el alquiler por inmueble vive en RRII)
panel_renta <- merge(iden, renta, by = c("IDENPER", "IDENHOG"))
nrow(panel_renta) %>% print()
cat("panel_renta IDENPER duplicados:", panel_renta[, .N, by = IDENPER][N > 1, .N], "\n")
panel_renta <- unique(panel_renta, by = "IDENPER") # solo actua si el check anterior es > 0

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
inm_car[, IN_CARACT := TRUE] # mismo patron de flag que IN_VIVHAB / IN_RRII
nrow(inm_car) %>% print()

# merge() matches NA == NA on the join key, which would wrongly link unrelated records
# that simply lack a catastral reference. Sentinel each NA so it can never falsely match.
inm_pr[is.na(RC_ANONIMA), RC_ANONIMA := -.I]
vivhab[is.na(RC_ANONIMA), RC_ANONIMA := -(.I + 1e8)]
inm_car[is.na(RC_ANONIMA), RC_ANONIMA := -(.I + 2e8)]
rrii[is.na(RC_ANONIMA), RC_ANONIMA := -(.I + 3e8)]

# Nivel-propiedad: cada inmueble del arrendador (INM_PR), enriquecido con su uso (VIVHAB),
# sus caracteristicas fisicas (INM_CARACT) y, ahora, su alquiler declarado especifico (RRII),
# todo identificado por RC_ANONIMA (y por IDENPER en el caso de RRII, para asegurar que el
# alquiler se atribuye al mismo arrendador que posee el inmueble en INM_PR).
property_level <- merge(inm_pr, vivhab, by = "RC_ANONIMA", all.x = TRUE, allow.cartesian = TRUE)
property_level[is.na(IN_VIVHAB), IN_VIVHAB := FALSE] # RC no presente en VIVHAB2023.txt en absoluto
property_level <- merge(property_level, inm_car, by = "RC_ANONIMA", all.x = TRUE, allow.cartesian = TRUE)
property_level[is.na(IN_CARACT), IN_CARACT := FALSE]
property_level <- merge(property_level, rrii, by = c("IDENPER", "RC_ANONIMA"), all.x = TRUE, allow.cartesian = TRUE)
property_level[is.na(IN_RRII), IN_RRII := FALSE] # inmueble sin declaracion de alquiler de ESTE arrendador ese anyo
property_level[RC_ANONIMA < 0, RC_ANONIMA := NA] # restaurar la ausencia real

# Cuantas propiedades DISTINTAS declara cada arrendador (uniqueN, no .N: evita que el fan-out
# de INM_CARACT o RRII infle este recuento si alguna RC tuviera mas de una fila coincidente)
property_level[, N_PROPIEDADES := uniqueN(RC_ANONIMA), by = IDENPER]
nrow(property_level) %>% print()

# Adjuntamos el contexto de renta a nivel persona (RB, RBD, M3/M31/M32) a cada inmueble.
# El alquiler especifico de cada inmueble ya vive en INGRESOS_INTEGROS/RENDIMIENTO_NETO_REDUCIDO
# (de RRII, arriba); esto es solo contexto adicional a nivel arrendador.
dt <- merge(property_level, panel_renta, by = "IDENPER")
nrow(dt) %>% print()

fwrite(dt, paste0("out/", sel_year, "/", sel_year, "dt_panel_inmo.gz"), na = "NA")
