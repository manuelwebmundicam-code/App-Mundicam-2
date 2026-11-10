# MundiCam · R19 QA: optimización SQL y búsqueda contextual
**Fecha:** 10 de noviembre de 2026 · **Estado:** LABORATORIO VALIDADO, **NO APTO PARA PUBLICAR SIN LAS PRUEBAS COMERCIALES**

## 1. Resumen para dirección
Se han localizado dos focos reales de lentitud: (a) lecturas directas repetidas a `wp_postmeta` durante la ordenación B2B por precio, (b) consultas repetidas a términos durante `/context-search`.

Se ha probado una mejora **acotada y reversible** de cada ruta sobre el WordPress **QA aislado**, sin modificar `www.mundicam.com` ni la app Flutter publicada.

**No sustituimos el precio efectivo comercial por el PVP**: el motor de cálculo B2B sigue ejecutándose sobre el cliente autenticado. Redis y Typesense no reciben precios B2B, tokens ni reglas comerciales.

## 2. Entorno y aislamiento
- WordPress QA local: `http://127.0.0.1:8770`, base de datos `mundicam_qa_r19`, WooCommerce 11.2.2, plugin R19 `1.9.64-r19-facets-only-optin`.
- **108 productos totalmente ficticios**, 36 por categoría **19, 20, 21**, con 3 opciones del atributo real `pa_resolucion`.
- Dos roles QA `cliente_35_60` y `cliente_52_69`. Cuentas automáticas nuevas `qa_bench_35`/`qa_bench_52` para HTTP; las cuentas interactivas de Android QA no se modificaron.
- Los archivos de credenciales y las copias SQL de QA quedan **solo en `secure/` dentro del VPS, permiso 0600**. No forman parte de esta entrega.
- Acceso Android solo por túnel SSH y `adb reverse`; servicios QA enlazados únicamente a localhost.

## 3. Modificaciones PHP SOLO QA
1. **Bug real del R19 original:** `resolve_role_filtered_price_data()` necesitaba capturar `$user_for_price` en el closure. Corrección de una sola línea, sin cambiar la fórmula de precio. Se eliminaron los avisos PHP; precios y orden pasaron las pruebas con ambos roles ficticios.
2. **Ordenación `/products?orderby=price_asc` y `price_desc`:** precarga *solo durante la petición* los metadatos base RAW `_price`, `_sale_price` y `_regular_price` de los IDs candidatos, en lotes de 80. Lee la última fila `meta_id`, igual que la consulta individual anterior. **No guarda precios comerciales entre peticiones ni usuarios**, no modifica Flycart, no usa `$order->calculate_totals()`. Control estricto `MUNDICAM_QA_BULK_RAW_META` + DB y URL QA.
3. **`/context-search`:** en el intervalo de **51–150 candidatos**, evalúa la precarga nativa de términos para evitar consultas repetidas; no altera la selección ni el ranking. Control estricto `MUNDICAM_QA_CONTEXT_TERMS` + DB y URL QA. Para más de 150 candidatos no hay cambio.
4. Otras rutas de API, carrito, presupuestos, pedido, Redsys, YITH, notificaciones y producción **no se tocaron**.
5. Experimento previo de reutilizar `WC_Customer` y precarga adicional de taxonomías en `price_asc` **descartados** al no mejorar consistentemente los tiempos.

**Importante:** las dos optimizaciones son pruebas con flags en `wp-config.php` **solo QA**. Su código actual tiene referencias explícitas a `mundicam_qa_r19` y `127.0.0.1:8770`, por lo que este parche **no es un plugin listo para producción**.

### Integridad de versiones PHP
- R19 original: `079b7afb63f2b65f077a7ca4b6343c3d4b20ed3527df3c94afc79ce5c09de979`
- R19 con corrección de closure: `a17e6169c51a361d2afe1f4b6a29499d455358a373851436414f7259e2671714`
- QA final **closure + lectura RAW en lotes + precarga contextual**: `38092b761feb80d23f70cc3d68df438029c5f51b527666733cf5c236148aee54`

La cadena de versión REST sigue siendo `1.9.64-r19-facets-only-optin`; el estado de preparación QA distingue la variante **por SHA-256**.

## 4. Resultados verificados

### Ordenación B2B `price_asc` / `price_desc`
| Indicador | Sin precarga RAW | Con precarga RAW |
| --- | ---: | ---: |
| SQL para ordenar 36 productos | 251 | 114 |
| SQL para ordenar 108 productos | 565 | 213 |
| Mediana de 16 ejecuciones con el mismo PHP (flag OFF/ON) | 913 ms | 505 ms |
| Mediana de los casos con 108 productos | 1.463 ms | 582 ms |
| Identidad de artículos, orden, precios, stock, etc. | — | **16/16 idénticos** |

