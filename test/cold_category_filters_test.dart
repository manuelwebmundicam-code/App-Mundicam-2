import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mundicam/features/catalog/presentation/widgets/filtro_selector.dart';

Widget drawerHarness(GlobalKey<ScaffoldState> key, {required bool enabled}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        key: key,
        body: ElevatedButton(
          onPressed: () => key.currentState!.openEndDrawer(),
          child: const Text('Abrir filtros de prueba'),
        ),
        endDrawer: FiltroSelector(
          parentCategoryId: 369,
          categoryName: 'VIDEO IP HD',
          productosEnPantalla: const [],
          loadEnabled: enabled,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hidden/deferred filters stay passive until enabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(drawerHarness(key, enabled: false));
    await tester.tap(find.text('Abrir filtros de prueba'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // No authenticated request is started by the disabled filter drawer:
    // a missing session does not turn the placeholder into a login error.
    expect(find.text('Cargando filtros de la web...'), findsOneWidget);
    expect(find.textContaining('Inicia sesión'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabled filters are blocked without a valid app session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(drawerHarness(key, enabled: true));
    await tester.tap(find.text('Abrir filtros de prueba'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.textContaining('Inicia sesión para ver tus filtros comerciales.'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
