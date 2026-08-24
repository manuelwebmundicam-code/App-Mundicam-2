import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/core/cache/product_cache_service.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/home/data/models/banner.dart';
import 'package:mundicam/features/home/data/models/noticia.dart';
import 'package:mundicam/features/orders/data/models/order_model.dart';
import 'package:mundicam/features/quotes/data/models/quote_model.dart';
import 'package:mundicam/features/quotes/data/models/local_quote_model.dart';
import 'package:mundicam/features/training/data/models/cursos_model.dart';


Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

int _parseInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final raw = value.toString().trim().replaceAll(',', '.');
  return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
}

double _parseDouble(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is int) return value.toDouble();
  if (value is double) return value;
  if (value is num) return value.toDouble();

  final raw = value
      .toString()
      .trim()
      .replaceAll('€', '')
      .replaceAll(' ', '')
      .replaceAll(',', '.');
  if (raw.isEmpty || raw.toLowerCase() == 'null') return fallback;
  return double.tryParse(raw) ?? fallback;
}

String? _firstNonEmptyString(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return null;
}

List<dynamic> _firstList(List<dynamic> values) {
  for (final value in values) {
    if (value is List) return value;
  }
  return <dynamic>[];
}


class PasswordResetRequestResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? rawData;

  const PasswordResetRequestResult({
    required this.success,
    required this.message,
    this.rawData,
  });

  factory PasswordResetRequestResult.success([String? message]) {
    return PasswordResetRequestResult(
      success: true,
      message: message?.trim().isNotEmpty == true
          ? message!.trim()
          : 'Si el correo está registrado, recibirás un mensaje para restablecer tu contraseña.',
    );
  }

  factory PasswordResetRequestResult.failure(String message) {
    return PasswordResetRequestResult(
      success: false,
      message: message.trim().isNotEmpty
          ? message.trim()
          : 'No se pudo solicitar la recuperación de contraseña.',
    );
  }
}

class OrderCreateResult {
  final bool success;
  final int? orderId;
  final String? orderKey;
  final String? orderNumber;
  final String? status;
  final String? paymentUrl;
  final String? errorMessage;
  final Map<String, dynamic>? rawData;

  const OrderCreateResult({
    required this.success,
    this.orderId,
    this.orderKey,
    this.orderNumber,
    this.status,
    this.paymentUrl,
    this.errorMessage,
    this.rawData,
  });

  factory OrderCreateResult.success(Map<String, dynamic> data) {
    final order = _asMap(data['order']);
    final source = order.isNotEmpty ? order : data;

    return OrderCreateResult(
      success: true,
      orderId: _parseInt(data['order_id'] ?? source['id']),
      orderKey: (data['order_key'] ?? source['order_key'])?.toString(),
      orderNumber: (data['number'] ?? source['number'])?.toString(),
      status: (data['status'] ?? source['status'])?.toString(),
      paymentUrl: _firstNonEmptyString([
        data['payment_url'],
        data['checkout_payment_url'],
        data['redirect_url'],
        source['payment_url'],
        source['checkout_payment_url'],
        source['redirect_url'],
      ]),
      rawData: data,
    );
  }

  factory OrderCreateResult.failure(String message) {
    return OrderCreateResult(success: false, errorMessage: message);
  }
}


class QuoteAcceptPayResult {
  final bool success;
  final int quoteId;
  final int pendingOrderId;
  final String status;
  final String statusLabel;
  final String paymentUrl;
  final bool canPay;
  final bool isPaid;
  final String message;
  final Map<String, dynamic> rawData;

  const QuoteAcceptPayResult({
    required this.success,
    required this.quoteId,
    required this.pendingOrderId,
    required this.status,
    required this.statusLabel,
    required this.paymentUrl,
    required this.canPay,
    required this.isPaid,
    required this.message,
    required this.rawData,
  });

  bool get hasPaymentUrl => paymentUrl.trim().isNotEmpty;

  factory QuoteAcceptPayResult.fromJson(Map<String, dynamic> json) {
    return QuoteAcceptPayResult(
      success: json['success'] != false,
      quoteId: _parseInt(json['quote_id'] ?? json['id']),
      pendingOrderId: _parseInt(json['pending_order_id'] ?? json['order_id']),
      status: (json['status'] ?? '').toString().trim(),
      statusLabel: _firstNonEmptyString([
            json['status_label'],
            json['statusLabel'],
          ]) ??
          '',
      paymentUrl: _firstNonEmptyString([
            json['payment_url'],
            json['checkout_payment_url'],
            json['redirect_url'],
          ]) ??
          '',
      canPay: json['can_pay'] == true,
      isPaid: json['is_paid'] == true,
      message: _firstNonEmptyString([json['message']]) ?? '',
      rawData: json,
    );
  }
}

class QuoteCreateResult {
  final bool success;
  final int quoteId;
  final String status;
  final double total;
  final String message;
  final Map<String, dynamic> rawData;

  const QuoteCreateResult({
    required this.success,
    required this.quoteId,
    required this.status,
    required this.total,
    required this.message,
    required this.rawData,
  });

  factory QuoteCreateResult.fromJson(Map<String, dynamic> json) {
    final quoteData = _asMap(json['quote']);
    return QuoteCreateResult(
      success: json['success'] != false,
      quoteId: _parseInt(
        json['quote_id'] ?? json['id'] ?? quoteData['id'] ?? quoteData['order_id'],
      ),
      status: (_firstNonEmptyString([
            json['status'],
            quoteData['status'],
            quoteData['order_status'],
          ]) ??
          '')
          .replaceFirst(RegExp(r'^wc-'), ''),
      total: _parseDouble(json['total'] ?? quoteData['total'] ?? quoteData['amount']),
      message: _firstNonEmptyString([json['message']]) ?? '',
      rawData: json,
    );
  }
}

class AccountDeleteRequestResult {
  final bool success;
  final String requestId;
  final bool accessBlocked;
  final bool alreadyRequested;
  final bool rgpdEmailSent;
  final bool emailRetryScheduled;
  final String message;
  final Map<String, dynamic> rawData;

  const AccountDeleteRequestResult({
    required this.success,
    required this.requestId,
    required this.accessBlocked,
    required this.alreadyRequested,
    required this.rgpdEmailSent,
    required this.emailRetryScheduled,
    required this.message,
    required this.rawData,
  });

  factory AccountDeleteRequestResult.fromJson(Map<String, dynamic> json) {
    return AccountDeleteRequestResult(
      success: json['success'] == true,
      requestId: (json['request_id'] ?? '').toString().trim(),
      accessBlocked: json['access_blocked'] == true,
      alreadyRequested: json['already_requested'] == true,
      rgpdEmailSent: json['support_email_sent'] == true || json['rgpd_email_sent'] == true,
      emailRetryScheduled: json['email_retry_scheduled'] == true,
      message: _firstNonEmptyString([json['message']]) ??
          'Solicitud de inhabilitación registrada.',
      rawData: json,
    );
  }
}


class ShippingOption {
  final String id;
  final String type;
  final String title;
  final String description;
  final bool requiresAddress;
  final String methodId;
  final String instanceId;
  final double total;
  final double tax;
  final double totalWithTax;
  final String displayTotal;

  const ShippingOption({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.requiresAddress,
    required this.methodId,
    required this.instanceId,
    required this.total,
    required this.tax,
    required this.totalWithTax,
    required this.displayTotal,
  });

  bool get isPickup => type == 'pickup' || methodId == 'local_pickup';

  factory ShippingOption.fromJson(Map<String, dynamic> json) {
    final cost = _parseDouble(json['total']);
    final tax = _parseDouble(json['tax']);
    return ShippingOption(
      id: _firstNonEmptyString([
            json['id'],
            json['rate_id'],
            json['method_rate_id'],
          ]) ??
          '',
      type: json['type']?.toString().trim() ?? 'delivery',
      title: _firstNonEmptyString([
            json['title'],
            json['label'],
            json['method_title'],
          ]) ??
          'Método de envío',
      description: json['description']?.toString().trim() ?? '',
      requiresAddress: json['requires_address'] != false,
      methodId: json['method_id']?.toString().trim() ?? '',
      instanceId: json['instance_id']?.toString().trim() ?? '',
      total: cost,
      tax: tax,
      totalWithTax: _parseDouble(json['total_with_tax'], fallback: cost + tax),
      displayTotal: json['display_total']?.toString().trim() ??
          ((cost + tax) <= 0 ? 'Gratis' : '${(cost + tax).toStringAsFixed(2)} €'),
    );
  }
}

class OrderPreviewResult {
  final String currency;
  final double subtotal;
  final double shipping;
  final double taxTotal;
  final double total;
  final double expectedTotal;
  final String cartHash;
  final String shippingHash;
  final String selectedShippingMethodId;
  final String shippingLabel;
  final String destinationLabel;
  final Map<String, dynamic> destination;
  final List<ShippingOption> shippingOptions;
  final Map<String, dynamic> rawData;

  const OrderPreviewResult({
    required this.currency,
    required this.subtotal,
    required this.shipping,
    required this.taxTotal,
    required this.total,
    required this.expectedTotal,
    required this.cartHash,
    required this.shippingHash,
    required this.selectedShippingMethodId,
    required this.shippingLabel,
    required this.destinationLabel,
    required this.destination,
    required this.shippingOptions,
    required this.rawData,
  });

  factory OrderPreviewResult.fromJson(Map<String, dynamic> json) {
    final totals = _asMap(json['totals']);
    final shipping = _asMap(json['shipping']);
    final options = _firstList([json['shipping_options']])
        .whereType<Map>()
        .map((raw) => ShippingOption.fromJson(Map<String, dynamic>.from(raw)))
        .where((option) => option.id.isNotEmpty)
        .toList();
    final total = _parseDouble(totals['total']);

    return OrderPreviewResult(
      currency: json['currency']?.toString().trim() ?? 'EUR',
      subtotal: _parseDouble(totals['subtotal']),
      shipping: _parseDouble(totals['shipping_total'] ?? totals['shipping']),
      taxTotal: _parseDouble(totals['tax_total']),
      total: total,
      expectedTotal: _parseDouble(json['expected_total'], fallback: total),
      cartHash: json['cart_hash']?.toString().trim() ?? '',
      shippingHash: json['shipping_hash']?.toString().trim() ?? '',
      selectedShippingMethodId:
          _firstNonEmptyString([
                shipping['selected_method_id'],
                shipping['selected_option_id'],
              ]) ??
              '',
      shippingLabel: shipping['label']?.toString().trim() ?? '',
      destinationLabel: json['destination_label']?.toString().trim() ?? '',
      destination: _asMap(json['destination']),
      shippingOptions: options,
      rawData: json,
    );
  }
}

class CatalogProductsResult {
  final List<Product> products;
  final int currentPage;
  final int totalPages;
  final int totalItems;

  const CatalogProductsResult({
    required this.products,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
  });

  bool get hasNextPage => currentPage < totalPages;
  bool get hasPreviousPage => currentPage > 1;

  CatalogProductsResult copyWith({
    List<Product>? products,
    int? currentPage,
    int? totalPages,
    int? totalItems,
  }) {
    return CatalogProductsResult(
      products: products ?? this.products,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      totalItems: totalItems ?? this.totalItems,
    );
  }
}

class CatalogFilterDefinition {
  final String key;
  final String title;
  final String taxonomy;
  final int attributeId;

  const CatalogFilterDefinition({
    required this.key,
    required this.title,
    required this.taxonomy,
    required this.attributeId,
  });
}

class CatalogFilterOption {
  final int id;
  final String name;
  final String slug;
  final int count;

  const CatalogFilterOption({
    required this.id,
    required this.name,
    required this.slug,
    required this.count,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'slug': slug,
        'count': count,
        'available_count': count,
      };
}

class CatalogFilterGroup {
  final String key;
  final String title;
  final String taxonomy;
  final int attributeId;
  final List<CatalogFilterOption> options;

  const CatalogFilterGroup({
    required this.key,
    required this.title,
    required this.taxonomy,
    required this.attributeId,
    required this.options,
  });
}

class _CatalogFiltersCacheEntry {
  final List<CatalogFilterGroup> groups;
  final DateTime createdAt;

  const _CatalogFiltersCacheEntry({
    required this.groups,
    required this.createdAt,
  });

  bool get isValid =>
      DateTime.now().difference(createdAt) < const Duration(minutes: 5);
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  static const String _baseUrl = 'https://www.mundicam.com';
  static const String _appNamespace = '/wp-json/mundicam-app/v1';
  static const String _filtersNamespace = '/wp-json/mundicam/v1';

  // Sensación de velocidad del buscador:
  // primera pantalla pequeña y páginas siguientes precargadas en segundo plano.
  static const int _fastSearchFirstPageSize = 10;
  static const int _fastSearchNextPageSize = 10;
  static const int _fastSearchMaxBackgroundPages = 3;

  static const String _wpSessionCookiePrefsKey = 'mundicam_wp_session_cookie';
  static const String _wpNoncePrefsKey = 'mundicam_wp_nonce';
  static const String _wpCartTokenPrefsKey = 'mundicam_wp_cart_token';
  static const String _appTokenPrefsKey = 'mundicam_app_token';
  static const String _userEmailPrefsKey = 'user_email';
  static const String _userPayloadPrefsKey = 'mundicam_app_user_payload';
  static const String _permissionsPrefsKey = 'mundicam_app_permissions_payload';
  static const String _localDeletionBlockedIdentifiersPrefsKey =
      'mundicam_local_deletion_blocked_identifiers_v1';

  late final Dio _dio;

  bool _sessionLoaded = false;
  Future<void>? _sessionLoadFuture;
  String _wpSessionCookie = '';
  String _wpNonce = '';
  String _wpCartToken = '';
  String _appToken = '';
  Map<String, dynamic> _currentUser = <String, dynamic>{};
  Map<String, dynamic> _currentPermissions = <String, dynamic>{};
  DateTime? _lastSessionContextRefresh;

