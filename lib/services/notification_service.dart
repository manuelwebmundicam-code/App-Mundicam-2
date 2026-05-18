import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    // Pedir permiso
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Obtener token FCM
    final token = await _messaging.getToken();
    debugPrint('📱 FCM Token: $token');
    await _saveToken(token);

    // Escuchar mensajes en primer plano
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('📩 Notificación: ${message.notification?.title}');
      debugPrint('   Body: ${message.notification?.body}');
    });

    // Escuchar cuando se abre desde notificación
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('👆 Abierta desde notificación: ${message.data}');
    });

    // Token refrescado
    _messaging.onTokenRefresh.listen(_saveToken);
  }

  Future<void> _saveToken(String? token) async {
    if (token == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'fcm_token': token}, SetOptions(merge: true));
      debugPrint('✅ Token FCM guardado');
    }
  }
}