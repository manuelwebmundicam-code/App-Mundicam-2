import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'banner_mix_provider.dart';

/// Provider que obtiene las RMA del usuario
final rmaProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return [];

  String? email;
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (userDoc.exists && userDoc.data() != null) {
      email = userDoc.get('email') as String?;
    }
  } catch (e) {
    debugPrint('Error al leer email: $e');
  }
  email ??= user.email ?? user.providerData.firstOrNull?.email;

  if (email == null || email.isEmpty) return [];

  return await apiService.getRmaRequests(email);
});
