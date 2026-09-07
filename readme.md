# Panel de Microdatos AEAT 2023: Alquiler, Patrimonio Inmobiliario y Catastro

## 1. Objetivo del Proyecto

El objetivo principal de este proyecto es construir un panel analítico transversal para el ejercicio fiscal 2023 que vincule, a nivel micro, los rendimientos declarados por arrendamiento de inmuebles en el Impuesto sobre la Renta de las Personas Físicas (IRPF) con el patrimonio inmobiliario real, las características físicas catastrales y el uso efectivo de las viviendas en España.

El procesamiento resuelve tres retos analíticos y computacionales:

1. **Unificación relacional estricta por inmueble (`RC_ANONIMA`)**: Supera la limitación de modelos basados en agregados personales/hogar, vinculando cada rendimiento explícito del arrendador con su propiedad física.
2. **Eliminación de la explosión cartesiana y saturación de RAM**: Agrega determinísticamente las relaciones $1:N$ y $M:N$ (múltiples inquilinos en una vivienda o co-propietarios de un inmueble) antes de las operaciones de cruce, reduciendo drásticamente el consumo de memoria.
3. **Resolución de la copropiedad sin doble cómputo**: Permite alternar metodológicamente entre el análisis patrimonial del arrendador (*perspectiva titular*) y el análisis del parque de viviendas en alquiler (*perspectiva inmueble físico*).

---

## 2. Arquitectura de Scripts y Flujo de Trabajo

El repositorio dispone de dos versiones de generación del panel conjunto (según la unidad muestral de interés) y sus correspondientes herramientas de diagnóstico:

### Scripts de Generación del Panel Conjunto

* **Versión 1 (Línea Base / Grano Título Registral)**: [`src/joint/getPanel2023_join.R`](src/joint/getPanel2023_join.R)
* Mantiene íntegros los **5.678.026 registros** originales de `INM_PR` sin consolidar títulos intra-anuales.
* Controla la memoria deduplicando `VIVHAB` e `INM_CARACT` mediante selección directa del primer registro por `RC_ANONIMA`.
* Genera el fichero: `out/2023/2023dt_panel_inmo.gz`.


