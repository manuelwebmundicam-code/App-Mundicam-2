// services/firebase_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/notifications/notification_service.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Singleton
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  // ================================================================
  // USUARIO ACTUAL
  // ================================================================
  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.uid;
  String? get currentUserEmail => _auth.currentUser?.email;

  // ================================================================
  // PERFIL DE USUARIO (AMPLIADO CON WOOCOMMERCE)
  // ================================================================

  /// Obtener los datos del perfil del usuario desde Firestore
  Future<Map<String, dynamic>?> getUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('Error al obtener perfil: $e');
      return null;
    }
  }

  /// Escuchar cambios en el perfil en tiempo real
  Stream<Map<String, dynamic>?> watchUserProfile() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _db
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((doc) => doc.exists ? doc.data() : null);
  }

  /// Actualizar el último acceso del usuario
  Future<void> updateLastLogin() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.collection('users').doc(user.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error al actualizar último acceso: $e');
    }
  }

  /// Crear o actualizar perfil de usuario (VERSIÓN COMPLETA)
  Future<void> saveUserProfile({
    required String email,
    String? wordpressId,
    String? displayName,
    String? phone,
    // Campos WooCommerce
    String? firstName,
    String? lastName,
    String? company,
    String? cifNif,
    String? address1,
    String? address2,
    String? postalCode,
    String? city,
    String? state,
    String? country,
    String? paymentMethod,
    double? creditLimit,
    double? creditUsed,
    String? assignedManager,
    int? wooCommerceId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final Map<String, dynamic> data = {
        'email': email,
        'uid': user.uid,
        'wordpress_id': wordpressId ?? '',
        'displayName': displayName ?? '',
        'phone': phone ?? '',
        'isBlocked': false,
        'lastLogin': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Añadir campos WooCommerce si están presentes
      if (firstName != null) data['first_name'] = firstName;
      if (lastName != null) data['last_name'] = lastName;
      if (company != null) data['company'] = company;
      if (cifNif != null) data['cif_nif'] = cifNif;
      if (address1 != null) data['address_1'] = address1;
      if (address2 != null) data['address_2'] = address2;
      if (postalCode != null) data['postal_code'] = postalCode;
      if (city != null) data['city'] = city;
      if (state != null) data['state'] = state;
      if (country != null) data['country'] = country;
      if (paymentMethod != null) data['payment_method'] = paymentMethod;
      if (creditLimit != null) data['credit_limit'] = creditLimit;
      if (creditUsed != null) data['credit_used'] = creditUsed;
      if (assignedManager != null) data['assigned_manager'] = assignedManager;
      if (wooCommerceId != null) data['woocommerce_id'] = wooCommerceId;

      await _db
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));
      debugPrint('✅ Perfil guardado en Firestore');
    } catch (e) {
      debugPrint('Error al guardar perfil: $e');
    }
  }

  /// Guardar datos de WooCommerce en el perfil del usuario
  Future<void> saveWooCommerceData(Map<String, dynamic> wooData) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.collection('users').doc(user.uid).set({
        'woocommerce_id': wooData['woocommerce_id'],
        'first_name': wooData['first_name'],
        'last_name': wooData['last_name'],
        'company': wooData['company'],
        'cif_nif': wooData['cif_nif'],
        'phone': wooData['phone'] ?? wooData['billing_phone'],
        'address_1': wooData['address_1'],
        'address_2': wooData['address_2'],
        'postal_code': wooData['postal_code'],
        'city': wooData['city'],
        'state': wooData['state'],
        'country': wooData['country'],
        'payment_method': wooData['payment_method'],
        'credit_limit': wooData['credit_limit'],
        'credit_used': wooData['credit_used'],
        'assigned_manager': wooData['assigned_manager'],
        'last_woo_sync': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ Datos de WooCommerce guardados en Firestore');
    } catch (e) {
      debugPrint('Error al guardar datos WooCommerce: $e');
    }
  }

  // ================================================================
  // FAVORITOS
  // ================================================================

  /// Añadir o quitar un producto de favoritos
  Future<void> toggleFavorito(int productoId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final docRef = _db
        .collection('users')
        .doc(user.uid)
        .collection('favoritos')
        .doc(productoId.toString());

    final doc = await docRef.get();

    if (doc.exists) {
      await docRef.delete();
      debugPrint('❤️ Favorito eliminado: $productoId');
    } else {
      await docRef.set({
        'id': productoId,
        'addedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('❤️ Favorito añadido: $productoId');
    }
  }

  /// Verificar si un producto es favorito (en tiempo real)
  Stream<bool> isFavorito(int productoId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(false);

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('favoritos')
        .doc(productoId.toString())
        .snapshots()
        .map((doc) => doc.exists);
  }

  /// Obtener todos los favoritos del usuario
  Future<List<int>> getFavoritos() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _db
          .collection('users')
          .doc(user.uid)
          .collection('favoritos')
          .get();

      return snapshot.docs
          .map((doc) => int.tryParse(doc.id) ?? 0)
          .where((id) => id > 0)
          .toList();
    } catch (e) {
      debugPrint('Error al obtener favoritos: $e');
      return [];
    }
  }

  // ================================================================
  // CARRITO (RESPALDO EN FIRESTORE)
  // ================================================================

  /// Guardar el carrito en Firestore
  Future<void> saveCart(List<Map<String, dynamic>> cartItems) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc('current')
          .set({'items': cartItems, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('Error al guardar carrito: $e');
    }
  }

  /// Cargar el carrito desde Firestore
  Future<List<Map<String, dynamic>>> loadCart() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final doc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc('current')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return List<Map<String, dynamic>>.from(data['items'] ?? []);
      }
      return [];
    } catch (e) {
      debugPrint('Error al cargar carrito: $e');
      return [];
    }
  }

  /// Limpiar el carrito en Firestore
  Future<void> clearCart() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('cart')
          .doc('current')
          .delete();
    } catch (e) {
      debugPrint('Error al limpiar carrito: $e');
    }
  }

  // ================================================================
  // PEDIDOS (RESPALDO LOCAL)
  // ================================================================

  /// Guardar un pedido en Firestore (respaldo)
  Future<void> saveOrder(Map<String, dynamic> orderData) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.collection('users').doc(user.uid).collection('orders').add({
        ...orderData,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
    } catch (e) {
      debugPrint('Error al guardar pedido: $e');
    }
  }

  /// Obtener pedidos del usuario desde Firestore
  Future<List<Map<String, dynamic>>> getUserOrders() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _db
          .collection('users')
          .doc(user.uid)
          .collection('orders')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error al obtener pedidos: $e');
      return [];
    }
  }

  // ================================================================
  // SESIÓN
  // ================================================================

  /// Cerrar sesión
  Future<void> signOut() async {
    await NotificationService().clearDeviceRegistration();
    await ApiService().clearWordPressSession();
    await _auth.signOut();
  }

  /// Verificar si el usuario está autenticado
  bool get isLoggedIn => _auth.currentUser != null;

  /// Escuchar cambios en la autenticación
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
