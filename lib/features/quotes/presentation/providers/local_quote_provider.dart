import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/local_quote_model.dart';

// Provider para acceder al notifier
final localQuotesProvider =
    StateNotifierProvider<LocalQuotesNotifier, List<LocalQuote>>((ref) {
  return LocalQuotesNotifier();
});

class LocalQuotesNotifier extends StateNotifier<List<LocalQuote>> {
  static const String _storageKey = 'mundicam_local_quotes';

  late final Future<void> _initialLoad;

  LocalQuotesNotifier() : super([]) {
    _initialLoad = _cargarPresupuestos();
  }

  Future<void> _esperarCargaInicial() => _initialLoad;

  // Cargar presupuestos guardados antes de aceptar mutaciones nuevas.
  Future<void> _cargarPresupuestos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        state = [];
        return;
      }

      final decoded = jsonDecode(jsonString);
      if (decoded is! List) {
        throw const FormatException('Formato de presupuestos locales no válido.');
      }

      final quotes = decoded
          .map((e) => LocalQuote.fromJson(e as Map<String, dynamic>))
          .toList();

      // Filtrar presupuestos expirados manteniendo disponible el contenido válido.
      final noExpirados = quotes.where((q) => !q.isExpired).toList();
      state = noExpirados;

      if (noExpirados.length != quotes.length) {
        try {
          await _guardarPresupuestos(noExpirados);
        } catch (e) {
          // La limpieza automática no debe ocultar presupuestos válidos ya cargados.
          if (kDebugMode) {
            debugPrint('No se pudieron limpiar presupuestos expirados: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error cargando presupuestos locales: $e');
      }
      state = [];
    }
  }

  // Persistencia comprobada. No cambia el estado en memoria si falla el disco.
  Future<void> _guardarPresupuestos(List<LocalQuote> nextState) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(nextState.map((e) => e.toJson()).toList());
      final saved = await prefs.setString(_storageKey, jsonString);
      if (!saved) {
        throw StateError('SharedPreferences rechazó el guardado.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error guardando presupuestos locales: $e');
      }
      throw Exception(
        'No se pudo guardar el presupuesto en este dispositivo. Inténtalo de nuevo.',
      );
    }
  }

  // Crear nuevo presupuesto local
  Future<LocalQuote> crearPresupuesto({
    required String orderId,
    required String nombre,
  }) async {
    await _esperarCargaInicial();

    final nuevo = LocalQuote(
      orderId: orderId,
      nombre: nombre,
      fechaCreacion: DateTime.now(),
      items: [],
    );

    final nextState = [...state, nuevo];
    await _guardarPresupuestos(nextState);
    state = nextState;
    return nuevo;
  }

  // Añadir item a un presupuesto existente
  Future<void> anadirItem({
    required String orderId,
    required LocalQuoteItem item,
  }) async {
    await _esperarCargaInicial();

    final index = state.indexWhere((q) => q.orderId == orderId);
    if (index == -1) {
      throw Exception('Presupuesto local no encontrado.');
    }

    final quote = state[index];
    final itemsActualizados = List<LocalQuoteItem>.from(quote.items);

    // Producto y variación forman la identidad de una línea.
    final existingIndex = itemsActualizados.indexWhere(
      (i) => i.productId == item.productId && i.variationId == item.variationId,
    );

    if (existingIndex != -1) {
      final existing = itemsActualizados[existingIndex];
      itemsActualizados[existingIndex] = LocalQuoteItem(
        productId: existing.productId,
        variationId: existing.variationId,
        productName: existing.productName,
        quantity: existing.quantity + item.quantity,
        price: existing.price,
      );
    } else {
      itemsActualizados.add(item);
    }

    final quoteActualizado = quote.copyWith(items: itemsActualizados);
    final nextState = [
      ...state.take(index),
      quoteActualizado,
      ...state.skip(index + 1),
    ];

    await _guardarPresupuestos(nextState);
    state = nextState;
  }

  // Eliminar item de un presupuesto
  Future<void> eliminarItem({
    required String orderId,
    required int productId,
    int variationId = 0,
  }) async {
    await _esperarCargaInicial();

    final index = state.indexWhere((q) => q.orderId == orderId);
    if (index == -1) {
      throw Exception('Presupuesto local no encontrado.');
    }

    final quote = state[index];
    final itemsActualizados = quote.items
        .where(
          (i) => !(i.productId == productId && i.variationId == variationId),
        )
        .toList();

    final quoteActualizado = quote.copyWith(items: itemsActualizados);
    final nextState = [
      ...state.take(index),
      quoteActualizado,
      ...state.skip(index + 1),
    ];

    await _guardarPresupuestos(nextState);
    state = nextState;
  }

  Future<void> renombrarPresupuesto({
    required String orderId,
    required String nombre,
  }) async {
    await _esperarCargaInicial();

    final cleanName = nombre.trim();
    if (cleanName.isEmpty) {
      throw Exception('El nombre del presupuesto no puede estar vacío.');
    }

    final index = state.indexWhere((q) => q.orderId == orderId);
    if (index == -1) {
      throw Exception('Presupuesto local no encontrado.');
    }

    final updated = state[index].copyWith(nombre: cleanName);
    final nextState = [
      ...state.take(index),
      updated,
      ...state.skip(index + 1),
    ];

    await _guardarPresupuestos(nextState);
    state = nextState;
  }

  // Eliminar presupuesto completo
  Future<void> eliminarPresupuesto(String orderId) async {
    await _esperarCargaInicial();

    final nextState = state.where((q) => q.orderId != orderId).toList();
    if (nextState.length == state.length) {
      return;
    }

    await _guardarPresupuestos(nextState);
    state = nextState;
  }

  // Obtener presupuesto por ID
  LocalQuote? getPresupuesto(String orderId) {
    try {
      return state.firstWhere((q) => q.orderId == orderId);
    } catch (_) {
      return null;
    }
  }

  // Restaurar o actualizar un presupuesto devuelto desde WooCommerce/YITH.
  Future<void> restaurarPresupuesto(LocalQuote quote) async {
    await _esperarCargaInicial();

    if (quote.orderId.trim().isEmpty || quote.items.isEmpty) {
      throw Exception('El presupuesto devuelto no contiene datos válidos.');
    }

    final index = state.indexWhere((q) => q.orderId == quote.orderId);
    final List<LocalQuote> nextState;
    if (index == -1) {
      nextState = [...state, quote];
    } else {
      nextState = [
        ...state.take(index),
        quote,
        ...state.skip(index + 1),
      ];
    }

    await _guardarPresupuestos(nextState);
    state = nextState;
  }

  // Limpiar presupuestos expirados
  Future<void> limpiarExpirados() async {
    await _esperarCargaInicial();

    final nextState = state.where((q) => !q.isExpired).toList();
    if (nextState.length == state.length) {
      return;
    }

    await _guardarPresupuestos(nextState);
    state = nextState;
  }
}
