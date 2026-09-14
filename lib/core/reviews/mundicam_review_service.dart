import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';

enum MundicamReviewTrigger {
  orderCompleted,
  quoteCompleted,
}

/// Solicita una valoración nativa de App Store / Google Play únicamente tras
/// hitos positivos reales de la app.
///
/// Es deliberadamente no crítico: cualquier fallo, indisponibilidad o cuota de
/// la tienda se ignora y nunca altera pedidos, presupuestos, pagos ni navegación.
class MundicamReviewService {
  MundicamReviewService._();

  static final MundicamReviewService instance = MundicamReviewService._();

  static const String _lastAttemptAtKey =
      'mundicam_in_app_review_last_attempt_at_v1';
  static const Duration _cooldown = Duration(days: 120);

  bool _requestInProgress = false;

  Future<void> requestIfEligible({
    required MundicamReviewTrigger trigger,
  }) async {
    if (_requestInProgress) return;
    _requestInProgress = true;

    final triggerName = trigger == MundicamReviewTrigger.orderCompleted
        ? 'order_completed'
        : 'quote_completed';

    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final lastAttemptMs = prefs.getInt(_lastAttemptAtKey) ?? 0;

      if (lastAttemptMs > 0) {
        final lastAttempt =
            DateTime.fromMillisecondsSinceEpoch(lastAttemptMs);
        final elapsed = now.difference(lastAttempt);
        if (!elapsed.isNegative && elapsed < _cooldown) {
          await _track(
            'review_prompt_suppressed',
            triggerName,
            <String, dynamic>{
              'reason': 'local_cooldown',
              'days_since_last_attempt': elapsed.inDays,
              'cooldown_days': _cooldown.inDays,
            },
          );
          return;
        }
      }

      final review = InAppReview.instance;
      final available = await review.isAvailable();
      if (!available) {
        await _track(
          'review_prompt_unavailable',
          triggerName,
          const <String, dynamic>{'reason': 'store_api_unavailable'},
        );
        return;
      }

      String appVersion = '';
      String buildNumber = '';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = info.version;
        buildNumber = info.buildNumber;
      } catch (_) {
        // La versión es informativa para analítica; nunca bloquea la valoración.
      }

      await _track(
        'review_prompt_requested',
        triggerName,
        <String, dynamic>{
          if (appVersion.isNotEmpty) 'app_version': appVersion,
          if (buildNumber.isNotEmpty) 'build_number': buildNumber,
        },
      );

      await review.requestReview();

      // Las APIs oficiales no confirman si el usuario vio o envió la valoración.
      // Guardamos el intento únicamente después de que la llamada haya terminado
      // sin excepción, para no acosar al usuario con solicitudes repetidas.
      await prefs.setInt(_lastAttemptAtKey, now.millisecondsSinceEpoch);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ Valoración in-app omitida (no crítica): $error');
      }
      await _track(
        'review_prompt_error',
        triggerName,
        <String, dynamic>{'error': error.runtimeType.toString()},
      );
    } finally {
      _requestInProgress = false;
    }
  }

  Future<void> _track(
    String eventName,
    String triggerName,
    Map<String, dynamic> metadata,
  ) async {
    try {
      await MundicamAnalyticsService.instance.track(
        eventName: eventName,
        objectType: 'app_review',
        metadata: <String, dynamic>{
          'trigger': triggerName,
          ...metadata,
        },
      );
    } catch (_) {
      // La analítica tampoco puede afectar al flujo comercial.
    }
  }
}
