import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'home_page.dart';
import 'forgot_password_page.dart';

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
      'https://mundicam.com/wp-json/mundicam/v1/firebase-login';

  static const String _registroUrl =
      'https://www.mundicam.com/altaweb-mundicam-security-distribution/';

  static const String _rememberEmailKey = 'remembered_email';
  static const String _rememberPasswordKey = 'remembered_password';
  static const String _rememberMeKey = 'remember_me_enabled';

  @override
  void initState() {
    super.initState();

    _emailController.addListener(_guardarCredencialesSiCorresponde);
    _passwordController.addListener(_guardarCredencialesSiCorresponde);

    _inicializarLogin();
  }

  // ================================================================
  // INICIALIZAR LOGIN
  // Si Recuérdame está activo, intenta entrar automáticamente
  // ================================================================
  Future<void> _inicializarLogin() async {
    final prefs = await SharedPreferences.getInstance();

    final bool rememberMeGuardado = prefs.getBool(_rememberMeKey) ?? false;
    final String emailGuardado = prefs.getString(_rememberEmailKey) ?? '';
    final String passwordGuardada = prefs.getString(_rememberPasswordKey) ?? '';

    if (!mounted) return;

    setState(() {
      _rememberMe = rememberMeGuardado;
      _emailController.text = rememberMeGuardado ? emailGuardado : '';
      _passwordController.text = rememberMeGuardado ? passwordGuardada : '';
      _isLoadingSavedCredentials = false;
    });

    if (rememberMeGuardado &&
        emailGuardado.trim().isNotEmpty &&
        passwordGuardada.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      setState(() {
        _isAutoLogin = true;
      });

      await _handleLogin(fromAutoLogin: true);
    }
  }

  // ================================================================
  // GUARDAR CREDENCIALES SI RECUÉRDAME ESTÁ ACTIVO
  // ================================================================
  Future<void> _guardarCredencialesSiCorresponde() async {
    if (!_rememberMe) return;
    if (_isLoadingSavedCredentials) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_rememberMeKey, true);
    await prefs.setString(_rememberEmailKey, _emailController.text.trim());
    await prefs.setString(_rememberPasswordKey, _passwordController.text);
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
      await prefs.setString(_rememberPasswordKey, _passwordController.text);
    } else {
      await prefs.setBool(_rememberMeKey, false);
      await prefs.remove(_rememberEmailKey);
      await prefs.remove(_rememberPasswordKey);
    }
  }

  Future<void> _abrirRegistro() async {
    final url = Uri.parse(_registroUrl);

    final abierto = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );

    if (!abierto) {
      _showSnackBar(
        'No se pudo abrir la página de registro.',
        isError: true,
      );
    }
  }

  Future<Map<String, dynamic>?> _authenticateWithWordPress({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_loginEndpoint),
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      debugPrint('Status WordPress login: ${response.statusCode}');
      debugPrint('Body WordPress login: ${response.body}');

      Map<String, dynamic>? body;

      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('Respuesta no válida del servidor.');
      }

      if (response.statusCode == 200) {
        return body;
      }

      throw Exception(
        body['message'] ?? 'Usuario o contraseña incorrectos.',
      );
    } catch (e) {
      debugPrint('Error WordPress: $e');
      rethrow;
    }
  }

  Future<void> _handleLogin({bool fromAutoLogin = false}) async {
    if (!fromAutoLogin) {
      if (!_formKey.currentState!.validate()) return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String email = _emailController.text.trim();
      final String password = _passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Introduce usuario y contraseña.');
      }

      // 1. Autenticar contra WordPress
      final wpResponse = await _authenticateWithWordPress(
        email: email,
        password: password,
      );

      if (wpResponse == null) {
        _showSnackBar(
          'Error al conectar con el servidor.',
          isError: true,
        );
        return;
      }

      if (wpResponse['success'] == false) {
        _showSnackBar(
          wpResponse['message'] ?? 'Credenciales incorrectas.',
          isError: true,
        );
        return;
      }

      // 2. Login en Firebase
      final bool vieneDeWordPress = wpResponse.containsKey('firebase_token');

      if (vieneDeWordPress) {
        await FirebaseAuth.instance.signInWithCustomToken(
          wpResponse['firebase_token'],
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _showSnackBar(
          'No se pudo iniciar sesión.',
          isError: true,
        );
        return;
      }

      // 3. Solo verificar email si NO viene de WordPress
      if (!vieneDeWordPress && !user.emailVerified) {
        _showSnackBar(
          'Debes verificar tu email antes de entrar.',
          isError: true,
        );

        await FirebaseAuth.instance.signOut();

        if (mounted) {
          setState(() {
            _isLoading = false;
            _isAutoLogin = false;
          });
        }

        return;
      }

      // 4. Crear/actualizar documento en Firestore
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
          'lastLogin': FieldValue.serverTimestamp(),
        });
      } else {
        await userRef.update({
          'lastLogin': FieldValue.serverTimestamp(),
          'email': email,
          'wordpress_id': wpResponse['user']?['id'] ?? '',
        });
      }

      // 5. Verificar si está bloqueado
      final doc = await userRef.get();

      final data = doc.data();
      final bool isBlocked = data?['isBlocked'] == true;

      if (isBlocked) {
        _showSnackBar(
          'Cuenta pendiente de validación fiscal.',
          isError: true,
        );

        await FirebaseAuth.instance.signOut();

        if (mounted) {
          setState(() {
            _isLoading = false;
            _isAutoLogin = false;
          });
        }

        return;
      }

      // 6. Guardar o borrar credenciales según Recuérdame
      final prefs = await SharedPreferences.getInstance();

      if (_rememberMe) {
        await prefs.setBool(_rememberMeKey, true);
        await prefs.setString(_rememberEmailKey, email);
        await prefs.setString(_rememberPasswordKey, password);
      } else {
        await prefs.setBool(_rememberMeKey, false);
        await prefs.remove(_rememberEmailKey);
        await prefs.remove(_rememberPasswordKey);
      }

      // 7. Entrar a la app
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HomePage(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Error de acceso.';

      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        message = 'Usuario o contraseña incorrectos.';
      } else if (e.code == 'wrong-password') {
        message = 'Contraseña incorrecta.';
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
    _emailController.removeListener(_guardarCredencialesSiCorresponde);
    _passwordController.removeListener(_guardarCredencialesSiCorresponde);

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
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/gif/fondo.gif',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
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
                          color: Colors.white.withOpacity(0.9),
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
                            Image.asset(
                              'assets/logo.png',
                              height: 60,
                            ),
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
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Campo requerido';
                                }

                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [
                                AutofillHints.password,
                              ],
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
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return 'Campo requerido';
                                }

                                return null;
                              },
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  activeColor: AppColors.primary,
                                  onChanged: _onCheckboxChanged,
                                ),
                                GestureDetector(
                                  onTap: () {
                                    _onCheckboxChanged(!_rememberMe);
                                  },
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
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                      const ForgotPasswordPage(),
                                    ),
                                  );
                                },
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
                          color: Colors.white.withOpacity(0.9),
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
      prefixIcon: Icon(
        icon,
        color: AppColors.primary,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.primary,
        ),
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