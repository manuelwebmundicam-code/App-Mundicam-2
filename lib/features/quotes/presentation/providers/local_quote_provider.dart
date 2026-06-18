import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/local_quote_model.dart';

final localQuotesProvider = StateNotifierProvider<LocalQuotesNotifier, List<LocalQuote>>((ref) {
  return LocalQuotesNotifier();
});

class LocalQuotesNotifier extends StateNotifier<List<LocalQuote>> {
  static const String _storageKey = 'mundicam_local_quotes';

  LocalQuotesNotifier() : super(const <LocalQuote>[]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.trim().isEmpty) {
        state = const <LocalQuote>[];
        return;
      }

      final decoded = jsonDecode(raw);
      final loaded = decoded is List
          ? decoded
          .whereType<Map>()
          .map((item) => LocalQuote.fromJson(Map<String, dynamic>.from(item)))
          .where((quote) => !quote.isExpired)
          .toList()
          : <LocalQuote>[];

      loaded.sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));
      state = loaded;
      await _persist();
    } catch (_) {
      state = const <LocalQuote>[];
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final activeQuotes = state.where((quote) => !quote.isExpired).toList()
      ..sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));

    state = activeQuotes;
    await prefs.setString(
      _storageKey,
      jsonEncode(activeQuotes.map((quote) => quote.toJson()).toList()),
    );
  }

  LocalQuote? getPresupuesto(String orderId) {
    final cleanId = orderId.trim();
    if (cleanId.isEmpty) return null;

    for (final quote in state) {
      if (quote.orderId == cleanId && !quote.isExpired) return quote;
    }

    return null;
  }

  Future<void> crearPresupuesto({
    required String orderId,
    required String nombre,
  }) async {
    final cleanId = orderId.trim().isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : orderId.trim();
    final cleanName = nombre.trim().isEmpty ? 'Presupuesto #$cleanId' : nombre.trim();

    final existing = getPresupuesto(cleanId);
    if (existing != null) return;

    state = [
      LocalQuote(
        orderId: cleanId,
        nombre: cleanName,
        fechaCreacion: DateTime.now(),
        items: const <LocalQuoteItem>[],
      ),
      ...state.where((quote) => !quote.isExpired),
    ];

    await _persist();
  }

  Future<void> anadirItem({
    required String orderId,
    required LocalQuoteItem item,
  }) async {
    final cleanId = orderId.trim();
    if (cleanId.isEmpty || item.productId <= 0 || item.quantity <= 0) return;

    var quote = getPresupuesto(cleanId);
    if (quote == null) {
      await crearPresupuesto(orderId: cleanId, nombre: 'Presupuesto #$cleanId');
      quote = getPresupuesto(cleanId);
    }
    if (quote == null) return;

    final items = List<LocalQuoteItem>.from(quote.items);
    final index = items.indexWhere((line) => line.productId == item.productId);

    if (index >= 0) {
      final current = items[index];
      items[index] = current.copyWith(
        quantity: current.quantity + item.quantity,
        price: item.price > 0 ? item.price : current.price,
        productName: item.productName.trim().isNotEmpty ? item.productName : current.productName,
      );
    } else {
      items.add(item);
    }

    state = state
        .map((candidate) => candidate.orderId == cleanId ? candidate.copyWith(items: items) : candidate)
        .where((candidate) => !candidate.isExpired)
        .toList()
      ..sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));

    await _persist();
  }

  Future<void> eliminarItem({
    required String orderId,
    required int productId,
  }) async {
    final cleanId = orderId.trim();
    if (cleanId.isEmpty || productId <= 0) return;

    final quote = getPresupuesto(cleanId);
    if (quote == null) return;

    final items = quote.items.where((item) => item.productId != productId).toList();

    if (items.isEmpty) {
      await eliminarPresupuesto(cleanId);
      return;
    }

    state = state
        .map((candidate) => candidate.orderId == cleanId ? candidate.copyWith(items: items) : candidate)
        .where((candidate) => !candidate.isExpired)
        .toList();

    await _persist();
  }

  Future<void> eliminarPresupuesto(String orderId) async {
    final cleanId = orderId.trim();
    if (cleanId.isEmpty) return;

    state = state.where((quote) => quote.orderId != cleanId && !quote.isExpired).toList();
    await _persist();
  }

  Future<void> limpiarCaducados() async {
    state = state.where((quote) => !quote.isExpired).toList();
    await _persist();
  }
}
