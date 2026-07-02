// pages/login_page.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/app/main_screen.dart';
import 'package:mundicam/features/auth/presentation/pages/forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoadingSavedCredentials = true;
  bool _isAutoLogin = false;

  static const String _loginEndpoint =
      'https://www.mundicam.com/wp-json/mundicam-app/v1/login';

  static const String _registroUrl =
      'https://www.mundicam.com/altaweb-mundicam-security-distribution/';

  static const String _rememberEmailKey = 'remembered_email';
  static const String _rememberMeKey = 'remember_me_enabled';

  // Deben coincidir con las claves usadas en ApiService.
  static const String _wpSessionCookiePrefsKey =
      'mundicam_wp_session_cookie';
  static const String _wpNoncePrefsKey = 'mundicam_wp_nonce';
  static const String _wpCartTokenPrefsKey = 'mundicam_wp_cart_token';
  static const String _appTokenPrefsKey = 'mundicam_app_token';

  @override
  void initState() {
    super.initState();
    _inicializarLogin();
  }

  // ================================================================
  // INICIALIZAR LOGIN
  // ================================================================
  Future<void> _inicializarLogin() async {
    final prefs = await SharedPreferences.getInstance();

    final bool rememberMeGuardado = prefs.getBool(_rememberMeKey) ?? false;
    final String emailGuardado = prefs.getString(_rememberEmailKey) ?? '';

    if (!mounted) return;

    setState(() {
      _rememberMe = rememberMeGuardado;
      _emailController.text = rememberMeGuardado ? emailGuardado : '';
      _isLoadingSavedCredentials = false;
    });

    final hasWpSession = await _hasStoredWordPressSession();

    if (!mounted) return;

    if (hasWpSession) {
      if (kDebugMode) {
        debugPrint(
          '✅ Sesión WordPress/WooCommerce detectada. Entrando a la app.',
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;

    // Si Firebase está logueado pero no hay sesión WooCommerce, se fuerza login limpio.
    // Esto evita entrar como invitado y cargar productos sin precios reales.
    if (currentUser != null) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Firebase tenía sesión activa, pero no había sesión WordPress/WooCommerce. '
              'Se fuerza login limpio.',
        );
      }

      await FirebaseAuth.instance.signOut();
      await ApiService().clearWordPressSession();
    }
  }

  Future<bool> _hasStoredWordPressSession() async {
    final prefs = await SharedPreferences.getInstance();

    final cookie = prefs.getString(_wpSessionCookiePrefsKey)?.trim() ?? '';
    final nonce = prefs.getString(_wpNoncePrefsKey)?.trim() ?? '';
    final cartToken = prefs.getString(_wpCartTokenPrefsKey)?.trim() ?? '';
    final appToken = prefs.getString(_appTokenPrefsKey)?.trim() ?? '';

    final hasSession = appToken.isNotEmpty || cartToken.isNotEmpty;

    if (kDebugMode) {
      debugPrint(
        '🔐 Sesión WP guardada en login: '
            'cookie=${cookie.isNotEmpty} '
            'nonce=${nonce.isNotEmpty} '
            'appToken=${appToken.isNotEmpty} cartToken=${cartToken.isNotEmpty}',
      );
    }

    return hasSession;
  }

  // ================================================================
  // CHECKBOX RECUÉRDAME
  // ================================================================
  Future<void> _onCheckboxChanged(bool? valor) async {
    final bool nuevoValor = valor ?? false;

    setState(() {
      _rememberMe = nuevoValor;
    });

    final prefs = await SharedPreferences.getInstance();

    if (nuevoValor) {
      await prefs.setBool(_rememberMeKey, true);
      await prefs.setString(_rememberEmailKey, _emailController.text.trim());
      // NO guardar contraseña.
    } else {
      await prefs.setBool(_rememberMeKey, false);
      await prefs.remove(_rememberEmailKey);
    }
  }

  Future<void> _abrirRegistro() async {
    final url = Uri.parse(_registroUrl);
    final abierto = await launchUrl(url, mode: LaunchMode.externalApplication);

    if (!abierto) {
      _showSnackBar('No se pudo abrir la página de registro.', isError: true);
    }
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty &&
          text.toLowerCase() != 'null' &&
          text.toLowerCase() != 'false') {
        return text;
      }
    }

    return null;
  }

  String _normalizeCookieHeader(String value) {
    final raw = value.trim();

    if (raw.isEmpty) return '';

    final cookies = <String>[];

    // Intenta separar varias cookies combinadas en una sola cabecera.
    final parts = raw.split(RegExp(r',\s*(?=[^;,]+=)'));

    for (final part in parts) {
      final firstSegment = part.split(';').first.trim();

      if (firstSegment.isEmpty || !firstSegment.contains('=')) continue;

      final name = firstSegment.split('=').first.trim().toLowerCase();

      if (name == 'path' ||
          name == 'expires' ||
          name == 'max-age' ||
          name == 'domain' ||
          name == 'samesite') {
        continue;
      }

      cookies.add(firstSegment);
    }

    return cookies.isEmpty ? raw : cookies.join('; ');
  }

  String? _cookieFromDynamic(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final clean = _normalizeCookieHeader(value.trim());
      return clean.isEmpty ? null : clean;
    }

    if (value is List) {
      final cookies = value
          .map(_cookieFromDynamic)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList();

      return cookies.isEmpty ? null : cookies.join('; ');
    }

    if (value is Map) {
      final cookies = value.values
          .map(_cookieFromDynamic)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList();

      return cookies.isEmpty ? null : cookies.join('; ');
    }

    return null;
  }

  Future<void> _guardarSesionWordPressDesdeRespuesta(
      http.Response response,
      Map<String, dynamic> body,
      ) async {
    final user = body['user'];
    final session = body['session'];
    final woo = body['woocommerce'];

    final Map<String, dynamic> userMap =
    user is Map ? Map<String, dynamic>.from(user) : <String, dynamic>{};

    final Map<String, dynamic> sessionMap = session is Map
        ? Map<String, dynamic>.from(session)
        : <String, dynamic>{};

    final Map<String, dynamic> wooMap =
    woo is Map ? Map<String, dynamic>.from(woo) : <String, dynamic>{};

    final headerCookie = response.headers['set-cookie'];

    final cookie = _cookieFromDynamic(headerCookie) ??
        _cookieFromDynamic(body['cookie']) ??
        _cookieFromDynamic(body['cookies']) ??
        _cookieFromDynamic(body['wordpress_cookie']) ??
        _cookieFromDynamic(body['wp_cookie']) ??
        _cookieFromDynamic(body['session_cookie']) ??
        _cookieFromDynamic(sessionMap['cookie']) ??
        _cookieFromDynamic(sessionMap['cookies']) ??
        _cookieFromDynamic(wooMap['cookie']) ??
        _cookieFromDynamic(userMap['cookie']);

    final nonce = _firstNonEmptyString([
      body['store_api_nonce'],
      body['nonce'],
      body['wp_nonce'],
      body['woocommerce_nonce'],
      body['wc_store_api_nonce'],
      sessionMap['store_api_nonce'],
      sessionMap['nonce'],
      sessionMap['wp_nonce'],
      wooMap['store_api_nonce'],
      wooMap['nonce'],
      userMap['nonce'],
    ]);

    final authMap = body['auth'] is Map
        ? Map<String, dynamic>.from(body['auth'] as Map)
        : <String, dynamic>{};
    final tokensMap = body['tokens'] is Map
        ? Map<String, dynamic>.from(body['tokens'] as Map)
        : <String, dynamic>{};
    final dataMap = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : <String, dynamic>{};

    final appToken = _firstNonEmptyString([
      body['app_token'],
      body['appToken'],
      body['token'],
      body['access_token'],
      body['session_token'],
      body['jwt'],
      body['cart_token'],
      body['cartToken'],
      sessionMap['app_token'],
      sessionMap['appToken'],
      sessionMap['token'],
      sessionMap['cart_token'],
      sessionMap['cartToken'],
      wooMap['app_token'],
      wooMap['appToken'],
      wooMap['token'],
      wooMap['cart_token'],
      wooMap['cartToken'],
      authMap['app_token'],
      authMap['token'],
      tokensMap['app_token'],
      tokensMap['token'],
      dataMap['app_token'],
      dataMap['token'],
    ]);

    if (kDebugMode) {
      debugPrint(
        '🔐 Datos sesión recibidos login MundiCam App API: '
            'appToken=${appToken != null && appToken.isNotEmpty}',
      );
    }

    await ApiService().saveWordPressSession(
      cookie: cookie,
      nonce: nonce,
      cartToken: appToken,
      appToken: appToken,
      user: userMap,
      permissions: body['permissions'] is Map
          ? Map<String, dynamic>.from(body['permissions'] as Map)
          : <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>?> _authenticateWithWordPress({
    required String email,
    required String password,
  }) async {
    final attempts = <Uri>[
      Uri.parse('$_loginEndpoint?app_login=1&nocache=${DateTime.now().millisecondsSinceEpoch}'),
      Uri.parse(_loginEndpoint),
    ];

    Object? lastError;

    for (final uri in attempts) {
      try {
        final response = await http.post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store, no-cache, must-revalidate',
            'Pragma': 'no-cache',
            'User-Agent': 'MundiCam-App-Flutter/1.7.6',
          },
          body: jsonEncode({
            'email': email,
            'username': email,
            'login': email,
            'password': password,
          }),
        );

        if (kDebugMode) {
          debugPrint('Status MundiCam App API login: ${response.statusCode}');
          if (response.statusCode >= 500) {
            final preview = response.body.length > 250
                ? response.body.substring(0, 250)
                : response.body;
            debugPrint('Respuesta login servidor preview: $preview');
          }
        }

        late final Map<String, dynamic> body;

        try {
          final decoded = jsonDecode(response.body);
          body = decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
        } catch (_) {
          if (response.statusCode >= 500) {
            throw Exception(
              'Servidor MundiCam no disponible temporalmente (${response.statusCode}). '
              'El endpoint /login no ha devuelto JSON.',
            );
          }
          throw Exception('Respuesta no válida del servidor.');
        }

        if (response.statusCode == 200) {
          await _guardarSesionWordPressDesdeRespuesta(response, body);
          return body;
        }

        final dataMap = body['data'] is Map
            ? Map<String, dynamic>.from(body['data'] as Map)
            : <String, dynamic>{};
        final status = dataMap['status'] ?? response.statusCode;
        final message = body['message']?.toString().trim();

        throw Exception(
          (message != null && message.isNotEmpty)
              ? message
              : 'Error de login App API ($status).',
        );
      } catch (e) {
        lastError = e;
        if (kDebugMode) {
          debugPrint('Error MundiCam App API login: $e');
        }
      }
    }

    if (lastError is Exception) throw lastError;
    throw Exception('No se pudo iniciar sesión con MundiCam App API.');
  }

  Future<User?> _tryLoginFirebaseForAppSession({
    required String email,
    required String password,
    required Map<String, dynamic> wpResponse,
  }) async {
    final String? firebaseToken =
        wpResponse['firebase_token']?.toString().trim();

    try {
      if (firebaseToken != null && firebaseToken.isNotEmpty) {
        await FirebaseAuth.instance.signInWithCustomToken(firebaseToken);
        return FirebaseAuth.instance.currentUser;
      }

      // v1.7.6: no usar la contraseña WordPress contra Firebase.
      // WordPress/App API es la fuente de verdad. Firebase queda como apoyo opcional.
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) return current;

      try {
        final credential = await FirebaseAuth.instance.signInAnonymously();
        if (kDebugMode) {
          debugPrint(
            '✅ Firebase anónimo activado como apoyo. uid=${credential.user?.uid}',
          );
        }
        return credential.user;
      } catch (anonError) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ Firebase anónimo no disponible. '
            'No bloquea acceso porque WordPress ya validó sesión. Error: $anonError',
          );
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Error no crítico iniciando Firebase. '
          'La sesión WordPress seguirá siendo válida. Error: $e',
        );
      }
      return null;
    }
  }

  Future<void> _handleLogin({bool fromAutoLogin = false}) async {
    if (!fromAutoLogin) {
      if (!_formKey.currentState!.validate()) return;
    }

    setState(() => _isLoading = true);

    try {
      final String email = _emailController.text.trim();
      final String password = _passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Introduce usuario y contraseña.');
      }

      // Limpiamos restos antiguos antes de iniciar sesión nueva.
      await ApiService().clearWordPressSession();

      // 1. Autenticar contra WordPress/WooCommerce.
      final wpResponse = await _authenticateWithWordPress(
        email: email,
        password: password,
      );

      if (wpResponse == null) {
        _showSnackBar('Error al conectar con el servidor.', isError: true);
        return;
      }

      if (wpResponse['success'] == false) {
        _showSnackBar(
          wpResponse['message'] ?? 'Credenciales incorrectas.',
          isError: true,
        );
        return;
      }

      // 2. Firebase es apoyo, no la fuente de verdad del acceso.
      // Si Firebase falla pero WordPress/MundiCam App API ha validado usuario
      // y ha guardado app_token, no se bloquea el acceso.
      final User? user = await _tryLoginFirebaseForAppSession(
        email: email,
        password: password,
        wpResponse: wpResponse,
      );

      // 3. Verificar que después del login existe sesión WordPress/WooCommerce.
      final hasWpSession = await _hasStoredWordPressSession();

      if (!hasWpSession) {
        await FirebaseAuth.instance.signOut();
        await ApiService().clearWordPressSession();

        throw Exception(
          'El login se ha validado, pero el plugin no ha devuelto app_token. '
          'Revisa que MundiCam App API esté activo y que /login devuelva app_token.',
        );
      }

      // 4. Crear/actualizar documento en Firestore solo si Firebase está disponible.
      // La sesión válida para entrar es WordPress/MundiCam App API.
      if (user != null) {
        try {
          final wpId = wpResponse['user']?['id']?.toString();
          final expectedUid = wpId != null && wpId.isNotEmpty ? 'wp_$wpId' : '';

          if (expectedUid.isNotEmpty && kDebugMode) {
            debugPrint(
              '👤 Firebase UID actual=${user.uid} | esperado=$expectedUid',
            );

            if (user.uid != expectedUid) {
              debugPrint(
                '⚠️ UID Firebase no coincide con WordPress ID. '
                'No es bloqueo: la sesión válida es MundiCam App API.',
              );
            }
          }

          final userRef =
              FirebaseFirestore.instance.collection('users').doc(user.uid);

          final userDoc = await userRef.get();

          if (!userDoc.exists) {
            await userRef.set({
              'email': email,
              'uid': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
              'isBlocked': false,
              'wordpress_id': wpResponse['user']?['id'] ?? '',
              'wordpress_roles': wpResponse['user']?['roles'] ?? [],
              'lastLogin': FieldValue.serverTimestamp(),
            });
          } else {
            await userRef.update({
              'lastLogin': FieldValue.serverTimestamp(),
              'email': email,
              'wordpress_id': wpResponse['user']?['id'] ?? '',
              'wordpress_roles': wpResponse['user']?['roles'] ?? [],
            });
          }

          final doc = await userRef.get();

          if (doc.data()?['isBlocked'] == true) {
            _showSnackBar('Cuenta pendiente de validación fiscal.', isError: true);

            await FirebaseAuth.instance.signOut();
            await ApiService().clearWordPressSession();

            if (mounted) {
              setState(() {
                _isLoading = false;
                _isAutoLogin = false;
              });
            }

            return;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ Firestore no disponible durante login. '
              'No se bloquea acceso porque WordPress ya validó sesión. Error: $e',
            );
          }
        }
      }

      // 8. Guardar email si Recuérdame. Nunca guardar contraseña.
      final prefs = await SharedPreferences.getInstance();

      if (_rememberMe) {
        await prefs.setBool(_rememberMeKey, true);
        await prefs.setString(_rememberEmailKey, email);
      } else {
        await prefs.setBool(_rememberMeKey, false);
        await prefs.remove(_rememberEmailKey);
      }

      // 9. Entrar a la app.
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } on FirebaseAuthException catch (e) {
      // No debería llegar aquí porque Firebase se maneja como apoyo, pero si llega
      // no borramos una sesión WordPress válida por un fallo de Firebase.
      final hasWpSession = await _hasStoredWordPressSession();

      if (hasWpSession) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
        return;
      }

      String message = 'Error de acceso.';

      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        message = 'Usuario o contraseña incorrectos en Firebase.';
      } else if (e.code == 'wrong-password') {
        message = 'Contraseña incorrecta en Firebase.';
      }

      _showSnackBar(message, isError: true);
    } catch (e) {
      _showSnackBar(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAutoLogin = false;
        });
      }
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontFamily: 'Oswald'),
        ),
        backgroundColor: isError ? Colors.red : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSavedCredentials || _isAutoLogin) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/gif/fondo2.gif',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Image.asset('assets/logo.png', height: 60),
                            const SizedBox(height: 16),
                            Text(
                              'INICIO DE SESIÓN',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                color: AppColors.primary,
                                fontFamily: 'Oswald',
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Oswald',
                              ),
                              decoration: _buildInputDecoration(
                                'Usuario / Email',
                                Icons.person_outline,
                              ),
                              validator: (val) =>
                              (val == null || val.trim().isEmpty)
                                  ? 'Campo requerido'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) {
                                if (!_isLoading) {
                                  _handleLogin();
                                }
                              },
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Oswald',
                              ),
                              decoration: _buildInputDecoration(
                                'Contraseña',
                                Icons.lock_outline,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: AppColors.primary,
                                  ),
                                  onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (val) =>
                              (val == null || val.isEmpty)
                                  ? 'Campo requerido'
                                  : null,
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  activeColor: AppColors.primary,
                                  onChanged: _onCheckboxChanged,
                                ),
                                GestureDetector(
                                  onTap: () => _onCheckboxChanged(!_rememberMe),
                                  child: const Text(
                                    'Recuérdame',
                                    style: TextStyle(
                                      fontFamily: 'Oswald',
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                child: _isLoading
                                    ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                    : const Text('ENTRAR'),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ForgotPasswordPage(),
                                  ),
                                ),
                                child: const Text(
                                  '¿Olvidaste contraseña?',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontFamily: 'Oswald',
                                    fontSize: 13,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '¿AÚN NO ERES CLIENTE?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Oswald',
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _abrirRegistro,
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text('SOLICITAR REGISTRO'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: AppColors.primary,
        fontFamily: 'Oswald',
      ),
      prefixIcon: Icon(icon, color: AppColors.primary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: 2,
        ),
      ),
      errorStyle: const TextStyle(
        fontFamily: 'Oswald',
        color: Colors.red,
      ),
    );
  }
}