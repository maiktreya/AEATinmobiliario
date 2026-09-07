# Panel 2023 de alquiler e inmuebles

## Objetivo

Dos scripts trabajan sobre los ficheros de microdatos de AEAT para el ejercicio
2023:

- **`revPanel2023_join.R`**: construye una única tabla, a **nivel inmueble**, que
  identifica qué propiedades posee cada arrendador, su uso catastral, sus
  características físicas y el alquiler que ese arrendador declaró
  específicamente por ese inmueble. Exporta el resultado a
  `out/2023/2023dt_panel_inmo.gz`.
- **`revPanel2023_check.R`**: lee esa tabla y calcula métricas de completeness
  sobre el código de uso catastral (`URBACLAVE`).

## Ficheros de origen

| Fichero | Contenido | Nivel |
| --- | --- | --- |
| `_1_IDEN2023.txt` | Identificadores y peso de calibración (`FACTORCAL`) | persona-hogar |
| `_2_Renta2023.txt` | Renta bruta/disponible y agregados de alquiler | persona-hogar |
| `_8_IRPF2023_RRII.txt` (Módulo 8) | Rendimientos de capital inmobiliario por inmueble concreto | persona-hogar-inmueble |
| `INM_PR2023.txt` (Módulo 2) | Inmuebles que posee cada persona (patrimonio) | persona-inmueble |
| `VIVHAB2023.txt` (Módulo 1) | Uso catastral (`URBACLAVE`) del inmueble declarado como vivienda habitual | inmueble (con ocupante) |
| `INM_CARACT2023.txt` (Módulo 3) | Características físicas del inmueble | inmueble |

## Cómo se construye la tabla

**Nivel de la unión: el inmueble (`RC_ANONIMA`), no la persona.** `INM_PR` (qué
posee cada arrendador) se une con `VIVHAB`, `INM_CARACT` y `RRII` por
`RC_ANONIMA` — y adicionalmente por `IDENPER` en el caso de `RRII`, para que el
alquiler se atribuya al mismo arrendador que posee el inmueble. Como `VIVHAB`
describe a quien ocupa el inmueble como vivienda habitual (que puede ser el
inquilino, no el propietario), sus columnas llevan el sufijo `_OCUPANTE`.

**Ausencia de referencia catastral.** Antes de unir, cada `RC_ANONIMA` ausente
se sustituye por un valor centinela único (para evitar que dos inmuebles sin
referencia catastral se emparejen entre sí solo por compartir esa ausencia) y
se restaura a `NA` al final.

**Alquiler por inmueble, no por persona.** `_8_IRPF2023_RRII.txt` incluye
`RefCatastral` (aquí `RC_ANONIMA`), lo que permite atribuir el alquiler
declarado al inmueble exacto en vez de a la persona. Los campos usados:

| Variable | Casilla | Significado |
| --- | --- | --- |
| `INGRESOS_INTEGROS` | PAR102 | Alquiler bruto de ese inmueble |
| `RENDIMIENTO_NETO` | PAR149 | Bruto menos gastos deducibles |
| `REDUCCION_ALQUILER_VIVIENDA` | PAR150 | Reducción art. 23.2 Ley IRPF (solo si es vivienda) |
| `REDUCCION_IRREGULAR` | PAR151 | Reducción por rendimientos irregulares |
| `RENDIMIENTO_MINIMO_PARENTESCO` | PAR152 | Rendimiento mínimo si hay parentesco con el inquilino |
| `RENDIMIENTO_NETO_REDUCIDO` | PAR154 | Cifra final que tributa |

Cuando un mismo inmueble tiene más de un registro en `RRII` (distintos periodos
de arrendamiento dentro del año, p. ej. cambio de inquilino), los importes se
**suman** antes de unir, y `N_PERIODOS_RRII` deja constancia de cuántos
registros se combinaron.

**Contexto de renta a nivel persona.** `_2_Renta2023.txt` aporta agregados de
renta bruta/disponible (`RB`, `RBD`) y de alquiler (`M3_ALQUILER_TOTAL`,
`M31_ALQUILER_PFISICAS`, `M32_ALQUILER_ENTIDADES` — este último mezcla locales
y viviendas, por lo que no se usa para identificar el subconjunto de alquiler).

**Valores ausentes.** `_2_Renta2023.txt` y `_8_IRPF2023_RRII.txt` usan `"."`
como marcador de ausencia en campos numéricos, además de la cadena vacía; se
trata explícitamente como valor ausente en la lectura. Al exportar, los `NA`
se escriben como texto `"NA"` (no como campo vacío) para que sigan siendo
distinguibles de una cadena vacía real al releer con `fread()`.

**Columnas indicador.** `IN_VIVHAB`, `IN_CARACT` e `IN_RRII` señalan
explícitamente si un inmueble aparece en cada uno de esos tres módulos,
independientemente de si el resto de sus columnas vienen vacías o `NA`.

## Estructura de la tabla final

Cada fila de `dt` es una combinación (inmueble, arrendador):

