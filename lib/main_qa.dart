import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'qa/mundicam_qa_client.dart';

/// Entrada independiente, SOLO para Android Studio/emulador:
/// flutter run --debug -t lib/main_qa.dart
///
/// Nunca inicia Firebase, usa ApiService real, ni lee sesiones guardadas.
/// No permite compras, presupuestos, envíos FCM ni acceso a producción.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) {
    throw StateError('MundiCam QA no se puede ejecutar en release/profile.');
  }
  final info = await PackageInfo.fromPlatform();
  if (info.packageName != 'com.mundicam.securitydistribution.qa') {
    throw StateError('Bloqueado: la versión Android no está aislada como .qa.');
  }
  runApp(const MundiCamQaApp());
}

class MundiCamQaApp extends StatelessWidget {
  const MundiCamQaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MundiCam QA · VPS R19',
    debugShowCheckedModeBanner: true,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF0A4C8C),
    ),
    home: const MundiCamQaScreen(),
  );
}

class MundiCamQaScreen extends StatefulWidget {
  const MundiCamQaScreen({super.key});
  @override
  State<MundiCamQaScreen> createState() => _MundiCamQaScreenState();
}

class _MundiCamQaScreenState extends State<MundiCamQaScreen> {
  final _client = MundicamQaClient();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _category = TextEditingController(text: '144');

  bool _busy = false;
  String _status = 'Sin conexión comprobada.';
  QaBenchmark? _last;

  @override
  void dispose() {
    _client.clearSession();
    _email.dispose();
    _password.dispose();
    _category.dispose();
    super.dispose();
  }

  String _safeError(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code != null) return 'HTTP $code. Comprueba PHP R19 o cuenta QA.';
      return 'No hay conexión con el túnel local (127.0.0.1:8770).';
    }
    if (error is FormatException || error is StateError) {
      return error.toString().replaceAll('FormatException: ', '');
    }
    return 'Fallo de QA; consulta el estado del WordPress de pruebas.';
  }

  Future<void> _execute(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = _safeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _caption(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('MundiCam · VPS QA'),
      backgroundColor: const Color(0xFFEAF3FC),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(15),
              child: Text(
                'PRUEBAS AISLADAS · NO PRODUCCIÓN\n'
                'Destino único: http://127.0.0.1:8770\n'
                'Sin Firebase, tokens reales, compras ni presupuestos.',
              ),
            ),
          ),
          _caption('1. Conexión WordPress QA y versión PHP'),
          FilledButton.icon(
            key: const Key('qa_status_button'),
            onPressed: _busy
                ? null
                : () => _execute(() async {
                    final version = await _client.status();
                    if (!mounted) return;
                    setState(() => _status = 'PHP correcto: $version');
                  }),
            icon: const Icon(Icons.health_and_safety_outlined),
            label: const Text('Comprobar R19'),
          ),
          _caption('2. Inicio de sesión con usuario FICTICIO de QA'),
          TextField(
            controller: _email,
            key: const Key('qa_email_input'),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email/usuario de pruebas (nunca producción)',
            ),
          ),
          TextField(
            controller: _password,
            key: const Key('qa_password_input'),
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Contraseña del usuario QA',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('qa_login_button'),
            onPressed: _busy
                ? null
                : () => _execute(() async {
                    await _client.login(_email.text, _password.text);
                    _password.clear();
                    if (!mounted) return;
                    setState(
                      () => _status = 'Sesión QA verificada mediante /me.',
                    );
                  }),
            child: const Text('Iniciar sesión QA (solo memoria)'),
          ),
          _caption('3. Comparar filtros y medir /products price_asc'),
          TextField(
            controller: _category,
            key: const Key('qa_category_input'),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'ID de categoría QA (144, 44, 85 o personalizado)',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('qa_benchmark_button'),
            onPressed: _busy || !_client.authenticated
                ? null
                : () => _execute(() async {
                    final id = int.tryParse(_category.text.trim()) ?? 0;
                    final result = await _client.benchmark(id);
                    if (!mounted) return;
                    setState(() {
                      _last = result;
                      _status = result.validated
                          ? 'Facetas R19 coincidentes. Verificar tarifas B2B aparte.'
                          : 'PRUEBA INCOMPLETA: revisar recuentos, facetas o datos QA.';
                    });
                  }),
            child: const Text('Medir filtros y productos en QA'),
          ),
          const SizedBox(height: 14),
          Text(_status, key: const Key('qa_status_text')),
          if (_last != null) ...[
            const Divider(height: 30),
            Text(
              'Categoría ${_last!.categoryId} · productos: ${_last!.totalProducts}',
            ),
            Text('Filtros completos: ${_last!.fullFiltersMs} ms'),
            Text('Filtros facets_only=1: ${_last!.fastFiltersMs} ms'),
            Text('Productos price_asc, página 1: ${_last!.productsMs} ms'),
            Text('Productos recibidos: ${_last!.firstPageCount}'),
            Text('Mismas facetas: ${_last!.sameFacets}'),
            Text('Mismos recuentos: ${_last!.sameTotal}'),
            Text('Sin agregados de precio/stock: ${_last!.skipsAggregates}'),
          ],
          const SizedBox(height: 22),
          OutlinedButton(
            onPressed: () {
              _client.clearSession();
              _password.clear();
              setState(() {
                _last = null;
                _status = 'Sesión QA borrada de memoria.';
              });
            },
            child: const Text('Cerrar sesión QA'),
          ),
        ],
      ),
    ),
  );
}
