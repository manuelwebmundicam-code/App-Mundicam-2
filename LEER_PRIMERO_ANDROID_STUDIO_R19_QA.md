# MundiCam — Android Studio QA contra WordPress R19 del VPS
Fecha: 09/11/2026. SOLO PRUEBAS. No instalar nada en WordPress de producción.

## Qué recibe Tony
- `lib/` COMPLETA, incluido `lib/main_qa.dart` y `lib/qa/mundicam_qa_client.dart`.
- `android/app/build.gradle.kts` con sufijo `.qa` condicionado por MUNDICAM_ANDROID_QA=1 en DEBUG solamente.
- `android/app/src/debug/AndroidManifest.xml` y `android/app/src/debug/res/xml/mundicam_qa_debug_network_security.xml` para permitir HTTP únicamente al loopback local.
- `test/` con pruebas de QA y contrato real R19.
- Script PowerShell `INICIAR_MUNDICAM_QA_ANDROID_STUDIO.ps1`.

Se debe hacer COPIA de seguridad de lib/, android/app/build.gradle.kts, android/app/src/debug/AndroidManifest.xml y test/ antes de sustituir. El ZIP no modifica pubspec, assets, iOS ni la app publicada. Descomprimir EN LA RAÍZ del proyecto Flutter.

## Por qué usamos otra entrada
`flutter run --debug -t lib/main_qa.dart` abre un panel específico que NO usa la sesión del cliente, no inicializa Firebase, no escribe pedidos ni presupuestos y no contacta con mundicam.com. El único destino del cliente QA es `http://127.0.0.1:8770` (via ADB reverse).

**Importante: el backend QA no ha terminado su instalación**. El servidor VPS tiene ficheros WordPress/WooCommerce y BD aislada, pero la creación del administrador WordPress QA fue bloqueada y R19 no está todavía subido. Mientras esos pasos no estén completados, la pantalla mostrará error de conexión o R19 no activo: ES ESPERADO.

## Preparación técnica del WordPress QA en VPS (Tony/técnico autorizado)
1. Con credenciales SSH autorizadas, conectar al VPS como usuario `mundicam-agent`. No compartir contraseñas ni llaves por chat.
2. Arrancar SOLO los servicios aislados:
   `systemctl --user start mundicam-wpqa-db-local.service mundicam-wordpress-r19-qa-local.service`
3. Desde OTRA consola Windows, abrir el túnel:
   `ssh -N -L 8770:127.0.0.1:8770 mundicam-agent@<HOST_DEL_VPS>`
4. En Chrome del PC abrir `http://127.0.0.1:8770/wp-admin/install.php`, crear WordPress con un administrador QA inventado. NUNCA usar email/contraseña de un cliente ni credenciales de producción.
5. Activar WooCommerce 11.2.2 en Plugins. El archivo ya está extraído en el VPS.
6. Subir **únicamente** el fichero PHP de `MundiCam_R19_SOLO_WORDPRESS_QA_INSTALACION.zip` a:
   `/home/mundicam-agent/mundicam-lab/wordpress-r19-staging-20261109/web/wp-content/plugins/mundicam-app-api/mundicam-app-api.php`
   Comprobar SHA256 `079b7afb63f2b65f077a7ca4b6343c3d4b20ed3527df3c94afc79ce5c09de979`.
7. Ejecutar en el VPS el verificador `python3 /home/mundicam-agent/mundicam-lab/wordpress-r19-staging-20261109/tests/qa_readiness.py`. Después activar con `bash /home/mundicam-agent/mundicam-lab/wordpress-r19-staging-20261109/tests/activate_r19_qa_only.sh`.
8. Confirmar desde el PC el `status`:
   `curl.exe -s http://127.0.0.1:8770/wp-json/mundicam-app/v1/status`
   Debe mostrar `1.9.64-r19-facets-only-optin`.
9. Crear en QA categorías y productos ficticios, y usuarios comerciales ficticios; sin pedidos reales ni emails. El filtro R19 no puede certificar Flycart/YITH si esos plugins no están instalados con su configuración comercial de pruebas.

## Android Studio — Windows PowerShell
1. Abrir un emulador Android; mantener abierto el túnel SSH de arriba.
2. Desde la raíz del proyecto, ejecutar:
   `./INICIAR_MUNDICAM_QA_ANDROID_STUDIO.ps1`
   O manualmente:
   ```powershell
   $env:MUNDICAM_ANDROID_QA = '1'
   adb reverse tcp:8770 tcp:8770
   flutter run --debug -t lib/main_qa.dart
   ```
3. La aplicación QA tiene ID `com.mundicam.securitydistribution.qa`, por lo que NO sobrescribe la app principal. Si la compilación no tiene ese ID, el arranque se bloquea.
4. Pulsar `Comprobar R19`, iniciar sesión con el usuario QA y medir los filtros de una categoría que tenga productos de prueba. Si sus IDs no son 144,44,85 o 49, introducir el ID real de esa categoría QA.
5. Copiar SOLO resultados agregados: duración de filtros normal/rápido, duración de productos price_asc, número de productos y booleanos de paridad. **No copiar tokens, contraseñas ni datos de clientes.**

## Límites y seguridad
- Todo QA es LOCAL (127.0.0.1:8770). No abrir al público ni publicar nuevas URLs sin control de acceso.
- El PHP comercial realmente instalado en producción es R17; NO se ha modificado.
- Una prueba con productos inventados NO valida las tarifas reales Flycart, YITH ni Redsys; hace falta una copia autorizada y configurada del entorno comercial.
- No se dispone de SDK de Android en este VPS, por lo que no se ha compilado todavía un APK real. Los tests Dart/Flutter sí se han ejecutado.
- El objetivo inicial es comprobar conexión real, contrato R19 y comparar rendimientos; no confundir esta utilidad de QA con la app comercial completa.
- Rollback Flutter: restaurar los archivos respaldados y ejecutar Flutter sin `main_qa.dart`.
- Rollback VPS: `systemctl --user stop mundicam-wordpress-r19-qa-local.service mundicam-wpqa-db-local.service`.

## Crear catálogo ficticio de prueba (una vez Woo y R19 estén activos)
Ya está preparado en el VPS el script:
`/home/mundicam-agent/mundicam-lab/wordpress-r19-staging-20261109/tests/qa_seed_catalog.php`
Se ejecuta exclusivamente contra la BD aislada y **se niega a actuar si el sitio no es localhost o la BD no es mundicam_qa_r19**:
```bash
php /home/mundicam-agent/mundicam-lab/wordpress-r19-staging-20261109/downloads/wp-cli.phar eval-file /home/mundicam-agent/mundicam-lab/wordpress-r19-staging-20261109/tests/qa_seed_catalog.php --path=/home/mundicam-agent/mundicam-lab/wordpress-r19-staging-20261109/web
```
Produce 3 categorías, 108 productos **inventados**, y atributos de resolución; no crea usuarios ni pedidos ni copia datos reales. Imprime los IDs de categoría que deben introducirse en Android QA. Ejecutarlo una vez, o repetir sin duplicar SKUs. Estos 108 productos no representan carga de 2.867 referencias, por lo que los tiempos serán preliminares. Las tarifas por rol requieren Flycart y reglas de prueba reales.
