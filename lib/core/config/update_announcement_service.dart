import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/core/config/force_update_service.dart';

@immutable
class UpdateAnnouncementState {
  final bool available;
  final String currentVersion;
  final String latestVersion;
  final String title;
  final String point1;
  final String point2;
  final String point3;
  final String moreText;
  final String updateButtonLabel;
  final String laterButtonLabel;
  final String storeUrl;

  const UpdateAnnouncementState({
    required this.available,
    required this.currentVersion,
    required this.latestVersion,
    required this.title,
    required this.point1,
    required this.point2,
    required this.point3,
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
        point1 = '',
        point2 = '',
        point3 = '',
        moreText = '',
        updateButtonLabel = '',
        laterButtonLabel = '',
        storeUrl = '';
}

/// Popup informativo de nueva versión para Home.
///
/// - Es independiente del bloqueo de actualización obligatoria.
/// - Solo se activa cuando Remote Config lo indica y la versión publicada es
///   superior a la instalada.
/// - Se muestra una sola vez por versión publicada en cada instalación.
/// - Si Remote Config falla o está incompleto, no molesta al usuario (fail-open).
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

  static const String _seenPrefix = 'mundicam_update_announcement_seen_';

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
        _clear('sin versión instalada');
        return;
      }

      if (!remoteConfig.getBool(enabledKey)) {
        _clear('aviso desactivado', currentVersion: currentVersion);
        return;
      }

      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

      if (!isAndroid && !isIos) {
        _clear('plataforma no compatible', currentVersion: currentVersion);
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
      final point1 = remoteConfig.getString(point1Key).trim();
      final point2 = remoteConfig.getString(point2Key).trim();
      final point3 = remoteConfig.getString(point3Key).trim();
      final moreText = remoteConfig.getString(moreTextKey).trim();
      final updateButtonLabel =
          remoteConfig.getString(updateButtonLabelKey).trim();
      final laterButtonLabel =
          remoteConfig.getString(laterButtonLabelKey).trim();

      // Para evitar popups incompletos, solo se activa cuando todo lo necesario
      // está configurado de forma explícita en Firebase.
      if (latestVersion.isEmpty ||
          storeUrl.isEmpty ||
          title.isEmpty ||
          point1.isEmpty ||
          point2.isEmpty ||
          point3.isEmpty ||
          moreText.isEmpty ||
          updateButtonLabel.isEmpty ||
          laterButtonLabel.isEmpty) {
        _clear(
          'configuración incompleta',
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
        return;
      }

      final comparison = _compareVersions(currentVersion, latestVersion);
      if (comparison == null || comparison >= 0) {
        _clear(
          comparison == null ? 'versión no válida' : 'app ya actualizada',
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
        return;
      }

      state.value = UpdateAnnouncementState(
        available: true,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        title: title,
        point1: point1,
        point2: point2,
        point3: point3,
        moreText: moreText,
        updateButtonLabel: updateButtonLabel,
        laterButtonLabel: laterButtonLabel,
        storeUrl: storeUrl,
      );

      debugPrint(
        '⬆️ Nueva versión disponible: $currentVersion < $latestVersion',
      );
    } catch (e) {
      _clear('error evaluando aviso: $e');
    }
  }

  Future<bool> wasSeen(String latestVersion) async {
    final version = latestVersion.trim();
    if (version.isEmpty) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_seenPrefix$version') ?? false;
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el estado del aviso: $e');
      return false;
    }
  }

  Future<void> markSeen(String latestVersion) async {
    final version = latestVersion.trim();
    if (version.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_seenPrefix$version', true);
    } catch (e) {
      debugPrint('⚠️ No se pudo guardar el estado del aviso: $e');
    }
  }

  void _clear(
    String reason, {
    String currentVersion = '',
    String latestVersion = '',
  }) {
    state.value = UpdateAnnouncementState.none(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
    );
    debugPrint('ℹ️ Aviso de nueva versión inactivo: $reason');
  }

  int? _compareVersions(String current, String latest) {
    final currentParts = _parseVersion(current);
    final latestParts = _parseVersion(latest);

    if (currentParts == null || latestParts == null) return null;

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
