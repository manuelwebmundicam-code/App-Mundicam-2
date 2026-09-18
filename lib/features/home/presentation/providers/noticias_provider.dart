import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/mundicam_content_service.dart';
import 'package:mundicam/features/home/data/models/noticia.dart';

final mundicamContentServiceProvider = Provider<MundicamContentService>((ref) {
  return MundicamContentService();
});

class NoticiasNotifier
    extends StateNotifier<AsyncValue<List<Noticia>>> {
  NoticiasNotifier(this._ref) : super(const AsyncValue.loading()) {
    _loadInitial();
  }

  final Ref _ref;
  bool _refreshing = false;

  Future<void> _loadInitial() async {
    final service = _ref.read(mundicamContentServiceProvider);
    final cached = service.noticiasCached;

    if (cached.isNotEmpty) {
      state = AsyncValue.data(cached);
      await refreshSilently();
      return;
    }

    try {
      // Primera respuesta ligera para que la pantalla aparezca rápido.
      final noticias = await service.getNoticias(fast: true);
      state = AsyncValue.data(noticias);

      // Una vez visible la pantalla, ampliamos el listado sin bloquearla.
      await refreshSilently();
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refreshSilently() async {
    if (_refreshing || state.isLoading) return;

    _refreshing = true;
    try {
      final service = _ref.read(mundicamContentServiceProvider);
      final noticias = await service.getNoticias(
        forceRefresh: true,
      );
      state = AsyncValue.data(noticias);
    } catch (_) {
      // Si falla WordPress, mantenemos lo que ya estaba visible.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> refreshFromPull() async {
    if (_refreshing) return;

    _refreshing = true;
    try {
      final service = _ref.read(mundicamContentServiceProvider);
      final noticias = await service.getNoticias(
        forceRefresh: true,
      );
      state = AsyncValue.data(noticias);
    } catch (error, stack) {
      if (!state.hasValue) {
        state = AsyncValue.error(error, stack);
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> retry() async {
    if (_refreshing) return;

    _refreshing = true;
    state = const AsyncValue.loading();

    try {
      final service = _ref.read(mundicamContentServiceProvider);
      final noticias = await service.getNoticias(
        forceRefresh: true,
        fast: true,
      );
      state = AsyncValue.data(noticias);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    } finally {
      _refreshing = false;
    }
  }
}

final noticiasProvider = StateNotifierProvider<
    NoticiasNotifier,
    AsyncValue<List<Noticia>>>((ref) {
  return NoticiasNotifier(ref);
});
