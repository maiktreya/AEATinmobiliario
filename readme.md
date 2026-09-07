# Panel 2023 de alquiler e inmuebles: qué hace el script 1 y por qué

## Objetivo

El script `revPanel2023_join.R` construye una única tabla, a **nivel inmueble**, que
identifica correctamente qué propiedades posee cada arrendador (`IDENPER`), qué uso
catastral tiene cada una (`URBACLAVE`), sus características físicas, y el alquiler
que ese arrendador declaró específicamente por ese inmueble. El resultado se exporta
a `out/2023/2023dt_panel_inmo.gz`, listo para `fread()`.

## Ficheros de origen

| Fichero | Contenido | Nivel |
| --- | --- | --- |
| `_1_IDEN2023.txt` | Identificadores y peso de calibración (`FACTORCAL`) | persona-hogar |
| `_2_Renta2023.txt` | Rentas y agregados de renta bruta/disponible | persona-hogar |
| `_8_IRPF2023_RRII.txt` (Módulo 8) | Rendimientos de capital inmobiliario **por inmueble concreto** | persona-hogar-inmueble |
| `INM_PR2023.txt` (Módulo 2) | Inmuebles que posee cada persona (patrimonio) | persona-inmueble |
| `VIVHAB2023.txt` (Módulo 1) | Uso catastral (`URBACLAVE`) del inmueble declarado como vivienda habitual, por quien lo declare | inmueble (con ocupante) |
| `INM_CARACT2023.txt` (Módulo 3) | Características físicas del inmueble (superficie, año, valor catastral...) | inmueble |

Las posiciones de `_1_IDEN`, `_2_Renta` y `_8_IRPF_RRII` están verificadas contra el
`DiseñoRegistro_2023.xlsx` oficial y el manual metodológico del panel (Documentos de
Trabajo del IEF 4/2025, `2025_04.pdf`). Las de los tres módulos inmobiliarios
(`INM_PR`, `VIVHAB`, `INM_CARACT`) proceden de la ficha de variables específica de
ese módulo.

## Decisiones clave y problemas resueltos

### 1. Vincular por inmueble (`RC_ANONIMA`), no por persona (`IDENPER`)

La primera versión del script enlazaba todo **por `IDENPER`** — es decir, asignaba a
cada arrendador el `URBACLAVE` y el alquiler de *su propia* vivienda habitual, no del
inmueble que realmente alquila (casi siempre un inmueble distinto). La versión
corregida une `INM_PR` (inmuebles que posee el arrendador) con `VIVHAB`,
`INM_CARACT` y `RRII` **por `RC_ANONIMA`** (y adicionalmente por `IDENPER` en el caso
de `RRII`, para que el alquiler se atribuya al mismo arrendador que posee el
inmueble), de modo que cada fila describe el inmueble concreto.

Como `VIVHAB` describe a quien declara el inmueble como habitual (que puede ser el
inquilino, no el propietario), sus columnas se renombraron con el sufijo `_OCUPANTE`.

### 2. `NA` no debe unirse con `NA`

`merge()` trata dos valores `NA` en la clave de unión como iguales entre sí. Como una
parte importante de `INM_PR`, `VIVHAB` y `RRII` carece de `RC_ANONIMA`, unir
directamente por esa clave enlazaría entre sí inmuebles completamente distintos que
solo comparten la ausencia de referencia. Antes de unir, cada `NA` en `RC_ANONIMA` se
sustituye por un centinela único y negativo (rango distinto por fichero) y se
restaura a `NA` después de la unión.

### 3. Posiciones corregidas en `_2_Renta2023.txt`

Las posiciones usadas originalmente (`RENTAB` en 707–718, `RENTAD` en 719–730,
`RENTA_ALQ` en 191–202) no correspondían a ningún campo real: leían fragmentos de
`Dividendos` (M22) y de `Cuota resultante/Cotizaciones sociales` (M711/M72), sin dar
ningún error porque seguían dentro de la longitud del registro. Verificado el diseño
oficial, los campos correctos son:

| Variable | Posición | Significado |
| --- | --- | --- |
| `M3_ALQUILER_TOTAL` | 233, long. 15 | Total rentas por arrendamiento (`M31+M32`) |
| `M31_ALQUILER_PFISICAS` | 248, long. 15 | De personas físicas — mezcla locales y viviendas |
| `M32_ALQUILER_ENTIDADES` | 263, long. 15 | De entidades en atribución de rentas |
| `RB` | 878, long. 15 | Renta bruta |
| `RBD` | 893, long. 15 | Renta bruta disponible |

`M31` sigue sin separar uso residencial de comercial, por lo que **no** se usa para
identificar el subconjunto de alquiler — para eso está `RRII` (punto 4).

