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

class MundiCamOrderNotification {
  static const Set<String> _orderEvents = <String>{
    'order_created',
    'new_order',
    'order_status_changed',
    'order_refunded',
    'order_partially_refunded',
    'order_partial_refund',
    'refund_created',
  };

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

  bool get isOrderCreated =>
      event == 'order_created' || event == 'new_order';

  bool get isRefund => event == 'order_refunded' ||
      event == 'order_partially_refunded' ||
      event == 'order_partial_refund' ||
      event == 'refund_created';

  bool get isStatusChanged => event == 'order_status_changed' || isRefund;

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

  bool get isOrderNotification {
    final type = data['type']?.toString().trim().toLowerCase() ?? '';
    final screen = data['screen']?.toString().trim().toLowerCase() ?? '';

    return orderId != null ||
        type == 'order' ||
        type == 'pedido' ||
        screen == 'orders' ||
        _orderEvents.contains(event);
  }

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
        debugPrint('[FCM] Payload local inválido: $e | END');
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
        _orderEvents.contains(event) ||
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

    final defaultTitle = _defaultOrderTitle(cleanEvent, status);

    final title = _firstNonEmptyString([
          data['title'],
          message.notification?.title,
          defaultTitle,
        ]) ??
        defaultTitle;

    final defaultBody = _defaultOrderBody(
      event: cleanEvent,
      orderNumber: orderNumber,
      status: status,
      refundAmount: _firstNonEmptyString([
        data['refund_amount'],
        data['amount'],
      ]),
    );

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

  static String _defaultOrderTitle(String event, String? status) {
    if (event == 'order_created' || event == 'new_order') {
      return 'Pedido recibido';
    }
    if (event == 'order_refunded' ||
        event == 'order_partially_refunded' ||
        event == 'order_partial_refund' ||
        event == 'refund_created') {
      return 'Reembolso del pedido';
    }

    switch (_normalizeStatus(status)) {
      case 'pending':
        return 'Pedido pendiente de pago';
      case 'on-hold':
        return 'Pedido en espera';
      case 'processing':
        return 'Pedido en preparación';
      case 'completed':
        return 'Pedido completado';
      case 'cancelled':
        return 'Pedido cancelado';
      case 'refunded':
        return 'Pedido reembolsado';
      case 'failed':
        return 'Pago del pedido fallido';
      default:
        return 'Pedido actualizado';
    }
  }

  static String _defaultOrderBody({
    required String event,
    required String? orderNumber,
    required String? status,
    required String? refundAmount,
  }) {
    final orderText = orderNumber == null ? 'Tu pedido' : 'Tu pedido #$orderNumber';

    if (event == 'order_created' || event == 'new_order') {
      return '$orderText se ha registrado correctamente.';
    }

    if (event == 'order_refunded' ||
        event == 'order_partially_refunded' ||
        event == 'order_partial_refund' ||
        event == 'refund_created') {
      final amountText = refundAmount == null ? '' : ' por $refundAmount';
      return 'Se ha realizado un reembolso$amountText en $orderText.';
    }

    final label = _statusLabel(status);
    if (label == null) {
      return '$orderText ha cambiado de estado.';
    }
    return '$orderText ahora está $label.';
  }

  static String _normalizeStatus(String? status) {
    return (status ?? '')
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^wc-'), '')
        .replaceAll('_', '-');
  }

  static String? _statusLabel(String? status) {
    switch (_normalizeStatus(status)) {
      case 'pending':
        return 'pendiente de pago';
      case 'on-hold':
        return 'en espera';
      case 'processing':
        return 'en preparación';
      case 'completed':
        return 'completado';
      case 'cancelled':
        return 'cancelado';
      case 'refunded':
        return 'reembolsado';
      case 'failed':
        return 'con el pago fallido';
      default:
        final clean = status?.trim() ?? '';
        return clean.isEmpty ? null : clean;
    }
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
  Future<bool>? _activeTokenSync;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedMessageSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  Stream<MundiCamOrderNotification> get orderNotifications =>
      _orderController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      unawaited(() async {
        await syncCurrentTokenWithBackend();
      }());
      return;
    }

    final activeInitialization = _initializationFuture;
    if (activeInitialization != null) {
      await activeInitialization;
      return;
    }

    final operation = _initializeInternal();
    _initializationFuture = operation;

