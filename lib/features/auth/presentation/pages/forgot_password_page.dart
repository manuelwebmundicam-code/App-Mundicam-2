import 'package:flutter/material.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _emailSent = false;
  String _successEmail = '';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _solicitarRecuperacion() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();

    try {
      final result = await ApiService()
          .requestPasswordReset(email: email)
          .timeout(const Duration(seconds: 28));

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _emailSent = true;
          _successEmail = email;
        });
      } else {
        _showSnackBar(_mensajeCliente(result.message), isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar(
        'No se pudo enviar el correo de recuperación. Inténtalo de nuevo en unos minutos.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mensajeCliente(String message) {
    final clean = message.trim();
    if (clean.isEmpty) {
      return 'No se pudo enviar el correo de recuperación. Inténtalo de nuevo.';
    }

    final lower = clean.toLowerCase();
    final isTechnical = lower.contains('exception') ||
        lower.contains('woocommerce') ||
        lower.contains('wordpress') ||
        lower.contains('endpoint') ||
        lower.contains('backend') ||
        lower.contains('html') ||
        lower.contains('json') ||
        lower.contains('php') ||
        lower.contains('/my-account') ||
        lower.contains('/wp-json');

    if (isTechnical) {
      debugPrint('Mensaje técnico ocultado en recuperación: $clean');
      return 'No se pudo enviar el correo de recuperación. Inténtalo de nuevo en unos minutos.';
    }

    return clean;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Oswald'),
        ),
        backgroundColor: isError ? Colors.red : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) return 'Introduce tu correo electrónico';

    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!regex.hasMatch(email)) {
      return 'Introduce un correo electrónico válido';
    }

    return null;
  }

  void _volverLogin() {
    Navigator.of(context).maybePop();
  }

  void _cambiarCorreo() {
    setState(() {
      _emailSent = false;
      _successEmail = '';
    });
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary),
      labelStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Oswald',
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.78),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Image.asset('assets/logo.png', height: 58),
        const SizedBox(height: 16),
        Text(
          _emailSent ? 'REVISA TU CORREO' : 'RECUPERAR CONTRASEÑA',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.primary,
                fontFamily: 'Oswald',
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildRequestForm() {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            const Text(
              'Introduce la dirección de correo electrónico de tu cuenta MundiCam y te enviaremos un mensaje para restablecer tu contraseña.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Oswald',
              ),
              decoration: _inputDecoration('Correo electrónico', Icons.email),
              validator: _validateEmail,
              onFieldSubmitted: (_) {
                if (!_isLoading) _solicitarRecuperacion();
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: _isLoading ? null : _solicitarRecuperacion,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : const Text(
                        'ENVIAR CORREO',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Oswald',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _isLoading ? null : _volverLogin,
              child: const Text(
                'Volver al inicio de sesión',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Oswald',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          color: AppColors.primary,
          size: 58,
        ),
        const SizedBox(height: 14),
        _buildHeader(),
        const SizedBox(height: 14),
        Text(
          'Hemos enviado un mensaje a:',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary.withOpacity(0.9),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _successEmail,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Oswald',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Abre el correo y pulsa el botón de recuperación para crear una nueva contraseña en la web segura de MundiCam.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            onPressed: _volverLogin,
            child: const Text(
              'VOLVER AL INICIO',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Oswald',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _cambiarCorreo,
          child: const Text(
            'Usar otro correo',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Oswald',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
            child: Container(color: Colors.black.withOpacity(0.3)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _emailSent ? _buildSuccessView() : _buildRequestForm(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
