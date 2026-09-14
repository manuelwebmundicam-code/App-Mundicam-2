import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

@immutable
class ForceUpdateState {
  final bool required;
  final String currentVersion;
  final String minimumVersion;
  final String title;
  final String message;
  final String buttonLabel;
  final String storeUrl;

  const ForceUpdateState({
    required this.required,
    required this.currentVersion,
    required this.minimumVersion,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.storeUrl,
  });

  const ForceUpdateState.allowed({
    this.currentVersion = '',
    this.minimumVersion = '',
  })  : required = false,
        title = '',
        message = '',
        buttonLabel = '',
        storeUrl = '';
}

/// Control de actualización mínima obligatoria de MundiCam.
///
/// IMPORTANTE:
/// - Está desactivado por defecto mediante Remote Config.
/// - La versión comercial se lee del binario instalado (p. ej. 1.6.6).
/// - El número de build (+31, +32...) se ignora deliberadamente.
/// - Si falta cualquier dato necesario para bloquear de forma segura,
///   la app NO bloquea al usuario (fail-open).
/// - No interviene en login, pedidos, precios, RMA ni notificaciones.
class ForceUpdateService {
  ForceUpdateService._();

  static final ForceUpdateService instance = ForceUpdateService._();

  static const String enabledKey = 'force_update_enabled';
  static const String minAndroidVersionKey = 'min_android_version';
  static const String minIosVersionKey = 'min_ios_version';
  static const String androidStoreUrlKey = 'android_store_url';
  static const String iosStoreUrlKey = 'ios_store_url';
  static const String titleKey = 'force_update_title';
  static const String messageKey = 'force_update_message';
  static const String buttonLabelKey = 'force_update_button_label';

  static const String _definedVersion = String.fromEnvironment(
    'MUNDICAM_APP_VERSION',
    defaultValue: '',
  );

  final ValueNotifier<ForceUpdateState> state =
      ValueNotifier<ForceUpdateState>(const ForceUpdateState.allowed());

  String _currentVersion = '';

  String get currentVersion => _currentVersion;

  Future<String> _resolveCurrentVersion() async {
    final cached = _currentVersion.trim();
    if (cached.isNotEmpty) return cached;

    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isNotEmpty) {
        _currentVersion = version;
        return version;
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo leer la versión instalada: $e');
    }

    final defined = _definedVersion.trim();
    if (defined.isNotEmpty) {
      _currentVersion = defined;
      return defined;
    }

    return '';
  }

  Future<void> evaluate(FirebaseRemoteConfig remoteConfig) async {
    try {
      final resolvedCurrentVersion = await _resolveCurrentVersion();
      if (resolvedCurrentVersion.isEmpty) {
        _allow('no se pudo determinar la versión instalada');
        return;
      }

      final enabled = remoteConfig.getBool(enabledKey);

      if (!enabled) {
        _allow('control desactivado');
        return;
      }

      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

      if (!isAndroid && !isIos) {
        _allow('plataforma no sujeta a bloqueo');
        return;
      }

      final minimumVersion = remoteConfig
          .getString(
            isIos ? minIosVersionKey : minAndroidVersionKey,
          )
          .trim();

      final storeUrl = remoteConfig
          .getString(
            isIos ? iosStoreUrlKey : androidStoreUrlKey,
          )
          .trim();

      final title = remoteConfig.getString(titleKey).trim();
      final message = remoteConfig.getString(messageKey).trim();
      final buttonLabel = remoteConfig.getString(buttonLabelKey).trim();

      // Protección anti-bloqueo accidental: para forzar actualización tienen
      // que estar configurados todos los campos necesarios en Firebase.
      if (minimumVersion.isEmpty ||
          storeUrl.isEmpty ||
          title.isEmpty ||
          message.isEmpty ||
          buttonLabel.isEmpty) {
        _allow('configuración obligatoria incompleta');
        return;
      }

      final comparison =
          _compareVersions(resolvedCurrentVersion, minimumVersion);
      if (comparison == null) {
        _allow('versión no válida');
        return;
      }

      if (comparison >= 0) {
        state.value = ForceUpdateState.allowed(
          currentVersion: resolvedCurrentVersion,
          minimumVersion: minimumVersion,
        );
        debugPrint(
          '✅ Versión MundiCam permitida: '
          '$resolvedCurrentVersion >= $minimumVersion',
        );
        return;
      }

      state.value = ForceUpdateState(
        required: true,
        currentVersion: resolvedCurrentVersion,
        minimumVersion: minimumVersion,
        title: title,
        message: message,
        buttonLabel: buttonLabel,
        storeUrl: storeUrl,
      );

      debugPrint(
        '⛔ Actualización obligatoria: '
        '$resolvedCurrentVersion < $minimumVersion',
      );
    } catch (e) {
      // Una caída de Firebase Remote Config nunca debe bloquear por error a
      // toda la base de clientes.
      _allow('error evaluando Remote Config: $e');
    }
  }

  void _allow(String reason) {
    state.value = ForceUpdateState.allowed(currentVersion: currentVersion);
    debugPrint('ℹ️ Actualización obligatoria inactiva: $reason');
  }

  int? _compareVersions(String current, String minimum) {
    final currentParts = _parseVersion(current);
    final minimumParts = _parseVersion(minimum);

    if (currentParts == null || minimumParts == null) {
      return null;
    }

    final length = currentParts.length > minimumParts.length
        ? currentParts.length
        : minimumParts.length;

    for (var i = 0; i < length; i++) {
      final currentValue = i < currentParts.length ? currentParts[i] : 0;
      final minimumValue = i < minimumParts.length ? minimumParts[i] : 0;

      if (currentValue > minimumValue) return 1;
      if (currentValue < minimumValue) return -1;
    }

    return 0;
  }

  List<int>? _parseVersion(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('v')) {
      value = value.substring(1);
    }

    // +31/+32 son builds internos y NO cambian la versión comercial mínima.
    value = value.split('+').first.split('-').first;
    if (value.isEmpty) return null;

    final parts = value.split('.');
    final parsed = <int>[];

    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null) return null;
      parsed.add(number);
    }

    return parsed.isEmpty ? null : parsed;
  }
}
