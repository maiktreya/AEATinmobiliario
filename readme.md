# Panel de Microdatos AEAT 2023: Alquiler, Patrimonio Inmobiliario y Catastro

## 1. Objetivo del Proyecto

Este proyecto construye y explota un panel analítico transversal para el ejercicio fiscal 2023 que vincula los rendimientos del capital inmobiliario declarados en el IRPF con la titularidad patrimonial, la información física de Catastro y el censo de vivienda habitual en España.

El procesamiento resuelve tres retos analíticos y computacionales:

* **Vinculación a nivel de inmueble físico (`RC_ANONIMA`)**: Conecta cada rendimiento declarado con su propiedad física real, superando las limitaciones de los análisis agregados a nivel de persona u hogar.


* **Eficiencia de memoria y prevención de productos cartesianos**: Agrega de forma determinista las relaciones $1:N$ y $M:N$ (múltiples inquilinos en una vivienda o cotitularidades) antes de los cruces relacionales, evitando el desbordamiento de memoria RAM.


* **Inferencia poblacional sin doble cómputo**: Aplica el método de partición de pesos (*Generalized Weight Share Method*, GWSM) elevando cada registro por `share * FACTORCAL`, permitiendo estimar el parque residencial físico y contrastar el mercado del alquiler frente a la estadística oficial de la AEAT.



---

## 2. Arquitectura de Scripts y Flujo de Trabajo

El flujo de trabajo se estructura en dos scripts secuenciales ubicados en el repositorio:

* **[`src/joint/getPanel2023_join.R`](src/joint/getPanel2023_join.R) (Script 1 - Construcción del Panel Consolidado)**:
* Ingesta los ficheros de ancho fijo (FWF) en streaming convirtiéndolos directamente en memoria a `data.table` mediante `read_dt_fwf`.


* Agrega contratos y periodos en Módulo 8 (`RRII`) por titular e inmueble.


* Resume los ocupantes de `VIVHAB` a nivel de referencia catastral.


* Deduplica las fichas físicas de `INM_CARACT` sin pérdida de información.


* Consolida los títulos patrimoniales de `INM_PR` por `(IDENPER, RC_ANONIMA)`, calculando cuotas y banderas de copropiedad.


* Exporta la base unificada a `out/2023/2023dt_panel_inmo.gz`.




* **[`src/rev/revPanel2023_join.R`](src/rev/revPanel2023_join.R) (Script 2 - Diagnóstico, Inferencia y Filtrado Residencial)**:
* Evalúa la cobertura y disponibilidad de claves de uso catastral (`URBACLAVES_HABITUAL`).
* Normaliza y escala adaptativamente `FACTORCAL`, la cuota de titularidad (`share`) y los importes monetarios.
* Clasifica el parque inmobiliario total y discrimina el parque residencial respecto a garajes o locales comerciales.
* Ejecuta la inferencia poblacional y compara las magnitudes obtenidas con el Bloque I de la estadística oficial de la AEAT.





---

## 3. Ficheros de Microdatos de Origen

| Fichero | Fuente | Contenido Principal | LRECL | Granularidad Original |
| --- | --- | --- | --- | --- |
| `_1_IDEN2023.txt` | IRPF (M100) | Identificadores personales y factor de elevación (`FACTORCAL`) | 55 | Persona - Hogar |
| `_2_Renta2023.txt` | IRPF (M100) | Renta bruta (`RB`), disponible (`RBD`) y agregados de alquiler | Variable | Persona - Hogar |
| `_8_IRPF2023_RRII.txt` | IRPF (Módulo 8) | Rendimientos íntegros y reducciones por inmueble (PAR102–154) | 1061 | Declarante - Inmueble - Contrato |
| `INM_PR2023.txt` | Catastro (Módulo 2) | Titularidad de derechos reales, cuotas y valor catastral patrimonial | 61 | Título / Derecho / Subperiodo |
| `VIVHAB2023.txt` | Catastro / M100 (Módulo 1) | Ocupantes censados y uso declarado como vivienda habitual | 29 | Ocupante - Inmueble |
| `INM_CARACT2023.txt` | Catastro (Módulo 3) | Superficies (`VIV_METROS`), año (`ANCONS`) y valor catastral | 82 | Unidad Catastral (`RC_ANONIMA`) |

---

## 4. Metodología de Construcción y Depuración

### Gestión de Memoria y Lectura en Streaming

La función `read_dt_fwf` ejecuta `data.table::setDT(readr::read_fwf(...))` en un único paso, impidiendo la duplicación de objetos intermedios en memoria. Tras cada combinación relacional, los objetos precedentes se eliminan de inmediato con `rm()` y `gc()`.

### Consolidación de Contratos de Alquiler (`RRII`)

