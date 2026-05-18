import 'package:flutter/material.dart';

/// Obtiene el Navigator más cercano que NO sea el root
/// Esto permite navegar dentro de la pestaña actual
NavigatorState? getTabNavigator(BuildContext context) {
  // Busca el Navigator más cercano (que será el de la pestaña)
  return Navigator.of(context);
}