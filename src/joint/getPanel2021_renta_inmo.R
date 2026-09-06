# Fichero principal 2023
library(magrittr)
library(readr)
library(data.table)
rm(list = ls()) # clean enviroment to avoid ram bottlenecks

sel_year <- 2023
################################


# RENTA
start_positions <- c(1, 12, 707, 719, 191)
end_positions <- c(11, 22, 718, 730, 202)
col_positions <- fwf_positions(start = start_positions, end = end_positions) # Use fwf_positions to define column positions
test_total <- read_fwf(paste0("data/", sel_year, "/_2_Renta", sel_year, ".txt"), col_positions = col_positions) %>% data.table()
colnames(test_total) <- c("IDENPER", "IDENHOG", "RENTAB", "RENTAD", "RENTA_ALQ")

# IDENTIFICADORES Y PESOS
start_iden <- c(1, 12, 35, 36) # Starting positions references
end_iden <- c(11, 22, 35, 55) # Ending positions references
col_iden <- fwf_positions(start = start_iden, end = end_iden) # Use fwf_positions to define column positions
iden <- read_fwf(paste0("data/", sel_year, "/_1_IDEN", sel_year, ".txt"), col_positions = col_iden) %>% data.table()
colnames(iden) <- c("IDENPER", "IDENHOG", "TRAMO", "FACTORCAL")

# PAR150 REDUCCI<U+00D3>N ALQUILER VIVIENDA solo comprobado para 2023!
start_dt150 <- c(1, 12, 962)
end_dt150 <- c(11, 22, 981)
col_dt150 <- fwf_positions(start = start_dt150, end = end_dt150) # Use fwf_positions to define column positions
dt150 <- read_fwf(paste0("data/", sel_year, "/_8_IRPF", sel_year, "_RRII.txt"), col_positions = col_dt150) %>% data.table()
colnames(dt150) <- c("IDENPER", "IDENHOG", "PAR150")
nrow(dt150) %>% print()

# INCORPORAR INFORMACION DEL MODULO INMOBILIARIO (PERMITE CLASIFICACION DE INMUEBLES POR USO)
start_vivhab <- c(1, 12, 14, 15, 26)
end_vivhab <- c(11, 13, 14, 25, 29)
col_vivhab <- fwf_positions(start = start_vivhab, end = end_vivhab) # Use fwf_positions to define column positions
vivhab <- read_fwf(paste0("data/", sel_year, "/VIVHAB", sel_year, ".txt"),
    col_positions = col_vivhab,
    col_types = "dccdc"
) %>% data.table()
colnames(vivhab) <- c("IDENPER", "TIPO", "URBACLAVE", "RC_ANONIMA", "MARCA")

# Merge both datasets based on IDs
dt <- merge(iden, test_total, by = c("IDENPER", "IDENHOG"))
dt <- merge(dt, dt150, by = c("IDENPER", "IDENHOG"))
dt <- merge(dt, vivhab, by = c("IDENPER"))

# Exportamos outer join del panel de hogares para todas las propiedades inmobiliaras de IDENPER incluidas en VIVHAB2023.txt
fwrite(dt, paste0("out/2023/", sel_year, "dt_panel_inmo.gz"))
