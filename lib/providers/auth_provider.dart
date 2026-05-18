import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserState {
  final String email;
  final bool isLoggedIn;

  UserState({required this.email, this.isLoggedIn = false});
}

class AuthNotifier extends StateNotifier<UserState> {
  AuthNotifier() : super(UserState(email: "", isLoggedIn: false)) {
    // Intentamos cargar la sesión en cuanto se crea el provider
    _loadSession();
  }

  // Carga el email guardado en el disco
  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('user_email');

    if (savedEmail != null && savedEmail.isNotEmpty) {
      state = UserState(email: savedEmail, isLoggedIn: true);
    }
  }

  // Inicia sesión y guarda en el disco
  Future<void> login(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', email);
    state = UserState(email: email, isLoggedIn: true);
  }

  // Borra la sesión del disco
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');
    state = UserState(email: "", isLoggedIn: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, UserState>((ref) {
  return AuthNotifier();
});