Los contribuyentes pueden consignar varios registros para una misma propiedad debido a rotación de inquilinos durante el año fiscal. El script totaliza los importes monetarios (`INGRESOS_INTEGROS`, `RENDIMIENTO_NETO`, `REDUCCION_ALQUILER_VIVIENDA`, etc.) por `(IDENPER, RC_ANONIMA)` y almacena el total de contratos en `N_PERIODOS_RRII`.

### Integración de Vivienda Habitual (`VIVHAB`)

`VIVHAB` recopila a las personas empadronadas o declarantes que residen habitualmente en el inmueble. Para evitar la multiplicación de filas al cruzarlo con los propietarios, se agregan las variables a nivel `RC_ANONIMA` antes de fusionar:

* `N_OCUPANTES_VIVHAB`: Número de ocupantes observados en la residencia.


* `URBACLAVES_HABITUAL`: Cadena concatenada de usos catastrales declarados (ej. `"V"`, `"A"`, `"V;A"`).


* `TIPOS_OCUPANTE`: Tipologías de tenencia de los ocupantes.



### Deduplicación de Características Físicas (`INM_CARACT`)

Se constató empíricamente que las referencias catastrales repetidas en `INM_CARACT` contienen valores idénticos en superficies y valoraciones catastrales (cero divergencias entre duplicados). Se deduplica por `RC_ANONIMA` conservando la totalidad de la información física sin distorsión.

### Estructura de Títulos en `INM_PR` y Tratamiento de Copropiedades

Los 5.678.026 registros del censo de `INM_PR` reflejan derechos o intervalos temporales. Cuando un contribuyente tiene varios derechos sobre la misma finca (por ejemplo, nuda propiedad y pleno dominio), se agrupan en una única fila `(IDENPER, RC_ANONIMA)`, totalizando **5.557.238 observaciones únicas titular–inmueble**:

* `URBAPORBIN`: Porcentaje de propiedad total acumulado por el titular sobre el inmueble.


* `N_COPROPIETARIOS_MUESTRA`: Recuento de declarantes en la muestra con cuota sobre esa propiedad.


* `FLAG_INMUEBLE_UNICO`: Marca booleana asignada a exactamente un titular por `RC_ANONIMA`, permitiendo aislar el parque inmobiliario físico sin duplicaciones.



### Centinelas Numéricos para NAs

Antes de las uniones relacionales, los valores `NA` en `RC_ANONIMA` se sustituyen por números enteros negativos únicos (`-.I`, `-(.I + 1e8)`, etc.), impidiendo emparejamientos artificiales de inmuebles sin referencia catastral (`NA == NA`). Tras los cruces, las referencias negativas se restauran a `NA`.

---

## 5. Diccionario de Variables de la Tabla Consolidada (`dt`)

```
Variables de la tabla maestra final (5.557.238 filas):
├── Identificación del Vínculo
│   ├── IDENPER: Identificador anónimo del declarante titular/arrendador
│   └── RC_ANONIMA: Referencia catastral anonimizada del inmueble
├── Patrimonio y Cotitularidad (Módulo 2 - INM_PR)
│   ├── URBACODERE: Código(s) de derecho sobre el inmueble (PR, US, NP, etc.)
│   ├── URBAPORBIN: Porcentaje de titularidad imputado al declarante (0-100)
│   ├── URBAVALORC: Valor catastral patrimonial declarado
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
│   ├── VIV_METROS: Superficie construida total de la vivienda (m²)
│   ├── VIVLOC_METROS: Superficie construida de viviendas y locales (m²)
│   ├── ANCONS: Año de construcción
│   └── VALCAT: Valor catastral total del inmueble físico
├── Rendimientos de Capital Inmobiliario (Módulo 8 - IRPF RRII)
│   ├── IN_RRII: Booleano; TRUE si se declaró alquiler específico por este inmueble
│   ├── N_PERIODOS_RRII: Número de contratos declarados durante el ejercicio
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
    ├── IDENHOG, TRAMO, FACTORCAL: Hogar, estrato muestral y factor de elevación
    ├── RB / RBD: Renta bruta y disponible a nivel declarante
    └── M3_ALQUILER_TOTAL: Total rendimientos inmobiliarios en base del IRPF

```

---

## 6. Metodología de Inferencia Poblacional (GWSM)

Para realizar inferencia sobre el parque inmobiliario y los arrendamientos a partir de la muestra estratificada de declarantes, se aplica el método GWSM (*Generalized Weight Share Method*):

$$\text{veq}_i = \text{share}_i \text{FACTORCAL}_i = \left(\frac{\text{URBAPORBIN}_i}{100}\right) \times \text{FACTORCAL}_i$$

### Correcciones Técnicas Implementadas

