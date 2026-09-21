MUNDICAM iOS - CONFIGURACION FINAL SOLICITADA

OBJETIVO
1. Mantener el icono/colores originales de MundiCam: fondo blanco + logo rojo.
2. Evitar Liquid Glass usando UIDesignRequiresCompatibility = YES.
3. Mantener soporte de Avisos y Promociones en iPhone, incluidas imagenes remotas
   cuando iOS entrega la notificacion mediante Notification Service Extension.

CAMBIOS MANTENIDOS
- ios/Runner/Info.plist:
  UIDesignRequiresCompatibility = true
  UIBackgroundModes incluye remote-notification
- ios/MundiCamNotificationService/:
  NotificationService.swift
  Info.plist
- ios/Runner.xcodeproj/project.pbxproj:
  target MundiCamNotificationService incluido y embebido en Runner
  bundle id: com.mundicam.app.MundiCamNotificationService
- Runner.entitlements / RunnerDebug.entitlements existentes para APNs.

CAMBIO DE ESTA REVISION
- Se han restaurado EXACTAMENTE los AppIcon originales proporcionados en ios.zip.
- NO se invierten colores.
- Se elimina el PNG auxiliar rojo/blanco invertido de la raiz de ios.

NO TOCADO
- lib Flutter
- Android
- catalogo, marcas, carrito, pedidos, presupuestos, precios o login

COMPILACION
- Usar Xcode 26.x para que UIDesignRequiresCompatibility se respete.
- Firmar Runner y MundiCamNotificationService con el mismo Team.
- La extension usa el bundle id com.mundicam.app.MundiCamNotificationService.

PRUEBAS RECOMENDADAS EN IPHONE REAL
1. Comprobar icono original (blanco + rojo).
2. Abrir la app en iOS 26 y verificar interfaz sin Liquid Glass.
3. Aviso sin imagen, app cerrada.
4. Aviso con imagen, app cerrada.
5. Promocion con imagen, app cerrada.
6. Tocar la promocion y verificar la navegacion esperada.

NOTA
La entrega real de push depende tambien de que APNs/Firebase y el provisioning de Apple
esten correctamente configurados fuera del codigo fuente.

ICONO PLANO / SIN EFECTOS AÑADIDOS POR EL ASSET
- Se mantienen los AppIcon PNG originales, planos, fondo blanco y logo rojo.
- No se incluye ningun archivo .icon de Icon Composer.
- UIDesignRequiresCompatibility = true para mantener el diseño clasico al compilar con Xcode 26.x.
- UIPrerenderedIcon = true para indicar que el icono se entrega prerenderizado y evitar el brillo/gloss historico.
- iOS sigue aplicando su mascara exterior y puede aplicar sombra/sistema visual propio; Apple no ofrece una opcion para desactivar absolutamente todo ese tratamiento del sistema.