  List<Map<String, dynamic>>? _cachedBrandTerms;
  final Map<String, _CatalogFiltersCacheEntry> _catalogFiltersCache = {};
  final Set<String> _backgroundSearchPrefetchRunning = <String>{};

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 18),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 18),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'MundiCam-App/1.4.6',
        },
      ),
    );
  }

  // ================================================================
  // SESIÓN WORDPRESS APP API
  // ================================================================

  Future<void> _ensureInitialized() async {
    if (_sessionLoaded) return;

    final running = _sessionLoadFuture;
    if (running != null) {
      await running;
      return;
    }

    final future = _loadWordPressSession();
    _sessionLoadFuture = future;

    try {
      await future;
    } finally {
      if (identical(_sessionLoadFuture, future)) {
        _sessionLoadFuture = null;
      }
    }
  }

  Future<void> _loadWordPressSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _wpSessionCookie = prefs.getString(_wpSessionCookiePrefsKey) ?? '';
      _wpNonce = prefs.getString(_wpNoncePrefsKey) ?? '';
      _wpCartToken = prefs.getString(_wpCartTokenPrefsKey) ?? '';
      _appToken = prefs.getString(_appTokenPrefsKey) ?? '';

      final rawUser = prefs.getString(_userPayloadPrefsKey);
      final rawPermissions = prefs.getString(_permissionsPrefsKey);

      _currentUser = _decodeStoredMap(rawUser);
      _currentPermissions = _decodeStoredMap(rawPermissions);

      if (_appToken.isEmpty && _wpCartToken.isNotEmpty) {
        // Compatibilidad con login anterior del puente: cart_token = app_token.
        _appToken = _wpCartToken;
      }

      _sessionLoaded = true;

      if (kDebugMode) {
        debugPrint(
          '✅ Sesión MundiCam App API cargada: token=${_appToken.isNotEmpty}',
        );
      }
    } catch (e) {
      _sessionLoaded = true;
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo cargar sesión App API: $e');
      }
    }
  }

  String get catalogCacheIdentity {
    final userId = _firstNonEmptyString([
          _currentUser['wordpress_id'],
          _currentUser['woocommerce_id'],
          _currentUser['id'],
        ]) ??
        'anon';

    final rolesValue = _currentUser['roles'];
    String roles = '';
    if (rolesValue is List) {
      roles = rolesValue.map((role) => role.toString()).join(',');
    } else {
      roles = _currentUser['role']?.toString() ?? '';
    }

    final normalizedRoles = _normalizeText(roles);
    final stockFlag = _currentPermissions['can_view_stock_details'] == true ||
        _currentPermissions['can_view_stock'] == true
        ? 'stock1'
        : 'stock0';

    return 'user:$userId|roles:$normalizedRoles|$stockFlag';
  }

  Future<bool> hasStoredWordPressSession() async {
    await _ensureInitialized();
    return _appToken.trim().isNotEmpty;
  }

  Future<bool> hasStoredAppSession() => hasStoredWordPressSession();

  /// Comprueba la sesión guardada contra /me.
  ///
  /// Un token presente en SharedPreferences no garantiza que siga siendo válido:
  /// puede haber caducado, haberse revocado o pertenecer a una instalación antigua.
  /// En 401/403 se limpia la sesión para evitar entrar en la app con pantallas vacías.
  /// Los fallos temporales de red no cierran la sesión.
  Future<bool> validateStoredAppSession() async {
    await _ensureInitialized();

    if (_appToken.trim().isEmpty) {
      return false;
    }

    try {
      final response = await _appGet('/me');
      final statusCode = response.statusCode ?? 0;
      final data = _responseMap(response.data);

      final valid = statusCode >= 200 &&
          statusCode < 300 &&
          data['success'] != false;

      if (!valid && (statusCode == 401 || statusCode == 403)) {
        await clearWordPressSession();
        return false;
      }

      if (valid) {
        final nestedData = _asMap(data['data']);
        final user = _userFromMeResponse(data);
        final permissions = _asMap(
          data['permissions'] ?? nestedData['permissions'],
        );
        if (user.isNotEmpty || permissions.isNotEmpty) {
          await saveWordPressSession(
            user: user,
            permissions: permissions,
          );
        }

        // /me ya ha actualizado el contexto de usuario/roles/permisos.
        // Evita repetir inmediatamente la misma petición al abrir catálogo.
        _lastSessionContextRefresh = DateTime.now();
      }

      return valid;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;

      if (statusCode == 401 || statusCode == 403) {
        if (kDebugMode) {
          debugPrint(
            '🔒 Sesión App API rechazada por el servidor ($statusCode).',
          );
        }
        await clearWordPressSession();
        return false;
      }

      // Sin conexión, timeout o error 5xx: no expulsamos al usuario. Las
      // pantallas podrán reintentar cuando vuelva la conectividad.
      if (kDebugMode) {
        debugPrint(
          '⚠️ No se pudo validar /me temporalmente. Se conserva la sesión: $e',
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Validación de sesión no concluyente. Se conserva la sesión: $e',
        );
      }
      return true;
    }
  }

  Future<Map<String, dynamic>> currentSessionUser() async {
    await _ensureInitialized();
    return Map<String, dynamic>.from(_currentUser);
  }

  Future<Map<String, dynamic>> currentSessionPermissions() async {
    await _ensureInitialized();
    return Map<String, dynamic>.from(_currentPermissions);
  }

  Future<String?> currentSessionEmail() async {
    await _ensureInitialized();

    final billing = _asMap(_currentUser['billing']);
    final candidates = <dynamic>[
      _currentUser['email'],
      _currentUser['user_email'],
      _currentUser['billing_email'],
      billing['email'],
      billing['billing_email'],
    ];

    for (final value in candidates) {
      final email = value?.toString().trim().toLowerCase() ?? '';
      if (email.isNotEmpty && email != 'null') return email;
    }

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_userEmailPrefsKey)?.trim().toLowerCase();
    if (stored != null && stored.isNotEmpty) return stored;

    return null;
  }

  Future<int?> currentSessionWordPressId() async {
    await _ensureInitialized();
    final id = _parseInt(
      _currentUser['id'] ??
          _currentUser['wordpress_id'] ??
          _currentUser['wp_id'] ??
          _currentUser['customer_id'],
    );
    return id > 0 ? id : null;
  }

  Future<List<String>> currentSessionRoles() async {
    await _ensureInitialized();
    final roles = _currentUser['roles'];
    if (roles is List) {
      return roles
          .map((role) => role.toString().trim())
          .where((role) => role.isNotEmpty)
          .toList();
    }

    final role = _currentUser['role']?.toString().trim();
    return role == null || role.isEmpty ? <String>[] : <String>[role];
  }

  /// Bloqueo local de seguridad para una cuenta que ha confirmado borrado.
  /// El PHP sigue siendo la autoridad global, pero esta lista impide reabrir
  /// la misma cuenta en esta instalación si la red falla durante la solicitud.
  Future<void> markAccountDeletionPendingLocally({
    required Iterable<String?> identifiers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = <String>{
      ...?prefs.getStringList(_localDeletionBlockedIdentifiersPrefsKey),
    };

    for (final identifier in identifiers) {
      final normalized = _normalizeAccountIdentifier(identifier);
      if (normalized.isNotEmpty) blocked.add(normalized);
    }

    if (blocked.isNotEmpty) {
      final values = blocked.toList()..sort();
      await prefs.setStringList(
        _localDeletionBlockedIdentifiersPrefsKey,
        values,
      );
    }
  }

  Future<bool> isAccountDeletionPendingLocally(String? identifier) async {
    final normalized = _normalizeAccountIdentifier(identifier);
    if (normalized.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final blocked = prefs
            .getStringList(_localDeletionBlockedIdentifiersPrefsKey)
            ?.map(_normalizeAccountIdentifier)
            .toSet() ??
        <String>{};
    return blocked.contains(normalized);
  }

  /// Limpia sesión y preferencias sin borrar la lista local de cuentas que ya
  /// confirmaron una solicitud de eliminación.
  Future<void> clearLocalAppDataPreservingDeletionBlocks() async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = prefs.getStringList(
          _localDeletionBlockedIdentifiersPrefsKey,
        ) ??
        const <String>[];

    await clearWordPressSession();
    await prefs.clear();

    if (blocked.isNotEmpty) {
      await prefs.setStringList(
        _localDeletionBlockedIdentifiersPrefsKey,
        blocked,
      );
    }
  }

  static String _normalizeAccountIdentifier(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty || normalized == 'null') return '';
    return normalized;
  }

  Map<String, dynamic> _userFromMeResponse(Map<String, dynamic> root) {
    final nestedData = _asMap(root['data']);
    final user = _asMap(root['user'] ?? nestedData['user']);
    _mergeManagerFieldsIntoUser(<String, dynamic>{...nestedData, ...root}, user);
    return user;
  }

  Future<void> refreshSessionContextFromBackend({bool force = false}) async {
    await _ensureInitialized();
    if (_appToken.trim().isEmpty) return;

    final lastRefresh = _lastSessionContextRefresh;
    if (!force &&
        lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < const Duration(seconds: 25)) {
      return;
    }

    _lastSessionContextRefresh = DateTime.now();

    try {
      final response = await _appGet('/me');
      final root = _responseMap(response.data);
      final nestedData = _asMap(root['data']);
      final user = _userFromMeResponse(root);
      final permissions = _asMap(root['permissions'] ?? nestedData['permissions']);

      var sessionChanged = false;

      if (user.isNotEmpty) {
        final oldIdentity = _sessionIdentityForCache(_currentUser, _currentPermissions);
        _currentUser = Map<String, dynamic>.from(user);
        final newIdentity = _sessionIdentityForCache(_currentUser, _currentPermissions);
        sessionChanged = sessionChanged || oldIdentity != newIdentity;
      }

      if (permissions.isNotEmpty) {
        final oldIdentity = _sessionIdentityForCache(_currentUser, _currentPermissions);
        _currentPermissions = Map<String, dynamic>.from(permissions);
        final newIdentity = _sessionIdentityForCache(_currentUser, _currentPermissions);
        sessionChanged = sessionChanged || oldIdentity != newIdentity;
      }

      final prefs = await SharedPreferences.getInstance();
      if (user.isNotEmpty) {
        await prefs.setString(_userPayloadPrefsKey, jsonEncode(_currentUser));
        final email = _currentUser['email']?.toString().trim();
        if (email != null && email.isNotEmpty) {
          await prefs.setString(_userEmailPrefsKey, email);
        }
      }
      if (permissions.isNotEmpty) {
        await prefs.setString(_permissionsPrefsKey, jsonEncode(_currentPermissions));
      }

      if (sessionChanged) {
        ProductCacheService().clearAll();
        _catalogFiltersCache.clear();
        _cachedBrandTerms = null;
        if (kDebugMode) {
          debugPrint('🧹 Caché limpiada por roles/permisos actualizados desde PHP v1.8.0');
        }
      }
    } catch (e) {
      // No bloqueamos catálogo ni login si /me falla puntualmente.
      if (kDebugMode) debugPrint('⚠️ No se pudo refrescar contexto de sesión: $e');
    }
  }

  String _sessionIdentityForCache(
    Map<String, dynamic> user,
    Map<String, dynamic> permissions,
  ) {
    final rolesValue = user['roles'];
    final roles = rolesValue is List
        ? rolesValue.map((role) => role.toString()).join(',')
        : user['role']?.toString() ?? '';
    final stockFlag = permissions['can_view_stock_details'] == true ||
            permissions['can_view_stock'] == true ||
            permissions['can_view_internal_stock'] == true
        ? 'stock1'
        : 'stock0';
    return '${user['id'] ?? user['wordpress_id'] ?? user['woocommerce_id'] ?? 'anon'}|${_normalizeText(roles)}|$stockFlag';
  }

  Future<bool?> currentSessionStockDetailsPermission() async {
    await _ensureInitialized();

    const keys = <String>[
      'can_view_stock',
      'can_view_internal_stock',
      'can_view_stock_details',
    ];

    final hasExplicitPermission =
        keys.any((key) => _currentPermissions.containsKey(key));
    if (!hasExplicitPermission) return null;

    return _currentPermissions['can_view_stock'] == true ||
        _currentPermissions['can_view_internal_stock'] == true ||
        _currentPermissions['can_view_stock_details'] == true;
  }

  Future<bool> currentSessionCanViewStockDetails() async {
    final storedPermission = await currentSessionStockDetailsPermission();
    if (storedPermission != null) {
      return storedPermission;
    }

    bool fromPermissions(Map<String, dynamic> permissions) {
      return permissions['can_view_stock'] == true ||
          permissions['can_view_internal_stock'] == true ||
          permissions['can_view_stock_details'] == true;
    }

    try {
      final me = await _loadMe();
      final permissions = _asMap(me['permissions']);
      return me['can_view_stock'] == true || fromPermissions(permissions);
    } catch (_) {
      return false;
    }
  }

  Future<void> saveWordPressSession({
    String? cookie,
    String? nonce,
    String? cartToken,
    String? appToken,
    Map<String, dynamic>? user,
    Map<String, dynamic>? permissions,
  }) async {
    final cleanCookie = _normalizeCookieHeader(cookie?.trim() ?? '');
    final cleanNonce = nonce?.trim() ?? '';
    final cleanCartToken = cartToken?.trim() ?? '';
    final cleanAppToken = appToken?.trim().isNotEmpty == true
        ? appToken!.trim()
        : cleanCartToken;

    final prefs = await SharedPreferences.getInstance();

    if (cleanCookie.isNotEmpty) {
      _wpSessionCookie = cleanCookie;
      await prefs.setString(_wpSessionCookiePrefsKey, cleanCookie);
    }

    if (cleanNonce.isNotEmpty) {
      _wpNonce = cleanNonce;
      await prefs.setString(_wpNoncePrefsKey, cleanNonce);
    }

    if (cleanCartToken.isNotEmpty) {
      _wpCartToken = cleanCartToken;
      await prefs.setString(_wpCartTokenPrefsKey, cleanCartToken);
    }

    if (cleanAppToken.isNotEmpty) {
      _appToken = cleanAppToken;
      await prefs.setString(_appTokenPrefsKey, cleanAppToken);
    }

    if (user != null && user.isNotEmpty) {
      _currentUser = Map<String, dynamic>.from(user);
      await prefs.setString(_userPayloadPrefsKey, jsonEncode(_currentUser));
      final email = _currentUser['email']?.toString().trim();
      if (email != null && email.isNotEmpty) {
        await prefs.setString(_userEmailPrefsKey, email);
      }
    }

    if (permissions != null && permissions.isNotEmpty) {
      _currentPermissions = Map<String, dynamic>.from(permissions);
      await prefs.setString(
        _permissionsPrefsKey,
        jsonEncode(_currentPermissions),
      );
    }

    _sessionLoaded = true;

    // Los precios dependen del usuario/rol WooCommerce. Si cambia la sesión,
    // no se pueden reutilizar productos cacheados de otro cliente/admin/comercial.
    ProductCacheService().clearAll();
    _catalogFiltersCache.clear();
    _cachedBrandTerms = null;

    if (kDebugMode) {
      debugPrint(
        '✅ Sesión MundiCam App API guardada: token=${_appToken.isNotEmpty}',
      );
      debugPrint('🧹 Caché de productos limpiada por cambio de sesión/rol');
    }
  }

  Future<void> saveAppSessionFromLogin(Map<String, dynamic> body) async {
    final session = _asMap(body['session']);
    final woo = _asMap(body['woocommerce']);
    final user = _asMap(body['user']);
    final permissions = _asMap(body['permissions']);

    final auth = _asMap(body['auth']);
    final tokens = _asMap(body['tokens']);
    final data = _asMap(body['data']);

    final token = _firstNonEmptyString([
      body['app_token'],
      body['appToken'],
      body['token'],
      body['access_token'],
      body['session_token'],
      body['jwt'],
      body['cart_token'],
      body['cartToken'],
      session['app_token'],
      session['appToken'],
      session['token'],
      session['cart_token'],
      session['cartToken'],
      woo['app_token'],
      woo['appToken'],
      woo['token'],
      woo['cart_token'],
      woo['cartToken'],
      auth['app_token'],
      auth['token'],
      tokens['app_token'],
      tokens['token'],
      data['app_token'],
      data['token'],
    ]);

    await saveWordPressSession(
      appToken: token,
      cartToken: token,
      user: user,
      permissions: permissions,
    );
  }


  Future<bool> registerFcmToken({
    required String token,
    required String platform,
    String? apnsToken,
  }) async {
    await _ensureInitialized();

    final cleanToken = token.trim();
    if (_appToken.trim().isEmpty || cleanToken.isEmpty) return false;

    final cleanPlatform = platform.trim().isEmpty ? 'android' : platform.trim();
    final email = await currentSessionEmail();
    final wordpressId = await currentSessionWordPressId();
    final roles = await currentSessionRoles();

    final payload = <String, dynamic>{
      'fcm_token': cleanToken,
      'token': cleanToken,
      'platform': cleanPlatform,
      if ((apnsToken ?? '').trim().isNotEmpty) 'apns_token': apnsToken!.trim(),
      if (email != null && email.isNotEmpty) 'email': email,
      if (wordpressId != null && wordpressId > 0) 'wordpress_id': wordpressId,
      if (roles.isNotEmpty) 'roles': roles,
    };

    for (final endpoint in const [
      '/fcm/register',
      '/notifications/register-device',
    ]) {
      try {
        final response = await _appPost(endpoint, data: payload);
        final data = _responseMap(response.data);
        final ok = response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300 &&
            data['success'] != false;

        if (ok) {
          if (kDebugMode) debugPrint('✅ FCM registrado en $endpoint');
          return true;
        }

        if (kDebugMode) {
          debugPrint('⚠️ FCM endpoint $endpoint respondió: ${response.data}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ registerFcmToken $endpoint: $e');
      }
    }

    return false;
  }

  Future<bool> unregisterFcmToken({
    required String token,
    required String platform,
  }) async {
    await _ensureInitialized();

    final cleanToken = token.trim();
    if (_appToken.trim().isEmpty || cleanToken.isEmpty) return false;

    final configuredEndpoint = const String.fromEnvironment(
      'MUNDICAM_FCM_UNREGISTER_PATH',
      defaultValue: '',
    ).trim();

    final endpoints = <String>[
      if (configuredEndpoint.isNotEmpty) configuredEndpoint,
      '/fcm/unregister',
      '/notifications/unregister-device',
    ];

    final payload = <String, dynamic>{
      'fcm_token': cleanToken,
      'token': cleanToken,
      'platform': platform.trim().isEmpty ? 'android' : platform.trim(),
    };

    for (final endpoint in endpoints.toSet()) {
      try {
        final response = await _appPost(endpoint, data: payload);
        final data = _responseMap(response.data);
        final ok = response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300 &&
            data['success'] != false;

        if (ok) {
          if (kDebugMode) debugPrint('✅ FCM desregistrado en $endpoint');
          return true;
        }

        if (kDebugMode) {
          debugPrint('⚠️ FCM unregister $endpoint: ${response.data}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ unregisterFcmToken $endpoint: $e');
      }
    }

    return false;
  }

  /// Llama al diagnóstico real del PHP 1.9.22.
  ///
  /// El servidor envía la prueba mediante la misma cuenta de servicio, los
  /// mismos tokens y la misma función FCM HTTP v1 usada para los pedidos.
  Future<Map<String, dynamic>> testFcmNotification() async {
    await _ensureInitialized();
    _ensureHasAppToken();

    try {
      final response = await _appPost('/fcm/test');
      return _responseMap(response.data);
    } on DioException catch (e) {
      final data = _responseMap(e.response?.data);
      final message = data['message']?.toString().trim() ?? '';

      throw Exception(
        message.isNotEmpty
            ? message
            : 'El servidor no pudo ejecutar la prueba FCM.',
      );
    }
  }

  Future<void> clearWordPressSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wpSessionCookiePrefsKey);
    await prefs.remove(_wpNoncePrefsKey);
    await prefs.remove(_wpCartTokenPrefsKey);
    await prefs.remove(_appTokenPrefsKey);
    await prefs.remove(_userPayloadPrefsKey);
    await prefs.remove(_permissionsPrefsKey);

    _wpSessionCookie = '';
    _wpNonce = '';
    _wpCartToken = '';
    _appToken = '';
    _currentUser = <String, dynamic>{};
    _currentPermissions = <String, dynamic>{};
    _sessionLoaded = true;

    ProductCacheService().clearAll();
    _catalogFiltersCache.clear();
    _cachedBrandTerms = null;

    if (kDebugMode) {
      debugPrint('🧹 Sesión MundiCam App API borrada');
    }
  }

  Options get _appOptions {
    final headers = <String, dynamic>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (_appToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_appToken';
      headers['X-MundiCam-App-Token'] = _appToken;
    }

    if (_wpSessionCookie.isNotEmpty) {
      headers['Cookie'] = _wpSessionCookie;
    }

    if (_wpNonce.isNotEmpty) {
      headers['Nonce'] = _wpNonce;
      headers['X-WP-Nonce'] = _wpNonce;
    }

    return Options(headers: headers);
  }

  Future<Response<dynamic>> _appGet(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    await _ensureInitialized();
    _ensureHasAppToken();
    return _dio.get(
      '$_appNamespace$path',
      queryParameters: _appQuery(queryParameters),
      options: _appOptions,
    );
  }

  Future<Response<dynamic>> _appPost(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    await _ensureInitialized();
    _ensureHasAppToken();
    return _dio.post(
      '$_appNamespace$path',
      data: data ?? const <String, dynamic>{},
      queryParameters: _appQuery(queryParameters),
      options: _appOptions,
    );
  }

  Map<String, dynamic> _appQuery(Map<String, dynamic>? queryParameters) {
    final query = _cleanQuery(queryParameters);

    // Seguridad: no enviamos app_token por URL para evitar exposición en logs,
    // historiales, proxies o analítica. La autenticación viaja en cabeceras
    // Authorization y X-MundiCam-App-Token.
    return query;
  }

  void _ensureHasAppToken() {
    if (_appToken.trim().isEmpty) {
      throw Exception(
        'Sesión no válida. Cierra sesión y vuelve a entrar con tu usuario.',
      );
    }
  }

  // ================================================================
  // PERFIL / CLIENTE
  // ================================================================


  Future<PasswordResetRequestResult> requestPasswordReset({
    required String email,
  }) async {
    final cleanEmail = email.trim();

    if (cleanEmail.isEmpty) {
      return PasswordResetRequestResult.failure('Introduce tu correo electrónico.');
    }

    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(cleanEmail)) {
      return PasswordResetRequestResult.failure('Introduce un correo electrónico válido.');
    }

    // 1) Endpoint propio recomendado en PHP. No requiere sesión porque el usuario
    // está recuperando acceso antes de iniciar sesión.
    final appEndpoints = <String>[
      '/auth/forgot-password',
      '/password/forgot',
      '/account/forgot-password',
      '/forgot-password',
    ];

    for (final path in appEndpoints) {
      try {
        final response = await _dio.post(
          '$_appNamespace$path',
          data: <String, dynamic>{
            'email': cleanEmail,
            'user_login': cleanEmail,
          },
          options: Options(
            headers: const <String, dynamic>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Cache-Control': 'no-store',
              'User-Agent': 'MundiCam-App/PasswordReset',
            },
            validateStatus: (status) => status != null && status < 500,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );

        final statusCode = response.statusCode ?? 0;
        if (statusCode == 404 || statusCode == 405) {
          continue;
        }

        final data = response.data;
        final body = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

        if (statusCode >= 200 && statusCode < 300 && body['success'] != false) {
          return PasswordResetRequestResult(
            success: true,
            message: _firstNonEmptyString([
                  body['message'],
                  body['data'] is Map ? (body['data'] as Map)['message'] : null,
                ]) ??
                'Si el correo está registrado, recibirás un mensaje para restablecer tu contraseña.',
            rawData: body,
          );
        }

        final message = _firstNonEmptyString([
          body['message'],
          body['error'],
          body['data'] is Map ? (body['data'] as Map)['message'] : null,
        ]);

        if (message != null && message.trim().isNotEmpty) {
          return PasswordResetRequestResult.failure(message);
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('⚠️ Endpoint app reset no disponible ($path): $error');
        }
      }
    }

    // 2) Fallback sin WebView: pedir nonce al formulario WooCommerce y hacer POST.
    // Esto evita abrir una pantalla web blanca/fea dentro de la app.
    return _requestWooCommercePasswordReset(cleanEmail);
  }

  Future<PasswordResetRequestResult> _requestWooCommercePasswordReset(
    String email,
  ) async {
    final lostPasswordPath = '/my-account/lost-password/';
    final lostPasswordUrl = '$_baseUrl$lostPasswordPath';

    try {
      final getResponse = await _dio.get<String>(
        lostPasswordUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: const <String, dynamic>{
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Cache-Control': 'no-store',
            'User-Agent': 'MundiCam-App/PasswordReset',
          },
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final html = getResponse.data ?? '';
      final nonce = _extractHtmlInputValue(
            html,
            'woocommerce-lost-password-nonce',
          ) ??
          _extractHtmlInputValue(html, '_wpnonce');

      if ((getResponse.statusCode ?? 0) >= 400 || nonce == null || nonce.isEmpty) {
        return PasswordResetRequestResult.failure(
          'No se pudo preparar la recuperación de contraseña. Inténtalo de nuevo en unos minutos.',
        );
      }

      final postResponse = await _dio.post<String>(
        lostPasswordUrl,
        data: <String, dynamic>{
          'user_login': email,
          'wc_reset_password': 'true',
          'woocommerce-lost-password-nonce': nonce,
          '_wpnonce': nonce,
          '_wp_http_referer': lostPasswordPath,
        },
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: true,
          headers: const <String, dynamic>{
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Cache-Control': 'no-store',
            'User-Agent': 'MundiCam-App/PasswordReset',
          },
          validateStatus: (status) => status != null && status < 500,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
        ),
      );

      final statusCode = postResponse.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 400) {
        return PasswordResetRequestResult.success();
      }

      return PasswordResetRequestResult.failure(
        'No se pudo enviar el correo de recuperación. Inténtalo de nuevo en unos minutos.',
      );
    } catch (error) {
      if (kDebugMode) debugPrint('⚠️ Reset WooCommerce falló: $error');
      return PasswordResetRequestResult.failure(
        'No se pudo conectar con MundiCam para recuperar la contraseña. Inténtalo de nuevo en unos minutos.',
      );
    }
  }

  String? _extractHtmlInputValue(String html, String inputName) {
    final escapedName = RegExp.escape(inputName);

    final patterns = <RegExp>[
      RegExp(
        '<input[^>]*name=["\\\']$escapedName["\\\'][^>]*value=["\\\']([^"\\\']*)["\\\'][^>]*>',
        caseSensitive: false,
      ),
      RegExp(
        '<input[^>]*value=["\\\']([^"\\\']*)["\\\'][^>]*name=["\\\']$escapedName["\\\'][^>]*>',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }

    return null;
  }

  Future<Map<String, dynamic>?> getCustomerByEmail(String email) async {
    try {
      final me = await _loadMe();
      final user = _asMap(me['user']);
      _mergeManagerFieldsIntoUser(me, user);
      if (user.isEmpty) return null;
      return _customerMapFromUser(user, _asMap(me['permissions']));
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ getCustomerByEmail: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    try {
      final me = await _loadMe();
      final user = _asMap(me['user']);
      _mergeManagerFieldsIntoUser(me, user);
      if (user.isEmpty) return null;
      final userId = _parseInt(user['id'] ?? user['wordpress_id']);
      if (id > 0 && userId > 0 && id != userId) return null;
      return _customerMapFromUser(user, _asMap(me['permissions']));
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ getCustomerById: $e');
      return null;
    }
  }

  Future<bool> canCustomerViewStockDetails(int wordpressId) async {
    try {
      final me = await _loadMe();
      final permissions = _asMap(me['permissions']);
      return me['can_view_stock'] == true ||
          permissions['can_view_stock'] == true ||
          permissions['can_view_internal_stock'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> canUserViewStockDetails(int wordpressId) {
    return canCustomerViewStockDetails(wordpressId);
  }

  Future<bool> canWordPressUserViewStockDetails(int wordpressId) {
    return canCustomerViewStockDetails(wordpressId);
  }

  Future<Map<String, dynamic>> _loadMe() async {
    final response = await _appGet('/me');
    final data = _responseMap(response.data);

    final user = _asMap(data['user']);
    final permissions = _asMap(data['permissions']);
    _mergeManagerFieldsIntoUser(data, user);

    if (user.isNotEmpty || permissions.isNotEmpty) {
      await saveWordPressSession(user: user, permissions: permissions);
    }

    return data;
  }

  // ================================================================
  // CATEGORÍAS / MARCAS
  // ================================================================

  Future<List<CategoryModel>> getCategorias({
    bool hideEmpty = false,
    bool parentOnly = false,
    int? parent,
  }) async {
    final queryParameters = <String, dynamic>{
      'hide_empty': hideEmpty ? 1 : 0,
      if (parentOnly) 'parent_only': 1,
    };
    if (parent != null) {
      queryParameters['parent'] = parent;
    }

    final response = await _appGet('/categories', queryParameters: queryParameters);

    final data = _responseMap(response.data);
    final raw = _firstList([
      data['categories'],
      data['data'],
      response.data,
    ]);

    return raw
        .whereType<Map>()
        .map((item) => CategoryModel.fromJson(Map<String, dynamic>.from(item)))
        .where((cat) => cat.id > 0 && !_isForbiddenCategory(cat.name))
        .toList();
  }

  Future<List<CategoryModel>> getSubcategoriasDe(int? parentId) async {
    if (parentId == null || parentId <= 0) return [];
    return getCategorias(parent: parentId, hideEmpty: false);
  }

  Future<List<CategoryModel>> getSubcategoriasDisponiblesCatalogo({
    required int parentCategoryId,
    int? brandId,
    String? search,
  }) async {
    final subcategorias = await getSubcategoriasDe(parentCategoryId);
    if (subcategorias.isEmpty) return [];

    final disponibles = <CategoryModel>[];
    for (final subcategoria in subcategorias) {
      try {
        final result = await getProductosCatalogoFiltrado(
          categoryId: subcategoria.id,
          brandId: brandId,
          search: search,
          page: 1,
          perPage: 1,
        );
        if (result.totalItems > 0 || result.products.isNotEmpty) {
          disponibles.add(subcategoria);
        }
      } catch (_) {}
    }
    return disponibles;
  }

  Future<List<Map<String, dynamic>>> getMarcas({
    bool hideEmpty = true,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedBrandTerms != null) {
      return _cachedBrandTerms!;
    }

    final response = await _appGet('/brands', queryParameters: {
      'hide_empty': hideEmpty ? 1 : 0,
    });

    final data = _responseMap(response.data);
    final raw = _firstList([data['brands'], data['data'], response.data]);

    final brands = raw.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return {
        'id': _parseInt(map['id']),
        'name': map['name']?.toString() ?? '',
        'slug': map['slug']?.toString() ?? '',
        'count': _parseInt(map['count']),
        'taxonomy': map['taxonomy']?.toString() ?? 'pa_marcas',
        'image': map['image']?.toString() ?? '',
      };
    }).where((item) {
      return _parseInt(item['id']) > 0 &&
          item['name'].toString().trim().isNotEmpty;
    }).toList();

    _cachedBrandTerms = brands;
    return brands;
  }

  Future<List<CategoryModel>> getCategoriasPorMarca({
    required int brandId,
    String? brandName,
    String? brandTaxonomy,
    int? parent,
    bool forceRefresh = false,
  }) async {
    if (brandId <= 0 && (brandName ?? '').trim().isEmpty) {
      return const <CategoryModel>[];
    }

    try {
      final response = await _appGet(
        '/brands/categories',
        queryParameters: <String, dynamic>{
          if (brandId > 0) 'brand_id': brandId,
          if ((brandName ?? '').trim().isNotEmpty)
            'brand_name': brandName!.trim(),
          if ((brandTaxonomy ?? '').trim().isNotEmpty)
            'brand_taxonomy': brandTaxonomy!.trim(),
          if (parent != null) 'parent': parent,
          if (forceRefresh) '_refresh': DateTime.now().millisecondsSinceEpoch,
        },
      );

      final data = _responseMap(response.data);
      final raw = _firstList([
        data['categories'],
        data['data'],
        response.data,
      ]);

      return raw
          .whereType<Map>()
          .map((item) => CategoryModel.fromJson(Map<String, dynamic>.from(item)))
          .where((category) => category.id > 0 && !_isForbiddenCategory(category.name))
          .toList();
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      if (status != 404 && status != 405) {
        rethrow;
      }

      // Compatibilidad de despliegue: si el PHP todavía no tiene el endpoint
      // 1.9.57, resolvemos solo el nivel solicitado con los endpoints existentes.
      // Es más lento, pero evita dejar la navegación de marcas rota durante una
      // actualización escalonada de Flutter/PHP.
      if (kDebugMode) {
        debugPrint('⚠️ /brands/categories no disponible, usando fallback: $error');
      }

      final candidates = parent == null
          ? await getCategorias(hideEmpty: true, parentOnly: true)
          : await getCategorias(hideEmpty: true, parent: parent);

      if (candidates.isEmpty) return const <CategoryModel>[];

      final available = <CategoryModel>[];
      for (final category in candidates) {
        try {
          final response = await _appGet(
            '/products',
            queryParameters: <String, dynamic>{
              'category': category.id,
              if (brandId > 0) 'brand_id': brandId,
              if ((brandName ?? '').trim().isNotEmpty)
                'brand_name': brandName!.trim(),
              'page': 1,
              'per_page': 1,
            },
          );
          final root = _responseMap(response.data);
          final products = _firstList([root['products'], root['data']]);
          final total = _parseInt(root['total']);
          if (total > 0 || products.isNotEmpty) {
            available.add(
              category.copyWith(
                count: total > 0 ? total : products.length,
              ),
            );
          }
        } catch (_) {
          // Un fallo puntual de una categoría no debe ocultar toda la marca.
        }
      }

      return available;
    }
  }

  Future<int?> getMarcaIdPorNombre(String? brandName) async {
    final clean = _normalizeText(brandName ?? '');
    if (clean.isEmpty) return null;

    final marcas = await getMarcas(hideEmpty: true);
    for (final marca in marcas) {
      final id = _parseInt(marca['id']);
      final name = _normalizeText(marca['name']?.toString() ?? '');
      final slug = _normalizeText(marca['slug']?.toString() ?? '');

      if (id > 0 && (name == clean || slug == clean)) {
        return id;
      }
    }

    for (final marca in marcas) {
      final id = _parseInt(marca['id']);
      final name = _normalizeText(marca['name']?.toString() ?? '');
      if (id > 0 && (name.contains(clean) || clean.contains(name))) {
        return id;
      }
    }

    return null;
  }

  Future<String?> getMarcaNombrePorId(int? brandId) async {
    if (brandId == null || brandId <= 0) return null;
    final marcas = await getMarcas(hideEmpty: true);
    for (final marca in marcas) {
      if (_parseInt(marca['id']) == brandId) {
        final name = marca['name']?.toString().trim();
        return name == null || name.isEmpty ? null : name;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getBrandsForCategory(
    int categoryId, {
    String? search,
  }) async {
    final groups = await getCatalogFiltersForCategory(
      categoryId: categoryId,
      search: search,
    );

    final fabricanteGroups = groups.where((group) {
      final normalized = _normalizeText('${group.taxonomy} ${group.title}');
      return normalized.contains('pamarcas') ||
          normalized.contains('pamarca') ||
          normalized.contains('fabricante') ||
          normalized.contains('marca');
    });

    if (fabricanteGroups.isEmpty) return [];

    return fabricanteGroups.first.options.map((option) {
      return {
        ...option.toMap(),
        'taxonomy': fabricanteGroups.first.taxonomy,
        'attribute_id': fabricanteGroups.first.attributeId,
        'source': 'mundicam_app_filters',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getMarcasDisponiblesCatalogo({
    int? categoryId,
    String? search,
  }) async {
    if (categoryId != null && categoryId > 0) {
      final brands = await getBrandsForCategory(categoryId, search: search);
      if (brands.isNotEmpty) return brands;
    }
    return getMarcas(hideEmpty: true);
  }

  // ================================================================
  // PRODUCTOS / CATÁLOGO
  // ================================================================

  Future<CatalogProductsResult> getProductosCatalogoFiltrado({
    int? categoryId,
    int? brandId,
    String? brandName,
    String? search,
    int page = 1,
    int perPage = 30,
    String? orderBy,
    Map<String, int>? attributeTermIds,
    Map<String, String>? attributeLabels,
  }) async {
    await refreshSessionContextFromBackend();

    final requestedPage = page <= 0 ? 1 : page;
    final requestedPerPage = perPage <= 0 ? 30 : perPage;
    final cleanBrandName = (brandName ?? '').trim();
    final cleanSearch = (search ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    final mappedOrderBy = _mapOrderByForApp(orderBy);

    final effectiveBrandId = brandId ?? await getMarcaIdPorNombre(brandName);

    // Si la búsqueda es amplia, no bloqueamos la pantalla esperando 60/80/100 productos.
    // Devolvemos 10 rápido y dejamos preparadas las páginas siguientes en caché.
    final useFastFirstPage = cleanSearch.isNotEmpty &&
        requestedPage == 1 &&
        requestedPerPage > _fastSearchFirstPageSize &&
        !_looksLikeSku(cleanSearch);
    final effectivePerPage = useFastFirstPage
        ? _fastSearchFirstPageSize
        : requestedPerPage;

    final cacheKey = _catalogProductsCacheKey(
      categoryId: categoryId,
      brandId: effectiveBrandId,
      brandName: cleanBrandName,
      search: cleanSearch,
      page: requestedPage,
      perPage: effectivePerPage,
      orderBy: mappedOrderBy,
      attributeTermIds: attributeTermIds,
    );

    final ttl = cleanSearch.isNotEmpty
        ? ProductCacheService.searchTtl
        : ProductCacheService.defaultTtl;

    final result = await ProductCacheService().getOrLoadMemory<CatalogProductsResult>(
      cacheKey,
      ttl: ttl,
      loader: () {
        return _requestCatalogProductsPage(
          categoryId: categoryId,
          brandId: effectiveBrandId,
          brandName: cleanBrandName,
          search: cleanSearch,
          page: requestedPage,
          perPage: effectivePerPage,
          orderBy: mappedOrderBy,
          attributeTermIds: attributeTermIds,
          attributeLabels: attributeLabels,
        );
      },
    );

    if (useFastFirstPage && result.hasNextPage) {
      _startBackgroundSearchPrefetch(
        categoryId: categoryId,
        brandId: effectiveBrandId,
        brandName: cleanBrandName,
        search: cleanSearch,
        orderBy: mappedOrderBy,
        attributeTermIds: attributeTermIds,
        attributeLabels: attributeLabels,
        startPage: 2,
      );
    }

    return result;
  }

  Future<CatalogProductsResult?> _requestContextSearchPage({
    required String search,
    required int perPage,
  }) async {
    final clean = search.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length < 2 || _looksLikeSku(clean)) return null;

    try {
      final params = <String, dynamic>{
        'search': clean,
        'q': clean,
        'per_page': perPage <= 0 ? 30 : perPage,
        'limit': perPage <= 0 ? 30 : perPage,
        'smart_search': 1,
        'search_mode': 'relevance',
        ..._buildSmartSearchParams(clean),
      };

      final response = await _appGet('/context-search', queryParameters: params);
      final result = _catalogResultFromResponse(
        response.data,
        requestedPage: 1,
        logPrefix: '✅ Context-search MundiCam',
      );

      if (result.products.isEmpty) return null;
      return _applyClientSearchRanking(
        result,
        clean,
        requestedPerPage: perPage,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Context-search no disponible para "$clean": $e');
      }
      return null;
    }
  }

  Future<CatalogProductsResult> _requestCatalogProductsPage({
    required int? categoryId,
    required int? brandId,
    required String brandName,
    required String search,
    required int page,
    required int perPage,
    required String? orderBy,
    required Map<String, int>? attributeTermIds,
    required Map<String, String>? attributeLabels,
  }) async {
    final smartSearchParams = _buildSmartSearchParams(search);
    final canUseContextSearch = search.trim().isNotEmpty &&
        !_looksLikeSku(search) &&
        page <= 1 &&
        (categoryId == null || categoryId <= 0) &&
        (brandId == null || brandId <= 0) &&
        brandName.trim().isEmpty &&
        (attributeTermIds == null || attributeTermIds.isEmpty) &&
        (orderBy == null || orderBy.trim().isEmpty);

    if (canUseContextSearch) {
      final contextResult = await _requestContextSearchPage(
        search: search,
        perPage: perPage,
      );
      if (contextResult != null && contextResult.products.isNotEmpty) {
        return contextResult;
      }
    }

    final params = <String, dynamic>{
      'page': page <= 0 ? 1 : page,
      'per_page': perPage <= 0 ? 30 : perPage,
      if (categoryId != null && categoryId > 0) 'category': categoryId,
      if (categoryId != null && categoryId > 0) 'category_id': categoryId,
      if (brandId != null && brandId > 0) 'brand_id': brandId,
      if (brandId != null && brandId > 0) 'brandId': brandId,
      if (brandName.isNotEmpty) 'brand': brandName,
      if (brandName.isNotEmpty) 'brand_name': brandName,
      if (search.isNotEmpty) 'search': search,
      if (search.isNotEmpty && _looksLikeSku(search)) 'sku': search,
      if ((orderBy ?? '').trim().isNotEmpty) 'orderby': orderBy,
      if ((orderBy ?? '').trim().isNotEmpty) 'orderBy': orderBy,
      ...smartSearchParams,
    };

    final attrPayload = _buildAttributeTermsPayload(attributeTermIds);
    if (attrPayload.isNotEmpty) {
      final encodedAttributes = jsonEncode(attrPayload);
      params['attribute_terms'] = encodedAttributes;
      params['attributeTerms'] = encodedAttributes;
    }

    final response = await _appGet('/products', queryParameters: params);
    final result = _catalogResultFromResponse(
      response.data,
      requestedPage: page,
      logPrefix: search.isNotEmpty
          ? '✅ Búsqueda rápida MundiCam App API'
          : '✅ Productos MundiCam App API',
    );

    // v1.9.65: si el usuario ha elegido un orden explícito (precio/nombre/fecha),
    // el servidor ya ha ordenado el universo completo ANTES de paginar. Reaplicar
    // relevancia aquí destruía ese orden, especialmente precio asc/desc.
    if ((orderBy ?? '').trim().isNotEmpty) {
      return result;
    }

    return _applyClientSearchRanking(
      result,
      search,
      requestedPerPage: perPage,
    );
  }

  String _catalogProductsCacheKey({
    required int? categoryId,
    required int? brandId,
    required String brandName,
    required String search,
    required int page,
    required int perPage,
    required String? orderBy,
    required Map<String, int>? attributeTermIds,
  }) {
    final attrPayload = _buildAttributeTermsPayload(attributeTermIds);
    final attrKey = attrPayload.isEmpty ? '' : jsonEncode(attrPayload);
    return [
      'api_products|$catalogCacheIdentity',
      'cat:${categoryId ?? 0}',
      'brandId:${brandId ?? 0}',
      'brand:${brandName.toLowerCase().trim()}',
      'search:${_normalizeText(search)}',
      'order:${orderBy ?? ''}',
      'attrs:$attrKey',
      'page:$page',
      'perPage:$perPage',
    ].join('|');
  }

  void _startBackgroundSearchPrefetch({
    required int? categoryId,
    required int? brandId,
    required String brandName,
    required String search,
    required String? orderBy,
    required Map<String, int>? attributeTermIds,
    required Map<String, String>? attributeLabels,
    required int startPage,
  }) {
    final cleanSearch = search.trim();
    if (cleanSearch.length < 2) return;

    final prefetchKey = [
      'prefetch',
      catalogCacheIdentity,
      categoryId ?? 0,
      brandId ?? 0,
      _normalizeText(brandName),
      _normalizeText(cleanSearch),
      orderBy ?? '',
      jsonEncode(_buildAttributeTermsPayload(attributeTermIds)),
    ].join('|');

    final cache = ProductCacheService();
    if (!cache.shouldPrewarm(prefetchKey, ttl: const Duration(seconds: 45))) {
      return;
    }
    if (_backgroundSearchPrefetchRunning.contains(prefetchKey)) return;

    _backgroundSearchPrefetchRunning.add(prefetchKey);
    cache.markPrewarmRun(prefetchKey);

    unawaited(Future<void>(() async {
      try {
        for (var page = startPage;
            page < startPage + _fastSearchMaxBackgroundPages;
            page++) {
          final cacheKey = _catalogProductsCacheKey(
            categoryId: categoryId,
            brandId: brandId,
            brandName: brandName,
            search: cleanSearch,
            page: page,
            perPage: _fastSearchNextPageSize,
            orderBy: orderBy,
            attributeTermIds: attributeTermIds,
          );

          final result = await cache.getOrLoadMemory<CatalogProductsResult>(
            cacheKey,
            ttl: ProductCacheService.searchTtl,
            loader: () {
              return _requestCatalogProductsPage(
                categoryId: categoryId,
                brandId: brandId,
                brandName: brandName,
                search: cleanSearch,
                page: page,
                perPage: _fastSearchNextPageSize,
                orderBy: orderBy,
                attributeTermIds: attributeTermIds,
                attributeLabels: attributeLabels,
              );
            },
          );

          if (kDebugMode) {
            debugPrint(
              '⚡ Precarga buscador "$cleanSearch": page=$page · ${result.products.length} productos',
            );
          }

          if (!result.hasNextPage || result.products.isEmpty) break;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Precarga buscador "$cleanSearch" cancelada: $e');
        }
      } finally {
        _backgroundSearchPrefetchRunning.remove(prefetchKey);
      }
    }));
  }


  Map<String, dynamic> _buildSmartSearchParams(String search) {
    final clean = search.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return const <String, dynamic>{};

    final tokens = _looseSearchTokens(clean);
    final brand = _knownBrandInSearch(clean);
    final cameraIntent = _queryHasCameraIntent(clean);
    final recorderIntent = _queryHasRecorderIntent(clean);

    return <String, dynamic>{
      // Parámetros que debe leer el PHP nuevo. Si el backend viejo no los
      // entiende, los ignora sin romper compatibilidad.
      'smart_search': 1,
      'search_mode': 'relevance',
      'prioritize_sku': 1,
      'include_relevance': 1,
      'stock_authority': 'woocommerce',
      'search_fields': 'sku,title,excerpt,content,brand,categories,attributes,tags',
      'token_operator': 'and_or',
      'allow_partial_tokens': 1,
      'normalize_accents': 1,
      'payload': 'card',
      'no_context_search': 1,
      'no_hydrate': 1,
      'fast': 1,
      // Alias de búsqueda para endpoints PHP con nombres distintos.
      'q': clean,
      'keyword': clean,
      'term': clean,
      's': clean,
      if (tokens.isNotEmpty) 'search_tokens': jsonEncode(tokens),
      if (tokens.isNotEmpty) 'tokens': tokens.join(','),
      if (brand != null) 'brand_guess': brand,
      if (brand != null) 'brand_name_guess': brand,
      if (cameraIntent) 'intent': 'camera',
      if (cameraIntent) 'product_intent': 'camera',
      if (recorderIntent) 'product_intent': 'recorder',
    };
  }

  CatalogProductsResult _applyClientSearchRanking(
    CatalogProductsResult result,
    String search, {
    required int requestedPerPage,
  }) {
    final clean = search.trim();
    if (clean.length < 2 || result.products.length <= 1) return result;

    final ranked = _sortSuggestionsForQuery(result.products, clean);
    final filtered = _filterWeakSearchMatches(ranked, clean);

    // Si el filtro local fuese demasiado agresivo por una respuesta especial del
    // backend, nunca dejamos la pantalla vacía: mantenemos la respuesta original
    // ordenada por relevancia local.
    final safeProducts = filtered.isEmpty ? ranked : filtered;

    return result.copyWith(products: safeProducts);
  }

  List<Product> _filterWeakSearchMatches(List<Product> products, String query) {
    if (query.trim().isEmpty) return products;

    final filtered = products
        .where((product) => _productMatchesOriginalSearchIntent(product, query))
        .toList();

    // No dejamos pantallas vacías por culpa del filtro local si el backend nuevo
    // devuelve datos con campos que no vienen en el payload reducido.
    if (filtered.isEmpty) return products;
    return filtered;
  }

  List<String> _meaningfulSearchTokens(String query) {
    const ignored = <String>{
      'camara',
      'camaras',
      'camera',
      'cameras',
      'cctv',
      'seguridad',
      'video',
      'videovigilancia',
      'ip',
      'hd',
      'wifi',
      'poe',
      'de',
      'del',
      'la',
      'el',
      'los',
      'las',
      'para',
      'con',
    };

    final rawTokens = query
        .toLowerCase()
        .split(RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ]+'));

    final tokens = <String>[];
    for (final raw in rawTokens) {
      final token = _normalizeText(raw);
      if (token.length < 2 || ignored.contains(token)) continue;
      if (!tokens.contains(token)) tokens.add(token);
    }
    return tokens;
  }

  String _productSearchHaystack(Product product) {
    final buffer = StringBuffer()
      ..write(' ')
      ..write(product.sku)
      ..write(' ')
      ..write(product.name)
      ..write(' ')
      ..write(product.brandName ?? '')
      ..write(' ')
      ..write(product.shortDescription)
      ..write(' ')
      ..write(product.categoryNames.join(' '))
      ..write(' ')
      ..write(product.categorySlugs.join(' '));

    for (final attr in product.attributes) {
      buffer
        ..write(' ')
        ..write(attr.name)
        ..write(' ')
        ..write(attr.options.join(' '));
    }

    return _normalizeText(buffer.toString());
  }

  CatalogProductsResult _catalogResultFromResponse(
    dynamic responseData, {
    required int requestedPage,
    required String logPrefix,
  }) {
    final data = _responseMap(responseData);
    final rawProducts = _firstList([
      data['products'],
      data['data'],
      data['items'],
      data['results'],
      responseData,
    ]);

    final products = rawProducts
        .whereType<Map>()
        .map((item) => Product.fromJson(Map<String, dynamic>.from(item)))
        .where((product) => product.id > 0)
        .toList();

    final total = _parseInt(
      data['total'] ?? data['total_items'] ?? data['count'],
      fallback: products.length,
    );
    final totalPages = _parseInt(
      data['total_pages'] ?? data['pages'] ?? data['max_num_pages'],
      fallback: products.isEmpty ? 1 : requestedPage,
    );
    final currentPage = _parseInt(
      data['page'] ?? data['current_page'],
      fallback: requestedPage,
    );

    if (kDebugMode) {
      debugPrint(
        '$logPrefix: ${products.length} / total=$total · page=$currentPage/$totalPages',
      );
    }

    return CatalogProductsResult(
      products: products,
      currentPage: currentPage,
      totalPages: totalPages <= 0 ? 1 : totalPages,
      totalItems: total <= 0 ? products.length : total,
    );
  }

  Future<List<Product>> getProductos({
    int? categoryId,
    int perPage = 100,
    String? brand,
    String? orderBy,
  }) async {
    final result = await getProductosCatalogoFiltrado(
      categoryId: categoryId,
      brandName: brand,
      page: 1,
      perPage: perPage,
      orderBy: orderBy,
    );
    return result.products;
  }

  Future<List<Product>> getProductosPaginado({
    int? categoryId,
    int page = 1,
    int perPage = 30,
    String? brand,
    int? brandId,
    String? search,
    String? orderBy,
  }) async {
    final result = await getProductosCatalogoFiltrado(
      categoryId: categoryId,
      brandId: brandId,
      brandName: brand,
      search: search,
      page: page,
      perPage: perPage,
      orderBy: orderBy,
    );
    return result.products;
  }

  Future<List<Product>> buscarProductosPredictivo(
    String query, {
    int limit = 12,
  }) async {
    final clean = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length < 2) return const <Product>[];

    await refreshSessionContextFromBackend();

    final perPage = limit.clamp(3, 20).toInt();

    try {
      final result = await getProductosCatalogoFiltrado(
        search: clean,
        page: 1,
        perPage: perPage,
      );
      return _sortSuggestionsForQuery(result.products, clean).take(perPage).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Predictivo rápido falló: $e');
      }
      return const <Product>[];
    }
  }

  List<String> _expandedPredictiveTerms(String query) {
    final compact = _normalizeText(query);
    final terms = <String>[];

    void add(String value) {
      final text = value.trim();
      if (text.length < 2) return;
      if (!terms.any((term) => term.toLowerCase() == text.toLowerCase())) {
        terms.add(text);
      }
    }

    if (compact.contains('dom')) {
      add('domo');
      add('dome');
      add('cámara domo');
      add('domo IP');
      add('domo HD');
    }
    if (compact.contains('turret') || compact.contains('turet')) {
      add('turret');
      add('cámara turret');
      add('eyeball');
    }
    if (compact.contains('bullet') || compact.contains('tubular')) {
      add('bullet');
      add('tubular');
      add('cámara bullet');
    }
    if (compact.contains('nvr') || compact.contains('grab')) {
      add('NVR');
      add('grabador');
      add('videograbador');
    }

    return terms;
  }

  List<String> _looseSearchTokens(String query) {
    const ignored = <String>{
      'de', 'del', 'la', 'el', 'los', 'las', 'para', 'por', 'con', 'sin',
      'un', 'una', 'unos', 'unas', 'y', 'o', 'a', 'al', 'the', 'and',
    };

    final normalized = query
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');

    final output = <String>[];
    for (final raw in normalized.split(RegExp(r'[^a-z0-9]+'))) {
      final token = raw.trim();
      if (token.length < 2 || ignored.contains(token)) continue;
      if (!output.contains(token)) output.add(token);
    }
    return output;
  }

  String? _knownBrandInSearch(String query) {
    final normalized = ' ${_looseSearchTokens(query).join(' ')} ';
    const brands = <String>[
      'dahua', 'hikvision', 'ajax', 'ksenia', 'teletek', 'mobotix',
      'hanwha', 'wisenet', 'axis', 'uniview', 'tplink', 'tp-link',
      'vigi', 'omada', 'secury360', 'evolve', 'wisim', 'zkteco',
      'anviz', 'paradox', 'satel', 'bosch', 'honeywell',
    ];

    for (final brand in brands) {
      final clean = brand.replaceAll('-', '');
      if (normalized.contains(' $brand ') || normalized.contains(' $clean ')) {
        return brand == 'tplink' ? 'TP-Link' : brand;
      }
    }
    return null;
  }

  bool _queryHasCameraIntent(String query) {
    final tokens = _looseSearchTokens(query).join(' ');
    return tokens.contains('camara') ||
        tokens.contains('camaras') ||
        tokens.contains('camera') ||
        tokens.contains('cameras') ||
        tokens.contains('cctv') ||
        tokens.contains('videovigilancia') ||
        tokens.contains('turret') ||
        tokens.contains('domo') ||
        tokens.contains('dome') ||
        tokens.contains('bullet') ||
        tokens.contains('tubular') ||
        tokens.contains('ptz') ||
        tokens.contains('ipc');
  }

  bool _queryHasRecorderIntent(String query) {
    final tokens = _looseSearchTokens(query).join(' ');
    return tokens.contains('nvr') ||
        tokens.contains('xvr') ||
        tokens.contains('dvr') ||
        tokens.contains('grabador') ||
        tokens.contains('videograbador');
  }

  bool _isCameraProduct(Product product) {
    final haystack = _productSearchHaystack(product);
    final sku = _normalizeText(product.sku);
    final name = _normalizeText(product.name);
    final categories = _normalizeText('${product.categoryNames.join(' ')} ${product.categorySlugs.join(' ')}');
    final attributes = _normalizeText(product.attributes.map((a) => '${a.name} ${a.options.join(' ')}').join(' '));
    final primary = '$sku $name $categories $attributes';

    final hasCameraSignal = primary.contains('camara') ||
        primary.contains('camera') ||
        primary.contains('cctv') ||
        primary.contains('videovigilancia') ||
        primary.contains('domo') ||
        primary.contains('dome') ||
        primary.contains('turret') ||
        primary.contains('bullet') ||
        primary.contains('tubular') ||
        primary.contains('ptz') ||
        sku.startsWith('ipc') ||
        sku.startsWith('hac') ||
        sku.contains('hdw') ||
        sku.contains('hfw') ||
        sku.contains('hdbw') ||
        attributes.contains('lente') ||
        attributes.contains('resolucion');

    if (!hasCameraSignal) return false;

    final looksLikeRecorder = haystack.contains('grabador') ||
        haystack.contains('videograbador') ||
        sku.startsWith('nvr') ||
        sku.startsWith('xvr') ||
        sku.startsWith('dvr');
    if (looksLikeRecorder &&
        !name.contains('camara') &&
        !name.contains('camera') &&
        !name.contains('domo') &&
        !name.contains('turret') &&
        !name.contains('bullet')) {
      return false;
    }

    final looksLikeAlarmOnly = haystack.contains('alarma') ||
        haystack.contains('hub') ||
        haystack.contains('detector') ||
        haystack.contains('sirena') ||
        haystack.contains('teclado');
    if (looksLikeAlarmOnly && !sku.startsWith('ipc') && !sku.startsWith('hac')) {
      return name.contains('camara') || name.contains('camera') || categories.contains('camara');
    }

    return true;
  }

  bool _productMatchesOriginalSearchIntent(Product product, String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return true;

    final rawQuery = _normalizeText(cleanQuery);
    final sku = _normalizeText(product.sku);
    if (sku.isNotEmpty && (sku == rawQuery || sku.contains(rawQuery))) return true;

    if (_queryHasCameraIntent(cleanQuery) && !_isCameraProduct(product)) {
      return false;
    }

    final brand = _knownBrandInSearch(cleanQuery);
    if (brand != null) {
      final brandNeedle = _normalizeText(brand);
      final text = _productSearchHaystack(product);
      if (!text.contains(brandNeedle)) return false;
    }

    final meaningful = _meaningfulSearchTokens(cleanQuery);
    if (meaningful.isEmpty) return true;

    final haystack = _productSearchHaystack(product);
    var hits = 0;
    for (final token in meaningful) {
      if (haystack.contains(token)) hits++;
    }

    if (meaningful.length == 1) return hits >= 1;
    return hits >= 1;
  }

  List<Product> _dedupeProductsById(Iterable<Product> products) {
    final seen = <int>{};
    final output = <Product>[];
    for (final product in products) {
      if (product.id <= 0 || seen.contains(product.id)) continue;
      seen.add(product.id);
      output.add(product);
    }
    return output;
  }

  bool _shouldRunExpandedSearch(String query, List<Product> primary) {
    if (query.trim().length < 3) return false;
    if (_looksLikeSku(query)) return false;
    if (_queryHasCameraIntent(query) && _knownBrandInSearch(query) != null) return true;
    if (primary.length < 8 && _looseSearchTokens(query).length >= 2) return true;
    return false;
  }

  List<String> _expandedSearchQueries(String query) {
    final clean = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    final brand = _knownBrandInSearch(clean);
    final tokens = _looseSearchTokens(clean);
    final queries = <String>[];

    void add(String value) {
      final q = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (q.length < 2) return;
      if (q.toLowerCase() == clean.toLowerCase()) return;
      if (!queries.any((item) => item.toLowerCase() == q.toLowerCase())) {
        queries.add(q);
      }
    }

    if (_queryHasCameraIntent(clean)) {
      if (brand != null) {
        add('$brand camara');
        add('$brand cámaras');
        add('$brand ipc');
        add('$brand turret');
        add('$brand domo');
        add('$brand bullet');
        add(brand);
      } else {
        add('camara');
        add('cámara IP');
        add('ipc');
      }
    }

    if (_queryHasRecorderIntent(clean) && brand != null) {
      add('$brand nvr');
      add('$brand grabador');
      add(brand);
    }

    for (final token in tokens) {
      if (token.length >= 4 &&
          !<String>{'camara', 'camaras', 'camera', 'cameras', 'video', 'seguridad'}.contains(token)) {
        add(token);
      }
    }

    return queries.take(7).toList();
  }

  List<Product> _sortSuggestionsForQuery(List<Product> products, String query) {
    final q = _normalizeText(query);
    final queryTokens = _looseSearchTokens(query);
    final brand = _knownBrandInSearch(query);
    final cameraIntent = _queryHasCameraIntent(query);

    int score(Product product) {
      final sku = _normalizeText(product.sku);
      final name = _normalizeText(product.name);
      final brandName = _normalizeText(product.brandName ?? '');
      final description = _normalizeText(product.shortDescription);
      final categories = _normalizeText('${product.categoryNames.join(' ')} ${product.categorySlugs.join(' ')}');
      final attributes = _normalizeText(product.attributes.map((a) => '${a.name} ${a.options.join(' ')}').join(' '));
      final text = '$sku $name $brandName $description $categories $attributes';
      var value = 0;

      if (sku.isNotEmpty && sku == q) value += 3000;
      if (sku.isNotEmpty && sku.startsWith(q)) value += 2200;
      if (sku.isNotEmpty && sku.contains(q)) value += 1700;
      if (name == q) value += 1200;
      if (name.startsWith(q)) value += 950;
      if (name.contains(q)) value += 800;

      if (brand != null) {
        final brandNeedle = _normalizeText(brand);
        if (brandName == brandNeedle) value += 850;
        if (brandName.contains(brandNeedle)) value += 700;
        if (text.contains(brandNeedle)) value += 420;
      }

      if (cameraIntent && _isCameraProduct(product)) value += 850;
      if (_queryHasRecorderIntent(query) && (sku.startsWith('nvr') || sku.startsWith('xvr') || text.contains('grabador'))) value += 750;

      for (final token in queryTokens) {
        final compactToken = _normalizeText(token);
        if (compactToken.length < 2) continue;
        if (sku.contains(compactToken)) value += 260;
        if (name.contains(compactToken)) value += 210;
        if (brandName.contains(compactToken)) value += 190;
        if (categories.contains(compactToken)) value += 130;
        if (attributes.contains(compactToken)) value += 120;
        if (description.contains(compactToken)) value += 55;
      }

      if (q.contains('dom') && (text.contains('domo') || text.contains('dome') || text.contains('minidomo'))) value += 420;
      if ((q.contains('turret') || q.contains('turet')) && text.contains('turret')) value += 420;
      if ((q.contains('bullet') || q.contains('tubular')) && (text.contains('bullet') || text.contains('tubular'))) value += 420;
      if (q.contains('ptz') && text.contains('ptz')) value += 380;
      if (q.contains('poe') && text.contains('poe')) value += 240;
      if (q.contains('wifi') && text.contains('wifi')) value += 240;

      if (product.imageUrl.trim().isNotEmpty) value += 20;
      if (product.hasStock) value += 16;
      return value;
    }

    final sorted = _dedupeProductsById(products);
    sorted.sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      if (byScore != 0) return byScore;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  Future<List<Product>> buscarProductos(String query) async {
    final clean = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return const <Product>[];

    // Respuesta rápida para chat, home y buscadores simples: primera página pequeña.
    // El resto queda precargándose desde getProductosCatalogoFiltrado().
    final primary = await getProductosCatalogoFiltrado(
      search: clean,
      page: 1,
      perPage: 12,
    );

    if (primary.products.isNotEmpty) {
      final ranked = _sortSuggestionsForQuery(primary.products, clean);
      final filtered = _filterWeakSearchMatches(ranked, clean);
      return _dedupeProductsById(filtered).take(12).toList();
    }

    // Solo si la primera búsqueda viene vacía hacemos fallback. No esperamos 7
    // búsquedas pesadas como antes: eso daba sensación de lentitud.
    if (_shouldRunExpandedSearch(clean, primary.products)) {
      for (final expandedQuery in _expandedSearchQueries(clean).take(3)) {
        try {
          final extra = await getProductosCatalogoFiltrado(
            search: expandedQuery,
            page: 1,
            perPage: 10,
          );
          if (extra.products.isNotEmpty) {
            final ranked = _sortSuggestionsForQuery(extra.products, clean);
            final filtered = _filterWeakSearchMatches(ranked, clean);
            return _dedupeProductsById(filtered).take(12).toList();
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Fallback búsqueda "$expandedQuery" falló: $e');
          }
        }
      }
    }

    return const <Product>[];
  }


  Future<List<Product>> _hydrateInternalStockDetailsIfAllowed(
    List<Product> products,
  ) async {
    if (products.isEmpty) return products;

    bool canViewStock = false;
    try {
      canViewStock = await currentSessionCanViewStockDetails();
    } catch (_) {
      canViewStock = false;
    }

    if (!canViewStock) return products;

    final hydrated = <Product>[];
    final stockCache = <int, Product?>{};

    for (final product in products) {
      if (product.hasStockLocationDetails) {
        hydrated.add(product);
        continue;
      }

      Product? fullProduct = stockCache[product.id];
      if (!stockCache.containsKey(product.id)) {
        fullProduct = await getProductoById(product.id);
        stockCache[product.id] = fullProduct;
      }

      if (fullProduct != null && fullProduct.hasStockLocationDetails) {
        // Solo copiamos stock/permisos comerciales. El precio visible se deja
        // intacto para no alterar el cálculo por rol que ya devuelve el listado.
        hydrated.add(product.copyWithStockFrom(fullProduct));
      } else {
        hydrated.add(product);
      }
    }

    return hydrated;
  }

  Future<Product?> getProductoById(int id) async {
    if (id <= 0) return null;

    try {
      final response = await _appGet('/products/$id');
      final data = _responseMap(response.data);
      final productMap = _asMap(data['product'] ?? data['data'] ?? response.data);
      if (productMap.isEmpty) return null;
      return Product.fromJson(productMap);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getProductoById($id): $e');
      return null;
    }
  }

  // ================================================================
  // FILTROS DE CATÁLOGO
  // ================================================================

  Future<List<CatalogFilterGroup>> getCatalogFiltersForCategory({
    required int categoryId,
    int? brandId,
    String? search,
    bool forceRefresh = false,
  }) async {
    if (categoryId <= 0) return [];

    final cacheKey = '$catalogCacheIdentity|cat:$categoryId|brandId:${brandId ?? 0}|search:${search?.trim().toLowerCase() ?? ''}';
    final cached = _catalogFiltersCache[cacheKey];
    if (!forceRefresh && cached != null && cached.isValid) {
      return cached.groups;
    }

    try {
      final response = await _dio.get(
        '$_filtersNamespace/catalog-filters',
        queryParameters: _cleanQuery({
          'category_id': categoryId,
          'include_subcategories': 1,
          if (brandId != null && brandId > 0) 'brand_id': brandId,
          if (brandId != null && brandId > 0) 'brandId': brandId,
          if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        }),
        options: _appOptions,
      );

      final root = _responseMap(response.data);
      final data = _asMap(root['data']);
      final rawGroups = _firstList([data['filters'], root['filters']]);
      final groups = <CatalogFilterGroup>[];

      for (final rawGroup in rawGroups.whereType<Map>()) {
        final group = Map<String, dynamic>.from(rawGroup);
        final taxonomy = group['taxonomy']?.toString().trim() ?? '';
        final options = <CatalogFilterOption>[];

        for (final rawOption in _firstList([group['options']]).whereType<Map>()) {
          final option = Map<String, dynamic>.from(rawOption);
          final id = _parseInt(option['id']);
          final name = option['name']?.toString().trim() ?? '';
          if (id <= 0 || name.isEmpty) continue;
          options.add(
            CatalogFilterOption(
              id: id,
              name: name,
              slug: option['slug']?.toString().trim() ?? '',
              count: _parseInt(option['count']),
            ),
          );
        }

        if (taxonomy.isEmpty || options.isEmpty) continue;

        groups.add(
          CatalogFilterGroup(
            key: group['key']?.toString().trim() ?? taxonomy,
            title: group['title']?.toString().trim() ?? taxonomy,
            taxonomy: taxonomy,
            attributeId: _parseInt(group['attribute_id']),
            options: options,
          ),
        );
      }

      _catalogFiltersCache[cacheKey] = _CatalogFiltersCacheEntry(
        groups: groups,
        createdAt: DateTime.now(),
      );

      return groups;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error cargando filtros catálogo: $e');
      return [];
    }
  }

  // ================================================================
  // CARRITO / PEDIDOS / PRESUPUESTOS
  // ================================================================

  Future<bool> addProductToRemoteCart({
    required int productId,
    required int quantity,
  }) async {
    try {
      final response = await _appPost('/cart/add', data: {
        'product_id': productId,
        'quantity': quantity <= 0 ? 1 : quantity,
      });
      return _responseMap(response.data)['success'] != false;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo sincronizar carrito remoto: $e');
      return false;
    }
  }


  Future<bool> clearRemoteCart() async {
    try {
      final response = await _appPost('/cart/clear');
      return _responseMap(response.data)['success'] != false;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo vaciar carrito remoto: $e');
      return false;
    }
  }


  Future<List<ShippingOption>> getShippingMethods({
    required List<Map<String, dynamic>> lineItems,
    required Map<String, dynamic> shippingAddress,
  }) async {
    final cleanItems = _sanitizeLineItems(lineItems);
    if (cleanItems.isEmpty) return <ShippingOption>[];

    try {
      final response = await _appPost('/shipping/methods', data: {
        'line_items': cleanItems,
        'shipping_address': shippingAddress,
      });
      final root = _responseMap(response.data);
      final nested = _asMap(root['data']);
      final rawOptions = _firstList([
        root['shipping_options'],
        nested['shipping_options'],
        root['methods'],
        nested['methods'],
        root['data'],
      ]);
      final options = rawOptions
          .whereType<Map>()
          .map((raw) => ShippingOption.fromJson(Map<String, dynamic>.from(raw)))
          .where((option) => option.id.isNotEmpty)
          .toList();

      if (kDebugMode) {
        final rootDestination = _asMap(root['destination']);
        final nestedDestination = _asMap(nested['destination']);
        final destination = rootDestination.isNotEmpty ? rootDestination : nestedDestination;
        debugPrint(
          '🚚 Métodos de envío recibidos: ${options.length}. Destino: $destination',
        );
      }

      return options;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudieron cargar métodos de envío: ${_mapDioError(e)}');
      return <ShippingOption>[];
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudieron cargar métodos de envío: $e');
      return <ShippingOption>[];
    }
  }

  Future<OrderPreviewResult?> previewOrder({
    required List<Map<String, dynamic>> lineItems,
    required Map<String, dynamic> shippingAddress,
    String? shippingMethodId,
  }) async {
    final cleanItems = _sanitizeLineItems(lineItems);
    if (cleanItems.isEmpty) return null;

    try {
      final response = await _appPost('/order/preview', data: {
        'line_items': cleanItems,
        'shipping_address': shippingAddress,
        if ((shippingMethodId ?? '').trim().isNotEmpty) ...{
          'shipping_method_id': shippingMethodId!.trim(),
          'shipping_option_id': shippingMethodId!.trim(),
        },
      });
      final root = _responseMap(response.data);
      final nested = _asMap(root['data']);
      final data = nested.isNotEmpty && nested.containsKey('totals') ? nested : root;
      if (data['success'] == false) return null;
      return OrderPreviewResult.fromJson(data);
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo calcular resumen de pedido: ${_mapDioError(e)}');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo calcular resumen de pedido: $e');
      return null;
    }
  }

  Future<OrderCreateResult> crearPedidoConResultado(
    Map<String, dynamic> orderData, {
    bool forceProcessingIfPending = false,
  }) async {
    try {
      final lineItems = _sanitizeLineItems(orderData['line_items']);
      if (lineItems.isEmpty) {
        return OrderCreateResult.failure('No hay productos válidos para crear el pedido.');
      }

      final enrichedOrderData =
          await MundicamAnalyticsService.instance.enrichPayload(orderData);
      final response = await _appPost('/order/create', data: {
        ...enrichedOrderData,
        'line_items': lineItems,
      });

      final data = _responseMap(response.data);
      if (data['success'] == false) {
        return OrderCreateResult.failure(
          data['message']?.toString() ?? 'No se pudo crear el pedido.',
        );
      }

      return OrderCreateResult.success(data);
    } on DioException catch (e) {
      return OrderCreateResult.failure(_mapDioError(e));
    } catch (e) {
      return OrderCreateResult.failure(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool> crearPedido(Map<String, dynamic> orderData) async {
    final result = await crearPedidoConResultado(orderData);
    return result.success;
  }

  Future<String?> getSecureCardPaymentUrl({
    required int orderId,
    required String orderKey,
  }) async {
    if (orderId <= 0 || orderKey.trim().isEmpty) return null;

    try {
      final response = await _appPost('/order/payment-url', data: {
        'order_id': orderId,
        'order_key': orderKey.trim(),
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) return null;
      return _firstNonEmptyString([
        data['payment_url'],
        data['checkout_payment_url'],
        data['redirect_url'],
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo obtener URL segura de pago: $e');
      return null;
    }
  }

  Future<bool> crearPresupuestoConProductos({
    required List<Map<String, dynamic>> items,
    String? customerNote,
    String? sourceLocalQuoteUuid,
  }) async {
    final result = await crearPresupuestoConProductosDetalle(
      items: items,
      customerNote: customerNote,
      sourceLocalQuoteUuid: sourceLocalQuoteUuid,
    );
    return result.success && result.quoteId > 0;
  }

  Future<QuoteCreateResult> crearPresupuestoConProductosDetalle({
    required List<Map<String, dynamic>> items,
    String? customerNote,
    String? sourceLocalQuoteUuid,
  }) async {
    final cleanItems = _sanitizeLineItems(items);
    if (cleanItems.isEmpty) {
      return const QuoteCreateResult(
        success: false,
        quoteId: 0,
        status: '',
        total: 0,
        message: 'No hay productos para guardar el presupuesto.',
        rawData: <String, dynamic>{},
      );
    }

    try {
      unawaited(
        MundicamAnalyticsService.instance.track(
          eventName: 'quote_started',
          value: cleanItems.length,
          metadata: <String, dynamic>{'items': cleanItems.length},
          dedupeKey: 'quote_started:${cleanItems.length}',
          dedupeWindow: const Duration(seconds: 2),
        ),
      );

      // PHP 1.9.27 mantiene un carrito de presupuesto persistente en servidor.
      // Para pasar un presupuesto LOCAL al flujo real de pago, primero se guarda
      // como presupuesto WooCommerce/YITH y después se llama a /quote/accept-and-pay.
      // Nunca se manda al carrito normal: si el usuario vuelve atrás o cancela,
      // seguirá apareciendo en Mis presupuestos.
      await _appPost('/quote/clear');

      for (final item in cleanItems) {
        final variationId = _parseInt(item['variation_id']);
        final addResponse = await _appPost('/quote/add', data: {
          'product_id': item['product_id'],
          if (variationId > 0) 'variation_id': variationId,
          'quantity': item['quantity'],
        });
        final addData = _responseMap(addResponse.data);
        if (addData['success'] == false) {
          return QuoteCreateResult(
            success: false,
            quoteId: 0,
            status: '',
            total: 0,
            message: _firstNonEmptyString([addData['message']]) ??
                'No se pudo añadir un producto al presupuesto.',
            rawData: addData,
          );
        }
      }

      final analyticsContext =
          await MundicamAnalyticsService.instance.requestContext();
      final createResponse = await _appPost('/quote/create', data: {
        if ((customerNote ?? '').trim().isNotEmpty)
          'customer_note': customerNote!.trim(),
        if ((sourceLocalQuoteUuid ?? '').trim().isNotEmpty)
          'source_local_quote_uuid': sourceLocalQuoteUuid!.trim(),
        ...analyticsContext,
      });
      final createData = _responseMap(createResponse.data);
      final result = QuoteCreateResult.fromJson(createData);
      if (kDebugMode) {
        debugPrint('✅ Presupuesto creado en servidor. ID: ${result.quoteId} · Estado: ${result.status.isEmpty ? 'sin estado' : result.status}');
        if (result.status == 'pending') {
          debugPrint('⚠️ El servidor ha devuelto pending. Comprueba que el PHP 1.9.27 esté activo.');
        }
      }
      return result;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error crearPresupuestoConProductosDetalle: $e');
      return QuoteCreateResult(
        success: false,
        quoteId: 0,
        status: '',
        total: 0,
        message: e.toString(),
        rawData: const <String, dynamic>{},
      );
    }
  }

  Future<bool> crearPresupuesto({
    required String email,
    required int productId,
    required String productName,
    required double price,
    required int quantity,
    String? customerNote,
  }) async {
    if (productId <= 0) return false;

    try {
      final addResponse = await _appPost('/quote/add', data: {
        'product_id': productId,
        'quantity': quantity <= 0 ? 1 : quantity,
      });

      final addData = _responseMap(addResponse.data);
      if (addData['success'] == false) return false;

      // El plugin mantiene un carrito de presupuesto persistente. Para que el
      // presupuesto aparezca inmediatamente en la pantalla "Presupuestos",
      // creamos la solicitud en WooCommerce/YITH justo después de añadir.
      unawaited(
        MundicamAnalyticsService.instance.track(
          eventName: 'quote_started',
          objectType: 'product',
          objectId: productId,
          value: quantity <= 0 ? 1 : quantity,
          dedupeKey: 'quote_started:$productId',
          dedupeWindow: const Duration(seconds: 2),
        ),
      );
      final analyticsContext =
          await MundicamAnalyticsService.instance.requestContext();
      final createResponse = await _appPost('/quote/create', data: {
        if ((customerNote ?? '').trim().isNotEmpty)
          'customer_note': customerNote!.trim(),
        ...analyticsContext,
      });

      final createData = _responseMap(createResponse.data);
      final quoteData = _asMap(createData['quote']);
      final status = (_firstNonEmptyString([
            createData['status'],
            quoteData['status'],
          ]) ??
          '')
          .replaceFirst(RegExp(r'^wc-'), '');
      if (kDebugMode) {
        debugPrint('✅ Presupuesto creado en servidor. Estado: ${status.isEmpty ? 'sin estado' : status}');
        if (status == 'pending') {
          debugPrint('⚠️ El servidor ha devuelto pending. Comprueba que el PHP 1.9.26 esté activo.');
        }
      }
      return createData['success'] != false;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error crearPresupuesto: $e');
      return false;
    }
  }

  Future<bool> actualizarPresupuesto({
    required String orderId,
    required int productId,
    required int quantity,
    int variationId = 0,
    int lineItemId = 0,
  }) async {
    try {
      final response = await _appPost('/quote/update', data: {
        'order_id': orderId,
        'product_id': productId,
        'variation_id': variationId,
        if (lineItemId > 0) 'line_item_id': lineItemId,
        'quantity': quantity <= 0 ? 1 : quantity,
      });
      return _responseMap(response.data)['success'] != false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> eliminarProductoPresupuesto({
    required String orderId,
    required int productId,
  }) async {
    try {
      final response = await _appPost('/quote/remove', data: {
        'product_id': productId,
      });
      return _responseMap(response.data)['success'] != false;
    } catch (_) {
      return false;
    }
  }

  Future<List<OrderMundicam>> getOrders(String customerEmail) async {
    try {
      final response = await _appGet('/orders', queryParameters: {
        'per_page': 50,
      });
      final data = _responseMap(response.data);
      final raw = _firstList([data['orders'], data['data']]);
      return raw
          .whereType<Map>()
          .map((item) => OrderMundicam.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getOrders: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getOrderStatus({
    required int orderId,
    String? orderKey,
  }) async {
    if (orderId <= 0) return null;

    try {
      final response = await _appGet('/order/status', queryParameters: {
        'order_id': orderId,
        if ((orderKey ?? '').trim().isNotEmpty) 'order_key': orderKey!.trim(),
      });
      final root = _responseMap(response.data);
      final nested = _asMap(root['data']);
      final data = nested.isNotEmpty && nested.containsKey('status') ? nested : root;
      if (data['success'] == false) return null;
      return data;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getOrderStatus: $e');
      return null;
    }
  }

  Future<OrderMundicam?> getOrderDetail({
    required int orderId,
    String? orderKey,
  }) async {
    if (orderId <= 0) return null;

    try {
      final response = await _appGet('/order/detail', queryParameters: {
        'order_id': orderId,
        if ((orderKey ?? '').trim().isNotEmpty) 'order_key': orderKey!.trim(),
      });
      final root = _responseMap(response.data);
      final nested = _asMap(root['order']);
      final data = nested.isNotEmpty ? nested : _asMap(root['data']);
      if (root['success'] == false || data.isEmpty) return null;
      return OrderMundicam.fromJson(data);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo cargar /order/detail: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getOrdenCompleta(String orderId) async {
    final cleanOrderId = orderId.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanOrderId.isEmpty) return null;

    try {
      final response = await _appGet('/order/detail', queryParameters: {
        'order_id': cleanOrderId,
      });
      final root = _responseMap(response.data);
      final nested = _asMap(root['order']);
      final data = nested.isNotEmpty ? nested : _asMap(root['data']);
      if (root['success'] != false && data.isNotEmpty) {
        return data;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo buscar detalle en /order/detail: $e');
    }

    // Para presupuestos web necesitamos las líneas de producto. /order/status
    // solo devuelve estado/importes y por eso la app podía mostrar "Sin productos"
    // aunque el presupuesto estuviera correcto en la web. Primero buscamos en
    // /quotes y /orders, que sí devuelven line_items/items; dejamos /order/status
    // como último respaldo.
    try {
      final quotesResponse = await _appGet('/quotes');
      final quotesData = _responseMap(quotesResponse.data);
      final rawQuotes = _firstList([quotesData['quotes'], quotesData['data']]);
      for (final item in rawQuotes.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final candidateId = _parseInt(
          map['id'] ?? map['order_id'] ?? map['quote_id'] ?? map['number'],
        ).toString();
        if (candidateId == cleanOrderId) {
          return map;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo buscar presupuesto completo en /quotes: $e');
    }

    try {
      final response = await _appGet('/orders', queryParameters: {'per_page': 50});
      final data = _responseMap(response.data);
      final raw = _firstList([data['orders'], data['data']]);
      for (final item in raw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        if (_parseInt(map['id']).toString() == cleanOrderId) {
          return map;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ No se pudo buscar pedido completo en /orders: $e');
    }

    final status = await getOrderStatus(orderId: _parseInt(cleanOrderId));
    if (status != null) return status;

    return null;
  }

  Future<List<QuoteMundicam>> getPresupuestosPorEmail(String email) async {
    try {
      final response = await _appGet('/quotes');
      final data = _responseMap(response.data);
      final raw = _firstList([data['quotes'], data['data']]);
      return raw
          .whereType<Map>()
          .map((item) => QuoteMundicam.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Presupuestos App API no disponibles: $e');
      return [];
    }
  }


  Future<Map<String, dynamic>> prepararPresupuestoEnCarrito({
    required int quoteId,
  }) async {
    if (quoteId <= 0) {
      throw Exception('No se pudo identificar el presupuesto.');
    }

    try {
      final response = await _appPost('/quote/prepare-cart', data: {
        'quote_id': quoteId,
      });
      final data = _responseMap(response.data);
      if (data['success'] == false || data['cart_ready'] != true) {
        throw Exception(
          data['message']?.toString() ??
              'No se pudo cargar el presupuesto en el carrito.',
        );
      }
      return data;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    }
  }

  Future<QuoteAcceptPayResult> aceptarYPagarPresupuesto({
    required int quoteId,
  }) async {
    if (quoteId <= 0) {
      throw Exception('No se pudo identificar el presupuesto.');
    }

    try {
      final response = await _appPost('/quote/accept-and-pay', data: {
        'quote_id': quoteId,
      });
      final data = _responseMap(response.data);
      final result = QuoteAcceptPayResult.fromJson(data);
      if (!result.success) {
        throw Exception(result.message.isNotEmpty
            ? result.message
            : 'No se pudo preparar el pago del presupuesto.');
      }
      return result;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    }
  }

  Future<Map<String, dynamic>> cancelarCheckoutPresupuesto({
    required int orderId,
    required String orderKey,
  }) async {
    if (orderId <= 0 || orderKey.trim().isEmpty) {
      throw Exception('No se pudo identificar el pedido que se va a cancelar.');
    }

    try {
      final response = await _appPost('/quote/cancel-checkout', data: {
        'order_id': orderId,
        'order_key': orderKey.trim(),
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw Exception(
          _firstNonEmptyString([data['message']]) ??
              'No se pudo cancelar el pedido.',
        );
      }
      return data;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    }
  }

  Future<OrderMundicam> cancelarPedido({
    required int orderId,
    required String orderKey,
  }) async {
    if (orderId <= 0 || orderKey.trim().isEmpty) {
      throw Exception('No se pudo identificar el pedido.');
    }

    try {
      final response = await _appPost('/order/cancel', data: {
        'order_id': orderId,
        'order_key': orderKey.trim(),
      });
      final data = _responseMap(response.data);
      final orderData = _asMap(data['order']);
      if (data['success'] == false || orderData.isEmpty) {
        throw Exception(
          _firstNonEmptyString([data['message']]) ??
              'No se pudo cancelar el pedido.',
        );
      }
      return OrderMundicam.fromJson(orderData);
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    }
  }

  Future<LocalQuote> devolverPresupuestoALocal({
    required int quoteId,
  }) async {
    if (quoteId <= 0) {
      throw Exception('No se pudo identificar el presupuesto.');
    }

    try {
      final response = await _appPost('/quote/return-local', data: {
        'quote_id': quoteId,
      });
      final data = _responseMap(response.data);
      final localData = _asMap(data['local_quote']);
      if (data['success'] == false || localData.isEmpty) {
        throw Exception(
          _firstNonEmptyString([data['message']]) ??
              'No se pudo devolver el presupuesto al móvil.',
        );
      }
      return LocalQuote.fromServerPayload(localData);
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    }
  }

  Future<Map<String, dynamic>> solicitarCambioDatos(
    String requestedChanges,
  ) async {
    final clean = requestedChanges.trim();
    if (clean.length < 5) {
      throw Exception('Indica qué datos necesitas modificar.');
    }

    try {
      final response = await _appPost(
        '/account/data-change-request',
        data: {
          'requested_changes': clean,
        },
      );
      final data = _responseMap(response.data);
      final message = data['message']?.toString().trim() ?? '';
      if (data['success'] != true) {
        throw Exception(
          message.isNotEmpty
              ? message
              : 'No se pudo enviar la solicitud de cambio de datos.',
        );
      }
      return data;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    }
  }

  Future<AccountDeleteRequestResult> solicitarInhabilitacionCuenta() async {
    try {
      final response = await _appPost('/account/disable-request', data: {
        'confirm': true,
      });
      final data = _responseMap(response.data);
      final result = AccountDeleteRequestResult.fromJson(data);
      final serverConfirmedBlock =
          result.accessBlocked || result.alreadyRequested;
      if (!result.success || !serverConfirmedBlock) {
        throw Exception(
          result.message.isNotEmpty
              ? result.message
              : 'El servidor no confirmó la inhabilitación de la cuenta en la app.',
        );
      }
      return result;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    }
  }

  // Compatibilidad interna con llamadas antiguas del proyecto.
  Future<AccountDeleteRequestResult> solicitarEliminacionCuenta() {
    return solicitarInhabilitacionCuenta();
  }

  // ================================================================
  // RMA / SOPORTE
  // ================================================================

  Future<Map<String, dynamic>> crearRmaDetalle({
    required String email,
    required int orderId,
    required int productId,
    int lineItemId = 0,
    int variationId = 0,
    required int quantity,
    required String motivo,
    required String descripcion,
  }) async {
    try {
      final safeQuantity = quantity < 1 ? 1 : quantity;
      final response = await _appPost('/rma', data: {
        // El servidor valida siempre la identidad real del app_token.
        // email se mantiene únicamente por compatibilidad con versiones anteriores.
        'email': email,
        'order_id': orderId,
        'product_id': productId,
        if (lineItemId > 0) 'line_item_id': lineItemId,
        if (variationId > 0) 'variation_id': variationId,
        'quantity': safeQuantity,
        'reason': motivo,
        'motivo': motivo,
        'description': descripcion,
        'descripcion': descripcion,
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        final message = data['message']?.toString().trim();
        throw Exception(message?.isNotEmpty == true ? message : 'No se pudo crear la solicitud RMA.');
      }
      if (response.statusCode != 200 && response.statusCode != 201 && data['success'] != true) {
        throw Exception('El servidor no confirmó la solicitud RMA.');
      }
      return data;
    } on DioException catch (e) {
      final message = _mapDioError(e);
      if (kDebugMode) debugPrint('❌ Error crearRmaDetalle: $message');
      throw Exception(message);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error crearRmaDetalle: $e');
      rethrow;
    }
  }

  // Compatibilidad con llamadas antiguas: por defecto solicita una unidad.
  Future<bool> crearRma({
    required String email,
    required int orderId,
    required int productId,
    int lineItemId = 0,
    int variationId = 0,
    int quantity = 1,
    required String motivo,
    required String descripcion,
  }) async {
    final data = await crearRmaDetalle(
      email: email,
      orderId: orderId,
      productId: productId,
      lineItemId: lineItemId,
      variationId: variationId,
      quantity: quantity,
      motivo: motivo,
      descripcion: descripcion,
    );
    return data['success'] != false;
  }

  Future<List<Map<String, dynamic>>> getRmaRequests(String customerEmail) async {
    try {
      final response = await _appGet('/rma', queryParameters: {
        if (customerEmail.trim().isNotEmpty) 'email': customerEmail.trim(),
      });
      final data = _responseMap(response.data);
      final raw = _firstList([data['rma'], data['requests'], data['data'], response.data]);
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on DioException catch (e) {
      final message = _mapDioError(e);
      if (kDebugMode) debugPrint('⚠️ Error getRmaRequests: $message');
      throw Exception(message);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error getRmaRequests: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getTickets(String customerEmail) async {
    try {
      final response = await _dio.get('/wp-json/wp/v2/posts', queryParameters: {
        'search': customerEmail,
        'per_page': 20,
      });
      final raw = response.data is List ? response.data as List : <dynamic>[];
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // ================================================================
  // HOME / ACADEMY / NOTICIAS
  // ================================================================

  Future<List<CourseModel>> getAcademyCourses() async {
    try {
      final response = await _dio.get('/wp-json/wp/v2/posts', queryParameters: {
        'per_page': 10,
        '_embed': 'true',
        'search': 'academy',
      });
      final raw = response.data is List ? response.data as List : <dynamic>[];
      return raw.map((post) => CourseModel.fromWordPress(post)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Noticia>> getNoticias() async {
    try {
      final response = await _dio.get('/wp-json/wp/v2/posts', queryParameters: {
        'per_page': 4,
        '_embed': 'true',
      });
      final raw = response.data is List ? response.data as List : <dynamic>[];
      return raw.map((item) => Noticia.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<BannerModel>> getBanners() async {
    try {
      final response = await _dio.get('/wp-json/mundicam/v1/banners');
      final raw = response.data is List ? response.data as List : <dynamic>[];
      return raw.map((item) => BannerModel.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  // ================================================================
  // HELPERS
  // ================================================================

  static Map<String, dynamic> _decodeStoredMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Map<String, dynamic> _responseMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic> _firstList(List<dynamic> values) {
    for (final value in values) {
      if (value is List) return value;
    }
    return <dynamic>[];
  }

  static String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final raw = value.toString().trim().replaceAll(',', '.');
    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }


  static Map<String, dynamic> _cleanQuery(Map<String, dynamic>? input) {
    final output = <String, dynamic>{};
    if (input == null) return output;
    input.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      output[key] = value;
    });
    return output;
  }

  static String _normalizeCookieHeader(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    final cookies = <String>[];
    final parts = raw.split(RegExp(r',\s*(?=[^;,]+=)'));
    for (final part in parts) {
      final firstSegment = part.split(';').first.trim();
      if (firstSegment.isEmpty || !firstSegment.contains('=')) continue;
      cookies.add(firstSegment);
    }
    return cookies.isEmpty ? raw : cookies.join('; ');
  }

  static bool _isForbiddenCategory(String value) {
    final normalized = _normalizeText(value);
    return normalized.contains('sincategoria') || normalized.contains('uncategorized');
  }

  static String _normalizeText(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static bool _looksLikeSku(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return false;

    // No tratamos frases como SKU. "dahua 6mp" o "camara ajax" son
    // búsquedas generales, aunque contengan números.
    if (RegExp(r'\s').hasMatch(raw)) return false;

    final compact = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (compact.length < 5) return false;
    if (!RegExp(r'[A-Z]').hasMatch(compact) || !RegExp(r'\d').hasMatch(compact)) {
      return false;
    }

    if (raw.contains('-') || raw.contains('_')) return true;

    const knownPrefixes = <String>[
      'IPC', 'HAC', 'NVR', 'XVR', 'DHI', 'DH', 'MC', 'PFA', 'PFM', 'PFH',
      'HIK', 'DS', 'AJ', 'AX', 'NVS', 'HDBW', 'HDW', 'TIOC', 'KIT',
    ];
    return knownPrefixes.any(compact.startsWith);
  }

  static Map<String, List<int>> _buildAttributeTermsPayload(
    Map<String, int>? attributeTermIds,
  ) {
    final payload = <String, List<int>>{};
    if (attributeTermIds == null || attributeTermIds.isEmpty) return payload;

    attributeTermIds.forEach((taxonomy, termId) {
      final cleanTaxonomy = taxonomy.trim();
      if (cleanTaxonomy.isEmpty || termId <= 0) return;
      payload.putIfAbsent(cleanTaxonomy, () => <int>[]).add(termId);
    });

    return payload;
  }

  static List<Map<String, dynamic>> _sanitizeLineItems(dynamic value) {
    final rawItems = value is List ? value : <dynamic>[];
    final items = <Map<String, dynamic>>[];

    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final productId = _parseInt(item['product_id'] ?? item['id']);
      final quantity = _parseInt(item['quantity'], fallback: 1);
      if (productId <= 0 || quantity <= 0) continue;
      items.add({
        'product_id': productId,
        'quantity': quantity,
        if (_parseInt(item['variation_id']) > 0) 'variation_id': _parseInt(item['variation_id']),
      });
    }

    return items;
  }

  static String _mapOrderByForApp(String? value) {
    final order = value?.trim().toLowerCase() ?? '';
    switch (order) {
      case 'price_low':
      case 'price_asc':
      case 'precio_asc':
        return 'price_asc';
      case 'price_high':
      case 'price_desc':
      case 'precio_desc':
        return 'price_desc';
      case 'name':
      case 'nombre':
        return 'name';
      case 'menu_order':
        return 'menu_order';
      case 'date':
        return 'date';
      default:
        // Si el usuario no ha elegido orden, no forzamos fecha desde Flutter.
        // El backend aplica el orden por defecto real de WooCommerce/web.
        return order;
    }
  }

  static void _mergeManagerFieldsIntoUser(
    Map<String, dynamic> root,
    Map<String, dynamic> user,
  ) {
    final nestedData = _asMap(root['data']);
    final rootManager = _asMap(root['manager']);
    final userManager = _asMap(user['manager']);
    final billing = _asMap(user['billing']);
    final shipping = _asMap(user['shipping']);
    final meta = user['meta_data'];
    final metaData = meta is List ? List<dynamic>.from(meta) : <dynamic>[];

    String? metaValue(String key) {
      for (final item in metaData) {
        if (item is! Map) continue;
        if (item['key']?.toString().trim().toLowerCase() != key.toLowerCase()) {
          continue;
        }
        final value = item['value']?.toString().trim() ?? '';
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return null;
    }

    String? cleanValue(dynamic value, {bool email = false}) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty || text == '—') return null;
      final lower = text.toLowerCase();
      if (lower == 'null' ||
          lower == 'false' ||
          lower == 'sin asignar' ||
          lower == 'no asignado' ||
          lower == '__mc_add_new_gestor__') {
        return null;
      }
      if (email) return text.contains('@') ? text : null;
      return text.contains('@') ? null : text;
    }

    final managerEmail = <dynamic>[
      rootManager['email'],
      userManager['email'],
      root['manager_email'],
      nestedData['manager_email'],
      user['manager_email'],
      billing['manager_email'],
      shipping['manager_email'],
      metaValue('manager_email'),
      user['assigned_manager_email'],
      user['gestor_email'],
      user['technical_manager_email'],
    ].map((value) => cleanValue(value, email: true)).firstWhere(
          (value) => value != null,
          orElse: () => null,
        );

    final managerName = <dynamic>[
      rootManager['name'],
      userManager['name'],
      root['manager_name'],
      root['wpuef_cid_c30'],
      root['gestor_asignado'],
      root['assigned_manager'],
      nestedData['manager_name'],
      nestedData['wpuef_cid_c30'],
      nestedData['gestor_asignado'],
      nestedData['assigned_manager'],
      user['manager_name'],
      user['wpuef_cid_c30'],
      user['gestor_asignado'],
      user['assigned_manager'],
      user['commercial_manager'],
      user['sales_manager'],
      metaValue('manager_name'),
      metaValue('wpuef_cid_c30'),
      metaValue('gestor_asignado'),
      metaValue('assigned_manager'),
    ].map((value) => cleanValue(value)).firstWhere(
          (value) => value != null,
          orElse: () => null,
        );

    final managerPhone = <dynamic>[
      rootManager['phone'],
      userManager['phone'],
      root['manager_phone'],
      nestedData['manager_phone'],
      user['manager_phone'],
      billing['manager_phone'],
      shipping['manager_phone'],
      metaValue('manager_phone'),
      user['assigned_manager_phone'],
      user['gestor_phone'],
    ].map((value) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') return null;
      return text;
    }).firstWhere((value) => value != null, orElse: () => null);

    bool hasMeta(String key) {
      return metaData.any((item) {
        if (item is! Map) return false;
        return item['key']?.toString().toLowerCase().trim() == key.toLowerCase();
      });
    }

    void addMeta(String key, String value) {
      if (value.trim().isEmpty || hasMeta(key)) return;
      metaData.add(<String, dynamic>{'key': key, 'value': value.trim()});
    }

    if (managerEmail != null && managerEmail.trim().isNotEmpty) {
      final email = managerEmail.trim();
      user['manager_email'] = email;
      addMeta('manager_email', email);
    }

    if (managerName != null && managerName.trim().isNotEmpty) {
      final name = managerName.trim();
      user['manager_name'] = name;
      user['wpuef_cid_c30'] = name;
      user['gestor_asignado'] = name;
      user['assigned_manager'] = name;
      addMeta('manager_name', name);
      addMeta('wpuef_cid_c30', name);
      addMeta('gestor_asignado', name);
      addMeta('assigned_manager', name);
    }

    if (managerPhone != null && managerPhone.trim().isNotEmpty) {
      final phone = managerPhone.trim();
      user['manager_phone'] = phone;
      addMeta('manager_phone', phone);
    }

    user['manager'] = <String, dynamic>{
      'name': user['manager_name']?.toString().trim() ?? '',
      'email': user['manager_email']?.toString().trim() ?? '',
      'phone': user['manager_phone']?.toString().trim() ?? '',
    };
    user['meta_data'] = metaData;
  }

  static Map<String, dynamic> _customerMapFromUser(
    Map<String, dynamic> user,
    Map<String, dynamic> permissions,
  ) {
    final billing = _asMap(user['billing']);
    final shipping = _asMap(user['shipping']);
    final metaData = <dynamic>[];

    if (user['meta_data'] is List) {
      metaData.addAll(user['meta_data'] as List);
    }

    void addMetaIfPresent(String key, List<dynamic> candidates) {
      for (final candidate in candidates) {
        final text = candidate?.toString().trim() ?? '';
        if (text.isEmpty || text.toLowerCase() == 'null') continue;
        final exists = metaData.any((item) {
          if (item is! Map) return false;
          return item['key']?.toString().toLowerCase().trim() == key.toLowerCase();
        });
        if (!exists) {
          metaData.add(<String, dynamic>{'key': key, 'value': text});
        }
        return;
      }
    }

    addMetaIfPresent('credit_limit', <dynamic>[
      user['credit_limit'],
      user['limite_credito'],
      user['limite_crediticio'],
      user['credito_limite'],
      user['customer_credit_limit'],
      permissions['credit_limit'],
    ]);
    addMetaIfPresent('credit_used', <dynamic>[
      user['credit_used'],
      user['credito_usado'],
      user['used_credit'],
      permissions['credit_used'],
    ]);
    addMetaIfPresent('credit_available', <dynamic>[
      user['credit_available'],
      user['credito_disponible'],
      user['saldo_credito'],
      permissions['credit_available'],
    ]);
    addMetaIfPresent('payment_terms_enabled', <dynamic>[
      user['payment_terms_enabled'],
      user['payment_terms_approved'],
      user['giro_activo'],
      user['giro_aprobado'],
      user['pago_aplazado_aprobado'],
      permissions['payment_terms_enabled'],
    ]);
    addMetaIfPresent('payment_method', <dynamic>[
      user['payment_method'],
      user['forma_pago'],
      user['metodo_pago'],
    ]);
    addMetaIfPresent('manager_email', <dynamic>[
      user['manager_email'],
      billing['manager_email'],
    ]);
    addMetaIfPresent('manager_phone', <dynamic>[
      user['manager_phone'],
      billing['manager_phone'],
    ]);
    addMetaIfPresent('wpuef_cid_c30', <dynamic>[
      user['wpuef_cid_c30'],
      user['manager_name'],
      user['assigned_manager'],
    ]);
    addMetaIfPresent('manager_name', <dynamic>[
      user['manager_name'],
      user['gestor_asignado'],
      user['assigned_manager'],
    ]);
    addMetaIfPresent('gestor_asignado', <dynamic>[
      user['gestor_asignado'],
      user['manager_name'],
    ]);
    addMetaIfPresent('assigned_manager', <dynamic>[
      user['assigned_manager'],
      user['manager_name'],
    ]);

    final managerEmail = _firstNonEmptyString(<dynamic>[
          user['manager_email'],
          billing['manager_email'],
        ]) ??
        '';
    final managerName = _firstNonEmptyString(<dynamic>[
          user['manager_name'],
          user['wpuef_cid_c30'],
          user['gestor_asignado'],
          user['assigned_manager'],
        ]) ??
        '';
    final managerPhone = _firstNonEmptyString(<dynamic>[
          user['manager_phone'],
          billing['manager_phone'],
        ]) ??
        '';

    return {
      'id': _parseInt(user['id'] ?? user['wordpress_id']),
      'email': user['email']?.toString() ?? billing['email']?.toString() ?? '',
      'first_name': user['first_name']?.toString() ?? billing['first_name']?.toString() ?? '',
      'last_name': user['last_name']?.toString() ?? billing['last_name']?.toString() ?? '',
      'username': user['email']?.toString() ?? '',
      'display_name': user['display_name']?.toString() ?? user['name']?.toString() ?? '',
      'role': user['role']?.toString() ?? '',
      'roles': user['roles'] is List ? user['roles'] : <dynamic>[],
      'billing': billing,
      'shipping': shipping,
      'meta_data': metaData,
      'billing_nif': user['billing_nif']?.toString() ?? billing['billing_nif']?.toString() ?? '',
      'cif_nif': user['cif_nif']?.toString() ?? billing['cif_nif']?.toString() ?? '',
      'manager_name': managerName,
      'gestor_asignado': managerName,
      'assigned_manager': managerName,
      'manager_email': managerEmail,
      'manager_phone': managerPhone,
      'wpuef_cid_c30': managerName,
      'manager': {
        'name': managerName,
        'email': managerEmail,
        'phone': managerPhone,
      },
      'can_view_stock': permissions['can_view_stock'] == true,
    };
  }

  static String _mapDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message']?.toString();
      if (message != null && message.trim().isNotEmpty) return message;
    }

    switch (e.response?.statusCode) {
      case 400:
        return 'Solicitud no válida.';
      case 401:
        return 'Sesión caducada. Vuelve a iniciar sesión.';
      case 403:
        return 'No tienes permisos para realizar esta acción.';
      case 404:
        return 'Endpoint no encontrado. Revisa que el plugin MundiCam App API esté activo.';
      case 500:
        return 'Error interno del servidor.';
      default:
        return e.message ?? 'Error de conexión.';
    }
  }
}
