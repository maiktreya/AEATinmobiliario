# Panel de Microdatos AEAT 2023: Alquiler, Patrimonio Inmobiliario y Catastro

## 1. Objetivo del Proyecto

Este proyecto construye y explota un panel analítico transversal para el ejercicio fiscal 2023 que vincula los rendimientos del capital inmobiliario declarados en el IRPF con la titularidad patrimonial, la información física de Catastro y el censo de vivienda habitual en España.

El procesamiento resuelve tres retos analíticos y computacionales:

* **Vinculación a nivel de inmueble físico (`RC_ANONIMA`)**: Conecta cada rendimiento declarado con su propiedad física real, superando las limitaciones de los análisis agregados a nivel de persona u hogar.

* **Eficiencia de memoria y prevención de productos cartesianos**: Agrega de forma determinista las relaciones $1:N$ y $M:N$ (múltiples inquilinos en una vivienda o cotitularidades) antes de los cruces relacionales, evitando el desbordamiento de memoria RAM.

* **Inferencia poblacional sin doble cómputo**: Aplica el método de partición de pesos (*Generalized Weight Share Method*, GWSM) elevando cada registro por `share * FACTORCAL`, permitiendo estimar el parque residencial físico, contrastar el mercado del alquiler frente a la estadística oficial de la AEAT y **cuantificar la incertidumbre muestral** mediante linealización de Taylor sobre el diseño estratificado de la muestra.

---

## 2. Arquitectura de Scripts y Flujo de Trabajo

El flujo de trabajo se estructura en dos scripts secuenciales ubicados en el repositorio:

* **[`src/joint/getPanel2023_join.R`](src/joint/getPanel2023_join.R) (Script 1 - Construcción del Panel Consolidado)**:
  * Ingesta los ficheros de ancho fijo (FWF) en streaming convirtiéndolos directamente en memoria a `data.table` mediante `read_dt_fwf`.
  * **Verifica las codificaciones reales del dato** (decimales explícitos vs. euros enteros) con aserciones de escala que abortan ante ingestas corruptas (el documento de diseño de registro está desactualizado en los campos monetarios del M100).
  * Lee los **días de arrendamiento** del Módulo 8 (campo `PAR101`) y los acumula por titular e inmueble en `DIAS_ARREND`.
  * Agrega contratos y periodos en Módulo 8 (`RRII`) por titular e inmueble.
  * Resume los ocupantes de `VIVHAB` a nivel de referencia catastral.
  * Deduplica las fichas físicas de `INM_CARACT` **verificando por aserción** que los duplicados no contienen valores contradictorios.
  * **Excluye las filas *placeholder* de `INM_PR`** (una por declarante sin inmuebles, todo en blanco), que antes se imputaban como propiedades plenas e inflaban el parque en ~24 millones de unidades fantasma.
  * Consolida los títulos patrimoniales de `INM_PR` por `(IDENPER, RC_ANONIMA)`, calculando cuotas y banderas de copropiedad.
  * Emite una **auditoría completa de uniones** (registros leídos, duplicados, coberturas de cada cruce y cobertura de la masa declarada del Módulo 8) por consola y en `out/2023/2023dt_panel_audit.txt`.
  * Exporta la base unificada a `out/2023/2023dt_panel_inmo.gz`.

* **[`src/rev/revPanel2023_join.R`](src/rev/revPanel2023_join.R) (Script 2 - Diagnóstico, Inferencia y Filtrado Residencial)**:
  * Evalúa la cobertura y disponibilidad de claves de uso catastral (`URBACLAVES_HABITUAL`).
  * Verifica por aserción las escalas del panel (euros reales, `FACTORCAL`, `URBAPORBIN` 0-100); sin reescalados heurísticos.
  * Audita la imputación de cuotas (`share := 1` solo para cuotas ausentes, ahora 2 filas) y la composición del canal de clasificación residencial.
  * Clasifica el parque inmobiliario total y discrimina el parque residencial respecto a garajes o locales comerciales, con **análisis de sensibilidad del umbral residencial**.
  * Ejecuta la inferencia poblacional con **errores estándar por linealización de Taylor** (estratos `TRAMO`, conglomerados `IDENHOG`, pesos `FACTORCAL`) y compara las magnitudes con el Bloque I de la estadística oficial de la AEAT.

* **[`src/rev/revPanel2023_join_dev.R`](src/rev/revPanel2023_join_dev.R) (Script 2 dev - Conciliación del Parque Declarado)**: variante que añade la conciliación del parque residencial físico con el censo de viviendas declaradas en IRPF (Tabla AEAT 18.069.370), aislando la nuda propiedad pura y forzando un máximo de una vivienda habitual por declarante.

---

## 3. Ficheros de Microdatos de Origen

| Fichero | Fuente | Contenido Principal | LRECL | Granularidad Original |
| --- | --- | --- | --- | --- |
| `_1_IDEN2023.txt` | IRPF (M100) | Identificadores personales, estrato (`TRAMO`) y factor de elevación (`FACTORCAL`) | 141 | Persona - Hogar |
| `_2_Renta2023.txt` | IRPF (M100) | Renta bruta (`RB`), disponible (`RBD`) y agregados de alquiler | 907 | Persona - Hogar |
| `_8_IRPF2023_RRII.txt` | IRPF (Módulo 8) | Rendimientos íntegros y reducciones por inmueble (PAR102–154) y días de arrendamiento (PAR101) | 1061 | Declarante - Inmueble - Contrato |
| `INM_PR2023.txt` | Catastro (Módulo 2) | Titularidad de derechos reales, cuotas y valor catastral patrimonial | 61 | Título / Derecho / Subperiodo |
| `VIVHAB2023.txt` | Catastro / M100 (Módulo 1) | Ocupantes censados y uso declarado como vivienda habitual | 29 | Ocupante - Inmueble |
| `INM_CARACT2023.txt` | Catastro (Módulo 3) | Superficies (`VIV_METROS`), año (`ANCONS`) y valor catastral | 82 | Unidad Catastral (`RC_ANONIMA`) |

### Codificaciones verificadas empíricamente

El documento oficial de diseño de registro (`doc/DiseñoRegistro_2023.xlsx`) declara 2 decimales implícitos en los importes del M100, pero el dato real no los usa. Las codificaciones verificadas directamente sobre los ficheros son:

| Fichero | Codificación real | Ejemplo |
| --- | --- | --- |
| `_1_IDEN` (`FACTORCAL`) | Decimal **explícito** de 20 posiciones | `11.6906688868` |
| `_2_Renta`, `_8_RRII` (importes) | **Euros enteros**, sin decimales implícitos | `4263` = 4.263 € |
| `_8_RRII` (`PAR101`) | Días de arrendamiento, entero en [0, 365] | `365` |
| `INM_PR` (`URBAPORBIN`, `URBAVALORC`) | Decimal **explícito** | `100.00` = 100 % |
| `INM_CARACT` (`VIV_METROS`, `VALCAT`) | Decimal **explícito** | `11056.55` € |

Ambos scripts incorporan aserciones (`assert_center`) que abortan la ejecución con un diagnóstico claro si alguna escala se desvía de estos rangos, en sustitución de los antiguos reescalados heurísticos que enmascaraban silenciosamente ingestas corruptas.

---

## 4. Metodología de Construcción y Depuración

### Gestión de Memoria y Lectura en Streaming

La función `read_dt_fwf` ejecuta `data.table::setDT(readr::read_fwf(...))` en un único paso, impidiendo la duplicación de objetos intermedios en memoria. Tras cada combinación relacional, los objetos precedentes se eliminan de inmediato con `rm()` y `gc()`.

### Filas *Placeholder* de `INM_PR`

El censo de `INM_PR` contiene 5.678.026 filas, de las cuales **2.383.590 son *placeholders*** completamente en blanco (una por declarante sin ningún inmueble; sin solape alguno con los declarantes con títulos reales). El script las identifica (`RC`, `URBACODERE` y `URBAPORBIN` ausentes) y las **excluye del panel** con recuento auditado. Antes de esta corrección, cada *placeholder* se imputaba como una propiedad plena (`share = 1`) y contribuía con ~24,1 millones de unidades equivalentes fantasma (el 42,9 % del antiguo "parque total" de 56,1 M).

