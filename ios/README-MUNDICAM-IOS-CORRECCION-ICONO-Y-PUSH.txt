MundiCam iOS - corrección quirúrgica de icono y notificaciones

CAMBIOS REALIZADOS
1. AppIcon iOS: fondo rojo MundiCam (#D71027 aproximado del arte original) y símbolo blanco.
   - Se han regenerado todas las medidas ya existentes del AppIcon.appiconset.
   - No se han dibujado esquinas, sombras, reflejos ni degradados dentro de los PNG.
   - El icono de marketing de 1024x1024 queda incluido en el mismo asset y es el usado por App Store Connect al compilar.
2. Info.plist: añadido UIDesignRequiresCompatibility=YES para pedir el diseño de compatibilidad sin Liquid Glass cuando se compile con SDK/Xcode 26.
3. Notificaciones iOS con imagen: añadida MundiCamNotificationService (UNNotificationServiceExtension).
   - Descarga image_url / notification_image_url / fcm_options.image y la adjunta a la notificación.
   - Corrige el caso iPhone con app en segundo plano o cerrada; en primer plano Flutter ya adjuntaba la imagen.

NO MODIFICADO
- Código Flutter/lib.
- Android.
- Login, catálogo, carrito, precios, cupones, pedidos o presupuestos.
- Plugin MundiCam Promociones App: su payload ya manda mutable-content + fcm_options.image cuando hay imagen.

IMPORTANTE SOBRE LIQUID GLASS
UIDesignRequiresCompatibility es una compatibilidad temporal de Apple. Con Xcode/SDK 27 Apple indica que se ignora.
Para la subida inmediata con Xcode 26 sirve para solicitar el aspecto de compatibilidad.

PRUEBA EN MAC / IPHONE
1. Reemplazar únicamente la carpeta ios por esta versión (o copiar los cambios equivalentes).
2. Ejecutar: flutter clean
3. Ejecutar: flutter pub get
4. Ejecutar: cd ios && pod install && cd ..
5. Abrir ios/Runner.xcworkspace en Xcode y comprobar Signing & Capabilities.
6. Instalar en iPhone real y aceptar notificaciones.
7. En WordPress > Comunicaciones App > Ajustes y pruebas:
   - Elegir el usuario de prueba.
   - Elegir Solo iOS.
   - Enviar una prueba SIN imagen.
   - Enviar otra CON imagen.
8. Repetir con la app abierta, en segundo plano y cerrada.
9. Confirmar en Últimos 100 intentos que FCM la acepta y en el iPhone que se presenta.

NOTA DE FIRMA
La nueva extensión usa el bundle id com.mundicam.app.MundiCamNotificationService.
Con firma automática Xcode debería gestionarlo con el mismo equipo. Si la cuenta usa perfiles manuales, habrá que crear/asignar el perfil de la extensión una sola vez.
