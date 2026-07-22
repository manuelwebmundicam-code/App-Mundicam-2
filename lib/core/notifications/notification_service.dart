import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:mundicam/core/network/api_service.dart';

class MundiCamOrderNotification {
  final String event;
  final int? orderId;
  final String? orderNumber;
  final String? status;
  final String title;
  final String body;
  final bool showPopup;
  final bool openedByUser;
  final String? messageId;
  final Map<String, dynamic> data;

  const MundiCamOrderNotification({
    required this.event,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.title,
    required this.body,
    required this.showPopup,
    this.openedByUser = false,
    this.messageId,
    required this.data,
  });

  bool get isOrderCreated => event == 'order_created';

  bool get isStatusChanged => event == 'order_status_changed';

  bool get isGeneralNotification {
    final String type = data['type']?.toString().trim().toLowerCase() ?? '';
    final String cleanEvent = event.trim().toLowerCase();

    return cleanEvent == 'general' ||
        type == 'general' ||
        type == 'info' ||
        type == 'aviso' ||
        type == 'notice' ||
        type == 'notification' ||
        type == 'notificacion';
  }

  bool get isOrderNotification => !isGeneralNotification;

  MundiCamOrderNotification copyWith({
    String? event,
    int? orderId,
    String? orderNumber,
    String? status,
    String? title,
    String? body,
    bool? showPopup,
    bool? openedByUser,
    String? messageId,
    Map<String, dynamic>? data,
  }) {
    return MundiCamOrderNotification(
      event: event ?? this.event,
      orderId: orderId ?? this.orderId,
      orderNumber: orderNumber ?? this.orderNumber,
      status: status ?? this.status,
      title: title ?? this.title,
      body: body ?? this.body,
      showPopup: showPopup ?? this.showPopup,
      openedByUser: openedByUser ?? this.openedByUser,
      messageId: messageId ?? this.messageId,
      data: data ?? this.data,
    );
  }

