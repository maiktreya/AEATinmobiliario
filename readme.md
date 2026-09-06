# Panel 2023 de alquiler e inmuebles: qué hace el script 1 y por qué

## Objetivo

El script `revPanel2023_join.R` construye una única tabla, a **nivel inmueble**, que
identifica correctamente qué propiedades posee cada arrendador (`IDENPER`), qué uso
catastral tiene cada una (`URBACLAVE`), sus características físicas, y el importe de
alquiler e incentivos fiscales asociados a esa persona. El resultado se exporta a
`out/2023/2023dt_panel_inmo.gz`, listo para `fread()`.

## Ficheros de origen

| Fichero | Contenido | Nivel |
| --- | --- | --- |
| `_1_IDEN2023.txt` | Identificadores y peso de calibración (`FACTORCAL`) | persona-hogar |
| `_2_Renta2023.txt` | Rendimientos declarados, incluida `RENTA_ALQ` | persona-hogar |
| `_8_IRPF2023_RRII.txt` | `PAR150`, importe de la reducción por alquiler de vivienda | persona-hogar |
| `INM_PR2023.txt` (Módulo 2) | Inmuebles que posee cada persona (patrimonio) | persona-inmueble |
| `VIVHAB2023.txt` (Módulo 1) | Uso catastral (`URBACLAVE`) del inmueble declarado como vivienda habitual, por quien lo declare | inmueble (con ocupante) |
| `INM_CARACT2023.txt` (Módulo 3) | Características físicas del inmueble (superficie, año, valor catastral...) | inmueble |

## Decisiones clave y problemas resueltos

### 1. Vincular por inmueble (`RC_ANONIMA`), no por persona (`IDENPER`)

La primera versión del script enlazaba `VIVHAB` con el resto de la información
**por `IDENPER`** — es decir, asignaba a cada arrendador el `URBACLAVE` de *su propia*
vivienda habitual, no el del inmueble que realmente alquila (que casi siempre es un
inmueble distinto). La versión corregida une `INM_PR` (los inmuebles que posee el
arrendador) con `VIVHAB` y `INM_CARACT` **por `RC_ANONIMA`**, de modo que cada fila
describe el uso y las características del inmueble concreto, sea o no la vivienda
habitual de su propietario.

Como `VIVHAB` describe a quien declara el inmueble como habitual (que puede ser el
inquilino, no el propietario), sus columnas se renombraron con el sufijo `_OCUPANTE`
para no confundirlas con los datos del arrendador.

### 2. `NA` no debe unirse con `NA`

`merge()` trata dos valores `NA` en la clave de unión como iguales entre sí. Como una
parte importante de `INM_PR` y `VIVHAB` carece de `RC_ANONIMA` (inmuebles sin
referencia catastral, declaraciones `M100` sin cruce con Catastro), unir directamente
por esa clave enlazaría entre sí registros de inmuebles completamente distintos que
simplemente comparten la ausencia de referencia. Antes de unir, cada `NA` en
`RC_ANONIMA` se sustituye por un valor centinela único y negativo (distinto rango por
fichero, para que tampoco coincidan entre sí), y se restaura a `NA` después de la
unión.

### 3. `PAR150` es un importe, no un indicador

El campo aparentaba ser una casilla de sí/no, pero al inspeccionar una muestra
(`table(trimws(...))`) resultó ser un importe: `"."` cuando no aplica, `"0"` cuando se
solicita con importe cero, y valores numéricos reales en el resto de casos. Al existir
varios registros de `PAR150` para una misma persona-hogar, se agregan **sumando** el
importe (`sum(PAR150, na.rm = TRUE)`) antes de unir, en lugar de quedarnos con el
primer registro o concatenar valores — más correcto y, al ser una suma numérica, mucho
más rápido que la alternativa de texto usada al principio.

### 4. `"."` como marcador de ausencia

Tanto `_2_Renta2023.txt` como `_8_IRPF2023_RRII.txt` usan `"."` para indicar ausencia
en campos numéricos, además de la cadena vacía habitual. Se declaró explícitamente
`na = c("", "NA", ".")` en la lectura de ambos ficheros; sin ello, `read_fwf()` seguía
convirtiendo esos valores en `NA` pero lo registraba como un fallo de parseo,
generando el aviso `"One or more parsing issues"` sin indicar la causa.

### 5. Tipos de columna explícitos

