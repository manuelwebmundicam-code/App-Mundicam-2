import 'package:flutter/material.dart';

import 'package:mundicam/shared/pages/mundicam_web_page.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  static const String _registroUrl =
      'https://www.mundicam.com/altaweb-mundicam-security-distribution/';

  @override
  Widget build(BuildContext context) {
    return const MundicamWebPage(
      title: 'Alta profesional',
      url: _registroUrl,
      headerTitle: 'Registro profesional MundiCam',
      headerMessage:
          'Completa el formulario oficial dentro de la app. Tu alta necesita validación profesional antes de poder iniciar sesión.',
    );
  }
}
