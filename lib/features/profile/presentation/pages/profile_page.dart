import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/core/notifications/notification_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/auth/presentation/pages/login_page.dart';
import 'package:mundicam/features/rma/presentation/pages/rma_page.dart';
import 'package:mundicam/features/support/presentation/pages/support_tickets_page.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0xFFE5E7EB);

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  Map<String, dynamic>? _wooCustomer;
  bool _loadingData = true;
  bool _isAdmin = false;
  String _roleLabel = 'Cliente';
  IconData _roleIcon = Icons.person_outline_rounded;
  String? _errorMessage;
  bool _requestingDataChange = false;
  bool _deletingAccount = false;

  Color get _roleColor {
    final label = _roleLabel.toLowerCase();
    if (_isAdmin || label.contains('admin')) return Colors.deepPurple;
    if (label.contains('comercial')) return const Color(0xFF128C4A);
    return AppColors.primary;
  }

  Color get _brandColor => _roleColor;

  void _setVisibleRole(List<String> roles) {
    final normalizedRoles = roles.map((role) => role.toLowerCase().trim()).toList();

    if (normalizedRoles.any((role) =>
        role == 'administrator' ||
        role == 'administrador' ||
        role == 'shop_manager' ||
        role == 'gestor_de_la_tienda' ||
        role.contains('admin'))) {
      _isAdmin = true;
      _roleLabel = 'Administrador';
      _roleIcon = Icons.admin_panel_settings_outlined;
      return;
    }

    if (normalizedRoles.any((role) => role.contains('comercial'))) {
      _isAdmin = false;
      _roleLabel = 'Comercial';
      _roleIcon = Icons.support_agent_outlined;
      return;
    }

    _isAdmin = false;
    _roleLabel = 'Cliente';
    _roleIcon = Icons.business_center_outlined;
  }

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    final apiService = ApiService();
    final user = FirebaseAuth.instance.currentUser;

    debugPrint('🔍 Cargando perfil - Firebase UID: ${user?.uid ?? '-'}');
    debugPrint(' Email Firebase Auth: ${user?.email ?? '-'}');

    try {
      Map<String, dynamic>? firestoreData;

      if (user != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            firestoreData = userDoc.data();
            if (firestoreData?['isBlocked'] == true) {
              if (mounted) {
                setState(() {
                  _errorMessage = 'Cuenta bloqueada';
                  _loadingData = false;
                });
              }
              return;
            }

            final firestoreRole = firestoreData?['role']?.toString().trim().toLowerCase();
            _isAdmin = firestoreRole == 'admin' ||
                firestoreRole == 'administrator' ||
                firestoreRole == 'administrador';
            if (_isAdmin) {
              _roleLabel = 'Administrador';
              _roleIcon = Icons.admin_panel_settings_outlined;
            } else if ((firestoreRole ?? '').contains('comercial')) {
              _roleLabel = 'Comercial';
              _roleIcon = Icons.support_agent_outlined;
            }

            debugPrint(' Firestore role: ${firestoreData?['role']}');
            debugPrint(' Firestore email: ${firestoreData?['email']}');
          }
        } catch (e) {
          debugPrint('⚠️ Firestore no disponible para perfil: $e');
        }
      }

      String? email = await apiService.currentSessionEmail();

      if (email == null || email.isEmpty) {
        email = user?.email?.trim().toLowerCase();
      }

      if (email == null || email.isEmpty) {
        email = _stringFromUserData(
          firestoreData,
          const [
            'email',
            'billing_email',
            'user_email',
            'customer_email',
          ],
        );
      }

      if ((email == null || email.isEmpty) && user != null && user.providerData.isNotEmpty) {
        email = user.providerData.first.email?.trim().toLowerCase();
      }

      int? wordpressId = await apiService.currentSessionWordPressId();
      wordpressId ??= _extractWordPressId(
        firestoreData: firestoreData,
        firebaseUid: user?.uid ?? '',
      );

      final roles = await apiService.currentSessionRoles();
      _setVisibleRole(roles);

      debugPrint(' Email final perfil: ${email ?? '-'}');
      debugPrint(' WordPress ID final perfil: ${wordpressId ?? '-'}');
      debugPrint(' Roles App API perfil: $roles');

      Map<String, dynamic>? wooCustomer;

      if (email != null && email.isNotEmpty) {
        wooCustomer = await apiService.getCustomerByEmail(email);
      }

      if (wooCustomer == null && wordpressId != null && wordpressId > 0) {
        wooCustomer = await apiService.getCustomerById(wordpressId);
      }

      if (wooCustomer != null) {
        debugPrint(
          '✅ Cliente encontrado: ${wooCustomer['first_name']} ${wooCustomer['last_name']}',
        );
        if (mounted) {
          setState(() {
            _wooCustomer = wooCustomer;
            _loadingData = false;
          });
        }
      } else {
        debugPrint('⚠️ Cliente no encontrado en WooCommerce');
        if (mounted) {
          setState(() {
            _errorMessage = 'Cliente no encontrado.\nContacta con tu gestor comercial.';
            _loadingData = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error de conexión';
          _loadingData = false;
        });
      }
    }
  }

  String? _stringFromUserData(
      Map<String, dynamic>? data,
      List<String> keys,
      ) {
    if (data == null || data.isEmpty) return null;

    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null &&
          value.isNotEmpty &&
          value != '—' &&
          value.toLowerCase() != 'null') {
        return value.toLowerCase();
      }
    }

    return null;
  }

  int? _extractWordPressId({
    required Map<String, dynamic>? firestoreData,
    required String firebaseUid,
  }) {
    final keys = [
      'wordpress_id',
      'wordpressId',
      'woocommerce_id',
      'woocommerceId',
      'customer_id',
      'customerId',
      'wp_user_id',
      'wpUserId',
      'woo_customer_id',
      'wooCustomerId',
      'uid',
    ];

    if (firestoreData != null && firestoreData.isNotEmpty) {
      for (final key in keys) {
        final parsed = _parsePositiveInt(firestoreData[key]);
        if (parsed != null && parsed > 0) return parsed;

        final parsedFromText = _extractWpIdFromText(firestoreData[key]);
        if (parsedFromText != null && parsedFromText > 0) {
          return parsedFromText;
        }
      }
    }

    return _extractWpIdFromText(firebaseUid);
  }

  int? _parsePositiveInt(dynamic value) {
    if (value == null) return null;

    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();

    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    final parsed = int.tryParse(raw);
    if (parsed != null && parsed > 0) return parsed;

    return null;
  }

  int? _extractWpIdFromText(dynamic value) {
    if (value == null) return null;

    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    final direct = int.tryParse(raw);
    if (direct != null && direct > 0) return direct;

    final match = RegExp(r'wp[_-]?(\d+)', caseSensitive: false).firstMatch(raw);
    if (match != null) {
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }

    return null;
  }

  void _refreshProfile() {
    setState(() {
      _loadingData = true;
      _errorMessage = null;
    });
    _cargarDatosUsuario();
  }

  String _getInicial() {
    if (_wooCustomer != null) {
      final n = _wooCustomer!['first_name']?.toString() ?? '';
      if (n.isNotEmpty) return n[0].toUpperCase();
      final c = _wooCustomer!['billing']?['company']?.toString() ?? '';
      if (c.isNotEmpty) return c[0].toUpperCase();
    }
    final e = _wooCustomer?['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '';
    return e.isNotEmpty ? e[0].toUpperCase() : 'M';
  }

  String _getDisplayName() {
    if (_wooCustomer != null) {
      final f = _wooCustomer!['first_name']?.toString() ?? '';
      final l = _wooCustomer!['last_name']?.toString() ?? '';
      if (f.isNotEmpty || l.isNotEmpty) return '$f $l'.trim();
    }
    return 'Usuario';
  }


  String _getMeta(String key) {
    if (_wooCustomer == null) return "—";
    final meta = _wooCustomer!['meta_data'] as List? ?? [];
    try {
      for (final m in meta) {
        if (m is Map && m['key']?.toString().toLowerCase().trim() == key.toLowerCase().trim()) {
          return m['value']?.toString() ?? "—";
        }
      }
    } catch (_) {}
    return "—";
  }

  String _safeValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return '—';
    return text;
  }

  String _maskSensitivePaymentData(String value) {
    var text = value.trim();
    if (text.isEmpty || text == '—' || text.toLowerCase() == 'null') {
      return '—';
    }
    text = text.replaceAllMapped(
      RegExp(r'\b([A-Z]{2}\d{2}[A-Z0-9\s]{10,34})\b', caseSensitive: false),
          (match) {
        final iban = match.group(1)!.replaceAll(' ', '').toUpperCase();
        final last4 = iban.length >= 4 ? iban.substring(iban.length - 4) : '****';
        final prefix = iban.length >= 2 ? iban.substring(0, 2) : '**';
        return '$prefix** **** **** **** **** $last4';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(?:\d[ -]?){12,19}\b'),
          (match) {
        final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
        if (digits.length < 12) return match.group(0)!;
        final last4 = digits.substring(digits.length - 4);
        return '****$last4';
      },
    );
    return text;
  }

  String _getPaymentMethodRaw() {
    final keys = [
      'payment_method',
      '_payment_method',
      'payment_method_title',
      '_payment_method_title',
      'billing_payment_method',
      'customer_payment_method',
      'default_payment_method',
      'b2b_payment_method',
    ];
    for (final key in keys) {
      final value = _getMeta(key).trim();
      if (value.isNotEmpty && value != '—' && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return '';
  }

  String _paymentMethodLabel() {
    final raw = _getPaymentMethodRaw().trim();
    if (raw.isEmpty || raw == '—' || raw.toLowerCase() == 'null') {
      return '—';
    }
    final value = raw.toLowerCase();
    final masked = _maskSensitivePaymentData(raw);

    if (value.contains('bacs') || value.contains('transferencia') || value.contains('bank') || value.contains('iban')) {
      return masked == raw ? 'Transferencia bancaria' : 'Transferencia bancaria · $masked';
    }
    if (value.contains('redsys') || value.contains('tarjeta') || value.contains('card') || value.contains('tpv') || value.contains('stripe')) {
      final last4Match = RegExp(r'\*{2,}\d{4}').firstMatch(masked);
      if (last4Match != null) {
        return 'Tarjeta terminada en ${last4Match.group(0)}';
      }
      return 'Tarjeta bancaria';
    }
    if (value.contains('paypal')) {
      return 'PayPal';
    }
    if (value.contains('cheque') || value.contains('giro') || value.contains('pagare') || value.contains('pagaré') || value.contains('aplazado') || value.contains('credito') || value.contains('crédito')) {
      return 'Giro / pago aplazado';
    }
    return masked;
  }

  String _creditLimitLabel() {
    final credit = _getMeta('credit_limit').trim();
    if (credit.isEmpty || credit == '—' || credit == '0' || credit == '0.0' || credit == '0.00' || credit.toLowerCase() == 'null') {
      return 'No aplica';
    }
    if (credit.contains('€')) return credit;
    return '$credit€';
  }


  // ================= MÉTODOS MEJORADOS =================
  String _cleanManagerValue(dynamic value) {
    final manager = value?.toString().trim() ?? '';
    if (manager.isEmpty || manager == '—') return '';
    final lower = manager.toLowerCase();
    if (lower == 'null' ||
        lower == 'false' ||
        lower == 'sin asignar' ||
        lower == 'no asignado' ||
        lower == '__mc_add_new_gestor__') {
      return '';
    }

    // El gestor de MundiCam viene del selector web wpuef_cid_c30 y debe
    // mostrarse como nombre/texto, no como email. Si el backend sigue
    // devolviendo solo un email, no lo usamos como nombre de gestor.
    if (manager.contains('@')) return '';

    return manager;
  }

  static const Map<String, Map<String, String>> _localManagerContacts = {
    'damian mateo': {
      'email': 'dmateo@mundicam.com',
      'phone': '633806898',
    },
    'juan garcia': {
      'email': 'jgarcia@mundicam.com',
      'phone': '622943654',
    },
    'manuel': {
      'email': 'mreynaldo@mundicam.com',
      'phone': '619078632',
    },
    'proshop murcia': {
      'email': 'proshop.murcia@mundicam.com',
      'phone': '616545669',
    },
    'ricardo': {
      'email': 'rcano@mundicam.com',
      'phone': '606111983',
    },
  };

  String _normalizeManagerLookupKey(String value) {
    var normalized = value.trim().toLowerCase();
    const replacements = <String, String>{
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
    };
    replacements.forEach((from, to) {
      normalized = normalized.replaceAll(from, to);
    });
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _getAssignedManagerNameCandidate() {
    final managerData = _wooCustomer?['manager'];
    final nestedManager = managerData is Map ? managerData : const <dynamic, dynamic>{};

    final directCandidates = <dynamic>[
      nestedManager['name'],
      _wooCustomer?['manager_name'],
      _wooCustomer?['gestor_asignado'],
      _wooCustomer?['assigned_manager'],
      _wooCustomer?['wpuef_cid_c30'],
      _wooCustomer?['commercial_manager'],
      _wooCustomer?['sales_manager'],
    ];

    for (final value in directCandidates) {
      final manager = _cleanManagerValue(value);
      if (manager.isNotEmpty) return manager;
    }

    final keys = [
      'wpuef_cid_c30',
      'manager_name',
      'gestor_asignado',
      'assigned_manager',
      'commercial_manager',
      'sales_manager',
    ];

    for (final key in keys) {
      final manager = _cleanManagerValue(_getMeta(key));
      if (manager.isNotEmpty) return manager;
    }

    return '';
  }

  Map<String, String>? _getLocalManagerContact() {
    final name = _getAssignedManagerNameCandidate();
    if (name.isEmpty) return null;
    return _localManagerContacts[_normalizeManagerLookupKey(name)];
  }

  String _getAssignedManager() {
    final manager = _getAssignedManagerNameCandidate();
    if (manager.isNotEmpty) return manager;

    return _getManagerEmail().contains('@')
        ? 'Gestor / técnico asignado'
        : 'No asignado';
  }

  String _getManagerEmail() {
    final managerData = _wooCustomer?['manager'];
    final nestedManager = managerData is Map ? managerData : const <dynamic, dynamic>{};
    final candidates = <dynamic>[
      nestedManager['email'],
      _wooCustomer?['manager_email'],
      _getMeta('manager_email'),
    ];

    for (final value in candidates) {
      final email = value?.toString().trim() ?? '';
      if (email.isNotEmpty &&
          email != '—' &&
          email.toLowerCase() != 'null' &&
          email.contains('@')) {
        return email;
      }
    }

    final localEmail = _getLocalManagerContact()?['email']?.trim() ?? '';
    if (localEmail.contains('@')) return localEmail;

    return '—';
  }

  String _getManagerPhone() {
    final managerData = _wooCustomer?['manager'];
    final nestedManager = managerData is Map ? managerData : const <dynamic, dynamic>{};
    final candidates = <dynamic>[
      nestedManager['phone'],
      _wooCustomer?['manager_phone'],
      _getMeta('manager_phone'),
    ];

    for (final value in candidates) {
      final phone = value?.toString().trim() ?? '';
      if (phone.isNotEmpty &&
          phone != '—' &&
          phone.toLowerCase() != 'null') {
        return phone;
      }
    }
    final localPhone = _getLocalManagerContact()?['phone']?.trim() ?? '';
    if (localPhone.isNotEmpty) return localPhone;

    return '—';
  }

  Future<void> _callManager() async {
    final phone = _getManagerPhone();
    if (phone == '—') return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir la aplicación de teléfono.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _emailManager() async {
    final email = _getManagerEmail();
    if (!email.contains('@')) return;

    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: const <String, String>{
        'subject': 'Consulta desde la app MundiCam',
      },
    );

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir la aplicación de correo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _getCifNif() {
    final possibleKeys = [
      'shipping_nif',
      'cif_nif',
      'cif',
      'nif',
      'vat_number',
      'billing_vat',
      'company_vat',
      'tax_id',
      'billing_cif',
      'billing_nif',
      '_billing_cif',
      '_billing_nif',
      '_cif_nif',
      'customer_vat',
      'dni',
      'document_number',
    ];

    for (final key in possibleKeys) {
      final value = _getMeta(key).trim();
      if (value.isNotEmpty && value != '—' && value.toLowerCase() != 'null') {
        return value;
      }
    }

    final billing = _wooCustomer?['billing'];
    if (billing is Map) {
      for (final key in possibleKeys) {
        final value = billing[key]?.toString().trim();
        if (value != null &&
            value.isNotEmpty &&
            value != '—' &&
            value.toLowerCase() != 'null') {
          return value;
        }
      }
    }

    final shipping = _wooCustomer?['shipping'];
    if (shipping is Map) {
      for (final key in possibleKeys) {
        final value = shipping[key]?.toString().trim();
        if (value != null &&
            value.isNotEmpty &&
            value != '—' &&
            value.toLowerCase() != 'null') {
          return value;
        }
      }
    }

    return '—';
  }
  // =================================================

  @override
  Widget build(BuildContext context) {
    MundicamAnalyticsService.instance
        .trackScreenViewForRoute(context, 'profile');
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: _ProfilePageAppBar(
        title: 'MI CUENTA',
        backgroundColor: _brandColor,
        onBack: () => Navigator.of(context).maybePop(),
        onRefresh: _refreshProfile,
        onLogout: () => _confirmSignOut(context),
      ),
      body: _loadingData
          ? Center(
        child: CircularProgressIndicator(color: _brandColor),
      )
          : SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                children: [
                  _buildMainCard(),
                  const SizedBox(height: 22),
                  _buildManagerCard(),
                  const SizedBox(height: 22),
                  _buildMenuCard(
                    context,
                    title: "DATOS DE LA CUENTA",
                    items: [
                      _buildActionMenuItem(
                        icon: Icons.manage_accounts_outlined,
                        title: "Solicitar cambio de datos",
                        subtitle: _requestingDataChange
                            ? "Enviando solicitud..."
                            : "Indica qué datos necesitas actualizar",
                        onTap: _requestingDataChange
                            ? null
                            : _requestDataChange,
                        trailing: _requestingDataChange
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _brandColor,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _buildMenuCard(
                    context,
                    title: "SOPORTE Y REPARACIONES",
                    items: [
                      _buildMenuItem(
                        context,
                        Icons.handyman_outlined,
                        "Gestión de RMA",
                        "Material en reparación",
                        const RmaPage(),
                      ),
                      _buildMenuItem(
                        context,
                        Icons.chat_bubble_outline_rounded,
                        "Tickets Técnicos",
                        "Habla con soporte",
                        const SupportTicketsPage(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _buildDeleteAccountCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: _pageBg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: _brandColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _brandColor.withOpacity(0.18),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _getInicial(),
                      style: TextStyle(
                        color: _brandColor,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Oswald',
                      ),
                    ),
                  ),
                ),
                if (_isAdmin)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield,
                        color: Colors.deepPurple,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _getDisplayName(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _dark,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Oswald',
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profilePill({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    if (_errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 34,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: _muted,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshProfile,
              icon: const Icon(Icons.refresh),
              label: const Text(
                "REINTENTAR",
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_wooCustomer == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Center(
          child: CircularProgressIndicator(color: _brandColor),
        ),
      );
    }

    final billing = _wooCustomer!['billing'] as Map<String, dynamic>? ?? {};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mainCardHeader(
            _isAdmin ? "PERFIL ADMINISTRADOR" : "PERFIL ${_roleLabel.toUpperCase()}",
            _isAdmin ? Icons.admin_panel_settings_outlined : _roleIcon,
          ),
          const SizedBox(height: 16),
          _dataGroup(
            title: 'Datos profesionales',
            children: [
              _infoRow(
                Icons.person_outline,
                "Nombre",
                "${_wooCustomer!['first_name'] ?? ''} ${_wooCustomer!['last_name'] ?? ''}"
                    .trim(),
              ),
              _infoRow(
                Icons.business_outlined,
                "Empresa",
                _safeValue(billing['company']),
              ),
              _infoRow(
                Icons.badge_outlined,
                "CIF / NIF",
                _getCifNif(),
              ),
              _infoRow(
                Icons.support_agent_outlined,
                "Gestor asignado",
                _getAssignedManager(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _dataGroup(
            title: 'Contacto',
            children: [
              _infoRow(
                Icons.phone_outlined,
                "Teléfono",
                _safeValue(billing['phone']),
              ),
              _infoRow(
                Icons.email_outlined,
                "Email",
                _safeValue(_wooCustomer!['email']),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _dataGroup(
            title: 'Dirección',
            children: [
              _infoRow(
                Icons.location_on_outlined,
                "Dirección",
                _safeValue(billing['address_1']),
              ),
              _infoRow(
                Icons.markunread_mailbox_outlined,
                "Código Postal",
                _safeValue(billing['postcode']),
              ),
              _infoRow(
                Icons.location_city_outlined,
                "Ciudad",
                _safeValue(billing['city']),
              ),
              _infoRow(
                Icons.map_outlined,
                "Provincia",
                _safeValue(billing['state']),
              ),
              _infoRow(
                Icons.flag_outlined,
                "País",
                _safeValue(billing['country']),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _dataGroup(
            title: 'Condiciones comerciales',
            children: [
              _infoRow(
                Icons.payments_outlined,
                "Forma de pago",
                _paymentMethodLabel(),
              ),
              _infoRow(
                Icons.account_balance_wallet_outlined,
                "Límite de crédito B2B",
                _creditLimitLabel(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mainCardHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: _brandColor,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _brandColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: _brandColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              fontFamily: 'Oswald',
              letterSpacing: 0.6,
              color: _dark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dataGroup({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              color: _brandColor,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 52),
                child: Divider(height: 18, color: _border),
              ),
          ],
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: _border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.035),
        blurRadius: 14,
        offset: const Offset(0, 6),
      ),
    ],
  );

  Widget _infoRow(IconData icon, String label, String value) {
    final displayValue = value.trim().isEmpty ? "—" : value.trim();
    final isEmpty = displayValue == "—";
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _brandColor.withOpacity(0.07),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            size: 18,
            color: _brandColor,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.3,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 13.3,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: isEmpty ? const Color(0xFF9CA3AF) : _dark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickButton(
      BuildContext context,
      IconData icon,
      String label,
      Widget page,
      ) {
    return Expanded(
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        child: Container(
          height: 112,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _brandColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: _brandColor,
                  size: 22,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    fontFamily: 'Oswald',
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManagerCard() {
    final managerName = _getAssignedManager();
    final managerEmail = _getManagerEmail();
    final managerPhone = _getManagerPhone();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mainCardHeader('GESTOR ASIGNADO', Icons.support_agent_outlined),
          const SizedBox(height: 14),
          _dataGroup(
            title: 'Contacto comercial',
            children: [
              _infoRow(
                Icons.person_pin_circle_outlined,
                'Gestor / comercial',
                managerName,
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: managerEmail.contains('@') ? _emailManager : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _infoRow(
                    Icons.email_outlined,
                    'Email del gestor',
                    managerEmail,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: managerPhone != '—' ? _callManager : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _infoRow(
                    Icons.phone_outlined,
                    'Teléfono del gestor',
                    managerPhone,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteAccountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.red.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.red,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INHABILITAR CUENTA EN LA APP',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Oswald',
                        letterSpacing: 0.5,
                        color: _dark,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Se inhabilitará el acceso a la app y se cerrarán las sesiones abiertas en todos tus dispositivos.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: _muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _deletingAccount ? null : _confirmDisableAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.red.shade300,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _deletingAccount
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'INHABILITANDO...',
                          style: TextStyle(
                            fontFamily: 'Oswald',
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'INHABILITAR CUENTA',
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
      BuildContext context, {
        required String title,
        required List<Widget> items,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: _brandColor,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: _dark,
            fontFamily: 'Oswald',
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
      BuildContext context,
      IconData icon,
      String title,
      String subtitle,
      Widget page,
      ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _brandColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          color: _brandColor,
          size: 21,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14.5,
          fontFamily: 'Oswald',
          color: _dark,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: _muted,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF9CA3AF),
      ),
    );
  }

  Widget _buildActionMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _brandColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: _brandColor, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14.5,
          fontFamily: 'Oswald',
          color: _dark,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: _muted,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ??
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF9CA3AF),
          ),
    );
  }

  Future<void> _requestDataChange() async {
    if (_requestingDataChange) return;

    String requestedChangesDraft = '';
    String? errorText;

    final requestedChanges = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Solicitar cambio de datos'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Por seguridad, los datos del perfil no se pueden editar directamente. Indica qué información necesitas actualizar y enviaremos la solicitud al equipo de soporte de MundiCam.',
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  minLines: 4,
                  maxLines: 6,
                  maxLength: 1200,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (value) {
                    requestedChangesDraft = value;
                  },
                  decoration: InputDecoration(
                    labelText: 'Datos que deseas cambiar',
                    hintText: 'Ejemplo: cambiar teléfono, dirección de envío o razón social...',
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCELAR'),
            ),
            FilledButton(
              onPressed: () {
                final clean = requestedChangesDraft.trim();
                if (clean.length < 5) {
                  setDialogState(() {
                    errorText = 'Indica qué datos necesitas modificar.';
                  });
                  return;
                }
                Navigator.pop(dialogContext, clean);
              },
              child: const Text('ENVIAR SOLICITUD'),
            ),
          ],
        ),
      ),
    );

    if (requestedChanges == null ||
        requestedChanges.trim().isEmpty ||
        !mounted) {
      return;
    }

    setState(() => _requestingDataChange = true);

    try {
      final result = await ApiService()
          .solicitarCambioDatos(requestedChanges)
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      final reference = result['request_id']?.toString().trim() ?? '';
      final message = reference.isEmpty
          ? 'Solicitud enviada al equipo de soporte de MundiCam.'
          : 'Solicitud enviada. Referencia: $reference';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _brandColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final clean = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            clean.isEmpty
                ? 'No se pudo enviar la solicitud. Inténtalo de nuevo.'
                : clean,
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _requestingDataChange = false);
      }
    }
  }

  Future<void> _confirmDisableAccount() async {
    if (_deletingAccount) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('¿Inhabilitar el acceso a la app?'),
        content: const Text(
          'Tu usuario dejará de poder acceder a la aplicación MundiCam. Enviaremos la solicitud al equipo de soporte para que gestione la inhabilitación.\n\n'
          'La cuenta de la web, los pedidos y los datos de WooCommerce permanecerán activos y no se eliminarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'SÍ, INHABILITAR',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _requestAccountDisable();
  }

  Future<void> _requestAccountDisable() async {
    if (_deletingAccount) return;
    setState(() => _deletingAccount = true);

    final apiService = ApiService();

    try {
      // El servidor es la autoridad. No se bloquea localmente ni se cierra la
      // sesión hasta que el PHP confirme la inhabilitación global de la app.
      final result = await apiService
          .solicitarInhabilitacionCuenta()
          .timeout(const Duration(seconds: 30));

      if (!result.success ||
          !(result.accessBlocked || result.alreadyRequested)) {
        throw Exception(
          result.message.isNotEmpty
              ? result.message
              : 'El servidor no confirmó la inhabilitación de la cuenta.',
        );
      }

      // El PHP ya ha revocado todos los tokens y FCM de la cuenta. Limpiamos
      // también este dispositivo para cerrar completamente la sesión local.
      try {
        await NotificationService()
            .clearDeviceRegistration()
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      await apiService.clearWordPressSession();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (!mounted) return;

      final reference = result.requestId.trim();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Icon(
            Icons.lock_outline_rounded,
            color: Colors.red.shade700,
            size: 48,
          ),
          title: const Text('Cuenta inhabilitada en la app'),
          content: Text(
            reference.isEmpty
                ? 'Las sesiones de la app se han cerrado en todos tus dispositivos. Tu cuenta web permanece activa y el equipo de soporte gestionará la solicitud.'
                : 'Las sesiones de la app se han cerrado en todos tus dispositivos. Tu cuenta web permanece activa. Referencia de soporte: $reference.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ENTENDIDO'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      final clean = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            clean.isEmpty
                ? 'No se pudo inhabilitar la cuenta. Tu sesión continúa activa.'
                : clean,
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("¿Cerrar sesión?"),
        content: const Text("Se cerrará la sesión."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () async {
              await NotificationService().clearDeviceRegistration();
              await FirebaseAuth.instance.signOut();
              await ApiService().clearWordPressSession();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();

              if (ctx.mounted) {
                Navigator.pop(ctx);
              }

              if (!context.mounted) return;

              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                    (_) => false,
              );
            },
            child: const Text(
              "CERRAR SESIÓN",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// APP BAR PERSONALIZADO PARA PERFIL (CON FLECHA VISIBLE Y TÍTULO CENTRADO)
// ═══════════════════════════════════════════════════════════════════════════

class _ProfilePageAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Color backgroundColor;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  const _ProfilePageAppBar({
    required this.title,
    required this.backgroundColor,
    required this.onBack,
    required this.onRefresh,
    required this.onLogout,
  });

  @override
  Size get preferredSize => const Size.fromHeight(86);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 86,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Flecha izquierda
              Positioned(
                left: 8,
                child: IconButton(
                  tooltip: 'Volver',
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: onBack,
                  splashRadius: 22,
                ),
              ),
              // Título centrado
              Center(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1.05,
                    color: Colors.white,
                    fontFamily: 'Oswald',
                    height: 1.05,
                  ),
                ),
              ),
              // Botones derecha
              Positioned(
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Actualizar datos',
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: onRefresh,
                      splashRadius: 22,
                    ),
                    IconButton(
                      tooltip: 'Cerrar sesión',
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: onLogout,
                      splashRadius: 22,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}