import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/quotes/data/models/quote_model.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';

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
  if (apiEmail != null && apiEmail.isNotEmpty) {
    return apiEmail;
  }

  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    debugPrint('❌ No hay usuario Firebase y la sesión App API no tiene email');
    return null;
  }

  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data();
      final email = data?['email']?.toString().trim();

      if (email != null && email.isNotEmpty) {
        return email;
      }
    }
  } catch (e) {
    debugPrint('⚠️ Error al leer email de Firestore: $e');
  }

  final authEmail = user.email?.trim();

  if (authEmail != null && authEmail.isNotEmpty) {
    return authEmail;
  }

  if (user.providerData.isNotEmpty) {
    final providerEmail = user.providerData.first.email?.trim();

    if (providerEmail != null && providerEmail.isNotEmpty) {
      return providerEmail;
    }
  }

  debugPrint('❌ No se encontró email para buscar presupuestos');
  return null;
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

  debugPrint('🔍 Buscando presupuestos para: $email');

  try {
    final presupuestos = await apiService.getPresupuestosPorEmail(email);

    // /orders solo devuelve pedidos procedentes de presupuestos cuando ya están
    // confirmados. Así eliminamos del almacenamiento local la copia que corresponda
    // después de Redsys o de la aprobación manual de transferencia/giro.
    try {
      final pedidosConfirmados = await apiService.getOrders(email);
      final localQuoteIds = pedidosConfirmados
          .map((order) => order.sourceLocalQuoteUuid.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (localQuoteIds.isNotEmpty) {
        await ref
            .read(localQuotesProvider.notifier)
            .eliminarPresupuestosConfirmados(localQuoteIds);
      }
    } catch (e) {
      debugPrint('⚠️ No se pudieron reconciliar presupuestos locales: $e');
    }

    /// Nos quedamos con presupuestos útiles para la app.
    /// PHP 1.9.25 crea los presupuestos reales como YITH `ywraq-pending`,
    /// que WordPress muestra en web como `status-ywraq-pending` /
    /// "Presupuesto pendiente".
    /// Mantenemos `pending` solo como compatibilidad con presupuestos antiguos
    /// creados antes de 1.9.25.
    final filtered = presupuestos.where((quote) {
      final status = quote.normalizedStatus;

      if (status.isEmpty) return true;

      return status == 'checkout-draft' ||
          status == 'pending' ||
          status == 'on-hold' ||
          status == 'presupuesto' ||
          status.startsWith('ywraq-') ||
          status.contains('quote');
    }).toList();

    debugPrint('📊 Presupuestos encontrados: ${filtered.length}');

    return filtered;
  } catch (e) {
    debugPrint('❌ Error cargando presupuestos: $e');
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