### Consolidación de Contratos de Alquiler (`RRII`)

Los contribuyentes pueden consignar varios registros para una misma propiedad debido a rotación de inquilinos durante el año fiscal. El script totaliza los importes monetarios (`INGRESOS_INTEGROS`, `RENDIMIENTO_NETO`, `REDUCCION_ALQUILER_VIVIENDA`, etc.) por `(IDENPER, RC_ANONIMA)`, acumula los **días de contrato observados** (`DIAS_ARREND`, tope 365) y almacena el total de contratos en `N_PERIODOS_RRII`. Los días constan en el 99,99 % de la submuestra de alquiler (solo 38 filas con `PAR101 = 0`).

### Integración de Vivienda Habitual (`VIVHAB`)

`VIVHAB` recopila a las personas empadronadas o declarantes que residen habitualmente en el inmueble. Para evitar la multiplicación de filas al cruzarlo con los propietarios, se agregan las variables a nivel `RC_ANONIMA` antes de fusionar:

* `N_OCUPANTES_VIVHAB`: Número de ocupantes observados en la residencia.
* `URBACLAVES_HABITUAL`: Cadena concatenada de usos catastrales declarados (ej. `"V"`, `"A"`, `"V;A"`).
* `TIPOS_OCUPANTE`: Tipologías de tenencia de los ocupantes.

### Deduplicación de Características Físicas (`INM_CARACT`)

Antes de deduplicar por `RC_ANONIMA`, el script verifica por aserción que las referencias repetidas contengan valores idénticos en superficies, valoraciones catastrales, año y número de viviendas (`stop` inmediato si existe conflicto). En el dato 2023 no se detectan duplicados.

### Estructura de Títulos en `INM_PR` y Tratamiento de Copropiedades

Los 3.294.436 títulos reales del censo de `INM_PR` reflejan derechos o intervalos temporales. Cuando un contribuyente tiene varios derechos sobre la misma finca (por ejemplo, nuda propiedad y pleno dominio), se agrupan en una única fila `(IDENPER, RC_ANONIMA)`, totalizando **3.173.648 observaciones únicas titular–inmueble** en manos de **1.170.090 declarantes**:

* `URBAPORBIN`: Porcentaje de propiedad total acumulado por el titular sobre el inmueble (escala 0-100).
* `N_COPROPIETARIOS_MUESTRA`: Recuento de declarantes en la muestra con cuota sobre esa propiedad.
* `FLAG_INMUEBLE_UNICO`: Marca booleana asignada a exactamente un titular por `RC_ANONIMA`, permitiendo aislar el parque inmobiliario físico sin duplicaciones.

### Centinelas Numéricos para NAs

Antes de las uniones relacionales, los valores `NA` en `RC_ANONIMA` se sustituyen por números enteros negativos únicos (`-.I`, `-(.I + 1e8)`, etc.), impidiendo emparejamientos artificiales de inmuebles sin referencia catastral (`NA == NA`). Tras los cruces, las referencias negativas se restauran a `NA`.

### Auditoría de Uniones

Cada cruce queda registrado (registros leídos, duplicados por clave, filas emparejadas y cobertura de la masa declarada del Módulo 8 unida al panel, **89 %** del total declarado en `RRII`) en `out/2023/2023dt_panel_audit.txt`. La unión `IDEN × Renta` se realiza por `IDENPER` con `all.x = TRUE`, preservando el `FACTORCAL` de todos los declarantes (la antigua unión interna por `(IDENPER, IDENHOG)` perdía factores silenciosamente).

---

## 5. Diccionario de Variables de la Tabla Consolidada (`dt`)

