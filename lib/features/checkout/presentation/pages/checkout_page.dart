// pages/checkout_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/orders/presentation/providers/order_provider.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/checkout/presentation/pages/payment_page.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';
import 'package:mundicam/shared/providers/badge_provider.dart';

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
  final VoidCallback? onGoHome;
  final VoidCallback? onGoCart;

  const CheckoutPage({
    super.key,
    this.onGoHome,
    this.onGoCart,
  });

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
  final _fiscalAddressController = TextEditingController();
  final _fiscalAddress2Controller = TextEditingController();
  final _fiscalCityController = TextEditingController();
  final _fiscalPostCodeController = TextEditingController();
  final _fiscalStateController = TextEditingController();
  final _fiscalCountryController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isLoading = false;
  bool _loadingProfile = true;
  String? _errorMessage;

  int? _customerId;
  double _creditLimit = 0;
  double _creditUsed = 0;
  String _paymentMethod = 'bacs';
  String? _assignedManager;
  String? _checkoutIdempotencyKey;

  List<ShippingOption> _shippingOptions = <ShippingOption>[];
  ShippingOption? _selectedShippingOption;
  OrderPreviewResult? _orderPreview;
  bool _loadingShipping = false;
  String? _shippingMessage;
  Timer? _shippingDebounce;

  static const String _baseUrl = 'https://www.mundicam.com';

  static const List<_CheckoutPaymentMethod> _paymentMethods = [
    _CheckoutPaymentMethod(
      id: 'bacs',
      title: 'Transferencia bancaria',
      description:
      'Pago por transferencia bancaria. Usa el número de pedido como concepto. El pedido queda en espera hasta validar el pago.',
      icon: Icons.account_balance_outlined,
    ),
    _CheckoutPaymentMethod(
      id: 'cheque',
      title: 'Giro / pago aplazado',
      description:
      'Forma de pago vinculada a condiciones comerciales y crédito disponible. Se bloquea si supera tu crédito.',
      icon: Icons.receipt_long_outlined,
      requiresCredit: true,
    ),
    _CheckoutPaymentMethod(
      id: 'redsys',
      title: 'Pago con tarjeta',
      description:
      'Pago seguro con tarjeta mediante Redsys. La app no guarda datos de tarjeta y el pedido queda pendiente hasta confirmación bancaria.',
      icon: Icons.credit_card_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _addressController,
      _cityController,
      _stateController,
      _countryController,
    ]) {
      controller.addListener(_onShippingAddressChanged);
    }
    _postCodeController.addListener(_onShippingPostcodeChanged);
    _cargarDatosCliente();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MundicamAnalyticsService.instance
          .trackScreenViewForRoute(context, 'checkout');
      final cartSource = ref.read(cartProvider.notifier);
      unawaited(
        MundicamAnalyticsService.instance.track(
          eventName: 'checkout_started',
          metadata: <String, dynamic>{
            'source': cartSource.sourceQuoteId > 0
                ? 'web_quote'
                : (cartSource.sourceLocalQuoteUuid.trim().isNotEmpty
                    ? 'local_quote'
                    : 'cart'),
          },
          dedupeKey: 'checkout_started',
          dedupeWindow: const Duration(seconds: 2),
        ),
      );
    });
  }

  @override
  void dispose() {
    _shippingDebounce?.cancel();
    for (final controller in [
      _addressController,
      _cityController,
      _stateController,
      _countryController,
    ]) {
      controller.removeListener(_onShippingAddressChanged);
    }
    _postCodeController.removeListener(_onShippingPostcodeChanged);
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
      _fiscalAddressController,
      _fiscalAddress2Controller,
      _fiscalCityController,
      _fiscalPostCodeController,
      _fiscalStateController,
      _fiscalCountryController,
      _stateController,
      _countryController,
      _notesController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

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


  List<Map<String, dynamic>> _currentLineItems() {
    final cartItems = ref.read(cartProvider);
    return cartItems
        .map((item) => {
              'product_id': item.product.id,
              'quantity': item.quantity,
            })
        .toList();
  }

  String _normalizeLoose(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String _normalizeCountryCode(String value) {
    final text = value.trim().toUpperCase();
    if (text.isEmpty) return 'ES';
    if (text == 'ESPAÑA' || text == 'SPAIN') return 'ES';
    return text;
  }

  String _countryDisplayName(String countryCode) {
    final code = _normalizeCountryCode(countryCode);
    if (code == 'ES') return 'España';
    return code;
  }

  String _spanishProvinceDisplayName(String stateCode) {
    const names = <String, String>{
      'C': 'A Coruña',
      'VI': 'Álava',
      'AB': 'Albacete',
      'A': 'Alicante',
      'AL': 'Almería',
      'O': 'Asturias',
      'AV': 'Ávila',
      'BA': 'Badajoz',
      'PM': 'Illes Balears',
      'B': 'Barcelona',
      'BU': 'Burgos',
      'CC': 'Cáceres',
      'CA': 'Cádiz',
      'S': 'Cantabria',
      'CS': 'Castellón',
      'CE': 'Ceuta',
      'CR': 'Ciudad Real',
      'CO': 'Córdoba',
      'CU': 'Cuenca',
      'GI': 'Girona',
      'GR': 'Granada',
      'GU': 'Guadalajara',
      'SS': 'Gipuzkoa',
      'H': 'Huelva',
      'HU': 'Huesca',
      'J': 'Jaén',
      'LO': 'La Rioja',
      'GC': 'Las Palmas',
      'LE': 'León',
      'L': 'Lleida',
      'LU': 'Lugo',
      'M': 'Madrid',
      'MA': 'Málaga',
      'ML': 'Melilla',
      'MU': 'Murcia',
      'NA': 'Navarra',
      'OR': 'Ourense',
      'P': 'Palencia',
      'PO': 'Pontevedra',
      'SA': 'Salamanca',
      'TF': 'Santa Cruz de Tenerife',
      'SG': 'Segovia',
      'SE': 'Sevilla',
      'SO': 'Soria',
      'T': 'Tarragona',
      'TE': 'Teruel',
      'TO': 'Toledo',
      'V': 'Valencia',
      'VA': 'Valladolid',
      'BI': 'Bizkaia',
      'ZA': 'Zamora',
      'Z': 'Zaragoza',
    };

    final code = stateCode.trim().toUpperCase();
    return names[code] ?? stateCode.trim();
  }

  String _normalizeSpanishProvinceCode({
    required String country,
    required String state,
    required String postcode,
  }) {
    final cleanCountry = _normalizeCountryCode(country);
    final rawState = state.trim();
    if (cleanCountry != 'ES') return rawState;

    const validCodes = <String>{
      'C', 'VI', 'AB', 'A', 'AL', 'O', 'AV', 'BA', 'PM', 'B', 'BU', 'CC',
      'CA', 'S', 'CS', 'CE', 'CR', 'CO', 'CU', 'GI', 'GR', 'GU', 'SS', 'H',
      'HU', 'J', 'LO', 'GC', 'LE', 'L', 'LU', 'M', 'MA', 'ML', 'MU', 'NA',
      'OR', 'P', 'PO', 'SA', 'TF', 'SG', 'SE', 'SO', 'T', 'TE', 'TO', 'V',
      'VA', 'BI', 'ZA', 'Z',
    };

    final upper = rawState.toUpperCase();
    if (validCodes.contains(upper)) return upper;

    const byName = <String, String>{
      'a coruna': 'C',
      'la coruna': 'C',
      'alava': 'VI',
      'araba': 'VI',
      'albacete': 'AB',
      'alicante': 'A',
      'alacant': 'A',
      'almeria': 'AL',
      'asturias': 'O',
      'avila': 'AV',
      'badajoz': 'BA',
      'baleares': 'PM',
      'illes balears': 'PM',
      'islas baleares': 'PM',
      'barcelona': 'B',
      'burgos': 'BU',
      'caceres': 'CC',
      'cadiz': 'CA',
      'cantabria': 'S',
      'castellon': 'CS',
      'castello': 'CS',
      'ceuta': 'CE',
      'ciudad real': 'CR',
      'cordoba': 'CO',
      'cuenca': 'CU',
      'girona': 'GI',
      'gerona': 'GI',
      'granada': 'GR',
      'guadalajara': 'GU',
      'guipuzcoa': 'SS',
      'gipuzkoa': 'SS',
      'huelva': 'H',
      'huesca': 'HU',
      'jaen': 'J',
      'la rioja': 'LO',
      'las palmas': 'GC',
      'leon': 'LE',
      'lleida': 'L',
      'lerida': 'L',
      'lugo': 'LU',
      'madrid': 'M',
      'malaga': 'MA',
      'melilla': 'ML',
      'murcia': 'MU',
      'navarra': 'NA',
      'nafarroa': 'NA',
      'ourense': 'OR',
      'orense': 'OR',
      'palencia': 'P',
      'pontevedra': 'PO',
      'salamanca': 'SA',
      'santa cruz de tenerife': 'TF',
      'tenerife': 'TF',
      'segovia': 'SG',
      'sevilla': 'SE',
      'soria': 'SO',
      'tarragona': 'T',
      'teruel': 'TE',
      'toledo': 'TO',
      'valencia': 'V',
      'valencia valencia': 'V',
      'valladolid': 'VA',
      'vizcaya': 'BI',
      'bizkaia': 'BI',
      'zamora': 'ZA',
      'zaragoza': 'Z',
    };

    final byStateName = byName[_normalizeLoose(rawState)];
    if (byStateName != null) return byStateName;

    final digits = postcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 2) {
      const byPostcodePrefix = <String, String>{
        '01': 'VI', '02': 'AB', '03': 'A', '04': 'AL', '05': 'AV',
        '06': 'BA', '07': 'PM', '08': 'B', '09': 'BU', '10': 'CC',
        '11': 'CA', '12': 'CS', '13': 'CR', '14': 'CO', '15': 'C',
        '16': 'CU', '17': 'GI', '18': 'GR', '19': 'GU', '20': 'SS',
        '21': 'H', '22': 'HU', '23': 'J', '24': 'LE', '25': 'L',
        '26': 'LO', '27': 'LU', '28': 'M', '29': 'MA', '30': 'MU',
        '31': 'NA', '32': 'OR', '33': 'O', '34': 'P', '35': 'GC',
        '36': 'PO', '37': 'SA', '38': 'TF', '39': 'S', '40': 'SG',
        '41': 'SE', '42': 'SO', '43': 'T', '44': 'TE', '45': 'TO',
        '46': 'V', '47': 'VA', '48': 'BI', '49': 'ZA', '50': 'Z',
        '51': 'CE', '52': 'ML',
      };
      final byPrefix = byPostcodePrefix[digits.substring(0, 2)];
      if (byPrefix != null) return byPrefix;
    }

    return rawState;
  }

  String _firstAddressValue(Map<String, dynamic> primary, Map<String, dynamic> fallback, String key) {
    final primaryValue = primary[key]?.toString().trim() ?? '';
    if (primaryValue.isNotEmpty && primaryValue.toLowerCase() != 'null') {
      return primaryValue;
    }
    final fallbackValue = fallback[key]?.toString().trim() ?? '';
    if (fallbackValue.isNotEmpty && fallbackValue.toLowerCase() != 'null') {
      return fallbackValue;
    }
    return '';
  }

  Map<String, dynamic> _shippingAddressPayload() {
    final country = _normalizeCountryCode(_countryController.text);
    final postcode = _postCodeController.text.trim();
    final state = _normalizeSpanishProvinceCode(
      country: country,
      state: _stateController.text,
      postcode: postcode,
    );
    final payload = {
      'first_name': _nameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'company': _companyController.text.trim(),
      'address_1': _addressController.text.trim(),
      'city': _cityController.text.trim(),
      'postcode': postcode,
      'state': state,
      'country': country,
    };

    debugPrint('🚚 Dirección enviada para envío: $payload');
    return payload;
  }

  Map<String, dynamic> _billingAddressPayload() {
    final country = _normalizeCountryCode(_fiscalCountryController.text);
    final postcode = _fiscalPostCodeController.text.trim();
    final state = _normalizeSpanishProvinceCode(
      country: country,
      state: _fiscalStateController.text,
      postcode: postcode,
    );
    return {
      'first_name': _nameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'company': _companyController.text.trim(),
      'address_1': _fiscalAddressController.text.trim(),
      'address_2': _fiscalAddress2Controller.text.trim(),
      'city': _fiscalCityController.text.trim(),
      'postcode': postcode,
      'state': state,
      'country': country,
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
    };
  }

  String _formatMoney(double value) => '${value.toStringAsFixed(2)} €';

  bool _isPaymentMethodEnabled(_CheckoutPaymentMethod method) {
    if (!method.requiresCredit) return true;
    final disponible = _creditLimit - _creditUsed;
    return _creditLimit > 0 && disponible > 0;
  }


  void _onShippingPostcodeChanged() {
    if (_loadingProfile) return;

    final country = _normalizeCountryCode(_countryController.text);
    if (country == 'ES') {
      final stateCode = _normalizeSpanishProvinceCode(
        country: country,
        state: '',
        postcode: _postCodeController.text,
      );
      if (stateCode.isNotEmpty) {
        final provinceName = _spanishProvinceDisplayName(stateCode);
        if (provinceName.isNotEmpty &&
            _stateController.text.trim() != provinceName) {
          _stateController.value = TextEditingValue(
            text: provinceName,
            selection: TextSelection.collapsed(offset: provinceName.length),
          );
        }
      }
    }

    _onShippingAddressChanged();
  }

  void _onShippingAddressChanged() {
    if (_loadingProfile) return;
    _shippingDebounce?.cancel();
    _shippingDebounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      _refreshShippingAndPreview();
    });
  }

  Future<OrderPreviewResult?> _refreshShippingAndPreview({
    bool showErrors = false,
  }) async {
    final lineItems = _currentLineItems();
    if (lineItems.isEmpty) return null;

    if (mounted) {
      setState(() {
        _loadingShipping = true;
        _shippingMessage = null;
      });
    }

    try {
      final address = _shippingAddressPayload();
      final options = await ApiService().getShippingMethods(
        lineItems: lineItems,
        shippingAddress: address,
      );

      ShippingOption? selected;
      final previousId = _selectedShippingOption?.id ?? '';
      for (final option in options) {
        if (option.id == previousId) {
          selected = option;
          break;
        }
      }
      selected ??= options.isNotEmpty ? options.first : null;

      OrderPreviewResult? preview;
      if (selected != null) {
        preview = await ApiService().previewOrder(
          lineItems: lineItems,
          shippingAddress: address,
          shippingMethodId: selected.id,
        );
      }

      final effectiveOptions = preview != null && preview.shippingOptions.isNotEmpty
          ? preview.shippingOptions
          : options;
      if (selected != null &&
          !effectiveOptions.any((option) => option.id == selected!.id)) {
        selected = effectiveOptions.isNotEmpty ? effectiveOptions.first : null;
        if (selected != null) {
          preview = await ApiService().previewOrder(
            lineItems: lineItems,
            shippingAddress: address,
            shippingMethodId: selected.id,
          );
        }
      }

      if (!mounted) return preview;
      setState(() {
        _shippingOptions = effectiveOptions;
        _selectedShippingOption = selected;
        _orderPreview = preview;
        _loadingShipping = false;
        _shippingMessage = effectiveOptions.isEmpty
            ? 'No hay métodos de envío disponibles para esta dirección.'
            : null;
      });
      return preview;
    } catch (e) {
      debugPrint('❌ Error actualizando envío/resumen: $e');
      if (!mounted) return null;
      setState(() {
        _loadingShipping = false;
        _shippingMessage =
            'No se pudieron cargar los métodos de envío. Inténtalo de nuevo.';
      });
      if (showErrors) {
        _mostrarError('No se pudieron cargar los métodos de envío. Inténtalo de nuevo.');
      }
      return null;
    }
  }

  Future<void> _selectShippingOption(ShippingOption option) async {
    HapticFeedback.selectionClick();
    if (mounted) {
      setState(() {
        _selectedShippingOption = option;
        _loadingShipping = true;
        _shippingMessage = null;
      });
    }

    OrderPreviewResult? preview;
    try {
      preview = await ApiService().previewOrder(
        lineItems: _currentLineItems(),
        shippingAddress: _shippingAddressPayload(),
        shippingMethodId: option.id,
      );
    } catch (e) {
      debugPrint('❌ Error seleccionando envío: $e');
    }

    if (!mounted) return;
    setState(() {
      _orderPreview = preview;
      _loadingShipping = false;
      if (preview != null && preview.shippingOptions.isNotEmpty) {
        _shippingOptions = preview.shippingOptions;
      }
      if (preview == null) {
        _shippingMessage = 'No se pudo actualizar el resumen del pedido.';
      }
    });
  }

  Future<OrderPreviewResult?> _ensurePreviewBeforeSubmit() async {
    if (_selectedShippingOption == null || _orderPreview == null) {
      return _refreshShippingAndPreview(showErrors: true);
    }

    final preview = await ApiService().previewOrder(
      lineItems: _currentLineItems(),
      shippingAddress: _shippingAddressPayload(),
      shippingMethodId: _selectedShippingOption!.id,
    );

    if (preview != null && mounted) {
      setState(() {
        _orderPreview = preview;
        if (preview.shippingOptions.isNotEmpty) {
          _shippingOptions = preview.shippingOptions;
        }
      });
    }

    final effectivePreview = preview ?? _orderPreview;
    final selectedId = _selectedShippingOption?.id ?? '';
    if (effectivePreview != null && selectedId.isNotEmpty) {
      final stillAvailable = effectivePreview.shippingOptions.isEmpty ||
          effectivePreview.shippingOptions.any((option) => option.id == selectedId);
      if (!stillAvailable) {
        _mostrarError('El método de envío seleccionado ya no está disponible. Actualiza el envío.');
        return null;
      }
    }

    return effectivePreview;
  }

  /// Vuelve al Home usando el callback si existe, si no, hace pop de la ruta.
  void _irAlInicio({String? mensaje}) {
    if (!mounted) return;

    if (mensaje != null && mensaje.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    if (widget.onGoHome != null) {
      widget.onGoHome!();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Maneja el botón de atrás del AppBar: mismo comportamiento que QuotesPage.
  void _handleBack() {
    if (_isLoading) return;
    if (widget.onGoHome != null) {
      widget.onGoHome!();
    } else {
      Navigator.of(context).pop();
    }
  }

  String _mensajeCliente(String msg) {
    final limpio = msg.trim();
    if (limpio.isEmpty) {
      return 'No se pudo completar la operación. Inténtalo de nuevo.';
    }

    final lower = limpio.toLowerCase();
    final esTecnico = lower.contains('backend') ||
        lower.contains('endpoint') ||
        lower.contains('woocommerce') ||
        lower.contains('wordpress') ||
        lower.contains('php') ||
        lower.contains('/order') ||
        lower.contains('/shipping') ||
        lower.contains('expected_total') ||
        lower.contains('expected_subtotal') ||
        lower.contains('idempotency') ||
        lower.contains('json') ||
        lower.contains('dioexception') ||
        lower.contains('exception:') ||
        lower.contains('app api');

    if (esTecnico) {
      debugPrint('Checkout mensaje interno ocultado al cliente: $limpio');
      return 'No se pudo completar la operación. Revisa el carrito o inténtalo de nuevo. Si continúa, contacta con MundiCam.';
    }

    return limpio;
  }

  void _mostrarError(String msg) {
    final publicMsg = _mensajeCliente(msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(publicMsg),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Carga de datos del cliente
  // ──────────────────────────────────────────────

  Future<void> _cargarDatosCliente() async {
    final apiService = ApiService();

    try {
      String? email = await apiService.currentSessionEmail();

      final user = FirebaseAuth.instance.currentUser;
      if ((email == null || email.isEmpty) && user != null) {
        email = user.email?.trim().toLowerCase();
        if (email == null || email.isEmpty) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          email = (userDoc.data()?['email'] as String?)?.trim().toLowerCase();
        }
      }

      if (email == null || email.isEmpty) {
        setState(() {
          _loadingProfile = false;
          _errorMessage = 'No se pudo obtener el email del usuario';
        });
        return;
      }

      final wooCustomer = await apiService.getCustomerByEmail(email);
      if (wooCustomer == null) {
        setState(() {
          _loadingProfile = false;
          _errorMessage =
          'No se encontraron tus datos. Contacta con soporte.';
        });
        return;
      }

      final wooEmail =
      wooCustomer['email']?.toString().trim().toLowerCase();
      if (wooEmail != email) {
        setState(() {
          _loadingProfile = false;
          _errorMessage = 'Error de seguridad al cargar los datos';
        });
        return;
      }

      _customerId = wooCustomer['id'];
      final billing = wooCustomer['billing'] as Map<String, dynamic>? ?? {};
      final shipping = wooCustomer['shipping'] as Map<String, dynamic>? ?? {};
      final metaData = wooCustomer['meta_data'];

      _creditLimit = _parseCreditAmount(
        _getFirstMetaValue(metaData, const <String>[
          'credit_limit',
          'limite_credito',
          'limite_crediticio',
          'credito_limite',
          'customer_credit_limit',
          'b2bking_credit_limit',
          'b2bking_user_credit_limit',
          'mundicam_credit_limit',
        ]),
      );
      _creditUsed = _parseCreditAmount(
        _getFirstMetaValue(metaData, const <String>[
          'credit_used',
          'credito_usado',
          'used_credit',
          'credito_consumido',
        ]),
      );

      final wooPaymentMethod = _getFirstMetaValue(metaData, const <String>[
        'payment_method',
        'forma_pago',
        'metodo_pago',
        'payment_terms',
      ]);
      _paymentMethod = _normalizePaymentMethod(wooPaymentMethod);
      if (!_isPaymentMethodEnabled(_selectedPaymentMethod)) {
        _paymentMethod = 'bacs';
      }

      _assignedManager = _getGestor(metaData);

      if (mounted) {
        setState(() {
          _nameController.text = wooCustomer['first_name']?.toString() ?? '';
          _lastNameController.text =
              wooCustomer['last_name']?.toString() ?? '';
          _emailController.text = (wooCustomer['email']?.toString() ?? email)!;
          _companyController.text = billing['company']?.toString() ?? '';
          _phoneController.text = billing['phone']?.toString() ?? '';
          _nifController.text = _getNifCif(metaData, billing);

          // Datos fiscales: siempre proceden de billing. No se mezclan con la
          // dirección de entrega, que puede modificarse de forma independiente.
          _fiscalAddressController.text = billing['address_1']?.toString() ?? '';
          _fiscalAddress2Controller.text = billing['address_2']?.toString() ?? '';
          _fiscalCityController.text = billing['city']?.toString() ?? '';
          _fiscalPostCodeController.text = billing['postcode']?.toString() ?? '';
          final fiscalCountry = _normalizeCountryCode(
            billing['country']?.toString() ?? '',
          );
          final fiscalStateCode = _normalizeSpanishProvinceCode(
            country: fiscalCountry,
            state: billing['state']?.toString() ?? '',
            postcode: _fiscalPostCodeController.text,
          );
          _fiscalStateController.text = fiscalCountry == 'ES'
              ? _spanishProvinceDisplayName(fiscalStateCode)
              : fiscalStateCode;
          _fiscalCountryController.text = _countryDisplayName(fiscalCountry);

          _addressController.text = _firstAddressValue(shipping, billing, 'address_1');
          _cityController.text = _firstAddressValue(shipping, billing, 'city');
          _postCodeController.text = _firstAddressValue(shipping, billing, 'postcode');
          final rawCountry = _firstAddressValue(shipping, billing, 'country');
          final country = _normalizeCountryCode(rawCountry);
          final rawState = _firstAddressValue(shipping, billing, 'state');
          _stateController.text = _normalizeSpanishProvinceCode(
            country: country,
            state: rawState,
            postcode: _postCodeController.text,
          );
          _countryController.text = country;
          _loadingProfile = false;
        });
        await _refreshShippingAndPreview();
      }
    } catch (e) {
      debugPrint('❌ Error cargando datos: $e');
      setState(() {
        _loadingProfile = false;
        _errorMessage = 'Error al cargar datos. Intenta de nuevo.';
      });
    }
  }

  // ──────────────────────────────────────────────
  // Metadatos
  // ──────────────────────────────────────────────

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

  double _parseCreditAmount(String? value) {
    if (value == null) return 0;
    final clean = value
        .replaceAll('€', '')
        .replaceAll(' ', '')
        .trim();
    if (clean.isEmpty || clean.toLowerCase() == 'null') return 0;
    if (clean.contains(',') && clean.contains('.')) {
      return double.tryParse(clean.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return double.tryParse(clean.replaceAll(',', '.')) ?? 0;
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
    if (metaValue != null && metaValue.isNotEmpty) return metaValue;

    final billingNif = billing['nif']?.toString().trim() ?? '';
    if (billingNif.isNotEmpty && billingNif != 'null') return billingNif;

    final billingCif = billing['cif']?.toString().trim() ?? '';
    if (billingCif.isNotEmpty && billingCif != 'null') return billingCif;

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
    return gestor != null && gestor.isNotEmpty
        ? gestor
        : 'pedidos@mundicam.com';
  }

  // ──────────────────────────────────────────────
  // Validación de stock + productos "bajo consulta"
  // ──────────────────────────────────────────────

  Future<bool> _validarStockActualAntesDeComprar() async {
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) {
      _mostrarError('El carrito está vacío.');
      return false;
    }
    try {
      for (final item in cartItems) {
        final productoActualizado =
        await ApiService().getProductoById(item.product.id);
        if (productoActualizado == null) {
          _mostrarError(
              'No se pudo verificar el stock de "${item.product.name}".');
          return false;
        }
        if (!productoActualizado.hasStock) {
          _mostrarError(
              'El producto "${item.product.name}" ya no está disponible.');
          return false;
        }
        if (productoActualizado.stockQuantity > 0 &&
            item.quantity > productoActualizado.stockQuantity) {
          _mostrarError(
              'Stock insuficiente para "${item.product.name}".\n'
                  'Disponible: ${productoActualizado.stockQuantity} uds.\n'
                  'Solicitado: ${item.quantity} uds.');
          return false;
        }

        // ⚠️ Rechazar productos "bajo consulta"
        final price = double.tryParse(
          productoActualizado.price.replaceAll(',', '.').trim(),
        ) ??
            0;
        if (price <= 0) {
          _mostrarError(
            '"${item.product.name}" es un producto bajo consulta '
                'y no puede comprarse directamente.\n'
                'Añádelo a un presupuesto para solicitar precio.',
          );
          return false;
        }
      }
      return true;
    } catch (e) {
      _mostrarError('No se pudo verificar el stock. Intenta de nuevo.');
      return false;
    }
  }

  Future<bool> _eliminarPresupuestoLocalSeguro(String localUuid) async {
    final cleanUuid = localUuid.trim();
    if (cleanUuid.isEmpty) return true;

    try {
      await ref
          .read(localQuotesProvider.notifier)
          .eliminarPresupuesto(cleanUuid);
      return true;
    } catch (e) {
      debugPrint('No se pudo eliminar la copia local $cleanUuid: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // Finalizar pedido
  // ──────────────────────────────────────────────

  Future<void> _finalizarPedido() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final cartNotifier = ref.read(cartProvider.notifier);
    final sourceQuoteId = cartNotifier.sourceQuoteId;
    final sourceLocalQuoteUuid = cartNotifier.sourceLocalQuoteUuid;
    final hasQuoteSource =
        sourceQuoteId > 0 || sourceLocalQuoteUuid.trim().isNotEmpty;

    final idempotencyKey = _checkoutIdempotencyKey ??=
        hasQuoteSource
            ? 'quote-${sourceQuoteId > 0 ? 'web-$sourceQuoteId' : 'local-$sourceLocalQuoteUuid'}'
            : 'app-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    final stockOk = await _validarStockActualAntesDeComprar();
    if (!stockOk) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final cartItems = ref.read(cartProvider);
    final notifier = cartNotifier;
    final preview = await _ensurePreviewBeforeSubmit();
    if (!mounted) return;

    if (_selectedShippingOption == null || preview == null) {
      setState(() => _isLoading = false);
      _mostrarError('Selecciona un método de envío disponible antes de confirmar el pedido.');
      return;
    }

    if (preview.shippingOptions.isNotEmpty &&
        !preview.shippingOptions.any((option) => option.id == _selectedShippingOption!.id)) {
      setState(() => _isLoading = false);
      _mostrarError('El método de envío seleccionado no está disponible para esta dirección. Actualiza el envío.');
      return;
    }

    final total = preview.expectedTotal > 0 ? preview.expectedTotal : preview.total;
    final disponible = _creditLimit - _creditUsed;
    final isCardPayment = _paymentMethod == 'redsys';

    if (_selectedPaymentMethod.requiresCredit && total > disponible) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() => _isLoading = false);
        _mostrarError(
            'Crédito insuficiente.\n'
                'Disponible: ${disponible.toStringAsFixed(2)} €\n'
                'Total pedido: ${total.toStringAsFixed(2)} €');
      }
      return;
    }

    final lineItems = cartItems
        .map((item) => {
              'product_id': item.product.id,
              'quantity': item.quantity,
            })
        .toList();
    final shippingAddress = _shippingAddressPayload();
    final effectiveIdempotencyKey = hasQuoteSource
        ? 'quote-${sourceQuoteId > 0 ? 'web-$sourceQuoteId' : 'local-$sourceLocalQuoteUuid'}-${preview.cartHash.isNotEmpty ? preview.cartHash : lineItems.toString().hashCode}'
        : idempotencyKey;

    final orderData = {
      if (_customerId != null) 'customer_id': _customerId,
      'payment_method': _paymentMethod,
      'payment_method_title': _paymentMethodTitle,
      'set_paid': false,
      'status': isCardPayment ? 'pending' : 'on-hold',
      if (sourceQuoteId > 0) 'source_quote_id': sourceQuoteId,
      if (sourceLocalQuoteUuid.trim().isNotEmpty)
        'source_local_quote_uuid': sourceLocalQuoteUuid.trim(),
      'billing': _billingAddressPayload(),
      'shipping': shippingAddress,
      'shipping_address': shippingAddress,
      'shipping_method_id': _selectedShippingOption!.id,
      if (preview.cartHash.isNotEmpty) 'cart_hash': preview.cartHash,
      if (preview.shippingHash.isNotEmpty) 'shipping_hash': preview.shippingHash,
      'shipping_option_id': _selectedShippingOption!.id,
      'line_items': lineItems,
      'expected_subtotal': preview.subtotal.toStringAsFixed(2),
      'expected_shipping_total': preview.shipping.toStringAsFixed(2),
      'expected_tax_total': preview.taxTotal.toStringAsFixed(2),
      'expected_total': total.toStringAsFixed(2),
      'expected_currency': preview.currency.isEmpty ? 'EUR' : preview.currency,
      'idempotency_key': effectiveIdempotencyKey,
      'customer_note': _notesController.text.trim(),
      'meta_data': [
        {'key': '_billing_nif', 'value': _nifController.text.trim()},
        {'key': 'billing_nif', 'value': _nifController.text.trim()},
        {'key': '_mundicam_payment_method_app', 'value': _paymentMethod},
        {
          'key': '_mundicam_payment_method_title',
          'value': _paymentMethodTitle
        },
        if (_assignedManager != null && _assignedManager!.trim().isNotEmpty)
          {'key': '_assigned_manager', 'value': _assignedManager!.trim()},
      ],
    };

    try {
      final result = await ApiService().crearPedidoConResultado(
        orderData,
        forceProcessingIfPending: false,
      );
      if (!mounted) return;

      if (!result.success || result.orderId == null) {
        _mostrarError(result.errorMessage ??
            'No se pudo crear el pedido. Puede que algún producto ya no tenga stock disponible.');
        return;
      }

      if (isCardPayment) {
        final orderKey = result.orderKey;
        if (orderKey == null || orderKey.isEmpty) {
          _mostrarError(
              'Pedido creado, pero no se obtuvo la clave de pago. Contacta con soporte.');
          return;
        }

        final paymentUrl = result.paymentUrl ??
            await ApiService().getSecureCardPaymentUrl(
              orderId: result.orderId!,
              orderKey: orderKey,
            );

        if (paymentUrl == null ||
            paymentUrl.trim().isEmpty ||
            !paymentUrl.contains('mundicam_app_payment_token=')) {
          _mostrarError(
            'El servidor no devolvió el enlace seguro de Redsys. '
            'No se abrirá la web general de MundiCam.',
          );
          return;
        }

        if (!mounted) return;

        setState(() => _isLoading = false);

        final paid = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentPage(
              orderId: result.orderId!,
              orderKey: orderKey,
              paymentUrl: paymentUrl,
              orderNumber: result.orderNumber,
              amount: total,
              paymentMethodTitle: _paymentMethodTitle,
              quotePayment: hasQuoteSource,
              quoteNumber: sourceQuoteId > 0
                  ? sourceQuoteId.toString()
                  : sourceLocalQuoteUuid,
            ),
          ),
        );
        if (!mounted) return;

        if (paid == true) {
          _checkoutIdempotencyKey = null;
          final localCleanupOk = await _eliminarPresupuestoLocalSeguro(
            sourceLocalQuoteUuid,
          );
          await ref.read(cartProvider.notifier).clearCart();
          ref.invalidate(ordersProvider);
          _irAlInicio(
            mensaje: localCleanupOk
                ? '✅ Pago confirmado. El pedido ya está en preparación.'
                : '✅ Pago confirmado. El pedido está en preparación. '
                    'No se pudo borrar la copia local; elimínala desde Presupuestos.',
          );
        } else {
          // En PaymentPage un checkout de presupuesto solo devuelve false después
          // de que /quote/cancel-checkout haya confirmado la cancelación. Si la
          // cancelación falla o Redsys ya confirmó, la pantalla permanece abierta.
          if (hasQuoteSource) {
            _checkoutIdempotencyKey = null;
            final localCleanupOk = await _eliminarPresupuestoLocalSeguro(
              sourceLocalQuoteUuid,
            );
            await ref.read(cartProvider.notifier).clearCart();
            ref.invalidate(ordersProvider);
            ref.invalidate(quotesProvider);
            ref.invalidate(quoteBadgeProvider);
            ref.invalidate(cartBadgeProvider);
            _irAlInicio(
              mensaje: localCleanupOk
                  ? 'Pedido cancelado. Puedes consultarlo en Mis pedidos.'
                  : 'Pedido cancelado. No se pudo borrar la copia local; '
                      'elimínala desde Presupuestos.',
            );
          } else {
            _mostrarError(
              'El pedido sigue pendiente de pago. Puedes reintentar el pago desde esta misma operación.',
            );
          }
        }
        return;
      }

      // Transferencia / giro
      _checkoutIdempotencyKey = null;
      await ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(ordersProvider);
      _irAlInicio(
        mensaje: hasQuoteSource
            ? 'Solicitud registrada. El presupuesto seguirá visible hasta que '
                'el pago quede confirmado.'
            : '✅ Pedido confirmado. Te llevamos al inicio.',
      );
    } catch (e) {
      debugPrint('❌ Error creando pedido: $e');
      _mostrarError(
          'No se pudo crear el pedido. Puede que algún producto ya no tenga stock disponible.');
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ──────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ProfessionalPageAppBar(
        title: 'FINALIZAR PEDIDO',
        onBack: _handleBack,
        onRefresh: _cargarDatosCliente,
      ),
      body: _loadingProfile
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.primary))
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
              title: 'DATOS PERSONALES',
              locked: true,
              children: [
                _buildLockedField('Nombre', _nameController),
                _buildLockedField('Apellidos', _lastNameController),
                _buildLockedField('Email', _emailController),
                _buildLockedField('Teléfono', _phoneController),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.business_outlined,
              title: 'DATOS FISCALES DE LA EMPRESA',
              subtitle:
                  'Se usarán para facturación. La dirección de entrega puede cambiarse más abajo.',
              locked: true,
              children: [
                _buildLockedField('Razón social / Empresa', _companyController),
                _buildLockedField('NIF/CIF', _nifController),
                _buildLockedField('Dirección fiscal', _fiscalAddressController),
                if (_fiscalAddress2Controller.text.trim().isNotEmpty)
                  _buildLockedField(
                    'Complemento de dirección',
                    _fiscalAddress2Controller,
                  ),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildLockedField(
                        'Código postal',
                        _fiscalPostCodeController,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _buildLockedField(
                        'Localidad',
                        _fiscalCityController,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildLockedField(
                        'Provincia',
                        _fiscalStateController,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildLockedField(
                        'País',
                        _fiscalCountryController,
                      ),
                    ),
                  ],
                ),
                _buildManagerInfo(),
                _buildCreditInfo(),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.local_shipping_outlined,
              title: 'DIRECCIÓN DE ENVÍO',
              subtitle: 'Puedes modificar la dirección de entrega',
              children: [
                _buildField('Dirección', _addressController,
                    icon: Icons.home_outlined),
                Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child:
                        _buildField('Ciudad', _cityController)),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _buildField('C.P.', _postCodeController,
                          keyboard: TextInputType.number),
                    ),
                  ],
                ),
                _buildField('Provincia', _stateController,
                    required: false),
                _buildField('País', _countryController,
                    required: false),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.local_shipping_outlined,
              title: 'MÉTODO DE ENVÍO',
              subtitle: 'Selecciona cómo quieres recibir el pedido',
              children: [_buildShippingMethods()],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.payment_outlined,
              title: 'MÉTODO DE PAGO',
              subtitle: 'Selecciona la forma de pago del pedido',
              children: [_buildPaymentInfo()],
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              icon: Icons.note_outlined,
              title: 'NOTAS DEL PEDIDO',
              subtitle: 'Opcional',
              children: [
                _buildField(
                    'Instrucciones adicionales', _notesController,
                    maxLines: 3, required: false),
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
              label: const Text('Reintentar'),
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
          _stepDot(true, 'Cesta'),
          _stepLine(),
          _stepDot(true, 'Datos'),
          _stepLine(),
          _stepDot(false, _paymentMethod == 'redsys' ? 'Pago' : 'Confirmar'),
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
                ? const Icon(Icons.check_rounded,
                color: Colors.white, size: 16)
                : Text(
              '3',
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
                      ? Colors.red.shade50
                      : AppColors.primary.withOpacity(0.08),
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
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                  ],
                ),
              ),
              if (locked)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'BLOQUEADO',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.red,
                        fontWeight: FontWeight.bold),
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
          labelText: required ? label : '$label (opcional)',
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
            const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        validator: required
            ? (v) {
          if (v == null || v.trim().isEmpty) return 'Campo requerido';
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
          suffixIcon: const Icon(Icons.lock_outline,
              size: 16, color: Colors.grey),
          border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
        color: AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border:
        Border.all(color: AppColors.primary.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.support_agent_outlined,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestor asignado',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  manager != null && manager.isNotEmpty
                      ? manager
                      : 'pedidos@mundicam.com',
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800),
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
            color: disponible > 0
                ? Colors.green.shade100
                : Colors.red.shade100),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Crédito disponible',
                  style:
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(
                '${disponible.toStringAsFixed(2)} €',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: disponible > 0
                        ? Colors.green.shade700
                        : Colors.red.shade700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: porcentaje,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(porcentaje > 0.8
                  ? Colors.red
                  : porcentaje > 0.5
                  ? Colors.orange
                  : Colors.green),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Usado: ${_creditUsed.toStringAsFixed(2)} €',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade600)),
              Text('Límite: ${_creditLimit.toStringAsFixed(2)} €',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildShippingMethods() {
    if (_loadingShipping && _shippingOptions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_shippingOptions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Text(
              _shippingMessage ??
                  'Introduce una dirección válida para ver los métodos de envío disponibles.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loadingShipping ? null : () => _refreshShippingAndPreview(showErrors: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Actualizar envío'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((_orderPreview?.destinationLabel ?? '').isNotEmpty) ...[
          Text(
            _orderPreview!.destinationLabel,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
        ],
        for (final option in _shippingOptions) ...[
          _buildShippingOption(option),
          if (option != _shippingOptions.last) const SizedBox(height: 10),
        ],
        if (_loadingShipping) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_shippingMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _shippingMessage!,
            style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
          ),
        ],
      ],
    );
  }

  Widget _buildShippingOption(ShippingOption option) {
    final selected = _selectedShippingOption?.id == option.id;
    return InkWell(
      onTap: _loadingShipping ? null : () => _selectShippingOption(option),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary.withOpacity(0.35) : Colors.grey.shade300,
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
                    ? AppColors.primary.withOpacity(0.08)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                option.isPickup ? Icons.storefront_outlined : Icons.local_shipping_outlined,
                size: 19,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    option.isPickup
                        ? 'Recogida en almacén.'
                        : 'Entrega según la dirección indicada.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              option.displayTotal,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
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
              Icon(Icons.info_outline_rounded,
                  size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El pago con tarjeta se realizará mediante una pasarela segura. '
                      'El giro está sujeto a crédito y condiciones comerciales aprobadas.',
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentOption(
      _CheckoutPaymentMethod method, double disponible) {
    final selected = _paymentMethod == method.id;
    final enabled = _isPaymentMethodEnabled(method);
    return InkWell(
      onTap: enabled
          ? () {
        HapticFeedback.selectionClick();
        setState(() => _paymentMethod = method.id);
      }
          : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.04)
              : enabled
              ? Colors.white
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary.withOpacity(0.35)
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
                      shape: BoxShape.circle),
                )
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(0.08)
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
                      'Se abrirá la pasarela segura de pago.',
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
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No disponible',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final notifier = ref.watch(cartProvider.notifier);
    final preview = _orderPreview;
    final subtotal = preview?.subtotal ?? notifier.subtotal;
    final shipping = preview?.shipping ?? 0.0;
    final taxTotal = preview?.taxTotal ?? notifier.iva;
    final total = preview?.expectedTotal ?? notifier.total;
    final disponible = _creditLimit - _creditUsed;
    final creditBlocked =
        _selectedPaymentMethod.requiresCredit && total > disponible;
    final shippingBlocked = _selectedShippingOption == null || preview == null;

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
              const Text('Subtotal'),
              Text(_formatMoney(subtotal)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _selectedShippingOption?.title ?? 'Envío',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(shipping <= 0 ? 'Gratis' : _formatMoney(shipping)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('IVA'),
              Text(_formatMoney(taxTotal)),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text(
                _formatMoney(total),
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
              Icon(Icons.payments_outlined,
                  size: 17, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Forma de pago: $_paymentMethodTitle',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_selectedShippingOption != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.local_shipping_outlined,
                    size: 17, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _orderPreview?.destinationLabel.trim().isNotEmpty == true
                        ? 'Envío a ${_orderPreview!.destinationLabel}'
                        : 'Método: ${_selectedShippingOption!.title}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          if (_assignedManager != null &&
              _assignedManager!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.support_agent_outlined,
                    size: 17, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Gestor: ${_assignedManager!.trim()}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          if (shippingBlocked) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_shipping_outlined,
                      color: Colors.orange.shade800, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Selecciona un método de envío para confirmar el pedido.',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
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
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Crédito insuficiente. Disponible: ${disponible.toStringAsFixed(2)} €',
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
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
              onPressed: (_isLoading || creditBlocked || shippingBlocked)
                  ? null
                  : _finalizarPedido,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      _paymentMethod == 'redsys'
                          ? 'PAGAR CON TARJETA'
                          : 'CONFIRMAR PEDIDO',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }}