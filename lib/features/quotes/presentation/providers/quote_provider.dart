import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/quotes/data/models/quote_model.dart';

/// Provider para el servicio API.
/// Se usa desde presupuestos y también desde pantallas que añaden productos al presupuesto.
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

/// Provider global para presupuestos ocultos temporalmente en la app.
/// Sirve para ocultar un presupuesto aceptado/eliminado sin esperar otra recarga.
final hiddenQuoteIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

/// Obtiene el email profesional del usuario actual.
/// Prioridad:
/// 1. Firestore users/{uid}.email
/// 2. FirebaseAuth.currentUser.email
/// 3. providerData.first.email
Future<String?> _resolveCurrentUserEmail() async {
  final apiEmail = await ApiService().currentSessionEmail();
  if (apiEmail != null && apiEmail.trim().isNotEmpty) {
    return apiEmail.trim().toLowerCase();
  }

  // Respaldo local sin realizar una lectura de red a Firestore.
  final user = FirebaseAuth.instance.currentUser;
  final fallback = user?.email ?? user?.providerData.firstOrNull?.email;
  final clean = fallback?.trim().toLowerCase() ?? '';

  if (clean.isEmpty) {
    if (kDebugMode) {
      debugPrint('[QUOTES] Email de sesión no disponible | END');
    }
    return null;
  }

  return clean;
}

/// Provider auxiliar con el email del usuario actual.
/// Puede usarse en futuras pantallas si necesitamos saber para quién se gestiona el presupuesto.
final currentQuoteEmailProvider = FutureProvider<String?>((ref) async {
  return _resolveCurrentUserEmail();
});

/// Provider que obtiene los presupuestos del usuario.
/// La lógica real de WooCommerce está en ApiService:
/// - getPresupuestosPorEmail(email)
/// - crearPresupuesto(...)
/// - actualizarPresupuesto(...)
/// - eliminarProductoPresupuesto(...)
final quotesProvider = FutureProvider<List<QuoteMundicam>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  final email = await _resolveCurrentUserEmail();

  if (email == null || email.isEmpty) {
    return [];
  }

  if (kDebugMode) {
    debugPrint(
      '[QUOTES] Buscando para email="$email" | length=${email.length} | END',
    );
  }

  try {
    final presupuestos = await apiService.getPresupuestosPorEmail(email);

    /// Nos quedamos con presupuestos útiles para la app.
    /// Si en el futuro WooCommerce devuelve otros estados, evitamos mostrar pedidos reales como presupuestos.
    final filtered = presupuestos.where((quote) {
      final status = quote.status.toLowerCase().trim();

      if (status.isEmpty) return true;

      return status == 'checkout-draft' ||
          status == 'pending' ||
          status == 'on-hold' ||
          status == 'presupuesto';
    }).toList();

    if (kDebugMode) {
      debugPrint('[QUOTES] Encontrados=${filtered.length} | END');
    }

    return filtered;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[QUOTES] Error cargando presupuestos: $e | END');
    }
    rethrow;
  }
});

/// Presupuestos visibles, quitando los que el usuario ha ocultado temporalmente.
final visibleQuotesProvider = Provider<AsyncValue<List<QuoteMundicam>>>((ref) {
  final quotesAsync = ref.watch(quotesProvider);
  final hiddenIds = ref.watch(hiddenQuoteIdsProvider);

  return quotesAsync.whenData((quotes) {
    return quotes.where((quote) => !hiddenIds.contains(quote.id)).toList();
  });
});

/// Número de presupuestos visibles para el badge inferior.
final visibleQuotesCountProvider = Provider<int>((ref) {
  final visibleQuotesAsync = ref.watch(visibleQuotesProvider);

  return visibleQuotesAsync.maybeWhen(
    data: (quotes) => quotes.length,
    orElse: () => 0,
  );
});

/// Número total de productos dentro de los presupuestos visibles.
/// Si el modelo todavía no trae line_items completos, devuelve 0 hasta que se carguen desde QuotesPage.
final visibleQuotesProductsCountProvider = Provider<int>((ref) {
  final visibleQuotesAsync = ref.watch(visibleQuotesProvider);

  return visibleQuotesAsync.maybeWhen(
    data: (quotes) {
      return quotes.fold<int>(
        0,
            (total, quote) => total + 1,
      );
    },
    orElse: () => 0,
  );
});

/// Total económico de todos los presupuestos visibles.
/// Usa displayTotal si el modelo lo tiene calculado.
final visibleQuotesTotalProvider = Provider<double>((ref) {
  final visibleQuotesAsync = ref.watch(visibleQuotesProvider);

  return visibleQuotesAsync.maybeWhen(
    data: (quotes) {
      return quotes.fold<double>(
        0,
            (total, quote) => total + quote.total,
      );
    },
    orElse: () => 0,
  );
});

/// Limpia presupuestos ocultos y fuerza recarga.
void refreshQuotes(WidgetRef ref) {
  ref.read(hiddenQuoteIdsProvider.notifier).state = <String>{};
  ref.invalidate(quotesProvider);
}