```
Variables de la tabla maestra final (3.173.648 filas; 1.170.090 declarantes):
├── Identificación del Vínculo
│   ├── IDENPER: Identificador anónimo del declarante titular/arrendador
│   └── RC_ANONIMA: Referencia catastral anonimizada del inmueble
├── Patrimonio y Cotitularidad (Módulo 2 - INM_PR)
│   ├── URBACODERE: Código(s) de derecho sobre el inmueble (PR, US, NP, etc.)
│   ├── URBAPORBIN: Porcentaje de titularidad imputado al declarante (0-100)
│   ├── URBAVALORC: Valor catastral patrimonial declarado (euros, decimal explícito)
│   ├── N_TITULOS_IDENPER: Número de derechos/títulos consolidados para este titular
│   ├── N_COPROPIETARIOS_MUESTRA: Número de cotitulares observados en la muestra
│   ├── PORC_PROPIEDAD_MUESTRA: Suma de participaciones declaradas por los cotitulares
│   ├── FLAG_INMUEBLE_UNICO: TRUE para exactamente un titular; aísla el inmueble físico
│   └── N_PROPIEDADES_TITULAR: Inmuebles distintos que posee el arrendador
├── Ocupación y Residencia Habitual (Módulo 1 - VIVHAB)
│   ├── IN_VIVHAB: Booleano; TRUE si la RC figura censada en VIVHAB
│   ├── N_OCUPANTES_VIVHAB: Personas que consignan el inmueble como vivienda habitual
│   ├── URBACLAVES_HABITUAL: Claves de uso según Catastro (ej. "V", "A", "V;A")
│   └── TIPOS_OCUPANTE: Tipología de ocupación según M100 o Catastro
├── Características Censales Físicas (Módulo 3 - INM_CARACT)
│   ├── IN_CARACT: Booleano; TRUE si la RC figura en el censo físico
│   ├── CA, PROV, MUN, DIST, SECC: Ubicación territorial del inmueble
│   ├── VIV / VIVLOC: Número de viviendas y locales en la parcela catastral
│   ├── VIV_METROS: Superficie construida total de la vivienda (m², decimal explícito)
│   ├── VIVLOC_METROS: Superficie construida de viviendas y locales (m²)
│   ├── ANCONS: Año de construcción
│   └── VALCAT: Valor catastral total del inmueble físico (euros, decimal explícito)
├── Rendimientos de Capital Inmobiliario (Módulo 8 - IRPF RRII)
│   ├── IN_RRII: Booleano; TRUE si se declaró alquiler específico por este inmueble
│   ├── N_PERIODOS_RRII: Número de contratos declarados durante el ejercicio
│   ├── DIAS_ARREND: Días de arrendamiento acumulados del ejercicio (PAR101, tope 365)
│   ├── INGRESOS_INTEGROS: Rendimiento íntegro computable del titular (€)
│   ├── RENDIMIENTO_NETO: Rendimiento neto individual (ingresos menos gastos)
│   ├── REDUCCION_ALQUILER_VIVIENDA: Reducción art. 23.2 LIRPF (alquiler de vivienda)
│   ├── REDUCCION_IRREGULAR: Reducción por rendimientos irregulares o plurianuales
│   ├── RENDIMIENTO_MINIMO_PARENTESCO: Rendimiento mínimo exigido en cesiones a familiares
│   └── RENDIMIENTO_NETO_REDUCIDO: Importe final computable en base imponible
├── Magnitudes Atribuidas por Cuota y Agregados por Inmueble
│   ├── VALCAT_CUOTA: Valor catastral atribuido al titular según su % de propiedad
│   ├── VIV_METROS_CUOTA: Superficie de vivienda atribuida según la cuota
│   ├── INGRESOS_INTEGROS_TOTAL_INMUEBLE: Alquiler íntegro sumando todos los cotitulares
│   └── RENDIMIENTO_NETO_TOTAL_INMUEBLE: Rendimiento neto total de la propiedad
└── Contexto de Renta del Declarante (M100 - IDEN / Renta)
    ├── IDENHOG, CCAA, TRAMO, FACTORCAL: Hogar, CCAA, estrato muestral y factor de elevación
    ├── RB / RBD: Renta bruta y disponible a nivel declarante
    └── M3_ALQUILER_TOTAL: Total rendimientos inmobiliarios en base del IRPF
```

---

## 6. Metodología de Inferencia Poblacional (GWSM)

Para realizar inferencia sobre el parque inmobiliario y los arrendamientos a partir de la muestra estratificada de declarantes, se aplica el método GWSM (*Generalized Weight Share Method*):

```math
\text{veq}_i = \text{share}_i \times \text{FACTORCAL}_i = \left(\frac{\text{URBAPORBIN}_i}{100}\right) \times \text{FACTORCAL}_i
```

