import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';

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
    required this.openedByUser,
    required this.messageId,
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

  MundiCamOrderNotification copyWith({
    bool? showPopup,
    bool? openedByUser,
  }) {
    return MundiCamOrderNotification(
      event: event,
      orderId: orderId,
      orderNumber: orderNumber,
      status: status,
      title: title,
      body: body,
      showPopup: showPopup ?? this.showPopup,
      openedByUser: openedByUser ?? this.openedByUser,
      messageId: messageId,
      data: data,
    );
  }

  String toPayload() {
    return jsonEncode({
      'event': event,
      'order_id': orderId,
      'order_number': orderNumber,
      'status': status,
      'title': title,
      'body': body,
      'message_id': messageId,
      'data': data,
    });
  }

  static MundiCamOrderNotification? fromPayload(
    String? payload, {
    required bool openedByUser,
  }) {
    final cleanPayload = payload?.trim() ?? '';
    if (cleanPayload.isEmpty) return null;

    try {
      final decoded = jsonDecode(cleanPayload);
      if (decoded is! Map) return null;

      final map = Map<String, dynamic>.from(decoded);
      final embeddedData = map['data'];
      final data = embeddedData is Map
          ? Map<String, dynamic>.from(embeddedData)
          : <String, dynamic>{};

      final event = _firstNonEmptyString([
            map['event'],
            data['event'],
            'general',
          ])!
          .toLowerCase();

      final orderId = _parseInt(
        map['order_id'] ?? data['order_id'] ?? data['orderId'],
      );

      final orderNumber = _firstNonEmptyString([
        map['order_number'],
        data['order_number'],
        data['orderNumber'],
        orderId,
      ]);

      final status = _firstNonEmptyString([
        map['status'],
        data['status'],
        data['new_status'],
        data['order_status'],
      ]);

      final title = _firstNonEmptyString([
            map['title'],
            data['title'],
            'Aviso MundiCam',
          ]) ??
          'Aviso MundiCam';

      final body = _firstNonEmptyString([
            map['body'],
            data['body'],
            'Tienes una nueva notificación.',
          ]) ??
          'Tienes una nueva notificación.';

      return MundiCamOrderNotification(
        event: event,
        orderId: orderId,
        orderNumber: orderNumber,
        status: status,
        title: title,
        body: body,
        showPopup: false,
        openedByUser: openedByUser,
        messageId: _firstNonEmptyString([
          map['message_id'],
          data['message_id'],
        ]),
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
    required bool openedByUser,
  }) {
    final data = Map<String, dynamic>.from(message.data);
    final type = data['type']?.toString().trim().toLowerCase() ?? '';
    final event = data['event']?.toString().trim().toLowerCase() ?? '';

    final titleHint = _firstNonEmptyString([
          data['title'],
          message.notification?.title,
        ])
            ?.toLowerCase() ??
        '';
    final bodyHint = _firstNonEmptyString([
          data['body'],
          message.notification?.body,
        ])
            ?.toLowerCase() ??
        '';

    // Firebase Console puede enviar una prueba sin todos los datos
    // personalizados. Si el título/cuerpo habla de un pedido o el payload
    // contiene campos de pedido, lo tratamos igualmente como actualización
    // de pedido para mostrar el camión y el botón «Ver pedidos».
    final hasOrderHint = titleHint.contains('pedido') ||
        bodyHint.contains('pedido') ||
        titleHint.contains('order') ||
        bodyHint.contains('order') ||
        data.containsKey('order_id') ||
        data.containsKey('orderId') ||
        data.containsKey('order_number') ||
        data.containsKey('orderNumber') ||
        data['screen']?.toString().trim().toLowerCase() == 'orders';

    final isOrderNotification = type == 'order' ||
        type == 'pedido' ||
        event == 'order_created' ||
        event == 'order_status_changed' ||
        hasOrderHint;

    if (isOrderNotification) {
      return _fromOrderMessage(
        message,
        data: data,
        event: event,
        showPopup: showPopup,
        openedByUser: openedByUser,
      );
    }

    final isGeneralNotification = type == 'general' ||
        type == 'info' ||
        type == 'aviso' ||
        type == 'notice' ||
        type == 'notification' ||
        type == 'notificacion';

    if (isGeneralNotification || message.notification != null) {
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
    final parsedOrderId = _parseInt(
      data['order_id'] ??
          data['orderId'] ??
          data['order_number'] ??
          data['orderNumber'] ??
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
      openedByUser: openedByUser,
      messageId: message.messageId,
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
      openedByUser: openedByUser,
      messageId: message.messageId,
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
  static const String androidChannelId = 'mundicam_orders';
  static const String androidChannelName = 'Pedidos MundiCam';
  static const String androidChannelDescription =
      'Actualizaciones de pedidos, envíos, cancelaciones y reembolsos.';

  static const String _processedMessageKeysPrefsKey =
      'mundicam_processed_fcm_message_keys_v1';
  static const String _lastFcmTokenPrefsKey = 'mundicam_last_fcm_token_v1';
  static const int _maxProcessedMessageKeys = 100;
  static const int _maxPendingNotifications = 20;

  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<MundiCamOrderNotification> _orderController =
      StreamController<MundiCamOrderNotification>.broadcast();

  final ListQueue<MundiCamOrderNotification> _pendingNotifications =
      ListQueue<MundiCamOrderNotification>();

  bool _initialized = false;
  bool _localNotificationsInitialized = false;
  Future<void>? _initializationFuture;

  Stream<MundiCamOrderNotification> get orderNotifications =>
      _orderController.stream;

  Future<void> initialize() {
    if (_initialized) {
      return syncCurrentTokenWithBackend();
    }

    final running = _initializationFuture;
    if (running != null) return running;

    final future = _initializeInternal();
    _initializationFuture = future;

    return future.whenComplete(() {
      _initializationFuture = null;
    });
  }

  Future<void> _initializeInternal() async {
    await _initializeLocalNotifications();

    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (kDebugMode) {
      debugPrint('🔔 Permiso notificaciones: ${settings.authorizationStatus}');
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    // Registrar listeners antes de pedir el token evita perder un refresco APNs/FCM
    // durante los primeros segundos de arranque en iOS.
    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_handleForegroundRemoteMessage(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleRemoteMessageOpenedByUser(message);
    });

    _messaging.onTokenRefresh.listen((token) async {
      final apnsToken = Platform.isIOS ? await _waitForApnsToken() : null;
      await _saveToken(token, apnsToken: apnsToken);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleRemoteMessageOpenedByUser(initialMessage);
    }

    await syncCurrentTokenWithBackend();
    _initialized = true;
  }

  static Future<void> handleBackgroundRemoteMessage(
    RemoteMessage message,
  ) async {
    // Los mensajes que ya contienen `notification` los muestra el sistema cuando
    // la app está en segundo plano/cerrada. Solo creamos un aviso local para
    // mensajes data-only, evitando notificaciones duplicadas.
    if (message.notification != null) return;

    final service = NotificationService();
    await service._initializeLocalNotifications();

    final notification = MundiCamOrderNotification.fromRemoteMessage(
      message,
      showPopup: false,
      openedByUser: false,
    );

    if (notification == null) return;

    final isNew = await service._markRemoteMessageAsProcessed(message);
    if (!isNew) return;

    await service._showLocalNotification(notification);
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      'ic_stat_mundicam',
    );

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description: androidChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    _localNotificationsInitialized = true;

    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;

    if (launchDetails?.didNotificationLaunchApp == true && response != null) {
      _handleLocalNotificationResponse(response);
    }
  }

  Future<void> _handleForegroundRemoteMessage(RemoteMessage message) async {
    final isNew = await _markRemoteMessageAsProcessed(message);
    if (!isNew) return;

    final notification = MundiCamOrderNotification.fromRemoteMessage(
      message,
      showPopup: false,
      openedByUser: false,
    );

    if (notification == null) {
      if (kDebugMode) {
        debugPrint('ℹ️ Notificación ignorada: ${message.data}');
      }
      return;
    }

    try {
      await _showLocalNotification(notification);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo mostrar aviso local: $e');
      }
    }

    // En primer plano mostramos también el aviso interno MundiCam.
    // De este modo el usuario ve el mensaje dentro de la app y, además,
    // conserva la notificación del sistema en la bandeja de Android.
    _emitNotification(
      notification.copyWith(showPopup: true),
    );
  }

  void _handleRemoteMessageOpenedByUser(RemoteMessage message) {
    final notification = MundiCamOrderNotification.fromRemoteMessage(
      message,
      showPopup: false,
      openedByUser: true,
    );

    if (notification == null) return;
    unawaited(
      MundicamAnalyticsService.instance.track(
        eventName: 'push_opened',
        objectType: notification.orderId != null ? 'order' : 'notification',
        objectId: notification.orderId,
        metadata: <String, dynamic>{
          'event': notification.event,
          if ((notification.status ?? '').trim().isNotEmpty)
            'status': notification.status!.trim(),
        },
      ),
    );
    _emitNotification(notification);
  }

  void _handleLocalNotificationResponse(NotificationResponse response) {
    final notification = MundiCamOrderNotification.fromPayload(
      response.payload,
      openedByUser: true,
    );

    if (notification == null) return;
    unawaited(
      MundicamAnalyticsService.instance.track(
        eventName: 'push_opened',
        objectType: notification.orderId != null ? 'order' : 'notification',
        objectId: notification.orderId,
        metadata: <String, dynamic>{
          'event': notification.event,
          if ((notification.status ?? '').trim().isNotEmpty)
            'status': notification.status!.trim(),
        },
      ),
    );
    _emitNotification(notification);
  }

  Future<void> _showLocalNotification(
    MundiCamOrderNotification notification,
  ) async {
    await _initializeLocalNotifications();

    final androidDetails = AndroidNotificationDetails(
      androidChannelId,
      androidChannelName,
      icon: 'ic_stat_mundicam',
      color: const Color(0xFFA60909),
      channelDescription: androidChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(notification.body),
      tag: notification.orderId == null
          ? 'mundicam_general'
          : 'mundicam_order_${notification.orderId}',
      groupKey: notification.isOrderNotification
          ? 'mundicam_order_updates'
          : 'mundicam_general_updates',
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      badgeNumber: 1,
      threadIdentifier: notification.orderId == null
          ? 'mundicam_general'
          : 'mundicam_order_${notification.orderId}',
    );

    await _localNotifications.show(
      _notificationId(notification),
      notification.title,
      notification.body,
      NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      ),
      payload: notification.toPayload(),
    );
  }


  int _notificationId(MundiCamOrderNotification notification) {
    final orderId = notification.orderId;
    if (orderId != null && orderId > 0) {
      return orderId & 0x7fffffff;
    }

    final source = notification.messageId ??
        '${notification.event}|${notification.title}|${notification.body}';

    var hash = 0x811c9dc5;
    for (final codeUnit in source.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
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

  List<MundiCamOrderNotification> takePendingOrderNotifications() {
    final pending = List<MundiCamOrderNotification>.unmodifiable(
      _pendingNotifications,
    );
    _pendingNotifications.clear();
    return pending;
  }

  // Compatibilidad temporal con llamadas antiguas del proyecto.
  MundiCamOrderNotification? takePendingOrderNotification() {
    if (_pendingNotifications.isEmpty) return null;
    return _pendingNotifications.removeFirst();
  }

  Future<bool> _markRemoteMessageAsProcessed(RemoteMessage message) async {
    final key = _remoteMessageDeduplicationKey(message);

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList(_processedMessageKeysPrefsKey) ??
          <String>[];

      if (keys.contains(key)) {
        if (kDebugMode) debugPrint('ℹ️ FCM duplicado ignorado: $key');
        return false;
      }

      keys.add(key);
      if (keys.length > _maxProcessedMessageKeys) {
        keys.removeRange(0, keys.length - _maxProcessedMessageKeys);
      }

      await prefs.setStringList(_processedMessageKeysPrefsKey, keys);
      return true;
    } catch (e) {
      // La deduplicación no debe bloquear una notificación válida.
      if (kDebugMode) debugPrint('⚠️ No se pudo deduplicar FCM: $e');
      return true;
    }
  }

  String _remoteMessageDeduplicationKey(RemoteMessage message) {
    final data = message.data;
    // PHP 1.9.22 envía event_id estable para cada alta, cambio de estado o
    // reembolso. Se prioriza frente al messageId de FCM, que puede cambiar en
    // reintentos y provocar avisos duplicados del mismo evento.
    final explicitId = data['event_id']?.toString().trim() ??
        data['eventId']?.toString().trim() ??
        message.messageId?.trim() ??
        data['message_id']?.toString().trim() ??
        data['notification_id']?.toString().trim() ??
        '';

    if (explicitId.isNotEmpty) return explicitId;

    final sentTime = message.sentTime?.millisecondsSinceEpoch ??
        data['timestamp'] ??
        data['sent_at'] ??
        '';

    return [
      data['event'],
      data['type'],
      data['order_id'] ?? data['orderId'],
      data['status'] ?? data['new_status'],
      sentTime,
      message.notification?.title ?? data['title'],
      message.notification?.body ?? data['body'],
    ].map((value) => value?.toString() ?? '').join('|');
  }

  Future<void> syncCurrentTokenWithBackend() async {
    try {
      String? apnsToken;

      if (Platform.isIOS) {
        apnsToken = await _waitForApnsToken();
        if ((apnsToken ?? '').isEmpty) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ APNs token no disponible todavía. FCM se reintentará al refrescar token.',
            );
          }
          return;
        }
      }

      final token = await _messaging.getToken();
      if (kDebugMode) debugPrint('📱 FCM Token $_platform: $token');
      await _saveToken(token, apnsToken: apnsToken);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo obtener/guardar token FCM: $e');
    }
  }

  Future<String?> _waitForApnsToken() async {
    String? apnsToken = await _messaging.getAPNSToken();

    for (var attempt = 0; apnsToken == null && attempt < 12; attempt++) {
      await Future.delayed(const Duration(milliseconds: 500));
      apnsToken = await _messaging.getAPNSToken();
    }

    if (apnsToken != null && kDebugMode) {
      debugPrint('🍎 APNs Token: $apnsToken');
    }

    return apnsToken;
  }

  Future<void> _saveToken(String? token, {String? apnsToken}) async {
    final cleanToken = token?.trim() ?? '';
    if (cleanToken.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastFcmTokenPrefsKey, cleanToken);

    await _saveTokenInFirestore(cleanToken, apnsToken: apnsToken);
    await _saveTokenInMundiCamBackend(cleanToken, apnsToken: apnsToken);
  }

  Future<void> _saveTokenInFirestore(String token, {String? apnsToken}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcm_token': token,
        'fcm_platform': _platform,
        if ((apnsToken ?? '').isNotEmpty) 'apns_token': apnsToken,
        'fcm_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) debugPrint('✅ Token FCM guardado en Firestore');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo guardar FCM en Firestore: $e');
    }
  }

  Future<void> _saveTokenInMundiCamBackend(
    String token, {
    String? apnsToken,
  }) async {
    try {
      final saved = await ApiService().registerFcmToken(
        token: token,
        platform: _platform,
        apnsToken: apnsToken,
      );

      if (kDebugMode) {
        debugPrint(
          saved
              ? '✅ Token FCM registrado en MundiCam App API'
              : 'ℹ️ Token FCM no registrado todavía: sin sesión App API o endpoint pendiente',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo registrar FCM en App API: $e');
    }
  }

  Future<void> clearDeviceRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString(_lastFcmTokenPrefsKey)?.trim() ?? '';

    String currentToken = storedToken;
    if (currentToken.isEmpty) {
      try {
        currentToken = (await _messaging.getToken())?.trim() ?? '';
      } catch (_) {}
    }

    if (currentToken.isNotEmpty) {
      try {
        await ApiService().unregisterFcmToken(
          token: currentToken,
          platform: _platform,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Backend aún no desregistró el token FCM: $e');
        }
      }
    }

    await _removeTokenFromFirestore(currentToken);

    try {
      await _messaging.deleteToken();
      if (kDebugMode) debugPrint('✅ Token FCM eliminado del dispositivo');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo eliminar token FCM local: $e');
    }

    await prefs.remove(_lastFcmTokenPrefsKey);
    await prefs.remove(_processedMessageKeysPrefsKey);
    _pendingNotifications.clear();
  }

  Future<void> _removeTokenFromFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snapshot = await ref.get();
      final savedToken = snapshot.data()?['fcm_token']?.toString() ?? '';

      if (token.isNotEmpty && savedToken.isNotEmpty && savedToken != token) {
        return;
      }

      await ref.set({
        'fcm_token': FieldValue.delete(),
        'fcm_platform': FieldValue.delete(),
        'apns_token': FieldValue.delete(),
        'fcm_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) debugPrint('✅ Token FCM eliminado de Firestore');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo eliminar token FCM de Firestore: $e');
      }
    }
  }

  String get _platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