Se fijó `col_types` en cada lectura en lugar de dejar que `readr` los adivinara.
Esto evita ambigüedades (por ejemplo, `RENTA_ALQ` adivinado como texto en vez de
número) y hace que las claves de unión (`IDENPER`, `IDENHOG`, `RC_ANONIMA`) sean del
mismo tipo en todos los ficheros, evitando fallos de unión silenciosos.

### 6. Duplicados en `_1_IDEN`/`_2_Renta`/`PAR150`

Antes de unir, se comprueba cuántas claves `(IDENPER, IDENHOG)` están duplicadas en
cada fichero. `IDEN` y `RENTA` no tienen duplicados; los duplicados observados en el
panel de renta procedían enteramente de `PAR150` (ver punto 3) y desaparecen al
agregar ese fichero antes de unirlo. Tras la agregación, cada persona (`IDENPER`)
mantiene un único registro fiscal anual.

### 7. `fwrite`/`fread` y la diferencia entre `NA` y `""`

`fwrite()` escribe los `NA` como campo vacío por defecto, indistinguible de una cadena
vacía real (`""`) al releer con `fread()`. Esto mezclaba dos situaciones muy distintas
para `URBACLAVE`: *el inmueble no aparece en `VIVHAB2023.txt`* (debería ser `NA`) frente
a *aparece en `VIVHAB`, pero el campo viene vacío en el fichero origen* (`""`
genuina). Se corrigió de dos formas complementarias:

- `fwrite(..., na = "NA")`: los `NA` se escriben como texto `"NA"`, que `fread()`
  reconoce como ausencia por defecto.
- Columna `IN_VIVHAB` (`TRUE`/`FALSE`): indicador explícito, calculado antes de la
  unión, que no depende de convenciones de texto y sobrevive a cualquier exportación
  futura.

### 8. Registros "vacíos salvo el identificador" en `VIVHAB`

Se comprobó, inspeccionando bytes concretos del fichero original, que algunos
registros de `VIVHAB2023.txt` solo contienen `IDENPER` y el resto de campos en blanco
a lo largo de todo el registro (longitud completa, 29 caracteres). Es un rasgo real
del fichero de origen — probablemente una persona del universo del panel sin ningún
dato de vivienda ese año — y no un efecto de la unión.

## Estructura final de la tabla

Cada fila de `dt` es una combinación (inmueble del arrendador, arrendador), con:

- **Identificación y propiedad**: `RC_ANONIMA`, `IDENPER`, `URBACODERE`, `URBAPORBIN`,
  `URBAVALORC`, `URBAFECHIN`, `URBAFECHFI`, `N_PROPIEDADES` (nº de inmuebles que posee
  ese arrendador).
- **Uso y ocupación** (de `VIVHAB`, puede no existir): `URBACLAVE`, `TIPO_OCUPANTE`,
  `MARCA_VIVHAB`, `IDENPER_OCUPANTE`, `IN_VIVHAB`.
- **Características físicas** (de `INM_CARACT`, puede no existir): `CA`, `PROV`, `MUN`,
  `DIST`, `SECC`, `VIVLOC`, `VIVLOC_METROS`, `VIV`, `VIV_METROS`, `ANCONS`, `VALCAT`.
- **Renta y fiscalidad del arrendador** (nivel persona, no por inmueble):
  `RENTAB`, `RENTAD`, `RENTA_ALQ`, `TRAMO`, `FACTORCAL`, `PAR150`, `N_PAR150`.

## Limitaciones a tener presentes

- **`RENTA_ALQ` y `PAR150` son importes a nivel persona/hogar, no por inmueble.** Si
  un arrendador tiene varios inmuebles (`N_PROPIEDADES > 1`), ese mismo importe se
  repite en cada una de sus filas; no es posible, con esta información, saber qué
  parte del alquiler corresponde a cada inmueble concreto.
- **Decimales de `RENTA_ALQ`, `RENTAB`, `RENTAD` y `PAR150` sin confirmar.** A
  diferencia de los campos de Módulo 2 y 3 (documentados con 2 decimales implícitos),
  no se dispone de la ficha oficial de estos campos, así que no se aplicó ningún
  ajuste de escala. Conviene confirmarlo contra la documentación de AEAT si los
  importes resultantes parecen ir desfasados en un factor de 100.
- **`URBACLAVE` solo está disponible para el subconjunto de inmuebles que aparecen en
  `VIVHAB2023.txt`.** Un inmueble alquilado que nunca fue declarado como vivienda
  habitual por nadie (ni por el arrendador ni por el inquilino) sencillamente no tiene
  este dato — no es un fallo de la unión, es una limitación de cobertura del propio
  fichero de origen.
