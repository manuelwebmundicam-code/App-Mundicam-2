// models/user_profile.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String nombreContacto;
  final String razonSocial;
  final String telefono;
  final String cifNif;
  final String role;
  final bool isBlocked;
  final DateTime? createdAt;

  // Campos adicionales de WooCommerce (opcionales)
  final String? gestorAsignado;
  final String? direccion;
  final String? codigoPostal;
  final String? ciudad;
  final String? provincia;
  final String? pais;
  final String? formaPago;
  final double? limiteCredito;
  final double? creditoUsado;

  const AppUser({
    required this.uid,
    required this.email,
    required this.nombreContacto,
    required this.razonSocial,
    required this.telefono,
    required this.cifNif,
    required this.role,
    required this.isBlocked,
    this.createdAt,
    this.gestorAsignado,
    this.direccion,
    this.codigoPostal,
    this.ciudad,
    this.provincia,
    this.pais,
    this.formaPago,
    this.limiteCredito,
    this.creditoUsado,
  });

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return AppUser(
      uid: doc.id,
      email: data['email'] ?? '',
      nombreContacto: data['nombre_contacto'] ?? '',
      razonSocial: data['razon_social'] ?? '',
      telefono: data['telefono'] ?? '',
      cifNif: data['cif_nif'] ?? '',
      role: data['role'] ?? 'cliente',
      isBlocked: data['isBlocked'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      // WooCommerce
      gestorAsignado: data['gestor_asignado'],
      direccion: data['direccion'],
      codigoPostal: data['codigo_postal'],
      ciudad: data['ciudad'],
      provincia: data['provincia'],
      pais: data['pais'],
      formaPago: data['forma_pago'],
      limiteCredito: data['limite_credito'] != null
          ? (data['limite_credito'] as num).toDouble()
          : null,
      creditoUsado: data['credito_usado'] != null
          ? (data['credito_usado'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'nombre_contacto': nombreContacto,
      'razon_social': razonSocial,
      'telefono': telefono,
      'cif_nif': cifNif,
      'role': role,
      'isBlocked': isBlocked,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      // WooCommerce
      if (gestorAsignado != null) 'gestor_asignado': gestorAsignado,
      if (direccion != null) 'direccion': direccion,
      if (codigoPostal != null) 'codigo_postal': codigoPostal,
      if (ciudad != null) 'ciudad': ciudad,
      if (provincia != null) 'provincia': provincia,
      if (pais != null) 'pais': pais,
      if (formaPago != null) 'forma_pago': formaPago,
      if (limiteCredito != null) 'limite_credito': limiteCredito,
      if (creditoUsado != null) 'credito_usado': creditoUsado,
    };
  }

  // Propiedades calculadas
  String get inicial {
    if (nombreContacto.isNotEmpty) {
      return nombreContacto[0].toUpperCase();
    }
    if (razonSocial.isNotEmpty) {
      return razonSocial[0].toUpperCase();
    }
    return email.isNotEmpty ? email[0].toUpperCase() : 'M';
  }

  String get nombreMostrar {
    if (nombreContacto.isNotEmpty) return nombreContacto;
    if (razonSocial.isNotEmpty) return razonSocial;
    return email.split('@').first;
  }

  double get creditoDisponible => (limiteCredito ?? 0) - (creditoUsado ?? 0);

  double get porcentajeCredito => limiteCredito != null && limiteCredito! > 0
      ? ((creditoUsado ?? 0) / limiteCredito!) * 100
      : 0;

  bool get tieneDireccion =>
      direccion != null || ciudad != null || provincia != null;

  bool get tieneDatosWooCommerce =>
      gestorAsignado != null || limiteCredito != null || formaPago != null;
}