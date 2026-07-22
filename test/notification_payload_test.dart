import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/notifications/notification_service.dart';

void main() {
  group('MundiCamOrderNotification payload', () {
    test('recupera pedido y navegación desde notificación local', () {
      const original = MundiCamOrderNotification(
        event: 'order_status_changed',
        orderId: 215017,
        orderNumber: '215017',
        status: 'completed',
        title: 'Pedido completado',
        body: 'Tu pedido #215017 ha sido completado.',
        showPopup: false,
        openedByUser: false,
        messageId: 'fcm-test-215017-completed',
        data: <String, dynamic>{
          'type': 'order',
          'event': 'order_status_changed',
          'order_id': '215017',
          'status': 'completed',
        },
      );

      final restored = MundiCamOrderNotification.fromPayload(
        original.toPayload(),
        openedByUser: true,
      );

      expect(restored, isNotNull);
      expect(restored!.orderId, 215017);
      expect(restored.orderNumber, '215017');
      expect(restored.status, 'completed');
      expect(restored.isOrderNotification, isTrue);
      expect(restored.openedByUser, isTrue);
      expect(restored.showPopup, isFalse);
    });

    test('rechaza payload local vacío', () {
      final restored = MundiCamOrderNotification.fromPayload(
        '',
        openedByUser: true,
      );

      expect(restored, isNull);
    });
  });
}
