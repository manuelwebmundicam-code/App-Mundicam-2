import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/orders/data/models/order_model.dart';
import 'package:mundicam/features/home/presentation/providers/banner_mix_provider.dart';

/// Obtiene los pedidos del usuario autenticado.
/// La fuente principal es la sesión WordPress/MundiCam App API.
final ordersProvider = FutureProvider<List<OrderMundicam>>((ref) async {
  final apiService = ref.read(apiServiceProvider);

  String? email = await apiService.currentSessionEmail();

  // Respaldo local sin consulta adicional a Firestore.
  if (email == null || email.trim().isEmpty) {
    final user = FirebaseAuth.instance.currentUser;
    email = user?.email ?? user?.providerData.firstOrNull?.email;
  }

  final normalizedEmail = email?.trim().toLowerCase() ?? '';

  if (normalizedEmail.isEmpty) {
    if (kDebugMode) {
      debugPrint('[ORDERS] Email de sesión no disponible | END');
    }
    return <OrderMundicam>[];
  }

  if (kDebugMode) {
    debugPrint(
      '[ORDERS] Buscando para email="$normalizedEmail" | '
      'length=${normalizedEmail.length} | END',
    );
  }

  final pedidos = await apiService.getOrders(normalizedEmail);

  if (kDebugMode) {
    debugPrint('[ORDERS] Encontrados=${pedidos.length} | END');
  }

  return pedidos;
});