    try {
      await operation;
    } finally {
      if (identical(_initializationFuture, operation)) {
        _initializationFuture = null;
      }
    }
  }

  Future<void> _initializeInternal() async {
    try {
      await _messaging.setAutoInitEnabled(true);
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
        debugPrint('[FCM] Permiso=${settings.authorizationStatus} | END');
      }

      // El aviso visible en primer plano se crea de forma local tanto en Android
      // como en iOS. Desactivamos la presentación remota automática de iOS para
      // evitar duplicados y mantener el mismo comportamiento en ambos sistemas.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      await _cancelMessagingSubscriptions();

      _foregroundMessageSubscription =
          FirebaseMessaging.onMessage.listen((message) {
        unawaited(_handleForegroundRemoteMessage(message));
      });

      _openedMessageSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleRemoteMessageOpenedByUser(message);
      });

      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
        unawaited(_handleTokenRefresh(token));
      });

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleRemoteMessageOpenedByUser(initialMessage);
      }

      _initialized = true;

      // Guardar el token no debe retrasar la activación de los listeners ni la
      // apertura de una notificación que lanzó la aplicación.
      unawaited(() async {
        await syncCurrentTokenWithBackend();
      }());
    } catch (e) {
      _initialized = false;
      await _cancelMessagingSubscriptions();
      rethrow;
    }
  }

  Future<void> _handleTokenRefresh(String token) async {
    try {
      final apnsToken = Platform.isIOS ? await _waitForApnsToken() : null;
      await _saveToken(token, apnsToken: apnsToken);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] Error guardando token renovado: $e | END');
      }
    }
  }

  Future<void> _cancelMessagingSubscriptions() async {
    await _foregroundMessageSubscription?.cancel();
    await _openedMessageSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription = null;
    _openedMessageSubscription = null;
    _tokenRefreshSubscription = null;
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
      'mundicam_notification_logo',
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

    if (Platform.isAndroid) {
      try {
        await androidPlugin?.requestNotificationsPermission();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[FCM] Permiso local Android no solicitado: $e | END');
        }
      }
    }

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
      showPopup: true,
      openedByUser: false,
    );

    if (notification == null) {
      if (kDebugMode) {
        debugPrint('[FCM] Notificación ignorada data=${message.data} | END');
      }
      return;
    }

    // Con la app abierta mostramos las dos capas solicitadas:
    // 1) notificación superior del sistema y 2) popup interno de MundiCam.
    // En iOS la presentación remota automática está desactivada, por lo que no
    // se duplica el aviso al crear esta notificación local.
    try {
      await _showLocalNotification(notification);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] No se pudo mostrar el aviso superior: $e | END');
      }
    }

    _emitNotification(notification);
  }

  void _handleRemoteMessageOpenedByUser(RemoteMessage message) {
    final notification = MundiCamOrderNotification.fromRemoteMessage(
      message,
      showPopup: false,
      openedByUser: true,
    );

    if (notification == null) return;
    _emitNotification(notification);
  }

  void _handleLocalNotificationResponse(NotificationResponse response) {
    final notification = MundiCamOrderNotification.fromPayload(
      response.payload,
      openedByUser: true,
    );

    if (notification == null) return;
    _emitNotification(notification);
  }

  Future<void> _showLocalNotification(
    MundiCamOrderNotification notification,
  ) async {
    await _initializeLocalNotifications();

    final androidDetails = AndroidNotificationDetails(
      androidChannelId,
      androidChannelName,
      icon: 'mundicam_notification_logo',
      color: const Color(0xFF000000),
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
    // Cada evento conserva su propio aviso en la bandeja. Si Firebase entrega un
    // messageId lo usamos como clave; en su ausencia se combinan pedido, evento,
    // estado y contenido. Así processing, completed o refunded no se pisan.
    final source = notification.messageId ??
        '${notification.orderId ?? ''}|${notification.event}|'
        '${notification.status ?? ''}|${notification.title}|${notification.body}';

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
        '[FCM] Recibida type=${notification.isGeneralNotification ? 'general' : 'order'} | '
        'event=${notification.event} | order=${notification.orderId ?? '-'} | '
        'opened=${notification.openedByUser} | popup=${notification.showPopup} | END',
      );
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
        if (kDebugMode) debugPrint('[FCM] Duplicado ignorado key=$key | END');
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
      if (kDebugMode) debugPrint('[FCM] Deduplicación omitida: $e | END');
      return true;
    }
  }

  String _remoteMessageDeduplicationKey(RemoteMessage message) {
    final data = message.data;
    final explicitId = message.messageId?.trim() ??
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

  Future<bool> syncCurrentTokenWithBackend() {
    final active = _activeTokenSync;
    if (active != null) return active;

    final operation = _syncCurrentTokenWithBackendInternal();
    _activeTokenSync = operation;

    return operation.whenComplete(() {
      if (identical(_activeTokenSync, operation)) {
        _activeTokenSync = null;
      }
    });
  }

  Future<bool> _syncCurrentTokenWithBackendInternal() async {
    try {
      String? apnsToken;

      if (Platform.isIOS) {
        apnsToken = await _waitForApnsToken();
        if ((apnsToken ?? '').isEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[FCM] APNs token no disponible todavía; se reintentará | END',
            );
          }
          return false;
        }
      }

      final token = await _messaging.getToken();
      final cleanToken = token?.trim() ?? '';

      if (cleanToken.isEmpty) {
        if (kDebugMode) {
          debugPrint('[FCM] Firebase no devolvió token | END');
        }
        return false;
      }

      if (kDebugMode) {
        final preview = cleanToken.length > 12
            ? '${cleanToken.substring(0, 6)}...${cleanToken.substring(cleanToken.length - 6)}'
            : cleanToken;
        debugPrint(
          '[FCM] Token $_platform="$preview" | '
          'length=${cleanToken.length} | END',
        );
      }

      return _saveToken(cleanToken, apnsToken: apnsToken);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] Error obteniendo/guardando token: $e | END');
      }
      return false;
    }
  }

  /// Se llama justo después de guardar una sesión válida de MundiCam App API.
  /// Conserva el token generado antes del login y lo vincula al usuario.
  Future<bool> syncAfterLogin({int maxAttempts = 4}) async {
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      final hasSession = await ApiService().hasStoredWordPressSession();

      if (!hasSession) {
        if (kDebugMode) {
          debugPrint(
            '[FCM] Registro poslogin intento $attempt/$attempts: '
            'sesión App API aún no disponible | END',
          );
        }
      } else {
        final registered = await syncCurrentTokenWithBackend();
        if (registered) {
          if (kDebugMode) {
            debugPrint(
              '[FCM] Registro poslogin completado en intento '
              '$attempt/$attempts | END',
            );
          }
          return true;
        }
      }

      if (attempt < attempts) {
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[FCM] No se pudo registrar tras el login; '
        'se reintentará al reiniciar o refrescar el token | END',
      );
    }
    return false;
  }

  Future<String?> _waitForApnsToken() async {
    String? apnsToken = await _messaging.getAPNSToken();

    for (var attempt = 0; apnsToken == null && attempt < 12; attempt++) {
      await Future.delayed(const Duration(milliseconds: 500));
      apnsToken = await _messaging.getAPNSToken();
    }

    if (apnsToken != null && kDebugMode) {
      debugPrint(
        '[FCM] APNs token recibido | length=${apnsToken.length} | END',
      );
    }

    return apnsToken;
  }

  Future<bool> _saveToken(String? token, {String? apnsToken}) async {
    final cleanToken = token?.trim() ?? '';
    if (cleanToken.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastFcmTokenPrefsKey, cleanToken);

    await _saveTokenInFirestore(cleanToken, apnsToken: apnsToken);
    return _saveTokenInMundiCamBackend(
      cleanToken,
      apnsToken: apnsToken,
    );
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

      if (kDebugMode) {
        debugPrint('[FCM] Token guardado en Firestore | END');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] Firestore no guardó el token: $e | END');
      }
    }
  }

  Future<bool> _saveTokenInMundiCamBackend(
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
              ? '[FCM] Token registrado en MundiCam App API | END'
              : '[FCM] Token conservado localmente; pendiente de sesión/endpoint | END',
        );
      }
      return saved;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] Error registrando en App API: $e | END');
      }
      return false;
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
          debugPrint('[FCM] Backend no desregistró el token: $e | END');
        }
      }
    }

    await _removeTokenFromFirestore(currentToken);

    try {
      await _messaging.deleteToken();
      if (kDebugMode) {
        debugPrint('[FCM] Token eliminado por cierre de sesión real | END');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] No se pudo eliminar token local: $e | END');
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

      if (kDebugMode) debugPrint('[FCM] Token eliminado de Firestore | END');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] No se pudo eliminar token de Firestore: $e | END');
      }
    }
  }

  String get _platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