El conjunto de pruebas tiene dos roles, tres categorías más búsqueda global, y orden ascendente y descendente. Estos tiempos son internos de PHP en el VPS con **productos inventados**, no carga visual de Android ni resultado extrapolable a miles de referencias.

### Búsqueda `/context-search`
| Indicador | Sin precarga términos | Con precarga términos |
| --- | ---: | ---: |
| Consultas SQL para búsqueda general de 108 productos | 423 | 312 |
| De ellas, consultas a términos | 369 | 258 |
| Primera medición directa de esa consulta | 1.627 ms | 1.318 ms |
| Mediana de 16 consultas de contexto (cachés calentadas) | 180 ms | 163 ms |
| Identidad de resultados, precios y contexto | — | **16/16 idénticos** |

Son dos ejecuciones controladas, pero no un estudio estadístico ni una prueba con 2.800+ referencias.

### Seguridad y regresión
Se ejecutó `tests/qa_run_smoke_all.sh`:
- `QA_READINESS_PASS variant=r19_qa_raw_meta_and_context`
- `QA_PHP_LINT_PASS`
- `QA_FACETS_ALL_PASS categories=3`
- `QA_PRICE_ROLE_CROSSCHECK_PASS`: el grupo 52 recibe precio inferior al 35 en diez mismos productos ficticios.
- `QA_PRICE_CLOSURE_WARNINGS_ZERO`
- `QA_REST_AUTH_FACETS_PASS records=6`: HTTP autenticado de ambos roles.
- `QA_CONTEXT_SEARCH_PASS records=16`
- `QA_UNAUTH_DENY_PASS`: cuatro rutas protegidas devuelven 401 sin token.
- `QA_SMOKE_ALL_PASS`.

No se crearon pedidos ni se probaron pagos reales.

## 5. Recuperación QA probada
Todas las copias PHP y de la BD ficticia están en:
`/home/mundicam-agent/mundicam-lab/wordpress-r19-staging-20261109/secure/qa-recovery-20261109/`

El script `tests/qa_restore_php.sh` acepta solo `original`, `closure`, `bulk_context`, y valida ruta, BD, URL localhost y SHA antes de modificar nada.

Se ha ejecutado **QA original → QA experimental**, comprobando sintaxis y respuesta REST. El PHP QA experimental ha quedado activo. Este procedimiento **NO sirve para instalar en producción**.

## 6. Qué falta realmente para subir nada a producción
1. Montar staging representativo **autorizado y sanitizado**, con los mismos mecanismos de tarifas y descuentos de Flycart; inventarios y reglas de visibilidad; YITH y Redsys en modo sandbox sin emails ni pagos reales.
2. Contrastar **dos tarifas reales de prueba** y promociones encadenadas con salida WooCommerce web, Flutter API y presupuestos (céntimo a céntimo).
3. Repetir `price_asc` y `/context-search` con una carga equivalente al catálogo real (miles de referencias y variaciones) y verificar CPU/RAM, tiempos fríos/calientes y concurrencia. En el laboratorio actual solo hay 108 productos ficticios.
4. Regresión con la app publicada en un entorno de pruebas, pedidos, YITH, Redsys, stock, emails, FCM y reglas de negocio.
5. Plan firmado de publicación: copia PHP/BD, despliegue acotado, flags inicialmente OFF, monitorización y rollback inmediato. **Sin aprobación empresarial, no tocar `www.mundicam.com`.**

## 7. Qué debe hacer Tony ahora
Para medir en Android Studio, puede utilizar **la misma `lib/main_qa.dart`**, sin volver a copiar ningún archivo Dart:
- Mantener el túnel SSH privado al puerto 8770 y ejecutar `adb reverse tcp:8770 tcp:8770` desde las platform-tools del SDK.
- App QA → **Comprobar R19** → cuenta QA ficticia con contraseña que él conoce → categoría **19, 20 o 21** → **Medir filtros y productos en QA**.
- Hacer tres repeticiones por categoría, frío/caliente, sin contraseñas ni tokens en capturas.
- Los tiempos visuales pueden ser mayores que los tiempos PHP (red, emulador, renderizado).

**Producción sigue intacta**: `www.mundicam.com` mantiene `1.9.62-r17-warranties-nativo-seguro`; rama principal GitHub de Flutter intacta.
