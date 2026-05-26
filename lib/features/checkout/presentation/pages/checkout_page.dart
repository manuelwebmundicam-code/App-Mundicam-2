// pages/checkout_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/orders/presentation/providers/order_provider.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/checkout/presentation/pages/payment_page.dart';

class _CheckoutPaymentMethod {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final bool requiresCredit;

  const _CheckoutPaymentMethod({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.requiresCredit = false,
  });
}

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _postCodeController = TextEditingController();
  final _companyController = TextEditingController();
  final _nifController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isLoading = false;
  bool _loadingProfile = true;
  bool _profileLoaded = false;
  String? _errorMessage;

  int? _customerId;
  double _creditLimit = 0;
  double _creditUsed = 0;
  String _paymentMethod = 'bacs';
  String? _assignedManager;

  static const String _baseUrl = 'https://www.mundicam.com';

  static const List<_CheckoutPaymentMethod> _paymentMethods = [
    _CheckoutPaymentMethod(
      id: 'bacs',
      title: 'Transferencia bancaria',
      description:
      'Pago mediante transferencia bancaria. El pedido será procesado por MundiCam.',
      icon: Icons.account_balance_outlined,
    ),
    _CheckoutPaymentMethod(
      id: 'cheque',
      title: 'Giro / pago aplazado',
      description:
      'Forma de pago vinculada a condiciones comerciales y crédito aprobado.',
      icon: Icons.receipt_long_outlined,
      requiresCredit: true,
    ),
    _CheckoutPaymentMethod(
      id: 'redsys',
      title: '💳 Pago con Tarjeta (Redsys)',
      description:
      'Pago seguro con tarjeta bancaria a través de la pasarela Redsys de WooCommerce.',
      icon: Icons.credit_card_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatosCliente();
  }

  @override
  void dispose() {
    _scrollController.dispose();

    for (var c in [
      _nameController,
      _lastNameController,
      _emailController,
      _phoneController,
      _addressController,
      _cityController,
      _postCodeController,
      _companyController,
      _nifController,
      _stateController,
      _countryController,
      _notesController,
    ]) {
      c.dispose();
    }

    super.dispose();
  }

  String _normalizePaymentMethod(String? value) {
    final text = value?.trim().toLowerCase() ?? '';

    if (text.contains('redsys') ||
        text.contains('tarjeta') ||
        text.contains('card')) {
      return 'redsys';
    }

    if (text.contains('giro') ||
        text.contains('cheque') ||
        text.contains('aplazado') ||
        text.contains('credito') ||
        text.contains('crédito') ||
        text.contains('credit')) {
      return 'cheque';
    }

    return 'bacs';
  }

  _CheckoutPaymentMethod get _selectedPaymentMethod {
    return _paymentMethods.firstWhere(
          (method) => method.id == _paymentMethod,
      orElse: () => _paymentMethods.first,
    );
  }

  String get _paymentMethodTitle => _selectedPaymentMethod.title;

  bool _isPaymentMethodEnabled(_CheckoutPaymentMethod method) {
    if (!method.requiresCredit) return true;

    final disponible = _creditLimit - _creditUsed;
    return _creditLimit > 0 && disponible > 0;
  }

  String _buildWooPaymentUrl({required int orderId, required String orderKey}) {
    return '$_baseUrl/checkout/order-pay/$orderId/?pay_for_order=true&key=${Uri.encodeComponent(orderKey)}';
  }

  // ============================================================
  // CARGAR DATOS DEL CLIENTE
  // Ahora usa las mismas claves que el perfil:
  // - CIF/NIF: billing_nif + fallback billing.nif / billing.cif
  // - Gestor: wpuef_cid_c30 + fallback pedidos@mundicam.com
  // - Forma de pago: payment_method
  // - Crédito: credit_limit / credit_used
  // ============================================================
  Future<void> _cargarDatosCliente() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _loadingProfile = false;
        _errorMessage = 'Debes iniciar sesión para continuar';
      });
      return;
    }

    debugPrint('Checkout - Cargando datos del cliente...');

    try {
      String? email = user.email?.trim().toLowerCase();

      if (email == null || email.isEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        email = (userDoc.data()?['email'] as String?)?.trim().toLowerCase();
      }

      if (email == null || email.isEmpty) {
        setState(() {
          _loadingProfile = false;
          _errorMessage = 'No se pudo obtener el email del usuario';
        });
        return;
      }

      debugPrint('   Email: $email');

      final apiService = ApiService();
      final wooCustomer = await apiService.getCustomerByEmail(email);

      if (wooCustomer == null) {
        debugPrint('⚠️ Cliente no encontrado en WooCommerce');

        setState(() {
          _loadingProfile = false;
          _errorMessage = 'No se encontraron tus datos. Contacta con soporte.';
        });

        return;
      }

      final wooEmail = wooCustomer['email']?.toString().trim().toLowerCase();

      if (wooEmail != email) {
        debugPrint('🚨 Email no coincide');

        setState(() {
          _loadingProfile = false;
          _errorMessage = 'Error de seguridad al cargar los datos';
        });

        return;
      }

      _customerId = wooCustomer['id'];

      final billing = wooCustomer['billing'] as Map<String, dynamic>? ?? {};
      final metaData = wooCustomer['meta_data'];

      _creditLimit =
          double.tryParse(_getMetaValue(metaData, 'credit_limit') ?? '0') ?? 0;

      _creditUsed =
          double.tryParse(_getMetaValue(metaData, 'credit_used') ?? '0') ?? 0;

      final wooPaymentMethod = _getMetaValue(metaData, 'payment_method');

      final normalizedPaymentMethod = _normalizePaymentMethod(wooPaymentMethod);

      final selectedMethod = _paymentMethods.firstWhere(
            (method) => method.id == normalizedPaymentMethod,
        orElse: () => _paymentMethods.first,
      );

      if (_isPaymentMethodEnabled(selectedMethod)) {
        _paymentMethod = normalizedPaymentMethod;
      } else {
        _paymentMethod = 'bacs';
      }

      _assignedManager = _getGestor(metaData);

      if (mounted) {
        setState(() {
          _nameController.text = wooCustomer['first_name']?.toString() ?? '';
          _lastNameController.text = wooCustomer['last_name']?.toString() ?? '';
          _emailController.text = wooCustomer['email']?.toString() ?? email!;
          _companyController.text = billing['company']?.toString() ?? '';
          _phoneController.text = billing['phone']?.toString() ?? '';
          _nifController.text = _getNifCif(metaData, billing);
          _addressController.text = billing['address_1']?.toString() ?? '';
          _cityController.text = billing['city']?.toString() ?? '';
          _postCodeController.text = billing['postcode']?.toString() ?? '';
          _stateController.text = billing['state']?.toString() ?? '';
          _countryController.text = billing['country']?.toString() ?? 'ES';

          _profileLoaded = true;
          _loadingProfile = false;
        });
      }

      debugPrint('✅ Datos cargados correctamente');
      debugPrint('   Cliente: $_customerId');
      debugPrint('   CIF/NIF: ${_nifController.text}');
      debugPrint('   Crédito: $_creditUsed / $_creditLimit €');
      debugPrint('   Pago: $_paymentMethod');
      debugPrint('   Gestor: ${_assignedManager ?? "Sin gestor asignado"}');
    } catch (e) {
      debugPrint('❌ Error: $e');

      setState(() {
        _loadingProfile = false;
        _errorMessage = 'Error al cargar datos. Intenta de nuevo.';
      });
    }
  }

  // ============================================================
  // MISMA LÓGICA DE METADATOS QUE PERFIL
  // ============================================================
  String? _getMetaValue(dynamic metaData, String key) {
    if (metaData == null || key.isEmpty) return null;

    try {
      final List<dynamic> metaList = metaData is List ? metaData : [];

      for (final meta in metaList) {
        if (meta is Map) {
          final metaKey = meta['key']?.toString().toLowerCase().trim();

          if (metaKey == key.toLowerCase().trim()) {
            final value = meta['value']?.toString().trim();

            if (value != null && value.isNotEmpty && value != 'null') {
              return value;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error en _getMetaValue: $e');
    }

    return null;
  }

  String? _getFirstMetaValue(dynamic metaData, List<String> keys) {
    for (final key in keys) {
      final value = _getMetaValue(metaData, key);

      if (value != null && value.trim().isNotEmpty && value != '—') {
        return value.trim();
      }
    }

    return null;
  }

  String _getNifCif(dynamic metaData, Map<String, dynamic> billing) {
    final metaValue = _getFirstMetaValue(metaData, [
      'billing_nif',
      '_billing_nif',
      'cif_nif',
      'cif',
      'nif',
      'billing_cif',
      'billing_nif_cif',
    ]);

    if (metaValue != null && metaValue.isNotEmpty) {
      return metaValue;
    }

    final billingNif = billing['nif']?.toString().trim() ?? '';
    if (billingNif.isNotEmpty && billingNif != 'null') {
      return billingNif;
    }

    final billingCif = billing['cif']?.toString().trim() ?? '';
    if (billingCif.isNotEmpty && billingCif != 'null') {
      return billingCif;
    }

    return '';
  }

  String _getGestor(dynamic metaData) {
    final gestor = _getFirstMetaValue(metaData, [
      'wpuef_cid_c30',
      'assigned_manager',
      '_assigned_manager',
      'gestor_asignado',
      'commercial_manager',
      'sales_manager',
    ]);

    if (gestor != null && gestor.isNotEmpty) {
      return gestor;
    }

    return 'pedidos@mundicam.com';
  }

  // ============================================================
  // VALIDAR STOCK ACTUAL ANTES DE CREAR PEDIDO
  // ============================================================
  Future<bool> _validarStockActualAntesDeComprar() async {
    final cartItems = ref.read(cartProvider);

    if (cartItems.isEmpty) {
      _mostrarError('El carrito está vacío.');
      return false;
    }

    try {
      for (final item in cartItems) {
        final productoActualizado = await ApiService().getProductoById(
          item.product.id,
        );

        if (productoActualizado == null) {
          _mostrarError(
            'No se pudo verificar el stock de "${item.product.name}". Intenta de nuevo.',
          );
          return false;
        }

        final estaDisponible = productoActualizado.hasStock;
        final stockActual = productoActualizado.stockQuantity;

        if (!estaDisponible) {
          _mostrarError(
            'El producto "${item.product.name}" ya no está disponible.',
          );
          return false;
        }

        if (stockActual > 0 && item.quantity > stockActual) {
          _mostrarError(
            'Stock insuficiente para "${item.product.name}".\n'
                'Disponible: $stockActual uds.\n'
                'Solicitado: ${item.quantity} uds.',
          );
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error validando stock antes del pedido: $e');

      _mostrarError(
        'No se pudo verificar el stock actualizado. Intenta de nuevo.',
      );

      return false;
    }
  }

  // ============================================================
  // FINALIZAR PEDIDO
  // ============================================================
  Future<void> _finalizarPedido() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    final stockOk = await _validarStockActualAntesDeComprar();

    if (!stockOk) {
      if (mounted) {
        setState(() => _isLoading = false);
      }

      return;
    }

    final cartItems = ref.read(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final total = notifier.total;
    final disponible = _creditLimit - _creditUsed;
    final isCardPayment = _paymentMethod == 'redsys';

    if (_selectedPaymentMethod.requiresCredit && total > disponible) {
      HapticFeedback.heavyImpact();

      if (mounted) {
        setState(() => _isLoading = false);

        _mostrarError(
          'Crédito insuficiente.\n'
              'Disponible: ${disponible.toStringAsFixed(2)} €\n'
              'Total pedido: ${total.toStringAsFixed(2)} €',
        );
      }

      return;
    }

    final lineItems = cartItems.map((item) {
      return {'product_id': item.product.id, 'quantity': item.quantity};
    }).toList();

    final orderData = {
      if (_customerId != null) 'customer_id': _customerId,
      'payment_method': _paymentMethod,
      'payment_method_title': _paymentMethodTitle,
      'set_paid': false,
      'status': isCardPayment ? 'pending' : 'processing',
      'billing': {
        'first_name': _nameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'company': _companyController.text.trim(),
        'address_1': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'postcode': _postCodeController.text.trim(),
        'state': _stateController.text.trim(),
        'country': _countryController.text.trim().isEmpty
            ? 'ES'
            : _countryController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
      },
      'shipping': {
        'first_name': _nameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'company': _companyController.text.trim(),
        'address_1': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'postcode': _postCodeController.text.trim(),
        'state': _stateController.text.trim(),
        'country': _countryController.text.trim().isEmpty
            ? 'ES'
            : _countryController.text.trim(),
      },
      'line_items': lineItems,
      'customer_note': _notesController.text.trim(),
      'meta_data': [
        {'key': '_billing_nif', 'value': _nifController.text.trim()},
        {'key': 'billing_nif', 'value': _nifController.text.trim()},
        {'key': '_mundicam_payment_method_app', 'value': _paymentMethod},
        {'key': '_mundicam_payment_method_title', 'value': _paymentMethodTitle},
        if (_assignedManager != null && _assignedManager!.trim().isNotEmpty)
          {'key': '_assigned_manager', 'value': _assignedManager!.trim()},
        if (_assignedManager != null && _assignedManager!.trim().isNotEmpty)
          {
            'key': '_mundicam_assigned_manager_app',
            'value': _assignedManager!.trim(),
          },
      ],
    };

    debugPrint('📦 Creando pedido para cliente $_customerId');
    debugPrint('   Método de pago: $_paymentMethod - $_paymentMethodTitle');
    debugPrint('   Status: ${isCardPayment ? "pending" : "processing"}');
    debugPrint('   CIF/NIF: ${_nifController.text.trim()}');
    debugPrint('   Gestor asignado: ${_assignedManager ?? "Sin gestor"}');

    try {
      final result = await ApiService().crearPedidoConResultado(
        orderData,
        forceProcessingIfPending: false,
      );

      if (!mounted) return;

      if (!result.success || result.orderId == null) {
        _mostrarError(
          result.errorMessage ??
              'No se pudo crear el pedido. Puede que algún producto ya no tenga stock disponible.',
        );

        return;
      }

      if (isCardPayment) {
        final orderKey = result.orderKey;

        if (orderKey == null || orderKey.isEmpty) {
          _mostrarError(
            'Pedido creado, pero WooCommerce no devolvió la clave de pago. Contacta con soporte.',
          );

          return;
        }

        final paymentUrl = _buildWooPaymentUrl(
          orderId: result.orderId!,
          orderKey: orderKey,
        );

        debugPrint('💳 URL Redsys/WooCommerce: $paymentUrl');

        setState(() => _isLoading = false);

        final paid = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentPage(
              orderId: result.orderId!,
              orderKey: orderKey,
              paymentUrl: paymentUrl,
            ),
          ),
        );

        if (!mounted) return;

        if (paid == true) {
          ref.read(cartProvider.notifier).clearCart();
          ref.invalidate(ordersProvider);

          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          _mostrarError(
            'Pedido creado pendiente de pago. Puedes finalizarlo desde la web o contactar con MundiCam.',
          );
        }

        return;
      }

      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(ordersProvider);
      _mostrarExito();
    } catch (e) {
      debugPrint('❌ Error creando pedido: $e');

      if (mounted) {
        _mostrarError(
          'No se pudo crear el pedido. Puede que algún producto ya no tenga stock disponible.',
        );
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _mostrarExito() {
    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF059669),
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "¡Pedido confirmado!",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'Oswald',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Tu pedido se ha procesado correctamente.\nRecibirás un email de confirmación.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(ctx).popUntil((route) => route.isFirst),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("VOLVER A LA TIENDA"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ProfessionalPageAppBar(
        title: "FINALIZAR PEDIDO",
        subtitle: '',
        icon: Icons.shopping_cart_checkout_rounded,
        onBack: () => Navigator.pop(context),
      ),
      body: _loadingProfile
          ? const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      )
          : _errorMessage != null
          ? _buildErrorState()
          : Form(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildSteps(),
            const SizedBox(height: 20),
            _buildSectionCard(
              icon: Icons.person_outline_rounded,
              title: "DATOS PERSONALES",
              locked: true,
              children: [
                _buildLockedField("Nombre", _nameController),
                _buildLockedField("Apellidos", _lastNameController),
                _buildLockedField("Email", _emailController),
                _buildLockedField("Teléfono", _phoneController),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.business_outlined,
              title: "DATOS DE EMPRESA",
              locked: true,
              children: [
                _buildLockedField("Empresa", _companyController),
                _buildLockedField("NIF/CIF", _nifController),
                _buildManagerInfo(),
                _buildCreditInfo(),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.local_shipping_outlined,
              title: "DIRECCIÓN DE ENVÍO",
              subtitle: "Puedes modificar la dirección de entrega",
              children: [
                _buildField(
                  "Dirección",
                  _addressController,
                  icon: Icons.home_outlined,
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildField("Ciudad", _cityController),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _buildField(
                        "C.P.",
                        _postCodeController,
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                _buildField(
                  "Provincia",
                  _stateController,
                  required: false,
                ),
                _buildField("País", _countryController, required: false),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.payment_outlined,
              title: "MÉTODO DE PAGO",
              subtitle: "Selecciona la forma de pago del pedido",
              children: [_buildPaymentInfo()],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.note_outlined,
              title: "NOTAS DEL PEDIDO",
              subtitle: "Opcional",
              children: [
                _buildField(
                  "Instrucciones adicionales",
                  _notesController,
                  maxLines: 3,
                  required: false,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSummary(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loadingProfile = true;
                  _errorMessage = null;
                });

                _cargarDatosCliente();
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
      ),
    );
  }

  Widget _buildSteps() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepDot(true, "Cesta"),
          _stepLine(),
          _stepDot(true, "Datos"),
          _stepLine(),
          _stepDot(false, "Confirmar"),
        ],
      ),
    );
  }

  Widget _stepDot(bool active, String label) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: active
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text(
              "3",
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _stepLine() => Container(
    width: 32,
    height: 2,
    color: Colors.grey.shade300,
    margin: const EdgeInsets.only(bottom: 18),
  );

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    String? subtitle,
    bool locked = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: locked
                      ? Colors.orange.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: locked ? Colors.red.shade700 : AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              if (locked)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField(
      String label,
      TextEditingController controller, {
        TextInputType keyboard = TextInputType.text,
        IconData? icon,
        bool required = true,
        int maxLines = 1,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          prefixIcon: icon != null
              ? Icon(icon, size: 18, color: AppColors.textSecondary)
              : null,
          labelText: required ? label : "$label (opcional)",
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        validator: required
            ? (v) {
          if (v == null || v.trim().isEmpty) return "Campo requerido";
          return null;
        }
            : null,
      ),
    );
  }

  Widget _buildLockedField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        enabled: false,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey.shade100,
          suffixIcon: const Icon(
            Icons.lock_outline,
            size: 16,
            color: Colors.grey,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
    );
  }

  Widget _buildManagerInfo() {
    final manager = _assignedManager?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.support_agent_outlined,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Gestor asignado",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  manager != null && manager.isNotEmpty
                      ? manager
                      : "pedidos@mundicam.com",
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditInfo() {
    final disponible = _creditLimit - _creditUsed;
    double porcentaje = 0.0;

    if (_creditLimit > 0) {
      porcentaje = _creditUsed / _creditLimit;

      if (porcentaje < 0.0) porcentaje = 0.0;
      if (porcentaje > 1.0) porcentaje = 1.0;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: disponible > 0 ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: disponible > 0 ? Colors.green.shade100 : Colors.red.shade100,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Crédito disponible",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                "${disponible.toStringAsFixed(2)} €",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: disponible > 0
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: porcentaje,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                porcentaje > 0.8
                    ? Colors.red
                    : porcentaje > 0.5
                    ? Colors.orange
                    : Colors.green,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Usado: ${_creditUsed.toStringAsFixed(2)} €",
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
              Text(
                "Límite: ${_creditLimit.toStringAsFixed(2)} €",
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo() {
    final disponible = _creditLimit - _creditUsed;

    return Column(
      children: [
        for (final method in _paymentMethods) ...[
          _buildPaymentOption(method, disponible),
          if (method != _paymentMethods.last) const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El pago con tarjeta se realizará mediante Redsys en entorno seguro de WooCommerce. '
                      'El giro está sujeto a crédito y condiciones comerciales aprobadas.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentOption(_CheckoutPaymentMethod method, double disponible) {
    final selected = _paymentMethod == method.id;
    final enabled = _isPaymentMethodEnabled(method);

    return InkWell(
      onTap: enabled
          ? () {
        HapticFeedback.selectionClick();

        setState(() {
          _paymentMethod = method.id;
        });
      }
          : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.04)
              : enabled
              ? Colors.white
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.35)
                : Colors.grey.shade300,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: Center(
                child: selected
                    ? Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                )
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                method.icon,
                size: 19,
                color: selected
                    ? AppColors.primary
                    : enabled
                    ? AppColors.textSecondary
                    : Colors.grey,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: enabled ? AppColors.textPrimary : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    method.description,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: enabled ? Colors.grey.shade600 : Colors.grey,
                    ),
                  ),
                  if (method.requiresCredit) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Crédito disponible: ${disponible.toStringAsFixed(2)} €',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: disponible > 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                  if (method.id == 'redsys') ...[
                    const SizedBox(height: 6),
                    Text(
                      'Se abrirá la página de pago del pedido en WooCommerce.',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.25,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!enabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No disponible',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final notifier = ref.watch(cartProvider.notifier);
    final total = notifier.total;
    final disponible = _creditLimit - _creditUsed;
    final creditBlocked =
        _selectedPaymentMethod.requiresCredit && total > disponible;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Base Imponible"),
              Text("${notifier.subtotal.toStringAsFixed(2)} €"),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("IVA (21%) incluido"),
              Text("${notifier.iva.toStringAsFixed(2)} €"),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TOTAL",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                "${total.toStringAsFixed(2)} €",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  fontFamily: 'Oswald',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.payments_outlined,
                size: 17,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Forma de pago seleccionada: $_paymentMethodTitle',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_assignedManager != null &&
              _assignedManager!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.support_agent_outlined,
                  size: 17,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Gestor asignado: ${_assignedManager!.trim()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (creditBlocked) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Crédito insuficiente. Disponible: ${disponible.toStringAsFixed(2)} €",
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: (_isLoading || creditBlocked)
                  ? null
                  : _finalizarPedido,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _isLoading
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : Text(
                _paymentMethod == 'redsys'
                    ? 'PAGAR CON TARJETA'
                    : 'CONFIRMAR PEDIDO',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}