### 4. `RRII`: de "`PAR150` sumado por persona" a alquiler real por inmueble

El fichero `_8_IRPF2023_RRII.txt` incluye `RefCatastral` (renombrado aquí
`RC_ANONIMA`), algo que la primera versión del script no aprovechaba: solo leía
`PAR150` a nivel persona-hogar, obligando a repetir ese importe en todas las
propiedades del arrendador. La versión corregida lee el desglose completo por
inmueble:

| Variable | Casilla | Significado |
| --- | --- | --- |
| `INGRESOS_INTEGROS` | PAR102 | Alquiler bruto de ese inmueble concreto |
| `RENDIMIENTO_NETO` | PAR149 | Bruto menos gastos deducibles |
| `REDUCCION_ALQUILER_VIVIENDA` | PAR150 | Reducción art. 23.2 Ley IRPF — solo aplica si es vivienda |
| `REDUCCION_IRREGULAR` | PAR151 | Reducción por rendimientos irregulares |
| `RENDIMIENTO_MINIMO_PARENTESCO` | PAR152 | Rendimiento mínimo si hay parentesco con el inquilino |
| `RENDIMIENTO_NETO_REDUCIDO` | PAR154 | Cifra final que tributa |

Al comprobar duplicados por `(IDENPER, RC_ANONIMA)` aparecieron 41.564 casos reales
— muy probablemente distintos periodos de arrendamiento del mismo inmueble dentro
del mismo año (p. ej. cambio de inquilino a mitad de año; el diseño de registro
incluye pares de fechas para cada bloque, PAR120/121 y PAR135/136). Se agregan
**sumando** los importes antes de unir, dejando constancia en `N_PERIODOS_RRII` de
cuántas filas originales se combinaron — el mismo criterio que se usó antes con
`PAR150`, aplicado esta vez al nivel correcto (inmueble, no persona).

### 5. `"."` como marcador de ausencia

Tanto `_2_Renta2023.txt` como `_8_IRPF2023_RRII.txt` usan `"."` para indicar ausencia
en campos numéricos, además de la cadena vacía habitual. Se declaró explícitamente
`na = c("", "NA", ".")` en la lectura de ambos; sin ello, `read_fwf()` seguía
convirtiendo esos valores en `NA` pero lo registraba como fallo de parseo.

### 6. Tipos de columna explícitos

Se fijó `col_types` en cada lectura en lugar de dejar que `readr` los adivinara,
para evitar ambigüedades y que las claves de unión sean del mismo tipo en todos los
ficheros.

### 7. Duplicados en `_1_IDEN` / `_2_Renta`

Antes de unir, se comprueba cuántas claves `(IDENPER, IDENHOG)` están duplicadas en
cada fichero. Ninguno de los dos presenta duplicados; el panel de renta mantiene un
único registro fiscal anual por persona.

### 8. `fwrite`/`fread` y la diferencia entre `NA` y `""`

`fwrite()` escribe los `NA` como campo vacío por defecto, indistinguible de una
cadena vacía real (`""`) al releer con `fread()`. Esto mezclaba, para `URBACLAVE`,
*el inmueble no aparece en `VIVHAB2023.txt`* (debería ser `NA`) con *aparece, pero el
campo viene vacío en origen* (`""` genuina). Se corrigió con `fwrite(..., na = "NA")`
y con tres columnas indicador explícitas — `IN_VIVHAB`, `IN_CARACT`, `IN_RRII` — que
no dependen de convenciones de texto y sobreviven a cualquier exportación futura.

### 9. Registros "vacíos salvo el identificador" en `VIVHAB`

Se comprobó, inspeccionando bytes concretos del fichero original, que algunos
registros de `VIVHAB2023.txt` solo contienen `IDENPER` y el resto en blanco a lo
largo de todo el registro. Es un rasgo real del fichero de origen, no un efecto de
la unión.

## Estructura final de la tabla

Cada fila de `dt` es una combinación (inmueble del arrendador, arrendador), con:

- **Identificación y propiedad**: `RC_ANONIMA`, `IDENPER`, `URBACODERE`,
  `URBAPORBIN`, `URBAVALORC`, `URBAFECHIN`, `URBAFECHFI`, `N_PROPIEDADES` (nº de
  inmuebles distintos que posee ese arrendador).
- **Uso y ocupación** (de `VIVHAB`, puede no existir): `URBACLAVE`, `TIPO_OCUPANTE`,
  `MARCA_VIVHAB`, `IDENPER_OCUPANTE`, `IN_VIVHAB`.
- **Características físicas** (de `INM_CARACT`, puede no existir): `CA`, `PROV`,
  `MUN`, `DIST`, `SECC`, `VIVLOC`, `VIVLOC_METROS`, `VIV`, `VIV_METROS`, `ANCONS`,
  `VALCAT`, `IN_CARACT`.
