import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationInboxEntry {
  final String id;
  final String title;
  final String body;
  final String event;
  final String? imageUrl;
  final int? orderId;
  final String? orderNumber;
  final String? status;
  final DateTime receivedAt;
  final bool openedByUser;

  const NotificationInboxEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.event,
    required this.imageUrl,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.receivedAt,
    required this.openedByUser,
  });

  bool get isTestOrDiagnostic {
    final cleanEvent = event.trim().toLowerCase();
    final cleanId = id.trim().toLowerCase();

    const testEvents = <String>{
      'diagnostic_test',
      'fcm_test',
      'push_test',
      'test',
    };

    return testEvents.contains(cleanEvent) ||
        cleanEvent.startsWith('diagnostic_') ||
        cleanId.startsWith('diagnostic:') ||
        cleanId.startsWith('test:') ||
        cleanId.startsWith('fcm-test:');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'event': event,
        'image_url': imageUrl,
        'order_id': orderId,
        'order_number': orderNumber,
        'status': status,
        'received_at': receivedAt.toIso8601String(),
        'opened_by_user': openedByUser,
      };

  static NotificationInboxEntry? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;

    final receivedAt = DateTime.tryParse(
          json['received_at']?.toString().trim() ?? '',
        ) ??
        DateTime.now();

    return NotificationInboxEntry(
      id: id,
      title: _clean(json['title'], fallback: 'Aviso MundiCam'),
      body: _clean(
        json['body'],
        fallback: 'Tienes una nueva notificación.',
      ),
      event: _clean(json['event'], fallback: 'general'),
      imageUrl: _nullableClean(json['image_url']),
      orderId: _parseInt(json['order_id']),
      orderNumber: _nullableClean(json['order_number']),
      status: _nullableClean(json['status']),
      receivedAt: receivedAt,
      openedByUser: json['opened_by_user'] == true,
    );
  }

  static String _clean(dynamic value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _nullableClean(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }
}

class NotificationInboxStore {
  static const String _prefsKeyPrefix = 'mundicam_notification_inbox_v1';
  static const int _maxEntries = 100;

  static final NotificationInboxStore instance = NotificationInboxStore._();
  NotificationInboxStore._();

  Future<List<NotificationInboxEntry>> load({required String scope}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawEntries =
          prefs.getStringList(_prefsKeyForScope(scope)) ?? const <String>[];
      final entries = <NotificationInboxEntry>[];

      for (final raw in rawEntries) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) continue;
          final entry = NotificationInboxEntry.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (entry != null && !entry.isTestOrDiagnostic) {
            entries.add(entry);
          }
        } catch (_) {
          // Una entrada antigua/corrupta nunca debe bloquear el buzón.
        }
      }

      entries.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      return entries;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo cargar el buzón de notificaciones: $e');
      }
      return const <NotificationInboxEntry>[];
    }
  }

  Future<void> save({
    required String scope,
    required String id,
    required String title,
    required String body,
    required String event,
    String? imageUrl,
    int? orderId,
    String? orderNumber,
    String? status,
    required bool openedByUser,
  }) async {
    try {
      final normalizedEvent = event.trim().toLowerCase();
      final normalizedId = id.trim().toLowerCase();
      const testEvents = <String>{
        'diagnostic_test',
        'fcm_test',
        'push_test',
        'test',
      };
      if (testEvents.contains(normalizedEvent) ||
          normalizedEvent.startsWith('diagnostic_') ||
          normalizedId.startsWith('diagnostic:') ||
          normalizedId.startsWith('test:') ||
          normalizedId.startsWith('fcm-test:')) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final current = await load(scope: scope);

      final existingIndex = current.indexWhere((entry) => entry.id == id);
      final existing = existingIndex >= 0 ? current[existingIndex] : null;

      final entry = NotificationInboxEntry(
        id: id,
        title: title.trim().isEmpty ? 'Aviso MundiCam' : title.trim(),
        body: body.trim().isEmpty
            ? 'Tienes una nueva notificación.'
            : body.trim(),
        event: event.trim().isEmpty ? 'general' : event.trim(),
        imageUrl: _nullableClean(imageUrl),
        orderId: orderId,
        orderNumber: _nullableClean(orderNumber),
        status: _nullableClean(status),
        receivedAt: existing?.receivedAt ?? DateTime.now(),
        openedByUser: openedByUser || (existing?.openedByUser ?? false),
      );

      current.removeWhere((item) => item.id == id);
      current.insert(0, entry);

      if (current.length > _maxEntries) {
        current.removeRange(_maxEntries, current.length);
      }

      await prefs.setStringList(
        _prefsKeyForScope(scope),
        current.map((item) => jsonEncode(item.toJson())).toList(),
      );
    } catch (e) {
      // El buzón es complementario: nunca debe interferir con FCM/APNs.
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo guardar notificación en el buzón: $e');
      }
    }
  }


  static String? scopeForUser({int? wordpressId, String? email}) {
    if (wordpressId != null && wordpressId > 0) {
      return 'wp:$wordpressId';
    }

    final cleanEmail = email?.trim().toLowerCase() ?? '';
    if (cleanEmail.isNotEmpty) return 'email:$cleanEmail';

    return null;
  }

  static String _prefsKeyForScope(String scope) {
    final encoded = base64Url.encode(utf8.encode(scope));
    return '${_prefsKeyPrefix}_$encoded';
  }

  static String? _nullableClean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
