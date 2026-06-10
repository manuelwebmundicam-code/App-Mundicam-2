import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPassController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. Crear usuario en Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      // 2. ENVIAR EMAIL DE VERIFICACIÓN
      await userCredential.user!.sendEmailVerification();

      // 3. Guardar en Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
            'uid': userCredential.user!.uid,
            'nombre_contacto': _nameController.text.trim(),
            'razon_social': _companyController.text.trim(),
            'cif_nif': _taxIdController.text.trim().toUpperCase(),
            'telefono': _phoneController.text.trim(),
            'email': _emailController.text.trim(),
            'isBlocked':
                false, // CAMBIADO A FALSE: Para que no de error fiscal al entrar tras verificar email
            'role': 'client',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        _showSnackBar("Registro casi listo. Verifica tu email para continuar.");
        await FirebaseAuth.instance.signOut();
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Error al registrar";
      if (e.code == 'email-already-in-use') msg = "El correo ya está en uso.";
      if (e.code == 'weak-password') msg = "La contraseña es muy débil.";
      _showSnackBar(msg, isError: true);
    } catch (e) {
      _showSnackBar("Error inesperado", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Oswald')),
        backgroundColor: isError ? Colors.red : AppColors.primary,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _taxIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/gif/fondo.gif', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Form(
                key: _formKey,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ALTA DE PROFESIONAL',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Datos requeridos para validación B2B',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),

                      _buildInput(
                        _companyController,
                        'Razón Social / Empresa',
                        Icons.business,
                      ),
                      const SizedBox(height: 12),
                      _buildInput(
                        _taxIdController,
                        'CIF / NIF',
                        Icons.featured_video_outlined,
                      ),
                      const SizedBox(height: 12),
                      _buildInput(
                        _nameController,
                        'Persona de Contacto',
                        Icons.person,
                      ),
                      const SizedBox(height: 12),
                      _buildInput(
                        _phoneController,
                        'Teléfono',
                        Icons.phone,
                        type: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _buildInput(
                        _emailController,
                        'Email Profesional',
                        Icons.email,
                        type: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildPasswordInput(_passwordController, 'Contraseña'),
                      const SizedBox(height: 12),
                      _buildPasswordInput(
                        _confirmPassController,
                        'Confirmar Contraseña',
                        isConfirm: true,
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleRegister,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('SOLICITAR ALTA'),
                        ),
                      ),

                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          '¿Ya tienes cuenta? Inicia sesión',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Oswald',
                          ),
                        ),
                      ),
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

  Widget _buildInput(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(
        fontFamily: 'Oswald',
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.primary),
        isDense: true,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildPasswordInput(
    TextEditingController ctrl,
    String label, {
    bool isConfirm = false,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: _obscurePassword,
      style: const TextStyle(
        fontFamily: 'Oswald',
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.primary),
        isDense: true,
        prefixIcon: const Icon(Icons.lock, color: AppColors.primary, size: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            size: 20,
            color: AppColors.primary,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Requerido';
        if (v.length < 6) return 'Mínimo 6 caracteres';
        if (isConfirm && v != _passwordController.text) return 'No coinciden';
        return null;
      },
    );
  }
}
