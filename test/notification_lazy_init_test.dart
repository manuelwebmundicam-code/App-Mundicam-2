import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Home y MainScreen pueden suscribirse antes de Firebase.initializeApp',
    () {
      // Regresión del error [core/no-app] en el primer frame.
      // No se inicializa Firebase para demostrar que el singleton no
      // solicita FirebaseMessaging.instance al construirse.
      final notificationService = NotificationService();
      expect(notificationService.orderNotifications.isBroadcast, isTrue);
      expect(notificationService.takePendingOrderNotifications(), isEmpty);

      final subscription = notificationService.orderNotifications.listen(
        (_) {},
      );
      addTearDown(subscription.cancel);
    },
  );
}