- **Identificación y propiedad**: `RC_ANONIMA`, `IDENPER`, `URBACODERE`,
  `URBAPORBIN`, `URBAVALORC`, `URBAFECHIN`, `URBAFECHFI`, `N_PROPIEDADES` (nº
  de inmuebles distintos que posee ese arrendador).
- **Uso y ocupación** (puede no existir): `URBACLAVE`, `TIPO_OCUPANTE`,
  `MARCA_VIVHAB`, `IDENPER_OCUPANTE`, `IN_VIVHAB`.
- **Características físicas** (puede no existir): `CA`, `PROV`, `MUN`, `DIST`,
  `SECC`, `VIVLOC`, `VIVLOC_METROS`, `VIV`, `VIV_METROS`, `ANCONS`, `VALCAT`,
  `IN_CARACT`.
- **Alquiler declarado de ese inmueble** (puede no existir):
  `INGRESOS_INTEGROS`, `RENDIMIENTO_NETO`, `REDUCCION_ALQUILER_VIVIENDA`,
  `REDUCCION_IRREGULAR`, `RENDIMIENTO_MINIMO_PARENTESCO`,
  `RENDIMIENTO_NETO_REDUCIDO`, `N_PERIODOS_RRII`, `IN_RRII`.
- **Contexto de renta del arrendador** (nivel persona): `IDENHOG`, `TRAMO`,
  `FACTORCAL`, `RB`, `RBD`, `M3_ALQUILER_TOTAL`, `M31_ALQUILER_PFISICAS`,
  `M32_ALQUILER_ENTIDADES`.

## Qué calcula el script de diagnóstico

`revPanel2023_check.R` compara el universo completo de inmuebles (`dt`) con el
subconjunto que tiene alquiler realmente declarado por ese inmueble
(`dt_sub <- dt[INGRESOS_INTEGROS > 0]`), y mide qué proporción de cada uno
tiene `URBACLAVE` disponible, tanto por texto (`is.na(URBACLAVE)`) como por el
indicador `IN_VIVHAB`.

**Hallazgo principal**: de 10.504.050 inmuebles del panel, 424.439 tienen
alquiler real declarado. De ellos, el **71% no aparece en `VIVHAB`** en
absoluto. Tiene sentido estructural: un inmueble alquilado no es la vivienda
habitual de su propietario, así que solo aparecerá en `VIVHAB` si el inquilino
(u otro ocupante) también está en el panel y declaró esa misma dirección como
propia. `URBACLAVE` solo permite clasificar directamente a una minoría
(~29%) de los inmuebles realmente alquilados.

## Interpretación de `URBACLAVE`

Cuando `URBACLAVE` está disponible, no siempre vale `"V"` (vivienda). El
código más frecuente después de `"V"`, `"A"`, aparece junto a un registro
`"V"` de la misma persona en el 98,5% de los casos en que se observa. Esto es
coherente con el **Real Decreto 1020/1993** (normas técnicas de valoración
catastral), que clasifica garajes, trasteros y locales en estructura como
modalidades dentro del uso residencial (normas 20, apartados 1.1.3, 1.2.3 y
1.3.2), previendo que estos anexos se tipifiquen junto a la vivienda a la que
sirven. Referencia: <https://www.boe.es/eli/es/rd/1993/06/25/1020/con>.

Los demás códigos observados (`Z`, `I`, `G`, `C`, `K`, `O`, `M`, `Y`, `E`,
`B`, `J`, `T`, `P`, `R`...) tienden a aparecer solos, consistente con usos no
residenciales (industrial, oficinas, comercial, deportivo...) recogidos en el
mismo RD. Para separar viviendas principales de garajes/trasteros u otros
usos, filtrar por `URBACLAVE == "V"` es el criterio correcto — no basta con
comprobar que el inmueble aparece en `VIVHAB`.

## Limitaciones

- **Cobertura de `URBACLAVE` limitada, especialmente entre alquilados
  (~29%)**: es una limitación real de origen, no del proceso de unión.
- **`N_PERIODOS_RRII` > 1 implica una suma de importes**, no un desglose por
  periodo; se pierde el detalle de fechas/inquilinos distintos dentro del año.
- **`M31_ALQUILER_PFISICAS` mezcla alquiler de locales y viviendas** — es
  contexto a nivel persona, no un indicador de uso residencial.
- Los importes monetarios de `RRII` y `_2_Renta` llevan 2 decimales
  implícitos, aplicados en la lectura.

```r
r$> source("/home/other/Downloads/informe alquiler MICO 4/src/rev/revPane
    l2023_join.R", encoding = "UTF-8")
|--------------------------------------------------|
|==================================================|
|--------------------------------------------------|
|==================================================|
[1] "total prop. inmobiliarias panel:  10504050"
[1] "total prop. inmobiliarias submuestra inmuebles alquilados:  424439"
[1] "Porcentaje de NAs sobre muestra de inmuebles: 0.4"
[1] "Porcentaje de NAs sobre submuestra inmuebles alquilados: 0.71"
[1] "no aparece en VIVHAB en absoluto: 0.71"
[1] "aparece con codigo de uso valido 0.29"
```
