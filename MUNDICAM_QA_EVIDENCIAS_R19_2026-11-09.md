# MundiCam · Estado de aceleración y QA R19
**Fecha:** 9 de noviembre de 2026  
**Entorno:** WordPress/WooCommerce privado del VPS · **NO PRODUCCIÓN**

## Resultado
La integración Android Studio → VPS QA → PHP R19 está montada y la API REST devuelve respuestas válidas. Se ha ejecutado una batería automatizada completa sin tocar pedidos, presupuestos ni pagos.

### Completado y medido
- WordPress **7.1.4**, WooCommerce **11.2.2**, PHP CLI **8.3.6**, plugin R19 `1.9.64-r19-facets-only-optin` en VPS QA.
- 108 productos **ficticios**, 3 categorías QA con IDs **19, 20, 21**, 36 productos por categoría.
- Filtro real `pa_resolucion` con 3 opciones. Categorías y precios inventados, sin datos de clientes reales.
- Dos usuarios ficticios, roles **cliente_35_60** y **cliente_52_69**. Credenciales guardadas **solo en el VPS** con permisos 0600; no están en este documento.
- Tres comparaciones directas PHP: filtros completos frente a `facets_only=1` preservan ID, nombres/opciones y recuentos; el modo rápido elimina agregados `price_range` y `stock_filter`.
- Seis consultas autenticadas completas por HTTP para ambos roles y las tres categorías: **6/6 comparaciones de facetas correctas**.
- Control sin autenticación: `/me`, `/products`, `/catalog-filters`, `/context-search` respondieron **HTTP 401**.
- Pruebas Flutter completas anteriores: **78/78**. Pruebas adicionales de Flutter con `MUNDICAM_FAST_FACETS_ONLY=true`: **14/14** (y análisis estático limpio).
- El script de regresión del VPS `tests/qa_run_smoke_all.sh` pasó todas sus comprobaciones.

### Tiempos reales de QA

| Prueba | Tiempos |
| --- | --- |
| Filtros completos HTTP, 36 productos | 0,75–1,59 s |
| Filtros R19 `facets_only=1` HTTP, 36 productos | 0,28–0,41 s |
| `/products` con `price_asc` HTTP, 36 productos | 0,94–2,27 s |
| `/context-search` HTTP, 108 productos | 1,86–1,95 s |
| Solo lógica PHP de filtros completos, 36 productos | 430–549 ms |
| Solo lógica PHP de facetas R19, 36 productos | 1,6–6,4 ms |

No sumar tiempos de peticiones paralelas ni extrapolar estos valores al catálogo productivo de miles de referencias.

### Perfilado real de `price_asc`
Con los dos roles y datos ficticios, en llamadas PHP se midió:

| Candidatos | Número de consultas SQL |
| --- | --- |
| 36 productos | 184–251 |
| 108 productos | 472–565 |

La función recorre y evalúa precios efectivos de todos los candidatos antes de devolver los diez primeros. El coste crece con la categoría. No sustituir por PVP ni ordenar en SQL por `_price`, porque puede alterar descuentos comerciales.

## Bug real R19 y corrección QA
En `resolve_role_filtered_price_data()`, el closure usaba `$user_for_price` sin capturarlo. Se observó **92 avisos PHP** para dos usuarios en una prueba pequeña.

Corrección *quirúrgica*, una sola línea (ver archivo `R19_QA_CIERRE_USE_USER_FOR_PRICE.diff`):

```diff
- function() use ($product, $price_context, $effective_role) {
+ function() use ($product, $price_context, $effective_role, $user_for_price) {
```

**Validaciones tras la corrección en WordPress QA:**
- **0 avisos** de variable indefinida.
- **6/6 huellas de precios y orden idénticas** frente al R19 original, ambos roles ficticios, las tres categorías.
- Precio del grupo 52 inferior al 35 para los diez mismos productos ficticios.
- Orden ascendente y grupos efectivos correctos.
- Mediana `price_asc`: 1.097 ms antes, 1.046 ms después. **No es evidencia concluyente de aceleración.**
- El experimento adicional de reutilizar `WC_Customer` no mejoró el tiempo de forma consistente y **fue descartado/restaurado**.

**Estado del QA:** plugin con la *única* corrección del closure, reconocido como variante `r19_qa_closure_fix` por `tests/qa_readiness.py`. La cadena de versión R19 no cambia, pero su SHA-256 sí. El PHP R19 original permanece recuperable en carpeta privada.

**Importante:** antes de integrar la corrección en un PHP de producción hay que verificar Flycart y descuentos encadenados de clientes reales en staging equivalente. Las pruebas aquí confirman un defecto de ámbito de variable y paridad con el catálogo ficticio, no con Flycart real.

## Seguridad, respaldo y recuperación
- QA solo en `127.0.0.1:8770`, accedido desde PC mediante SSH privado y `adb reverse`. No se ha añadido DNS público.
- BD propia por socket Unix sin TCP. Cron, actualizaciones automáticas y llamadas WP HTTP externas desactivadas; correo bloqueado en QA.
- Copia SQL comprimida solo de QA ficticio y ambas versiones PHP en `wordpress-r19-staging-20261109/secure/qa-recovery-20261109/` con permisos **0600**. **No subir esa carpeta a GitHub.**
- WordPress real `www.mundicam.com` sigue en **R17 `1.9.62-r17-warranties-nativo-seguro`**.
- No se han modificado los pagos Redsys, los presupuestos YITH, Factusol ni la app publicada.

## Cómo continuar en Android Studio
Tony puede mantener su `lib/main_qa.dart` ya instalada.

1. Mantener abierto el túnel SSH autorizado hacia `127.0.0.1:8770` del VPS.
2. Ejecutar en PowerShell: `& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8770 tcp:8770`.
3. Emulador Android con MundiCam QA abierta: pulsar **Comprobar R19**; debe indicar `1.9.64-r19-facets-only-optin`.
4. Usar una **cuenta ficticia de QA**, no credenciales de MundiCam real. En WordPress QA → Usuarios se pueden asignar contraseñas nuevas de prueba a las cuentas con roles cliente 35 y 52 (sin comunicarlas por chat).
5. En la pantalla QA, introducir **19, 20 o 21**, no 144/44/85: son los IDs del catálogo ficticio.
6. Pulsar **Medir filtros y productos en QA** y recoger solo tiempos y booleanos de igualdad, nunca tokens ni contraseñas.

## Próximos bloqueos antes de producción
1. Clonar en un **staging protegido y sanitizado** las reglas comerciales auténticas de Flycart, YITH y Redsys en modo sandbox. No volcar credenciales ni enviar emails.
2. Repetir comparativas R17/R19 y la corrección PHP con **dos roles y los mismos datos**, incluidos descuentos encadenados y stock.
3. Diseñar una reducción real del coste O(N) de `price_asc` con invalidez de caché documentada o índice seguro por contexto comercial; no cachear PVP como si fuera B2B.
4. Medir `/context-search` y activar progresivamente rutas públicas Typesense/Redis con hidratación comercial autenticada.
5. Validar regresiones contra versión de app publicada, pedidos, YITH, Redsys y notificaciones.
6. Preparar backup y rollback verificables antes de decidir una única publicación PHP final.

**Conclusión:** QA operativo, corrección real aislada y protección de producción verificadas. La aceleración final de los listados B2B de miles de productos **todavía no está resuelta**.
