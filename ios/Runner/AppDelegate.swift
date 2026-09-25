import Flutter
import UIKit

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    DispatchQueue.main.async {
      print("🍎 Solicitando registro APNs nativo...")
      print("🔎 MUNDICAM_APNS_DIAG REGISTER_REQUESTED")
      application.registerForRemoteNotifications()
    }

    return result
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    print("✅ APNs device token recibido (\(deviceToken.count) bytes)")
    print("🔎 MUNDICAM_APNS_DIAG REGISTER_SUCCESS bytes=\(deviceToken.count)")

    #if canImport(FirebaseMessaging)
    Messaging.messaging().apnsToken = deviceToken
    print("✅ APNs token entregado a Firebase Messaging")
    #endif

    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let nsError = error as NSError

    // Diagnóstico seguro para TestFlight/Consola. No expone tokens ni claves.
    print("❌ MUNDICAM_APNS_DIAG REGISTER_FAILED")
    print("❌ MUNDICAM_APNS_DIAG domain=\(nsError.domain)")
    print("❌ MUNDICAM_APNS_DIAG code=\(nsError.code)")
    print("❌ MUNDICAM_APNS_DIAG description=\(nsError.localizedDescription)")
    print("❌ MUNDICAM_APNS_DIAG userInfo=\(nsError.userInfo)")

    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(
      with: engineBridge.pluginRegistry
    )
  }
}
