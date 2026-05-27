import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/local_quote_model.dart';

// Provider para acceder al notifier
final localQuotesProvider = StateNotifierProvider<LocalQuotesNotifier, List<LocalQuote>>((ref) {
  return LocalQuotesNotifier();
});

class LocalQuotesNotifier extends StateNotifier<List<LocalQuote>> {
  static const String _storageKey = 'mundicam_local_quotes';

  LocalQuotesNotifier() : super([]) {
    _cargarPresupuestos();
  }

  // Cargar presupuestos guardados
  Future<void> _cargarPresupuestos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        final quotes = decoded.map((e) => LocalQuote.fromJson(e as Map<String, dynamic>)).toList();

        // Filtrar presupuestos expirados
        final noExpirados = quotes.where((q) => !q.isExpired).toList();
        state = noExpirados;
        await _guardarPresupuestos();
      }
    } catch (e) {
      print('Error cargando presupuestos locales: $e');
      state = [];
    }
  }

  // Guardar presupuestos
  Future<void> _guardarPresupuestos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(state.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      print('Error guardando presupuestos locales: $e');
    }
  }

  // Crear nuevo presupuesto local
  Future<LocalQuote> crearPresupuesto({
    required String orderId,
    required String nombre,
  }) async {
    final nuevo = LocalQuote(
      orderId: orderId,
      nombre: nombre,
      fechaCreacion: DateTime.now(),
      items: [],
    );
    state = [...state, nuevo];
    await _guardarPresupuestos();
    return nuevo;
  }

  // Anadir item a un presupuesto existente
  Future<void> anadirItem({
    required String orderId,
    required LocalQuoteItem item,
  }) async {
    final index = state.indexWhere((q) => q.orderId == orderId);
    if (index == -1) return;

    final quote = state[index];
    final itemsActualizados = List<LocalQuoteItem>.from(quote.items);

    // Buscar si el producto ya existe
    final existingIndex = itemsActualizados.indexWhere((i) => i.productId == item.productId);
    if (existingIndex != -1) {
      // Actualizar cantidad
      final existing = itemsActualizados[existingIndex];
      itemsActualizados[existingIndex] = LocalQuoteItem(
        productId: existing.productId,
        productName: existing.productName,
        quantity: existing.quantity + item.quantity,
        price: existing.price,
      );
    } else {
      itemsActualizados.add(item);
    }

    final quoteActualizado = quote.copyWith(items: itemsActualizados);
    state = [
      ...state.take(index),
      quoteActualizado,
      ...state.skip(index + 1),
    ];
    await _guardarPresupuestos();
  }

  // Eliminar item de un presupuesto
  Future<void> eliminarItem({
    required String orderId,
    required int productId,
  }) async {
    final index = state.indexWhere((q) => q.orderId == orderId);
    if (index == -1) return;

    final quote = state[index];
    final itemsActualizados = quote.items.where((i) => i.productId != productId).toList();

    final quoteActualizado = quote.copyWith(items: itemsActualizados);
    state = [
      ...state.take(index),
      quoteActualizado,
      ...state.skip(index + 1),
    ];
    await _guardarPresupuestos();
  }

  // Eliminar presupuesto completo
  Future<void> eliminarPresupuesto(String orderId) async {
    state = state.where((q) => q.orderId != orderId).toList();
    await _guardarPresupuestos();
  }

  // Obtener presupuesto por ID
  LocalQuote? getPresupuesto(String orderId) {
    try {
      return state.firstWhere((q) => q.orderId == orderId);
    } catch (_) {
      return null;
    }
  }

  // Limpiar presupuestos expirados
  Future<void> limpiarExpirados() async {
    state = state.where((q) => !q.isExpired).toList();
    await _guardarPresupuestos();
  }
}