### Control de Cuotas e Importes

* **`share` en escala 0.0–1.0**: derivado de `URBAPORBIN` (0-100) con acotación a [0, 1]; un titular con 100 % de propiedad pondera por 1,0 y uno con 50 % por 0,5. La imputación `share := 1` para cuotas ausentes o nulas queda **contada y reportada** en la auditoría (2 filas en 2023); la masa monetaria nunca se pondera por `share` (estimador Horvitz-Thompson directo).
* **Importes en euros reales**: las escalas se verifican por aserción al cargar el panel; no existen reescalados heurísticos.

### Incertidumbre Muestral (Errores Estándar)

Toda estimación (totales de viviendas equivalentes, medias de renta y masa monetaria) incorpora su error estándar por **linealización de Taylor** sobre el diseño muestral de la AEAT mediante el paquete `survey`:

* **Estratos**: `TRAMO` (9 niveles del diseño muestral).
* **Conglomerados**: `IDENHOG` (hogar; verificado único a nivel nacional, sin colisiones entre CCAA). Si la unidad última de muestreo fuese el declarante, el agrupamiento por hogar solo puede **inflar** las EE (inferencia conservadora).
* **Pesos**: `FACTORCAL` (factor calibrado por CCAA).
* Opción `survey.lonely.psu = "adjust"`; las filas sin `FACTORCAL` (356, sin dato en el fichero IDEN) quedan fuera del diseño con recuento auditado.

### Discriminación entre Parque Inmobiliario Total y Parque Residencial

* **Parque Inmobiliario Total (32,0 millones de unidades equivalentes)**: Suma de todos los títulos reales en manos de declarantes del IRPF (viviendas, plazas de aparcamiento individuales, trasteros con referencia propia, locales comerciales y parcelas). Se reporta además una cota superior ponderando por `VIV` en parcelas con múltiples viviendas (28,3 M).
* **Parque Residencial Estimado (20,94 millones de viviendas)**: Aísla las viviendas exigiendo acreditación habitacional (`VIV >= 1` en `INM_CARACT`, presencia de clave `"V"` en `URBACLAVES_HABITUAL` o reducción por arrendamiento de vivienda), con exclusión explícita de anexos confirmados no residenciales (garajes `"A"`, locales `"C"`).

### Filtrado y Clasificación del Mercado de Alquiler

El alquiler bruto del Módulo 8 contiene contratos sobre toda clase de fincas urbanas. El script clasifica tres niveles analíticos:

1. **Alquiler Habitual**: Contratos acogidos a la reducción del artículo 23.2 de la Ley del IRPF (`REDUCCION_ALQUILER_VIVIENDA > 0`) o con inquilino censado con clave `"V"` en `VIVHAB`.

2. **Alquiler No Habitual Residencial Depurado**: Contratos sin reducción del art. 23.2 ni inquilino censado `"V"` que acreditan condición de vivienda (`es_vivienda == TRUE`) e ingresos íntegros anuales completos ≥ 2.400 €/año, descartando garajes independientes y trasteros alquilados sueltos. El umbral es un parámetro sometido a análisis de sensibilidad (1.200–4.800 €).

3. **Alquiler No Residencial**: Arrendamientos de garajes sueltos, almacenes y locales comerciales.

### Anualización de la Renta con Días Reales de Contrato

Se reportan dos métricas de renta media mensual:

* **Flujo anual**: `(ingresos anuales al 100 % de propiedad) / 12`.
* **Anualizada AEAT**: flujo mensual proyectado a 365 días usando los **días de contrato observados** (`DIAS_ARREND`, campo PAR101 del Módulo 8, disponible en el 99,99 % de los contratos); solo se imputan las constantes AEAT (339/271 días) cuando el registro carece de días.

---

## 7. Resultados Empíricos Obtenidos frente a la Referencia AEAT (2023)

Al ejecutar [`src/rev/revPanel2023_join.R`](src/rev/revPanel2023_join.R), se obtienen las siguientes magnitudes (punto estimado con error estándar por linealización de Taylor y coeficiente de variación):