  String toPayload() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'event': event,
      'order_id': orderId,
      'order_number': orderNumber,
      'status': status,
      'title': title,
      'body': body,
      'show_popup': showPopup,
      'opened_by_user': openedByUser,
      'message_id': messageId,
      'data': data,
    };

    return jsonEncode(payload);
  }

  static MundiCamOrderNotification? fromPayload(
      String? payload, {
        required bool openedByUser,
      }) {
    final String cleanPayload = payload?.trim() ?? '';

    if (cleanPayload.isEmpty) {
      return null;
    }

    try {
      final Object? decoded = jsonDecode(cleanPayload);

      if (decoded is! Map) {
        return null;
      }

      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);

      final Object? embeddedData = map['data'];
      final Map<String, dynamic> data = embeddedData is Map
          ? Map<String, dynamic>.from(embeddedData)
          : <String, dynamic>{};

      final String event = _firstNonEmptyString(<dynamic>[
        map['event'],
        data['event'],
        'general',
      ])!
          .toLowerCase();

      final int? orderId = _parseInt(
        map['order_id'] ??
            map['orderId'] ??
            data['order_id'] ??
            data['orderId'] ??
            data['id'],
      );

      final String? orderNumber = _firstNonEmptyString(<dynamic>[
        map['order_number'],
        map['orderNumber'],
        data['order_number'],
        data['orderNumber'],
        data['number'],
        orderId,
      ]);

      final String? status = _firstNonEmptyString(<dynamic>[
        map['status'],
        data['status'],
        data['new_status'],
        data['order_status'],
      ]);

      final String title = _firstNonEmptyString(<dynamic>[
        map['title'],
        data['title'],
        orderId == null ? 'Aviso MundiCam' : 'Pedido actualizado',
      ]) ??
          'Aviso MundiCam';

      final String body = _firstNonEmptyString(<dynamic>[
        map['body'],
        data['body'],
        orderId == null
            ? 'Tienes una nueva notificación.'
            : 'Tu pedido #${orderNumber ?? orderId} ha sido actualizado.',
      ]) ??
          'Tienes una nueva notificación.';

      final bool showPopup = _parseBool(
        map['show_popup'] ?? map['showPopup'] ?? data['show_popup'],
      );

      final String? messageId = _firstNonEmptyString(<dynamic>[
        map['message_id'],
        map['messageId'],
        data['message_id'],
        data['messageId'],
        data['notification_id'],
      ]);

      return MundiCamOrderNotification(
        event: event,
        orderId: orderId,
        orderNumber: orderNumber,
        status: status,
        title: title,
        body: body,
        showPopup: showPopup,
        openedByUser: openedByUser,
        messageId: messageId,
        data: data,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Payload local inválido: $e');
      }

      return null;
    }
  }

  static MundiCamOrderNotification? fromRemoteMessage(
      RemoteMessage message, {
        required bool showPopup,
        bool openedByUser = false,
      }) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);

    final String type = data['type']?.toString().trim().toLowerCase() ?? '';
    final String event = data['event']?.toString().trim().toLowerCase() ?? '';

    final bool isOrderNotification = type == 'order' ||
        type == 'pedido' ||
        event == 'order_created' ||
        event == 'order_status_changed';

    if (isOrderNotification) {
      return _fromOrderMessage(
        message,
        data: data,
        event: event,
        showPopup: showPopup,
        openedByUser: openedByUser,
      );
    }

    final bool isGeneralNotification = type == 'general' ||
        type == 'info' ||
        type == 'aviso' ||
        type == 'notice' ||
        type == 'notification' ||
        type == 'notificacion';

    if (isGeneralNotification) {
      return _fromGeneralMessage(
        message,
        data: data,
        event: event,
        showPopup: showPopup,
        openedByUser: openedByUser,
      );
    }

    return null;
  }

  static MundiCamOrderNotification _fromOrderMessage(
      RemoteMessage message, {
        required Map<String, dynamic> data,
        required String event,
        required bool showPopup,
        required bool openedByUser,
      }) {
    final int? parsedOrderId = _parseInt(
      data['order_id'] ??
          data['orderId'] ??
          data['id'] ??
          message.notification?.android?.tag,
    );

    final String cleanEvent = event.isNotEmpty
        ? event
        : parsedOrderId != null
        ? 'order_status_changed'
        : 'order';

    final String? status = _firstNonEmptyString(<dynamic>[
      data['status'],
      data['new_status'],
      data['order_status'],
    ]);

    final String? orderNumber = _firstNonEmptyString(<dynamic>[
      data['order_number'],
      data['orderNumber'],
      data['number'],
      parsedOrderId,
    ]);

    final String defaultTitle =
    cleanEvent == 'order_created' ? 'Pedido recibido' : 'Pedido actualizado';

    final String title = _firstNonEmptyString(<dynamic>[
      data['title'],
      message.notification?.title,
      defaultTitle,
    ]) ??
        defaultTitle;

    final String defaultBody = orderNumber == null
        ? 'Hay una novedad en tus pedidos.'
        : cleanEvent == 'order_created'
        ? 'Tu pedido #$orderNumber se ha registrado correctamente.'
        : status == null
        ? 'Tu pedido #$orderNumber ha cambiado de estado.'
        : 'Tu pedido #$orderNumber ha cambiado a $status.';

    final String body = _firstNonEmptyString(<dynamic>[
      data['body'],
      message.notification?.body,
      defaultBody,
    ]) ??
        defaultBody;

    final String? messageId = _firstNonEmptyString(<dynamic>[
      message.messageId,
      data['message_id'],
      data['messageId'],
      data['notification_id'],
    ]);

    return MundiCamOrderNotification(
      event: cleanEvent,
      orderId: parsedOrderId,
      orderNumber: orderNumber,
      status: status,
      title: title,
      body: body,
      showPopup: showPopup,
      openedByUser: openedByUser,
      messageId: messageId,
      data: data,
    );
  }

  static MundiCamOrderNotification _fromGeneralMessage(
      RemoteMessage message, {
        required Map<String, dynamic> data,
        required String event,
        required bool showPopup,
        required bool openedByUser,
      }) {
    final String cleanEvent = event.isNotEmpty ? event : 'general';

    final String title = _firstNonEmptyString(<dynamic>[
      data['title'],
      message.notification?.title,
      'Aviso MundiCam',
    ]) ??
        'Aviso MundiCam';

    final String body = _firstNonEmptyString(<dynamic>[
      data['body'],
      message.notification?.body,
      'Tienes una nueva notificación.',
    ]) ??
        'Tienes una nueva notificación.';

    final String? messageId = _firstNonEmptyString(<dynamic>[
      message.messageId,
      data['message_id'],
      data['messageId'],
      data['notification_id'],
    ]);

    return MundiCamOrderNotification(
      event: cleanEvent,
      orderId: null,
      orderNumber: null,
      status: null,
      title: title,
      body: body,
      showPopup: showPopup,
      openedByUser: openedByUser,
      messageId: messageId,
      data: data,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    final String raw = value.toString().trim();

    if (raw.isEmpty) {
      return null;
    }

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt();
  }

  static bool _parseBool(dynamic value) {
    if (value == null) {
      return false;
    }

    if (value is bool) {
      return value;
    }

    final String text = value.toString().trim().toLowerCase();

    return text == 'true' || text == '1' || text == 'yes' || text == 'si';
  }

  static String? _firstNonEmptyString(List<dynamic> values) {
    for (final dynamic value in values) {
      final String text = value?.toString().trim() ?? '';

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return null;
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();

  factory NotificationService() => _instance;

  NotificationService._();

  static const int _maxPendingNotifications = 20;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final StreamController<MundiCamOrderNotification> _orderController =
  StreamController<MundiCamOrderNotification>.broadcast();

  final Queue<MundiCamOrderNotification> _pendingNotifications =
  Queue<MundiCamOrderNotification>();

  bool _initialized = false;

  Stream<MundiCamOrderNotification> get orderNotifications =>
      _orderController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      await syncCurrentTokenWithBackend();
      return;
    }

    _initialized = true;

    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (kDebugMode) {
      debugPrint('🔔 Permiso notificaciones: ${settings.authorizationStatus}');
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await syncCurrentTokenWithBackend();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleRemoteMessage(
        message,
        showPopup: true,
        openedByUser: false,
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleRemoteMessage(
        message,
        showPopup: false,
        openedByUser: true,
      );
    });

    final RemoteMessage? initialMessage = await _messaging.getInitialMessage();

    if (initialMessage != null) {
      _handleRemoteMessage(
        initialMessage,
        showPopup: false,
        openedByUser: true,
      );
    }

    _messaging.onTokenRefresh.listen((String token) async {
      await _saveToken(token);
    });
  }

  Future<void> syncCurrentTokenWithBackend() async {
    try {
      if (Platform.isIOS) {
        final bool apnsReady = await _waitForApnsToken();

        if (!apnsReady) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ APNs token no disponible todavía. FCM se reintentará al refrescar token.',
            );
          }

          return;
        }
      }

      final String? token = await _messaging.getToken();

      if (kDebugMode) {
        debugPrint('📱 FCM Token: $token');
      }

      await _saveToken(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo obtener/guardar token FCM: $e');
      }
    }
  }

  Future<bool> _waitForApnsToken() async {
    String? apnsToken = await _messaging.getAPNSToken();

    for (int attempt = 0; apnsToken == null && attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      apnsToken = await _messaging.getAPNSToken();
    }

    if (apnsToken != null && kDebugMode) {
      debugPrint('🍎 APNs Token: $apnsToken');
    }

    return apnsToken != null;
  }

  MundiCamOrderNotification? takePendingOrderNotification() {
    if (_pendingNotifications.isEmpty) {
      return null;
    }

    return _pendingNotifications.removeFirst();
  }

  List<MundiCamOrderNotification> takePendingOrderNotifications() {
    final List<MundiCamOrderNotification> pending =
    List<MundiCamOrderNotification>.unmodifiable(_pendingNotifications);

    _pendingNotifications.clear();

    return pending;
  }

  void _handleRemoteMessage(
      RemoteMessage message, {
        required bool showPopup,
        required bool openedByUser,
      }) {
    final MundiCamOrderNotification? notification =
    MundiCamOrderNotification.fromRemoteMessage(
      message,
      showPopup: showPopup,
      openedByUser: openedByUser,
    );

    if (notification == null) {
      if (kDebugMode) {
        debugPrint('ℹ️ Notificación ignorada: ${message.data}');
      }

      return;
    }

    _emitNotification(notification);
  }

  void _emitNotification(MundiCamOrderNotification notification) {
    if (kDebugMode) {
      debugPrint(
        notification.isGeneralNotification
            ? '📩 Notificación general: ${notification.title}'
            : '📩 Notificación pedido: ${notification.title}',
      );
      debugPrint('   Body: ${notification.body}');
      debugPrint('   Opened by user: ${notification.openedByUser}');
      debugPrint('   Data: ${notification.data}');
    }

    if (_orderController.hasListener) {
      _orderController.add(notification);
      return;
    }

    if (_pendingNotifications.length >= _maxPendingNotifications) {
      _pendingNotifications.removeFirst();
    }

    _pendingNotifications.addLast(notification);
  }

  Future<void> _saveToken(String? token) async {
    final String cleanToken = token?.trim() ?? '';

    if (cleanToken.isEmpty) {
      return;
    }

    await _saveTokenInFirestore(cleanToken);
    await _saveTokenInMundiCamBackend(cleanToken);
  }

  Future<void> _saveTokenInFirestore(String token) async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        <String, dynamic>{
          'fcm_token': token,
          'fcm_platform': _platform,
          'fcm_updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (kDebugMode) {
        debugPrint('✅ Token FCM guardado en Firestore');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo guardar FCM en Firestore: $e');
      }
    }
  }

  Future<void> _saveTokenInMundiCamBackend(String token) async {
    try {
      final bool saved = await ApiService().registerFcmToken(
        token: token,
        platform: _platform,
      );

      if (kDebugMode) {
        debugPrint(
          saved
              ? '✅ Token FCM registrado en MundiCam App API'
              : 'ℹ️ Token FCM no registrado todavía: sin sesión App API',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo registrar FCM en App API: $e');
      }
    }
  }

  String get _platform {
    if (Platform.isAndroid) {
      return 'android';
    }

    if (Platform.isIOS) {
      return 'ios';
    }

    return 'unknown';
  }
}