import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Analítica operativa de MundiCam.
///
/// Es deliberadamente independiente del flujo comercial. Ningún fallo de este
/// servicio puede bloquear login, carrito, presupuestos, pedidos o pagos.
class MundicamAnalyticsService {
  MundicamAnalyticsService._();

  static final MundicamAnalyticsService instance =
      MundicamAnalyticsService._();

  static const String _endpoint =
      'https://www.mundicam.com/wp-json/mundicam-analytics/v1/event';
  static const String _installationIdKey =
      'mundicam_analytics_installation_id';
  static const String _firstOpenSentKey =
      'mundicam_analytics_first_open_sent';
  static const String _appTokenKey = 'mundicam_app_token';
  static const String _cartTokenKey = 'mundicam_wp_cart_token';

  /// Puede sobrescribirse en compilación con --dart-define.
  static const String appVersion = String.fromEnvironment(
    'MUNDICAM_APP_VERSION',
    defaultValue: '1.7.6',
  );

  static const Duration _requestTimeout = Duration(seconds: 4);
  static const Duration _foregroundSessionGap = Duration(minutes: 30);

  final Random _random = Random.secure();
  final Expando<String> _trackedRoutes = Expando<String>();
  final Map<String, DateTime> _recentEvents = <String, DateTime>{};

  String? _installationId;
  String _sessionId = '';
  int _eventSequence = 0;
  DateTime? _backgroundedAt;
  bool _bootstrapped = false;

