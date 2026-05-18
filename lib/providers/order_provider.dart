import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/order_model.dart';
import 'banner_mix_provider.dart';

/// Provider que obtiene los pedidos del usuario
final ordersProvider = FutureProvider<List<OrderMundicam>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    return [];
  }

  // Obtener email desde Firestore, Firebase Auth o providerData
  String? email;
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

  if (email == null || email.isEmpty) {
    debugPrint('❌ No se encontró email para buscar pedidos');
    return [];
  }

  debugPrint('🔍 Buscando pedidos para: $email');
  final pedidos = await apiService.getOrders(email);
  debugPrint('📦 Pedidos encontrados: ${pedidos.length}');
  return pedidos;
});