- **Alquiler declarado de ESE inmueble** (de `RRII`, puede no existir):
  `INGRESOS_INTEGROS`, `RENDIMIENTO_NETO`, `REDUCCION_ALQUILER_VIVIENDA`,
  `REDUCCION_IRREGULAR`, `RENDIMIENTO_MINIMO_PARENTESCO`,
  `RENDIMIENTO_NETO_REDUCIDO`, `N_PERIODOS_RRII`, `IN_RRII`.
- **Contexto de renta del arrendador** (nivel persona, no por inmueble): `IDENHOG`,
  `TRAMO`, `FACTORCAL`, `RB`, `RBD`, `M3_ALQUILER_TOTAL`, `M31_ALQUILER_PFISICAS`,
  `M32_ALQUILER_ENTIDADES`.

## Script 2: diagnóstico de completeness (`revPanel2023_check.R`)

Lee la tabla ya construida (no la modifica) y compara el universo completo de
inmuebles (`dt`) con el subconjunto que genera alquiler realmente declarado por ese
inmueble concreto (`dt_sub <- dt[INGRESOS_INTEGROS > 0]`).

**Resultado actual**: de 10.504.050 inmuebles del panel, **424.439 tienen alquiler
real declarado**. De ellos, **el 71 % no aparece en `VIVHAB` en absoluto** — muy por
encima del ~25–40 % que se observaba con el filtro anterior (`RENTA_ALQ`, que leía
posiciones incorrectas y por tanto no aislaba realmente a los arrendadores). Tiene
sentido: un inmueble alquilado no es, por definición, la vivienda habitual de su
propietario, así que solo aparecerá en `VIVHAB` si el inquilino (u otro ocupante)
también está en el panel y declaró esa misma dirección como propia. **Implicación
práctica**: `URBACLAVE` solo permite clasificar directamente a una minoría (~29 %)
de los inmuebles realmente alquilados; el resto requerirá otra fuente o quedará sin
clasificar por uso.

## Por qué `URBACLAVE` puede no ser `"V"` incluso en registros bien formados

Al inspeccionar `VIVHAB2023.txt` se observó que una misma persona
(`IDENPER_OCUPANTE`) frecuentemente tiene más de un registro: uno con
`URBACLAVE = "V"` (la vivienda) y otro con un código distinto — el más frecuente,
`"A"`, aparece junto a un registro `"V"` en el **98,5 %** de los casos en que se
observa. No es un error de unión: el **Real Decreto 1020/1993** (normas técnicas de
valoración catastral) clasifica explícitamente garajes, trasteros y locales en
estructura como *modalidades dentro del uso residencial* (normas 20, apartados
1.1.3, 1.2.3 y 1.3.2), y prevé expresamente que estos anexos se tipifiquen junto a
la vivienda a la que sirven. Referencia:
<https://www.boe.es/eli/es/rd/1993/06/25/1020/con>.

Los demás códigos observados con mucha menor frecuencia (`Z`, `I`, `G`, `C`, `K`,
`O`, `M`, `Y`, `E`, `B`, `J`, `T`, `P`, `R`...) tienden a aparecer solos, no
emparejados con `"V"`, consistente con que representen usos no residenciales
(industrial, oficinas, comercial, deportivo...) también recogidos en el mismo RD.

**Implicación práctica**: para separar viviendas principales de garajes, trasteros u
otros usos, filtrar estrictamente por `URBACLAVE == "V"` es el criterio correcto —
no basta con comprobar que el inmueble aparece en `VIVHAB`.

## Limitaciones a tener presentes

- **Cobertura de `VIVHAB` sobre inmuebles alquilados es baja (~29 %, ver arriba).**
  No es un fallo de la unión ni de la lectura; es una limitación real de cobertura
  del propio fichero de origen para este caso de uso.
- **`N_PERIODOS_RRII` > 1 implica una suma de importes**, no una lista detallada por
  periodo. Se pierde el desglose de fechas/tenencias distintas dentro del año a
  cambio de mantener una fila por inmueble; si el análisis necesita ese detalle,
  habría que releer `RRII` sin agregar y trabajar a nivel periodo.
- **`M31_ALQUILER_PFISICAS` (contexto a nivel persona) mezcla alquiler de locales y
  viviendas.** No se usa para identificar el subconjunto de alquiler (para eso está
  `INGRESOS_INTEGROS`, ya a nivel inmueble), pero conviene no interpretarlo como
  "solo vivienda" si se usa como agregado de control.
- **Los importes de `RRII` y `_2_Renta` llevan 2 decimales implícitos**, confirmado
  contra el diseño de registro oficial (ya no es una asunción pendiente de
  verificar).