  String get platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return Platform.operatingSystem.toLowerCase();
  }

  String get deviceModel {
    // El ZIP entregado solo contiene lib/ y no permite añadir device_info_plus
    // sin tocar pubspec. Se envía una identificación técnica estable y no PII.
    final raw = Platform.operatingSystemVersion.trim();
    if (raw.isEmpty) return platform;
    return raw.length <= 160 ? raw : raw.substring(0, 160);
  }

  String get sessionId {
    if (_sessionId.isEmpty) {
      _sessionId = _newSessionId();
    }
    return _sessionId;
  }

  Future<String> installationId() async {
    final cached = _installationId?.trim() ?? '';
    if (cached.isNotEmpty) return cached;

    final generated = 'mc_${_randomHex(32)}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_installationIdKey)?.trim() ?? '';
      if (stored.isNotEmpty) {
        _installationId = stored;
        return stored;
      }

      _installationId = generated;
      await prefs.setString(_installationIdKey, generated);
      return generated;
    } catch (error) {
      // Incluso si el almacenamiento local falla, la analítica no bloquea la app.
      _installationId = generated;
      if (kDebugMode) {
        debugPrint('⚠️ installation_id en memoria por fallo no crítico: $error');
      }
      return generated;
    }
  }

  Future<Map<String, dynamic>> requestContext() async {
    try {
      return <String, dynamic>{
        'installation_id': await installationId(),
        'platform': platform,
        'app_version': appVersion,
        'device_model': deviceModel,
        'session_id': sessionId,
      };
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ Contexto analítico no crítico: $error');
      }
      return <String, dynamic>{
        'installation_id': _installationId ?? 'mc_${_randomHex(32)}',
        'platform': platform,
        'app_version': appVersion,
        'device_model': deviceModel,
        'session_id': sessionId,
      };
    }
  }

  Future<Map<String, dynamic>> enrichPayload(
    Map<String, dynamic> payload,
  ) async {
    try {
      return <String, dynamic>{
        ...payload,
        ...await requestContext(),
      };
    } catch (_) {
      return Map<String, dynamic>.from(payload);
    }
  }

  /// Registra primera apertura y apertura normal sin retrasar la interfaz.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    sessionId;

    try {
      final prefs = await SharedPreferences.getInstance();
      final firstOpenSent = prefs.getBool(_firstOpenSentKey) ?? false;

      if (!firstOpenSent) {
        final sent = await _sendEvent(eventName: 'first_open');
        if (sent) {
          await prefs.setBool(_firstOpenSentKey, true);
        }
      }

      await _sendEvent(eventName: 'app_open');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ Analítica de apertura no crítica: $error');
      }
    }
  }

  void handleLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.now();
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return;

    if (DateTime.now().difference(backgroundedAt) >= _foregroundSessionGap) {
      _sessionId = _newSessionId();
      unawaited(track(eventName: 'app_open'));
    }
  }

  Future<void> screenView(String screenName) {
    final clean = _cleanEventName(screenName);
    if (clean.isEmpty) return Future<void>.value();
    return track(
      eventName: 'screen_view',
      metadata: <String, dynamic>{'screen': clean},
      dedupeKey: 'screen_view:$clean',
      dedupeWindow: const Duration(seconds: 2),
    );
  }

  /// Se puede llamar desde build(): solo registra una vez por instancia de ruta.
  void trackScreenViewForRoute(BuildContext context, String screenName) {
    final route = ModalRoute.of(context);
    if (route == null) return;
    final clean = _cleanEventName(screenName);
    if (clean.isEmpty || _trackedRoutes[route] == clean) return;
    _trackedRoutes[route] = clean;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(screenView(clean));
    });
  }

  Future<void> track({
    required String eventName,
    String? objectType,
    int? objectId,
    num? value,
    Map<String, dynamic>? metadata,
    String? dedupeKey,
    Duration dedupeWindow = const Duration(milliseconds: 750),
  }) async {
    final cleanEventName = _cleanEventName(eventName);
    if (cleanEventName.isEmpty) return;

    final effectiveDedupeKey = dedupeKey?.trim() ?? '';
    if (effectiveDedupeKey.isNotEmpty &&
        _isRecentDuplicate(effectiveDedupeKey, dedupeWindow)) {
      return;
    }

    try {
      await _sendEvent(
        eventName: cleanEventName,
        objectType: objectType,
        objectId: objectId,
        value: value,
        metadata: metadata,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ Evento analítico no crítico $cleanEventName: $error');
      }
    }
  }

  Future<bool> _sendEvent({
    required String eventName,
    String? objectType,
    int? objectId,
    num? value,
    Map<String, dynamic>? metadata,
  }) async {
    final now = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    final appToken = _firstNonEmpty(<String?>[
      prefs.getString(_appTokenKey),
      prefs.getString(_cartTokenKey),
    ]);

    final body = <String, dynamic>{
      'installation_id': await installationId(),
      'event_name': eventName,
      'platform': platform,
      'app_version': appVersion,
      'device_model': deviceModel,
      'session_id': sessionId,
      'event_id': _newEventId(eventName, now),
      'occurred_at': now.toIso8601String(),
      if ((objectType ?? '').trim().isNotEmpty)
        'object_type': objectType!.trim().toLowerCase(),
      if (objectId != null && objectId > 0) 'object_id': objectId,
      if (value != null) 'value': value,
      if (metadata != null && metadata.isNotEmpty)
        'metadata': _sanitizeMetadata(metadata),
    };

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'User-Agent': 'MundiCam-App-Flutter/$appVersion',
      if (appToken.isNotEmpty) 'Authorization': 'Bearer $appToken',
    };

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok && kDebugMode) {
      debugPrint(
        '⚠️ Analítica HTTP ${response.statusCode} para $eventName',
      );
    }
    return ok;
  }

  Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> input) {
    const forbiddenKeys = <String>{
      'password',
      'pass',
      'token',
      'app_token',
      'fcm_token',
      'authorization',
      'email',
      'phone',
      'telefono',
      'address',
      'direccion',
      'nif',
      'cif',
      'card',
      'pan',
      'cvv',
    };

    final output = <String, dynamic>{};
    for (final entry in input.entries) {
      final key = entry.key.trim().toLowerCase();
      if (key.isEmpty || forbiddenKeys.contains(key)) continue;
      final value = _sanitizeValue(entry.value, depth: 0);
      if (value != null) output[key] = value;
    }
    return output;
  }

  dynamic _sanitizeValue(dynamic value, {required int depth}) {
    if (value == null || depth > 3) return null;
    if (value is bool || value is num) return value;
    if (value is String) {
      var clean = value.trim();
      if (clean.isEmpty) return '';
      if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(clean)) {
        return '[redacted]';
      }
      if (clean.length > 160) clean = clean.substring(0, 160);
      return clean;
    }
    if (value is Iterable) {
      return value
          .take(20)
          .map((item) => _sanitizeValue(item, depth: depth + 1))
          .where((item) => item != null)
          .toList();
    }
    if (value is Map) {
      final converted = <String, dynamic>{};
      for (final entry in value.entries.take(20)) {
        final key = entry.key.toString().trim().toLowerCase();
        if (key.isEmpty) continue;
        final clean = _sanitizeValue(entry.value, depth: depth + 1);
        if (clean != null) converted[key] = clean;
      }
      return converted;
    }
    return _sanitizeValue(value.toString(), depth: depth + 1);
  }

  bool _isRecentDuplicate(String key, Duration window) {
    final now = DateTime.now();
    final previous = _recentEvents[key];
    _recentEvents[key] = now;
    _recentEvents.removeWhere(
      (_, timestamp) => now.difference(timestamp) > const Duration(minutes: 5),
    );
    return previous != null && now.difference(previous) < window;
  }

  String _cleanEventName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _newSessionId() {
    return 'session_${DateTime.now().millisecondsSinceEpoch}_${_randomHex(6)}';
  }

  String _newEventId(String eventName, DateTime now) {
    _eventSequence += 1;
    return '${eventName}_${now.microsecondsSinceEpoch}_${_eventSequence}_${_randomHex(4)}';
  }

  String _randomHex(int length) {
    const alphabet = '0123456789abcdef';
    return List<String>.generate(
      length,
      (_) => alphabet[_random.nextInt(alphabet.length)],
      growable: false,
    ).join();
  }

  String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final clean = value?.trim() ?? '';
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }
}