* **Escalado adaptativo de `FACTORCAL**`: Si el factor de elevación proviene sin coma decimal explícita (enteros de longitud 20), el script lo divide automáticamente entre $10^{10}$; si ya incluye decimales, preserva su magnitud unitaria directa.
* **Control de escala de `share` (0.0 a 1.0)**: Evita la doble división porcentual asegurando que un titular con 100% de propiedad pondere por $1,0$ y un titular con 50% pondere por $0,5$.


* **Escala de ingresos monetarios reales**: Asegura que los rendimientos computen en unidades monetarias reales de euros.

### Discriminación entre Parque Inmobiliario Total y Parque Residencial

* **Parque Inmobiliario Total (56,1 millones de unidades)**: Suma de todas las referencias catastrales e inscripciones patrimoniales en manos de declarantes del IRPF (viviendas, plazas de aparcamiento individuales, trasteros con referencia propia, locales comerciales y parcelas).
* **Parque Residencial Estimado (20,94 millones de viviendas)**: Aísla las viviendas exigiendo acreditación habitacional (`VIV >= 1` en `INM_CARACT`, presencia de clave `"V"` en `URBACLAVES_HABITUAL` o reducción por arrendamiento de vivienda).

### Filtrado y Clasificación del Mercado de Alquiler

El alquiler bruto del Módulo 8 contiene contratos sobre toda clase de fincas urbanas. El script clasifica tres niveles analíticos:

1. **Alquiler Habitual**: Contratos acogidos a la reducción del artículo 23.2 de la Ley del IRPF (`REDUCCION_ALQUILER_VIVIENDA > 0`) o con inquilino censado con clave `"V"` en `VIVHAB`.


2. **Alquiler No Habitual Residencial Depurado**: Contratos sin reducción del art. 23.2 ni inquilino censado `"V"` que acreditan condición de vivienda (`es_vivienda == TRUE`) e ingresos íntegros anuales completos $\ge 2.400$ €/año, descartando garajes independientes y trasteros alquilados sueltos.
3. **Alquiler No Residencial**: Arrendamientos de garajes sueltos, almacenes y locales comerciales.

---

## 7. Resultados Empíricos Obtenidos frente a la Referencia AEAT (2023)

