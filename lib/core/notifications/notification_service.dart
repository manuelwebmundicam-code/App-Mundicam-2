import 'dart:async';
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
  final Map<String, dynamic> data;

  const MundiCamOrderNotification({
    required this.event,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.title,
    required this.body,
    required this.showPopup,
    required this.data,
  });

  bool get isOrderCreated => event == 'order_created';
  bool get isStatusChanged => event == 'order_status_changed';

  bool get isGeneralNotification {
    final type = data['type']?.toString().trim().toLowerCase() ?? '';

    return event == 'general' ||
        type == 'general' ||
        type == 'info' ||
        type == 'aviso' ||
        type == 'notice' ||
        type == 'notification' ||
        type == 'notificacion';
  }

  bool get isOrderNotification => !isGeneralNotification;

  static MundiCamOrderNotification? fromRemoteMessage(
      RemoteMessage message, {
        required bool showPopup,
      }) {
    final data = Map<String, dynamic>.from(message.data);
    final type = data['type']?.toString().trim().toLowerCase() ?? '';
    final event = data['event']?.toString().trim().toLowerCase() ?? '';

    final isOrderNotification = type == 'order' ||
        type == 'pedido' ||
        event == 'order_created' ||
        event == 'order_status_changed';

    if (isOrderNotification) {
      return _fromOrderMessage(
        message,
        data: data,
        event: event,
        showPopup: showPopup,
      );
    }

    final isGeneralNotification = type == 'general' ||
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
      );
    }

    return null;
  }

  static MundiCamOrderNotification _fromOrderMessage(
      RemoteMessage message, {
        required Map<String, dynamic> data,
        required String event,
        required bool showPopup,
      }) {
    final parsedOrderId = _parseInt(
      data['order_id'] ??
          data['orderId'] ??
          data['id'] ??
          message.notification?.android?.tag,
    );

    final cleanEvent = event.isNotEmpty
        ? event
        : parsedOrderId != null
        ? 'order_status_changed'
        : 'order';

    final status = _firstNonEmptyString([
      data['status'],
      data['new_status'],
      data['order_status'],
    ]);

    final orderNumber = _firstNonEmptyString([
      data['order_number'],
      data['orderNumber'],
      data['number'],
      parsedOrderId,
    ]);

    final defaultTitle = cleanEvent == 'order_created'
        ? 'Pedido recibido'
        : 'Pedido actualizado';

    final title = _firstNonEmptyString([
      data['title'],
      message.notification?.title,
      defaultTitle,
    ]) ??
        defaultTitle;

    final defaultBody = orderNumber == null
        ? 'Hay una novedad en tus pedidos.'
        : cleanEvent == 'order_created'
        ? 'Tu pedido #$orderNumber se ha registrado correctamente.'
        : status == null
        ? 'Tu pedido #$orderNumber ha cambiado de estado.'
        : 'Tu pedido #$orderNumber ha cambiado a $status.';

    final body = _firstNonEmptyString([
      data['body'],
      message.notification?.body,
      defaultBody,
    ]) ??
        defaultBody;

    return MundiCamOrderNotification(
      event: cleanEvent,
      orderId: parsedOrderId,
      orderNumber: orderNumber,
      status: status,
      title: title,
      body: body,
      showPopup: showPopup,
      data: data,
    );
  }

  static MundiCamOrderNotification _fromGeneralMessage(
      RemoteMessage message, {
        required Map<String, dynamic> data,
        required String event,
        required bool showPopup,
      }) {
    final cleanEvent = event.isNotEmpty ? event : 'general';

    final title = _firstNonEmptyString([
      data['title'],
      message.notification?.title,
      'Aviso MundiCam',
    ]) ??
        'Aviso MundiCam';

    final body = _firstNonEmptyString([
      data['body'],
      message.notification?.body,
      'Tienes una nueva notificación.',
    ]) ??
        'Tienes una nueva notificación.';

    return MundiCamOrderNotification(
      event: cleanEvent,
      orderId: null,
      orderNumber: null,
      status: null,
      title: title,
      body: body,
      showPopup: showPopup,
      data: data,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt();
  }

  static String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final StreamController<MundiCamOrderNotification> _orderController =
  StreamController<MundiCamOrderNotification>.broadcast();

  bool _initialized = false;
  MundiCamOrderNotification? _pendingOrderNotification;

  Stream<MundiCamOrderNotification> get orderNotifications =>
      _orderController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      await syncCurrentTokenWithBackend();
      return;
    }

    _initialized = true;

    final settings = await _messaging.requestPermission(
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

    FirebaseMessaging.onMessage.listen((message) {
      _handleRemoteMessage(message, showPopup: true);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleRemoteMessage(message, showPopup: false);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleRemoteMessage(initialMessage, showPopup: false);
    }

    _messaging.onTokenRefresh.listen((token) async {
      await _saveToken(token);
    });
  }

  Future<void> syncCurrentTokenWithBackend() async {
    try {
      final token = await _messaging.getToken();
      if (kDebugMode) debugPrint('📱 FCM Token: $token');
      await _saveToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo obtener/guardar token FCM: $e');
    }
  }

  MundiCamOrderNotification? takePendingOrderNotification() {
    final notification = _pendingOrderNotification;
    _pendingOrderNotification = null;
    return notification;
  }

  void _handleRemoteMessage(
      RemoteMessage message, {
        required bool showPopup,
      }) {
    final notification = MundiCamOrderNotification.fromRemoteMessage(
      message,
      showPopup: showPopup,
    );

    if (notification == null) {
      if (kDebugMode) {
        debugPrint('ℹ️ Notificación ignorada: ${message.data}');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
        notification.isGeneralNotification
            ? '📩 Notificación general: ${notification.title}'
            : '📩 Notificación pedido: ${notification.title}',
      );
      debugPrint('   Body: ${notification.body}');
      debugPrint('   Data: ${notification.data}');
    }

    if (_orderController.hasListener) {
      _orderController.add(notification);
    } else {
      _pendingOrderNotification = notification;
    }
  }

  Future<void> _saveToken(String? token) async {
    final cleanToken = token?.trim() ?? '';
    if (cleanToken.isEmpty) return;

    await _saveTokenInFirestore(cleanToken);
    await _saveTokenInMundiCamBackend(cleanToken);
  }

  Future<void> _saveTokenInFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcm_token': token,
        'fcm_platform': _platform,
        'fcm_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) debugPrint('✅ Token FCM guardado en Firestore');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo guardar FCM en Firestore: $e');
    }
  }

  Future<void> _saveTokenInMundiCamBackend(String token) async {
    try {
      final saved = await ApiService().registerFcmToken(
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
      if (kDebugMode) debugPrint('⚠️ No se pudo registrar FCM en App API: $e');
    }
  }

  String get _platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}