import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:mundicam/core/config/force_update_service.dart';

@immutable
class UpdateAnnouncementState {
  final bool available;
  final String currentVersion;
  final String latestVersion;
  final String title;
  final List<String> points;
  final String moreText;
  final String updateButtonLabel;
  final String laterButtonLabel;
  final String storeUrl;

  const UpdateAnnouncementState({
    required this.available,
    required this.currentVersion,
    required this.latestVersion,
    required this.title,
    required this.points,
    required this.moreText,
    required this.updateButtonLabel,
    required this.laterButtonLabel,
    required this.storeUrl,
  });

  const UpdateAnnouncementState.none({
    this.currentVersion = '',
    this.latestVersion = '',
  })  : available = false,
        title = '',
        points = const <String>[],
        moreText = '',
        updateButtonLabel = '',
        laterButtonLabel = '',
        storeUrl = '';
}

/// Aviso OPCIONAL de nueva versión.
///
/// Reglas:
/// - Si la versión instalada es igual o superior a latest_*: no muestra nada.
/// - Si es inferior a latest_* pero sigue permitida por min_*: muestra aviso.
/// - El bloqueo obligatorio sigue perteneciendo exclusivamente a
///   ForceUpdateService.
/// - Si Remote Config está incompleto o falla, no molesta al usuario.
class UpdateAnnouncementService {
  UpdateAnnouncementService._();

  static final UpdateAnnouncementService instance =
      UpdateAnnouncementService._();

  static const String enabledKey = 'update_announcement_enabled';
  static const String latestAndroidVersionKey = 'latest_android_version';
  static const String latestIosVersionKey = 'latest_ios_version';
  static const String titleKey = 'update_announcement_title';
  static const String point1Key = 'update_announcement_point_1';
  static const String point2Key = 'update_announcement_point_2';
  static const String point3Key = 'update_announcement_point_3';
  static const String moreTextKey = 'update_announcement_more_text';
  static const String updateButtonLabelKey =
      'update_announcement_update_button_label';
  static const String laterButtonLabelKey =
      'update_announcement_later_button_label';

  final ValueNotifier<UpdateAnnouncementState> state =
      ValueNotifier<UpdateAnnouncementState>(
    const UpdateAnnouncementState.none(),
  );

  String _currentVersion = '';

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
      debugPrint('⚠️ No se pudo leer la versión para el aviso: $e');
    }

    return '';
  }

  Future<void> evaluate(FirebaseRemoteConfig remoteConfig) async {
    try {
      final currentVersion = await _resolveCurrentVersion();
      if (currentVersion.isEmpty) {
        _clear('no se pudo determinar la versión instalada');
        return;
      }

      if (!remoteConfig.getBool(enabledKey)) {
        _clear('aviso opcional desactivado');
        return;
      }

      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

      if (!isAndroid && !isIos) {
        _clear('plataforma no sujeta al aviso');
        return;
      }

      final latestVersion = remoteConfig
          .getString(
            isIos ? latestIosVersionKey : latestAndroidVersionKey,
          )
          .trim();

      final storeUrl = remoteConfig
          .getString(
            isIos
                ? ForceUpdateService.iosStoreUrlKey
                : ForceUpdateService.androidStoreUrlKey,
          )
          .trim();

      final title = remoteConfig.getString(titleKey).trim();
      final updateButtonLabel =
          remoteConfig.getString(updateButtonLabelKey).trim();
      final laterButtonLabel =
          remoteConfig.getString(laterButtonLabelKey).trim();

      // Estos campos son los mínimos necesarios para un aviso utilizable.
      if (latestVersion.isEmpty ||
          storeUrl.isEmpty ||
          title.isEmpty ||
          updateButtonLabel.isEmpty ||
          laterButtonLabel.isEmpty) {
        _clear('configuración del aviso incompleta');
        return;
      }

      final comparison = _compareVersions(currentVersion, latestVersion);
      if (comparison == null) {
        _clear('versión no válida');
        return;
      }

      if (comparison >= 0) {
        state.value = UpdateAnnouncementState.none(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
        debugPrint(
          '✅ Sin aviso opcional: $currentVersion >= $latestVersion',
        );
        return;
      }

      final points = <String>[
        remoteConfig.getString(point1Key).trim(),
        remoteConfig.getString(point2Key).trim(),
        remoteConfig.getString(point3Key).trim(),
      ].where((value) => value.isNotEmpty).toList(growable: false);

      state.value = UpdateAnnouncementState(
        available: true,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        title: title,
        points: points,
        moreText: remoteConfig.getString(moreTextKey).trim(),
        updateButtonLabel: updateButtonLabel,
        laterButtonLabel: laterButtonLabel,
        storeUrl: storeUrl,
      );

      debugPrint(
        'ℹ️ Nueva versión disponible: $currentVersion < $latestVersion',
      );
    } catch (e) {
      _clear('error evaluando el aviso opcional: $e');
    }
  }

  void _clear(String reason) {
    state.value = UpdateAnnouncementState.none(
      currentVersion: _currentVersion,
    );
    debugPrint('ℹ️ Aviso opcional inactivo: $reason');
  }

  int? _compareVersions(String current, String latest) {
    final currentParts = _parseVersion(current);
    final latestParts = _parseVersion(latest);

    if (currentParts == null || latestParts == null) {
      return null;
    }

    final length = currentParts.length > latestParts.length
        ? currentParts.length
        : latestParts.length;

    for (var i = 0; i < length; i++) {
      final currentValue = i < currentParts.length ? currentParts[i] : 0;
      final latestValue = i < latestParts.length ? latestParts[i] : 0;

      if (currentValue > latestValue) return 1;
      if (currentValue < latestValue) return -1;
    }

    return 0;
  }

  List<int>? _parseVersion(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('v')) {
      value = value.substring(1);
    }

    // El build (+44, +45...) no cambia la versión comercial.
    value = value.split('+').first.split('-').first;
    if (value.isEmpty) return null;

    final parsed = <int>[];
    for (final part in value.split('.')) {
      final number = int.tryParse(part);
      if (number == null) return null;
      parsed.add(number);
    }

    return parsed.isEmpty ? null : parsed;
  }
}
