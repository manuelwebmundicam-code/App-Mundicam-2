import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/quotes/data/models/quote_model.dart';

/// Provider para el servicio de API
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

/// Provider global para presupuestos ocultos en la app
final hiddenQuoteIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

/// Provider que obtiene los presupuestos filtrados por el usuario
final quotesProvider = FutureProvider<List<QuoteMundicam>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    debugPrint('❌ No hay usuario autenticado');
    return [];
  }

  String? email;

  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data();
      email = data?['email']?.toString();
    }
  } catch (e) {
    debugPrint('Error al leer email de Firestore: $e');
  }

  email ??= user.email;

  if ((email == null || email.isEmpty) && user.providerData.isNotEmpty) {
    email = user.providerData.first.email;
  }

  if (email == null || email.isEmpty) {
    debugPrint('❌ No se encontró email para buscar presupuestos');
    return [];
  }

  debugPrint('🔍 Buscando presupuestos para: $email');

  final presupuestos = await apiService.getPresupuestosPorEmail(email);

  debugPrint('📊 Presupuestos encontrados: ${presupuestos.length}');

  return presupuestos;
});

/// Presupuestos visibles, quitando los que el usuario ha ocultado
final visibleQuotesProvider = Provider<AsyncValue<List<QuoteMundicam>>>((ref) {
  final quotesAsync = ref.watch(quotesProvider);
  final hiddenIds = ref.watch(hiddenQuoteIdsProvider);

  return quotesAsync.whenData((quotes) {
    return quotes.where((quote) => !hiddenIds.contains(quote.id)).toList();
  });
});

/// Número de presupuestos visibles para la pelotita/badge inferior
final visibleQuotesCountProvider = Provider<int>((ref) {
  final visibleQuotesAsync = ref.watch(visibleQuotesProvider);

  return visibleQuotesAsync.maybeWhen(
    data: (quotes) => quotes.length,
    orElse: () => 0,
  );
});