* **Versión 2 (Recomendada / Grano Titular–Inmueble con Copropiedad)**: [`src/joint/getPanel2023_join.v2.R`](https://www.google.com/search?q=src/joint/getPanel2023_join.v2.R)
* Agrega de forma determinista y sin pérdida de información los ocupantes de `VIVHAB` (`N_OCUPANTES_VIVHAB`, `URBACLAVES_HABITUAL`) e `INM_CARACT`.
* Consolida títulos y derechos múltiples de un mismo declarante sobre un mismo inmueble, totalizando **5.557.238 filas**.
* Incorpora métricas de cuota atribuida (`VALCAT_CUOTA`, `VIV_METROS_CUOTA`), agregados totales del inmueble (`INGRESOS_INTEGROS_TOTAL_INMUEBLE`) y el flag de aislamiento del parque físico `FLAG_INMUEBLE_UNICO`.
* Genera el fichero: `out/2023/2023dt_panel_inmo2.gz`.



### Scripts de Auditoría y Diagnóstico

* **`revPanel2023_join.R`**: Evalúa el panel v1 analizando la presencia de `URBACLAVE` y la tasa de emparejamiento sobre `dt_sub`.
* **`revPanel2023_join.v2.R`**: Audita el panel v2 evaluando la completitud de `URBACLAVES_HABITUAL`, la consistencia de los flags booleanos (`IN_VIVHAB`) y la integridad muestral de los rendimientos.

---

## 3. Ficheros de Origen y Granularidad

| Fichero | Fuente | Contenido Principal | Longitud (LRECL) | Registros Oficiales | Granularidad Original |
| --- | --- | --- | --- | --- | --- |
| `_1_IDEN2023.txt` | IRPF (M100) | Identificadores personales, tramos y pesos (`FACTORCAL`) | 55 | Variable | Persona - Hogar |
| `_2_Renta2023.txt` | IRPF (M100) | Renta bruta (`RB`), disponible (`RBD`) y agregados de alquiler | Variable | Variable | Persona - Hogar |
| `_8_IRPF2023_RRII.txt` | IRPF (Módulo 8) | Rendimientos de capital inmobiliario por inmueble (PAR102 a PAR154) | 1061 | Variable | Persona - Inmueble - Periodo |
| `INM_PR2023.txt` | Catastro / M100 (Módulo 2) | Patrimonio inmobiliario titularidad de personas físicas | 61 | 5.678.026 | Título legal / Sub-periodo titular |
| `VIVHAB2023.txt` | Catastro / M100 (Módulo 1) | Inmuebles declarados como vivienda habitual y ocupantes | 29 | 3.801.233 | Ocupante - Inmueble |
| `INM_CARACT2023.txt` | Catastro (Módulo 3) | Características físicas, superficies y valores catastrales | 82 | 2.447.212 | Inmueble (`RC_ANONIMA`) |

---

## 4. Metodología de Procesamiento y Reglas de Negocio

### Gestión de Memoria y Lectura Directa

La función auxiliar `read_dt_fwf` convierte el flujo en memoria de forma inmediata mediante `data.table::setDT()`, evitando la retención simultánea de data frames intermedios. Las tablas transitorias se eliminan explícitamente con `rm()` y `gc()` tras cada fase de cruce.

### Consolidación de Arrendamientos en Módulo 8 (`RRII`)

En la declaración de IRPF, un mismo arrendador puede presentar varias líneas para una misma referencia catastral si ha habido cambios de contrato o inquilinos en el ejercicio. Para evitar duplicidades en el panel, se agregan a nivel `(IDENPER, RC_ANONIMA)`:

* Los importes monetarios (`INGRESOS_INTEGROS`, `RENDIMIENTO_NETO`, `REDUCCION_ALQUILER_VIVIENDA`, `REDUCCION_IRREGULAR`, `RENDIMIENTO_MINIMO_PARENTESCO` y `RENDIMIENTO_NETO_REDUCIDO`) se totalizan mediante suma.
* `N_PERIODOS_RRII`: Registra la cantidad de contratos o declaraciones acumuladas durante el año natural.

### Integración de Ocupación sin Pérdida de Información (`VIVHAB`)

`VIVHAB` refleja a la persona que reside habitualmente en el inmueble (frecuentemente el inquilino o el propietario residente). En [`src/joint/getPanel2023_join.v2.R`](https://www.google.com/search?q=src/joint/getPanel2023_join.v2.R), las filas se agregan a nivel `RC_ANONIMA` antes de la unión para preservar el volumen de hogares sin inflar las filas de los propietarios:

* `N_OCUPANTES_VIVHAB`: Conteo exacto de personas que declararon dicho inmueble como residencia habitual.
* `URBACLAVES_HABITUAL`: Concatenación de las claves catastrales de uso observadas (p. ej., `V` para vivienda, `A` para anexos).
* `TIPOS_OCUPANTE`: Concatenación de tipologías de ocupación (propietario, arrendatario, etc.).

### Deduplicación de Características Físicas (`INM_CARACT`)

Se verificó empíricamente mediante diagnóstico sobre el total de las 847.553 referencias repetidas que en el 100% de los casos las superficies (`VIVLOC_METROS`) y valoraciones (`VALCAT`) son exactamente idénticas (0 divergencias). Por tanto, la deduplicación por `RC_ANONIMA` es completamente neutra y no sesga las magnitudes físicas.

### Estructura de Derechos en Patrimonio (`INM_PR`)

El fichero oficial contiene **5.678.026 registros**, correspondientes a títulos legales o sub-periodos temporales de tenencia.

* En [`src/joint/getPanel2023_join.R`](https://www.google.com/search?q=src/joint/getPanel2023_join.R), se preservan todas las líneas individuales de derechos.
* En [`src/joint/getPanel2023_join.v2.R`](https://www.google.com/search?q=src/joint/getPanel2023_join.v2.R), las participaciones de un mismo contribuyente sobre un mismo inmueble se consolidan a nivel `(IDENPER, RC_ANONIMA)`, totalizando **5.557.238 filas** (reducción exacta de 120.788 títulos secundarios). Se preserva el desglose del tipo de derecho en `URBACODERE` y el número de títulos en `N_TITULOS_IDENPER`.

### Protección de Claves Ausentes (Centinelas NA)

Para evitar que registros sin referencia catastral emparejen masivamente entre sí en las operaciones `merge` (`NA == NA`), se sustituyen previamente los vacíos por identificadores enteros negativos únicos (`-.I`, `-(.I + 1e8)`, etc.) y se restauran a `NA` tras completar los cruces relacionales.

---

## 5. Diccionario de Variables de la Base Consolidada v2 (`dt`)

```
Variables de la tabla maestra final (5.557.238 filas):
├── Identificación del Vínculo
│   ├── IDENPER: Identificador anónimo de la persona titular/arrendadora
│   └── RC_ANONIMA: Referencia catastral anonimizada del inmueble
├── Patrimonio y Co-propiedad (Módulo 2 - INM_PR)
│   ├── URBACODERE: Código(s) de derecho sobre el inmueble (PR, US, NP, etc.)
│   ├── URBAPORBIN: Porcentaje de titularidad imputado a este declarante (0-100)
│   ├── URBAVALORC: Valor catastral proporcional registrado en el módulo de patrimonio
│   ├── N_TITULOS_IDENPER: Número de registros contractuales o periodos acumulados por el titular
│   ├── N_COPROPIETARIOS_MUESTRA: Número de personas en el panel que declaran poseer cuota en la RC
│   ├── PORC_PROPIEDAD_MUESTRA: Suma de porcentajes de propiedad declarados por los cotitulares
│   ├── FLAG_INMUEBLE_UNICO: Indicador booleano (TRUE para exactamente un titular; aísla el inmueble físico)
│   └── N_PROPIEDADES_TITULAR: Inmuebles distintos que integran la cartera del titular
├── Ocupación y Vivienda Habitual (Módulo 1 - VIVHAB)
│   ├── IN_VIVHAB: Booleano; TRUE si la RC aparece declarada en VIVHAB
│   ├── N_OCUPANTES_VIVHAB: Número de personas empadronadas/declarantes en esa residencia
│   ├── URBACLAVES_HABITUAL: Usos catastrales declarados (ej. "V", "A", "V;A")
│   └── TIPOS_OCUPANTE: Tipología de ocupación según M100 o Catastro
├── Características Físicas y Territoriales (Módulo 3 - INM_CARACT)
│   ├── IN_CARACT: Booleano; TRUE si la RC figura en el censo físico
│   ├── CA, PROV, MUN, DIST, SECC: Desglose territorial (Comunidad, Provincia, Municipio, Distrito, Sección)
│   ├── VIVLOC / VIV: Número de locales y viviendas comprendidos en la unidad catastral
│   ├── VIV_METROS: Superficie construida total de la vivienda en metros cuadrados
│   ├── VIVLOC_METROS: Superficie construida conjunta de viviendas y locales
│   ├── ANCONS: Año de construcción del inmueble
│   └── VALCAT: Valor catastral total del inmueble (físico global)
├── Rendimientos de Capital Inmobiliario (Módulo 8 - IRPF RRII)
│   ├── IN_RRII: Booleano; TRUE si este titular declaró alquiler específico por este inmueble
│   ├── N_PERIODOS_RRII: Número de contratos declarados por este arrendador en el año
│   ├── INGRESOS_INTEGROS: Rendimiento íntegro computable anual declarado por el titular (€)
│   ├── RENDIMIENTO_NETO: Rendimiento neto individual (ingresos íntegros menos gastos deducibles)
│   ├── REDUCCION_ALQUILER_VIVIENDA: Reducción por arrendamiento de vivienda (art. 23.2 Ley IRPF)
│   ├── REDUCCION_IRREGULAR: Reducción aplicable por rendimientos irregulares o plurianuales
│   ├── RENDIMIENTO_MINIMO_PARENTESCO: Rendimiento mínimo exigido en cesiones a familiares
│   └── RENDIMIENTO_NETO_REDUCIDO: Importe final sujeto a base imponible general
├── Magnitudes Ajustadas por Cuota y Agregadas por Inmueble
│   ├── VALCAT_CUOTA: Valor catastral atribuido al titular según su % de propiedad
│   ├── VIV_METROS_CUOTA: Superficie de vivienda atribuida al titular según su cuota
│   ├── INGRESOS_INTEGROS_TOTAL_INMUEBLE: Alquiler íntegro total sumando todos los cotitulares
│   └── RENDIMIENTO_NETO_TOTAL_INMUEBLE: Rendimiento neto total generado por el inmueble
└── Contexto de Renta del Declarante (M100 - IDEN / Renta)
    ├── IDENHOG, TRAMO, FACTORCAL: Identificador del hogar, estrato y factor de elevación
    ├── RB / RBD: Renta bruta y renta disponible declaradas a nivel personal/familiar
    └── M3_ALQUILER_TOTAL: Agregado de rendimientos de capital inmobiliario en base IRPF

```

---

## 6. Guía de Uso Analítico: Prevención del Doble Cómputo

### Análisis a Nivel Arrendador / Titular

Para distribuciones de renta, carteras inmobiliarias o elasticidades de oferta por individuo, debe utilizarse la tabla completa y las variables imputadas por cuota:

```r
# Renta de alquiler declarada y capital catastral atribuido por arrendador
perfil_arrendador <- dt[, .(
  INGRESOS_ALQUILER_TOTAL = sum(INGRESOS_INTEGROS, na.rm = TRUE),
  CAPITAL_VALCAT_ATRIBUIDO = sum(VALCAT_CUOTA, na.rm = TRUE),
  SUPERFICIE_TOTAL_M2     = sum(VIV_METROS_CUOTA, na.rm = TRUE),
  NUMERO_INMUEBLES        = uniqueN(RC_ANONIMA)
), by = .(IDENPER, RB, RBD, FACTORCAL)]

```

### Análisis a Nivel Inmueble Físico / Parque Alquilado

Para analizar precios medios de alquiler por metro cuadrado, años de construcción o distribución territorial del parque residencial, se debe **filtrar por `FLAG_INMUEBLE_UNICO == TRUE**`, evitando duplicar métricas físicas en copropiedades:

```r
# Métricas del parque físico residencial alquilado (1 fila por inmueble físico)
parque_alquiler <- dt[FLAG_INMUEBLE_UNICO == TRUE & INGRESOS_INTEGROS_TOTAL_INMUEBLE > 0 & !is.na(RC_ANONIMA), .(
  RC_ANONIMA,
  PROV, MUN, DIST,
  SUPERFICIE_M2          = VIV_METROS,
  VALOR_CATASTRAL        = VALCAT,
  ANO_CONSTRUCCION       = ANCONS,
  RENTABILIDAD_ANUAL     = INGRESOS_INTEGROS_TOTAL_INMUEBLE,
  PRECIO_M2_ANUAL        = INGRESOS_INTEGROS_TOTAL_INMUEBLE / VIV_METROS,
  COPROPIETARIOS_DECLAR  = N_COPROPIETARIOS_MUESTRA,
  OCUPANTES_HABITUALES   = N_OCUPANTES_VIVHAB
)]

```

---

## 7. Resultados de Diagnóstico y Completitud de Cobertura

La comparación entre ambas parametrizaciones arroja las siguientes conclusiones:

* **Registros Totales del Panel**:
* v1 ([`src/joint/getPanel2023_join.R`](https://www.google.com/search?q=src/joint/getPanel2023_join.R)): 5.678.026 filas.
* v2 ([`src/joint/getPanel2023_join.v2.R`](https://www.google.com/search?q=src/joint/getPanel2023_join.v2.R)): 5.557.238 filas.


* **Inmuebles identificados con `RC_ANONIMA` válida**: 3.173.648 en v2 (frente a 3.294.436 en v1; la diferencia son exactamente los 120.788 títulos secundarios agrupados).
* **Submuestra de inmuebles con alquiler declarado (`INGRESOS_INTEGROS > 0`)**: 377.992 registros en v2 (frente a 388.555 en v1).
* **Completitud de `URBACLAVES_HABITUAL` / Presencia en `VIVHAB**`:
* En la muestra general de inmuebles: **25% con presencia en VIVHAB** (75% NAs).
* En la submuestra de inmuebles alquilados: **23% con presencia en VIVHAB** (77% NAs).



### Justificación Normativa y Fiscal de la Cobertura en `VIVHAB`

El hecho de que el 77% de los inmuebles alquilados no aparezca en `VIVHAB` es coherente con las normas de declaración del impuesto:

1. **Asimetría de declaración**: El arrendador declara el inmueble en `INM_PR` y `RRII`, pero **no en `VIVHAB**`, ya que solo consigna allí su propia vivienda habitual.
2. **Obligación de declarar**: Gran parte de la población arrendataria percibe ingresos por debajo del umbral legal de obligación en IRPF (22.000 € anuales con un pagador; 14.000/15.000 € con varios pagadores) y no presenta modelo 100.
3. **Incentivo a deducir el alquiler**: Los inquilinos solo consignan la referencia catastral si tienen derecho y solicitan deducciones autonómicas de arrendamiento (acotadas a colectivos específicos por edad o renta).
4. **Alquileres no residenciales**: Los arrendamientos comerciales o a personas jurídicas no constituyen vivienda habitual y no generan registro en el Módulo 1.

### Tipología de Usos Catastrales (`URBACLAVE`)

En los inmuebles con presencia en `VIVHAB`, la clave de uso dominante es `"V"` (residencial). La presencia de códigos secundarios como `"A"` (almacén o aparcamiento) no refleja inconsistencias, sino la aplicación del **Real Decreto 1020/1993** (Normas técnicas de valoración catastral), que clasifica garajes y trasteros vinculados como modalidades integradas dentro del uso residencial cuando sirven a la vivienda habitual.
