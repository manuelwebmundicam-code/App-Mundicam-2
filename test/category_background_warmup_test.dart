import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/cache/category_background_warmup.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';

void main() {
  final roots = List.generate(
    8, (i) => CategoryModel(id: i + 1, name: 'Categoria $i'),
  );

  test('precarga máximo cuatro raíces sin cambiar orden', () async {
    final seen = <int>[];
    await CategoryBackgroundWarmup.run(
      roots: roots,
      hasSession: () async => true,
      loadChildren: (id) async { seen.add(id); return const []; },
    );
    expect(seen, [1, 2, 3, 4]);
  });

  test('sin sesión no hace consultas', () async {
    var calls = 0;
    await CategoryBackgroundWarmup.run(
      roots: roots,
      hasSession: () async => false,
      loadChildren: (id) async { calls++; return const []; },
    );
    expect(calls, 0);
  });

  test('ignora raíces duplicadas, hojas y errores aislados', () async {
    final seen = <int>[];
    await CategoryBackgroundWarmup.run(
      roots: const [
        CategoryModel(id: 4, name: 'Raiz'),
        CategoryModel(id: 4, name: 'Duplicada'),
        CategoryModel(id: 5, name: 'Hoja', parent: 4),
        CategoryModel(id: 6, name: 'Sin hijas', hasChildren: false),
        CategoryModel(id: 7, name: 'Raiz 2'),
      ],
      hasSession: () async => true,
      loadChildren: (id) async {
        seen.add(id);
        if (id == 4) throw StateError('red');
        return const [];
      },
    );
    expect(seen, [4, 7]);
  });

  test('segunda ejecución simultánea no duplica la precarga', () async {
    final pending = Completer<List<CategoryModel>>();
    var calls = 0;
    final first = CategoryBackgroundWarmup.run(
      roots: roots,
      hasSession: () async => true,
      loadChildren: (id) {
        calls++;
        return id == 1 ? pending.future : Future.value(const []);
      },
    );
    await Future<void>.delayed(Duration.zero);
    await CategoryBackgroundWarmup.run(
      roots: roots,
      hasSession: () async => true,
      loadChildren: (id) async { calls += 100; return const []; },
    );
    pending.complete(const []);
    await first;
    expect(calls, 4);
  });
}