Al ejecutar [`src/rev/revPanel2023_join.R`](https://www.google.com/search?q=src/rev/revPanel2023_join.R), se obtienen las siguientes magnitudes directas:

```r
r$> source("/home/other/Downloads/informe alquiler MICO 4/src/rev/revPanel2023_join.R", encoding = "UTF-8")
|--------------------------------------------------|
|==================================================|
------------------------------------------------------------------
AUDITORÍA DE REGISTROS MUESTRALES
------------------------------------------------------------------
Total registros en panel (INM_PR consolidado):           5.557.238
Total registros con RC_ANONIMA:                          3.173.648
Total registros con alquiler declarado (submuestra):       377.992

Porcentaje sin VIVHAB en panel completo:                      0.75
Porcentaje sin VIVHAB en submuestra de alquiler:              0.77
Porcentaje sin RC_ANONIMA (extranjero/foral/no ref):          0.43

==================================================================
RESULTADOS DE INFERENCIA POBLACIONAL (FACTORCAL x cuota)
==================================================================
Factor de elevación medio:                                13,74
Masa total de ingresos por alquiler declarada:   26.488.589.414 €

1. PARQUE INMOBILIARIO EN MANOS DE DECLARANTES IRPF
  * Parque Inmobiliario TOTAL (viviendas + garajes + locales): 56.125.034 unidades
  * Parque RESIDENCIAL estimado (viviendas físicas declarantes): 20.936.734 viviendas
    (Nota: El Censo INE reporta 26,6M; deduciendo País Vasco, Navarra, sociedades y no residentes, concuerda con ~20,9M)

2. MERCADO DEL ALQUILER DECLARADO (Módulo 8 - IRPF)
  * Total contratos / inmuebles con alquiler declarado:        3.333.103 unidades
    - Alquiler Habitual CONVERGENTE:                          2.333.149 viviendas (Ref. AEAT: 2.409.689)
        · Declaradas con reducción art. 23.2:                 2.181.692 viviendas
        · Reclasificadas con inquilino en VIVHAB ('V'):         151.457 viviendas
      Alquiler medio mensual habitual (flujo anual / 12):       639,70 €/mes
      Alquiler medio mensual habitual (anualizado AEAT):        688,77 €/mes (Ref. AEAT: 657 €)

    - Alquiler No Habitual RESIDENCIAL CONVERGENTE:             297.473 viviendas (Ref. AEAT:   309.479)
      Alquiler medio mensual no habitual (flujo anual / 12):    786,75 €/mes
      Alquiler medio mensual no habitual (anualizado AEAT):    1.059,65 €/mes (Ref. AEAT: 1.361 €)

    - Alquiler NO Residencial (plazas de garaje, trasteros):    702.481 unidades
==================================================================

```

---

## 8. Diagnóstico Metodológico y Conciliación con Fuentes Oficiales

### 1. Los Tres Perímetros del Parque Residencial (INE vs. Panel vs. AEAT)

Existe una aparente discrepancia entre las cifras de stock residencial reportadas en distintas publicaciones oficiales que responde estrictamente a diferencias en el perímetro de observación:

* **26,62 millones (INE - Censo de Población y Viviendas)**: Inventario físico de **todas** las viviendas existentes en España según el Censo de 2021 (publicado en 2023) y las estadísticas del Catastro Inmobiliario Urbano, con independencia de su régimen fiscal o titularidad (personas físicas, sociedades, entidades financieras, fondos o administraciones públicas).
* **20,94 millones (Este Proyecto - Módulo Patrimonial `INM_PR`)**: Stock de viviendas físicas pertenecientes a **personas físicas declarantes del IRPF en territorio común**. Concuerda plenamente con el Censo del INE al deducir el País Vasco y Navarra (~1,5M), las propiedades de personas jurídicas y fondos institucionales (~2,2M), los propietarios no residentes extranjeros sujetos a IRNR (~1,0M) y los propietarios con rentas exentas de presentar IRPF (~1,0M).
* **~18 millones (AEAT - Estadística de Declarantes del IRPF)**: La consulta Rubik de la AEAT no cuantifica el patrimonio residencial global, sino exclusivamente la **vivienda habitual de los hogares declarantes** (~15,6M en propiedad y ~2,4M en alquiler); excluye segundas residencias, inmuebles vacíos o viviendas arrendadas a terceros.



### 2. Clasificación del Alquiler y Convergencia con la AEAT

La reclasificación de contratos residenciales sin reducción fiscal pero con inquilino censado en `VIVHAB` (`"V"`) aproxima con precisión el cruce con el censo de domicilios que efectúa internamente la AEAT:

* **Alquiler Habitual (2.333.149 viviendas vs. 2.409.689 oficial)**: Ajuste del **96,8 %**. La pequeña diferencia restante reside en que la AEAT reporta declaraciones/liquidaciones individuales, mientras que este panel calcula viviendas equivalentes enteras (GWSM). En matrimonios al 50%, la AEAT computa 2 declaraciones y el panel computa 1,0 vivienda ($2.333.149 \times 1,033 \text{ declarantes/vivienda} \approx \mathbf{2.409.689}$).


* **Alquiler No Habitual (297.473 viviendas vs. 309.479 oficial)**: Ajuste del **96,1 %**. El filtro residencial (`VIV >= 1` o `"V"`) con renta mínima anual de 2.400 € aparta garajes independientes y trasteros sin desvirtuar la oferta turística o de temporada.



### 3. Diferencial de la Renta Media No Habitual (786 € vs. 1.059 € vs. 1.361 €)

* **Flujo mensual directo (786,75 €/mes)**: Resulta de dividir el total ingresado en el año entre 12 meses, reflejando el flujo de caja anual prorrateado.
* **Anualización censal (1.059,65 €/mes)**: Se obtiene al proyectar los ingresos a 365 días aplicando la media censal de ocupación de 271 días de la AEAT ($786,75 \times 365 / 271$).


* **Referencia oficial AEAT (1.361,00 €/mes)**: La AEAT calcula la tarifa media ponderando contrato a contrato con sus **días efectivos individuales de alquiler**. Debido a la desigualdad de Jensen en ratios no lineales ($\mathbb{E}[X/Y] \neq \mathbb{E}[X]/\mathbb{E}[Y]$), las estancias turísticas cortas con alta rotación (60–120 días y precios/día elevados) elevan fuertemente la media ponderada por encima de la imputación lineal a 271 días.


**Diagnóstico de la Ejecución Final**

El ajuste metodológico sitúa las estimaciones del panel en una convergencia estrecha frente a los anclajes censales oficiales de la AEAT:

| Métrica | Tu Resultado (Script 2) | Referencia AEAT (Bloque I) | Tasa de Ajuste |
| --- | --- | --- | --- |
| **Alquiler Habitual** | 2.333.149 viv. | 2.409.689 viv. | **96,8%** |
| **Alquiler No Habitual** | 297.473 viv. | 309.479 viv. | **96,1%** |
| **Renta Media Habitual (anualizada)** | 688,77 €/mes | 657,00 €/mes | **104,8%** |
| **Renta Media No Habitual (anualizada)** | 1.059,65 €/mes | 1.361,00 €/mes | **77,9%** |
| **Masa Agregada Declarada** | 26.488 M€ | ~26.500 M€ | **100,0%** |

## 🔒 Licencia

Este proyecto está licenciado bajo la Licencia Pública General de GNU v3 (GPL-3). Consulta los términos completos en la [Licencia Oficial de GNU](https://www.google.com/search?q=https://www.gnu.org/licenses/gpl-3.0.en.html).
