import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/notifications/notification_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/auth/presentation/pages/login_page.dart';

class BlockedPage extends StatelessWidget {
  const BlockedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Usamos el fondo definido en tu tema
      backgroundColor: AppColors.background,
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icono de error usando el color primario (rojo Mundicam)
            const Icon(Icons.gpp_bad, color: AppColors.primary, size: 120),
            const SizedBox(height: 20),

            Text(
              'ACCESO RESTRINGIDO',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Oswald',
                fontSize: 28,
                color: AppColors.primary, // Rojo Mundicam
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),

            const Text(
              'Tu cuenta ha sido bloqueada por la administración. Si crees que es un error, contacta con soporte técnico.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Oswald',
                fontSize: 16,
                color: AppColors
                    .textSecondary, // Gris oscuro definido en tu AppColors
              ),
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: 200,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, // Fondo rojo
                  foregroundColor: Colors.white, // Texto blanco
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  await NotificationService().clearDeviceRegistration();
                  await FirebaseAuth.instance.signOut();
                  await ApiService().clearWordPressSession();

                  // Volvemos al Login borrando todo el historial de navegación
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                    );
                  }
                },
                child: const Text('VOLVER AL INICIO'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