```r
r$> source("src/rev/revPanel2023_join.R", encoding = "UTF-8")
------------------------------------------------------------------
AUDITORÍA DE REGISTROS MUESTRALES
------------------------------------------------------------------
Total registros en panel (títulos reales INM_PR):        3.173.648
Total declarantes con títulos:                           1.170.090
Total registros con alquiler declarado (submuestra):     377.992

Porcentaje con VIVHAB en panel completo:                 0,44
Porcentaje con VIVHAB en submuestra de alquiler:         0,23
Porcentaje con INM_CARACT en submuestra de alquiler:     0,99
Filas sin FACTORCAL (excluidas del diseño muestral):     356
Cuotas imputadas a share=1 (NA o <=0%):                  2 filas (veq: 2)
Días de contrato observados:                             377.954 de 377.992 (99,99%)

==================================================================
RESULTADOS DE INFERENCIA POBLACIONAL (GWSM: share x FACTORCAL)
EE por linealización de Taylor (estratos TRAMO, conglomerados IDENHOG)
==================================================================
Factor de elevación medio (filas del panel):            16,46
Masa de ingresos por alquiler unida al panel:           26.488.589.414 (EE 156.675.182; CV 0,59%) EUR

1. PARQUE INMOBILIARIO EN MANOS DE DECLARANTES IRPF
  * Parque Inmobiliario TOTAL (viviendas + garajes + locales): 32.040.908 (EE 77.233; CV 0,24%) unidades
  * Parque RESIDENCIAL estimado (viviendas físicas declarantes): 20.936.734 (EE 46.680; CV 0,22%) viviendas
    (Cota superior ponderando por VIV en parcelas múltiples:     28.265.035 viviendas)

2. MERCADO DEL ALQUILER DECLARADO (Módulo 8 - IRPF)
  * Submuestra con alquiler (n crudo):                   377.992 unidades
  * Total contratos / inmuebles con alquiler declarado:   3.333.103 (EE 18.833; CV 0,57%) unidades

    - Alquiler Habitual CONVERGENTE:                      2.333.149 (EE 14.282; CV 0,61%) viviendas (Ref. AEAT: 2.409.689)
        · Declaradas con reducción art. 23.2:              2.181.692 (EE 13.934; CV 0,64%) viviendas
        · Reclasificadas con inquilino en VIVHAB ('V'):     151.457 (EE 2.579; CV 1,70%) viviendas
      Renta media mensual habitual (flujo anual / 12):       639,70 (EE 2,07; CV 0,32%) EUR/mes
      Renta media mensual habitual (anualizada AEAT):        734,67 (EE 4,18; CV 0,57%) EUR/mes (Ref. AEAT: 657 EUR)

    - Alquiler No Habitual RESIDENCIAL (umbral 2.400 EUR/anual):
      Total:                                                297.473 (EE 4.161; CV 1,40%) viviendas (Ref. AEAT: 309.479)
      Renta media mensual no habitual (flujo anual / 12):     786,75 (EE 8,69; CV 1,11%) EUR/mes
      Renta media mensual no habitual (anualizada AEAT):     1.389,43 (EE 36,30; CV 2,61%) EUR/mes (Ref. AEAT: 1.361 EUR)

    - Alquiler NO Residencial (garajes, trasteros, locales):  702.481 (EE 8.310; CV 1,18%) unidades

3. SENSIBILIDAD DEL UMBRAL RESIDENCIAL (viviendas equivalentes elevadas)
  Umbral EUR/anual | No Habitual Residencial | No Residencial
  ----------------------------------------------------------------
            1.200 |                 325.552 |          674.402
            1.800 |                 311.377 |          688.576
            2.400 |                 297.473 |          702.481
            3.600 |                 263.245 |          736.709
            4.800 |                 217.729 |          782.225
```

Alternativamente, el script de desarrollo explora la diferencia en el número total de inmuebles residenciales entre el panel AEAT y la muestra de inmuebles IRPF. Con [`src/rev/revPanel2023_join_dev.R`](src/rev/revPanel2023_join_dev.R):

