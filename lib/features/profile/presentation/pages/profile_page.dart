// pages/profile_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/orders/presentation/pages/orders_page.dart';
import 'package:mundicam/features/quotes/presentation/pages/quotes_page.dart';
import 'package:mundicam/features/rma/presentation/pages/rma_page.dart';
import 'package:mundicam/features/support/presentation/pages/support_tickets_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  Map<String, dynamic>? _wooCustomer;
  bool _loadingData = true;
  bool _isAdmin = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) setState(() => _loadingData = false);
      return;
    }

    debugPrint('🔍 Cargando perfil - UID: ${user.uid}');
    debugPrint('   Email Firebase Auth: ${user.email}');

    try {
      // 1. Obtener datos de Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      Map<String, dynamic>? firestoreData;

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
        _isAdmin = firestoreData?['role'] == 'admin';
        debugPrint('   Firestore role: ${firestoreData?['role']}');
        debugPrint('   Firestore email: ${firestoreData?['email']}');
      }

      // 2. Obtener email (múltiples fuentes)
      String? email = user.email?.trim().toLowerCase();
      if (email == null || email.isEmpty) {
        email = (firestoreData?['email'] as String?)?.trim().toLowerCase();
      }
      if (email == null || email.isEmpty) {
        email = user.providerData.firstOrNull?.email?.trim().toLowerCase();
      }

      debugPrint('   Email final: $email');

      if (email == null || email.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Email no disponible. Contacta con soporte.';
            _loadingData = false;
          });
        }
        return;
      }

      // 3. Buscar en WooCommerce
      final apiService = ApiService();
      final wooCustomer = await apiService.getCustomerByEmail(email);

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
            _errorMessage =
                'Cliente no encontrado.\nContacta con tu gestor comercial.';
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

  // UI Helpers
  String _getInicial() {
    if (_wooCustomer != null) {
      final n = _wooCustomer!['first_name']?.toString() ?? '';
      if (n.isNotEmpty) return n[0].toUpperCase();
      final c = _wooCustomer!['billing']?['company']?.toString() ?? '';
      if (c.isNotEmpty) return c[0].toUpperCase();
    }
    final e =
        _wooCustomer?['email'] ??
        FirebaseAuth.instance.currentUser?.email ??
        '';
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

  String _getCompany() =>
      _wooCustomer?['billing']?['company']?.toString() ?? '';

  String _getMeta(String key) {
    if (_wooCustomer == null) return "—";
    final meta = _wooCustomer!['meta_data'] as List? ?? [];
    try {
      for (final m in meta) {
        if (m is Map &&
            m['key']?.toString().toLowerCase().trim() ==
                key.toLowerCase().trim()) {
          return m['value']?.toString() ?? "—";
        }
      }
    } catch (_) {}
    return "—";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text("MI CUENTA"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _isAdmin ? Colors.deepPurple : AppColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () {
              setState(() {
                _loadingData = true;
                _errorMessage = null;
              });
              _cargarDatosUsuario();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: () => _confirmSignOut(context),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text("No has iniciado sesión"))
          : _loadingData
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildMainCard(),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            _quickButton(
                              context,
                              Icons.request_quote_outlined,
                              "Presupuestos",
                              const QuotesPage(),
                            ),
                            const SizedBox(width: 12),
                            _quickButton(
                              context,
                              Icons.local_shipping_outlined,
                              "Mis Pedidos",
                              const OrdersPage(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
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
                        const SizedBox(height: 32),
                        Text(
                          "Mundicam Security Distribution v2.0.1",
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 20),
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
      decoration: BoxDecoration(
        color: _isAdmin ? Colors.deepPurple : AppColors.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isAdmin
                            ? Colors.amber
                            : Colors.white.withValues(alpha: 0.3),
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _getInicial(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Oswald',
                        ),
                      ),
                    ),
                  ),
                  if (_isAdmin)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shield,
                          color: Colors.deepPurple,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _getDisplayName(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Oswald',
                ),
              ),
              if (_getCompany().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _getCompany(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _wooCustomer?['email'] ?? '',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              if (_isAdmin) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        color: Colors.amber,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        "ADMINISTRADOR",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainCard() {
    if (_errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loadingData = true;
                  _errorMessage = null;
                });
                _cargarDatosUsuario();
              },
              icon: const Icon(Icons.refresh),
              label: const Text("Reintentar"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final billing = _wooCustomer!['billing'] as Map<String, dynamic>? ?? {};
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: _isAdmin ? Colors.deepPurple : AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _isAdmin ? "PERFIL ADMINISTRADOR" : "DATOS DEL CLIENTE",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _infoRow(
            Icons.person_outline,
            "Nombre",
            "${_wooCustomer!['first_name'] ?? ''} ${_wooCustomer!['last_name'] ?? ''}"
                .trim(),
          ),
          const Divider(height: 20),
          _infoRow(
            Icons.business_outlined,
            "Empresa",
            billing['company'] ?? "—",
          ),
          const Divider(height: 20),
          _infoRow(Icons.badge_outlined, "CIF / NIF", _getMeta('cif_nif')),
          const Divider(height: 20),
          _infoRow(
            Icons.support_agent_outlined,
            "Gestor asignado",
            _getMeta('assigned_manager'),
          ),
          const Divider(height: 20),
          _infoRow(Icons.phone_outlined, "Teléfono", billing['phone'] ?? "—"),
          const Divider(height: 20),
          _infoRow(
            Icons.location_on_outlined,
            "Dirección",
            billing['address_1'] ?? "—",
          ),
          const Divider(height: 20),
          _infoRow(
            Icons.markunread_mailbox_outlined,
            "Código Postal",
            billing['postcode'] ?? "—",
          ),
          const Divider(height: 20),
          _infoRow(
            Icons.location_city_outlined,
            "Ciudad",
            billing['city'] ?? "—",
          ),
          const Divider(height: 20),
          _infoRow(Icons.map_outlined, "Provincia", billing['state'] ?? "—"),
          const Divider(height: 20),
          _infoRow(Icons.flag_outlined, "País", billing['country'] ?? "—"),
          const Divider(height: 20),
          _infoRow(
            Icons.email_outlined,
            "Email",
            _wooCustomer!['email'] ?? "—",
          ),
          const Divider(height: 20),
          _infoRow(
            Icons.payments_outlined,
            "Forma de pago",
            _getMeta('payment_method'),
          ),
          const Divider(height: 20),
          _infoRow(
            Icons.account_balance_wallet_outlined,
            "Crédito disponible",
            "${_getMeta('credit_limit')}€",
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  Widget _infoRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (_isAdmin ? Colors.deepPurple : AppColors.primary).withOpacity(
            0.06,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: _isAdmin ? Colors.deepPurple : AppColors.primary,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.isEmpty ? "—" : value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _quickButton(
    BuildContext context,
    IconData icon,
    String label,
    Widget page,
  ) => Expanded(
    child: GestureDetector(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: _isAdmin ? Colors.deepPurple : AppColors.primary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required List<Widget> items,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade600,
            letterSpacing: 0.8,
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(children: items),
      ),
    ],
  );

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) => ListTile(
    onTap: () =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _isAdmin
            ? Colors.deepPurple.withValues(alpha: 0.08)
            : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: _isAdmin ? Colors.deepPurple : AppColors.primary,
        size: 20,
      ),
    ),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
  );

  void _confirmSignOut(BuildContext context) => showDialog(
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
            await FirebaseAuth.instance.signOut();
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            if (ctx.mounted) Navigator.pop(ctx);
            SystemNavigator.pop();
          },
          child: const Text(
            "CERRAR SESIÓN",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}
