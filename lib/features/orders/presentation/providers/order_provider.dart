import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/orders/data/models/order_model.dart';
import 'package:mundicam/features/home/presentation/providers/banner_mix_provider.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';

/// Provider que obtiene los pedidos del usuario
final ordersProvider = FutureProvider<List<OrderMundicam>>((ref) async {
  final apiService = ref.read(apiServiceProvider);

  // La sesión principal es WordPress/MundiCam App API. Firebase queda como apoyo.
  String? email = await apiService.currentSessionEmail();

  final user = FirebaseAuth.instance.currentUser;

  if ((email == null || email.isEmpty) && user != null) {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        email = userDoc.get('email') as String?;
      }
    } catch (e) {
      debugPrint('Error al leer email de Firestore: $e');
    }
    email ??= user.email;
    email ??= user.providerData.firstOrNull?.email;
  }

  if (email == null || email.isEmpty) {
    debugPrint('❌ No se encontró email para buscar pedidos');
    return [];
  }

  debugPrint('🔍 Buscando pedidos para: $email');
  final pedidos = await apiService.getOrders(email);

  // La web es la autoridad del pago. Si WooCommerce confirma como pagado un
  // pedido procedente de presupuesto local (incluso tras una callback tardía),
  // se retira únicamente esa copia local para evitar duplicados visuales.
  for (final pedido in pedidos) {
    final localUuid = pedido.sourceLocalQuoteUuid.trim();
    if (localUuid.isNotEmpty && pedido.isPaid) {
      try {
        await ref
            .read(localQuotesProvider.notifier)
            .eliminarPresupuesto(localUuid);
      } catch (e) {
        debugPrint(
          'No se pudo retirar la copia local $localUuid del pedido pagado: $e',
        );
      }
    }
  }

  debugPrint('📦 Pedidos encontrados: ${pedidos.length}');
  return pedidos;
});