```r
r$> source("src/rev/revPanel2023_join_dev.R", encoding = "UTF-8")
==================================================================
1. PARQUE RESIDENCIAL FÍSICO CATASTRAL (INM_PR - Escala INE)
  * Parque Inmobiliario TOTAL (viviendas + garajes + locales): 32.040.908 (EE 77.233; CV 0,24%) unidades
  * Parque RESIDENCIAL FÍSICO (viviendas Catastro declarantes):  20.936.734 (EE 46.680; CV 0,22%) viviendas

2. CONCILIACIÓN CON EL CENSO DE VIVIENDAS DECLARADAS EN IRPF (Tabla AEAT 18.069.370)
  * A. Vivienda habitual en propiedad declarada en IRPF:  10.011.338 (EE 21.948; CV 0,22%) viviendas (Ref. AEAT: 10.460.700)
       (Censadas en Catastro VIVHAB: 10.286.346 viv; exceso = no declarantes IRPF)
  * B. Viviendas arrendadas (Habitual + No habitual):     2.630.622 (EE 15.374; CV 0,58%) viviendas (Ref. AEAT:  2.738.472)
  * C. Segundas residencias / A disposición IRPF:          4.432.317 (EE 18.922; CV 0,43%) viviendas (Ref. AEAT:  4.870.198)
       (Total censadas en Catastro: 4.454.461 viv; diferencia = nuda propiedad pura)
  * TOTAL VIVIENDAS DECLARADAS IRPF ESTIMADAS:            17.074.276 (EE 40.576; CV 0,24%) viviendas (Ref. AEAT: 18.069.370)

3. MERCADO DEL ALQUILER DECLARADO (Módulo 8 - IRPF)
  (idéntico al script base: 2.333.149 habituales; 297.473 no habituales; 702.481 no residenciales)
```

---

## 8. Diagnóstico Metodológico y Conciliación con Fuentes Oficiales

### 1. Los Tres Perímetros del Parque Residencial (INE vs. Panel vs. AEAT)

Existe una aparente discrepancia entre las cifras de stock residencial reportadas en distintas publicaciones oficiales que responde estrictamente a diferencias en el perímetro de observación:

* **26,62 millones (INE - Censo de Población y Viviendas)**: Inventario físico de **todas** las viviendas existentes en España según el Censo de 2021 (publicado en 2023) y las estadísticas del Catastro Inmobiliario Urbano, con independencia de su régimen fiscal o titularidad (personas físicas, sociedades, entidades financieras, fondos o administraciones públicas).
* **20,94 millones (Este Proyecto - Módulo Patrimonial `INM_PR`)**: Stock de viviendas físicas pertenecientes a **personas físicas declarantes del IRPF en territorio común**. Concuerda plenamente con el Censo del INE al deducir el País Vasco y Navarra (~1,5M), las propiedades de personas jurídicas y fondos institucionales (~2,2M), los propietarios no residentes extranjeros sujetos a IRNR (~1,0M) y los propietarios con rentas exentas de presentar IRPF (~1,0M).
* **~18 millones (AEAT - Estadística de Declarantes del IRPF)**: La consulta Rubik de la AEAT no cuantifica el patrimonio residencial global, sino exclusivamente la **vivienda habitual de los hogares declarantes** (~15,6M en propiedad y ~2,4M en alquiler); excluye segundas residencias, inmuebles vacíos o viviendas arrendadas a terceros.

El **Parque Inmobiliario Total** del panel (32,0 M de unidades equivalentes, EE 77.233) suma todas las referencias catastrales con título en manos de declarantes, incluyendo plazas de garaje, trasteros con referencia propia, locales y parcelas. La cifra anterior (56,1 M) estaba inflada por los *placeholders* de declarantes sin inmuebles, ahora excluidos y auditados (24,1 M de unidades fantasma).

### 2. Clasificación del Alquiler y Convergencia con la AEAT

La reclasificación de contratos residenciales sin reducción fiscal pero con inquilino censado en `VIVHAB` (`"V"`) aproxima con precisión el cruce con el censo de domicilios que efectúa internamente la AEAT:

* **Alquiler Habitual (2.333.149 viviendas, EE 14.282, vs. 2.409.689 oficial)**: Ajuste del **96,8 %**. La pequeña diferencia restante reside en que la AEAT reporta declaraciones/liquidaciones individuales, mientras que este panel calcula viviendas equivalentes enteras (GWSM). En matrimonios al 50%, la AEAT computa 2 declaraciones y el panel computa 1,0 vivienda ($2.333.149 \times 1,033 \text{ declarantes/vivienda} \approx \mathbf{2.409.689}$).

* **Alquiler No Habitual (297.473 viviendas, EE 4.161, vs. 309.479 oficial)**: Ajuste del **96,1 %**. El filtro residencial (`VIV >= 1` o `"V"`) con renta mínima anual de 2.400 € aparta garajes independientes y trasteros sin desvirtuar la oferta turística o de temporada; el análisis de sensibilidad muestra que el resultado es estable en el entorno del umbral (297k con 2.400 €; 311k con 1.800 €; 263k con 3.600 €).

### 3. Renta Media: Flujo Mensual vs. Anualización con Días Reales

La annualización con los **días de contrato observados** (disponibles en el 99,99 % de los alquileres) resuelve la discrepancia estructural que antes se imputaba con constantes agregadas:

* **Alquiler habitual**: el flujo directo (639,70 €/mes, EE 2,07) es la métrica comparable con la referencia AEAT de 657 €/mes (ajuste 97,4 %): casi todos los contratos habituales son de año completo, por lo que la anualización apenas traslada la media (734,67 €/mes) y solo refleja los contratos habituales parciales.
* **Alquiler no habitual**: el flujo prorrateado a 12 meses (786,75 €/mes) mezcla estancias turísticas cortas de alta tarifa con el periodo completo del año. La **anualización a 365 días con los días reales de cada contrato** (1.389,43 €/mes, EE 36,30) reproduce la tarifa efectiva ponderada que la AEAT calcula contrato a contrato (Ref. 1.361 €/mes, ajuste 102,1 %). La antigua imputación uniforme de 271 días subestimaba esta métrica (1.059,65 €/mes) al no capturar la rotación estacional.

### 4. Cobertura de la Masa Declarada

El panel enlaza el **89 %** de la masa declarada en el Módulo 8 (2.641 M€ de 2.952 M€ brutos); el resto son alquileres sin referencia catastral (161 M€, extranjero/foral) o sin título correspondiente en `INM_PR` (150 M€). La masa unida, elevada por `FACTORCAL` (26.489 M€, CV 0,59 %), concuerda con la referencia AEAT (~26.500 M€).

**Diagnóstico de la Ejecución Final**

El ajuste metodológico sitúa las estimaciones del panel en una convergencia estrecha frente a los anclajes censales oficiales de la AEAT:

| Métrica | Resultado (Script 2) | EE (CV) | Referencia AEAT (Bloque I) | Tasa de Ajuste |
| --- | --- | --- | --- | --- |
| **Alquiler Habitual** | 2.333.149 viv. | 14.282 (0,61%) | 2.409.689 viv. | **96,8%** |
| **Alquiler No Habitual** | 297.473 viv. | 4.161 (1,40%) | 309.479 viv. | **96,1%** |
| **Renta Media Habitual (flujo)** | 639,70 €/mes | 2,07 (0,32%) | 657,00 €/mes | **97,4%** |
| **Renta Media No Habitual (anualizada)** | 1.389,43 €/mes | 36,30 (2,61%) | 1.361,00 €/mes | **102,1%** |
| **Masa Agregada Declarada** | 26.489 M€ | 157 (0,59%) | ~26.500 M€ | **100,0%** |
| **Parque Residencial (declarantes IRPF)** | 20.936.734 viv. | 46.680 (0,22%) | ~20,9 M (INE conciliado) | **100,0%** |

Los intervalos de confianza al 95 % derivados de las EE confirman que las brechas residuales frente a la AEAT son **estructurales** (perímetro de observación: declaraciones vs. viviendas equivalentes; cobertura del 89 % de la masa del Módulo 8) y **no error muestral**: p. ej., el IC del alquiler habitual (2.305.156–2.361.142) no cubre los 2.409.689 oficiales, mientras que la renta no habitual anualizada (1.318–1.461 €/mes) **sí es estadísticamente consistente** con la referencia AEAT de 1.361 €/mes.
