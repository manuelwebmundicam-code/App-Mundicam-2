import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/rma/presentation/pages/rma_page.dart';
import 'package:mundicam/features/rma/presentation/providers/rma_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class RmaFormPage extends ConsumerStatefulWidget {
  final int orderId;
  final int productId;
  final String productName;
  final int lineItemId;
  final int variationId;
  final int maxQuantity;
  final String sku;
  final List<String> serialNumbers;
  final DateTime? orderDate;
  final VoidCallback? onGoRma;

  const RmaFormPage({
    super.key,
    required this.orderId,
    required this.productId,
    required this.productName,
    this.lineItemId = 0,
    this.variationId = 0,
    this.maxQuantity = 1,
    this.sku = '',
    this.serialNumbers = const <String>[],
    this.orderDate,
    this.onGoRma,
  });

  @override
  ConsumerState<RmaFormPage> createState() => _RmaFormPageState();
}

class _RmaFormPageState extends ConsumerState<RmaFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _motivoController = TextEditingController();
  final _descripcionController = TextEditingController();
  bool _isLoading = false;
  bool _loadingSerialNumbers = false;
  int _quantity = 1;
  String? _selectedSerialNumber;
  List<String> _serialNumbers = const <String>[];
  Future<void>? _serialLookupFuture;

  String? _selectedMotivo;
  final List<String> _motivos = const [
    'Producto defectuoso',
    'No funciona correctamente',
    'Dañado durante el envío',
    'Error en el pedido',
    'No coincide con la descripción',
    'Otro',
  ];

  int get _maxQuantity => widget.maxQuantity <= 0 ? 1 : widget.maxQuantity;

  DateTime? get _warrantyUntil =>
      widget.orderDate?.add(const Duration(days: 730));

  bool? get _isInWarranty {
    final warrantyUntil = _warrantyUntil;
    if (warrantyUntil == null) return null;

    final now = DateTime.now();
    final endOfWarrantyDay = DateTime(
      warrantyUntil.year,
      warrantyUntil.month,
      warrantyUntil.day,
      23,
      59,
      59,
    );
    return !now.isAfter(endOfWarrantyDay);
  }

  @override
  void initState() {
    super.initState();

    _serialNumbers = _cleanSerialNumbers(widget.serialNumbers);
    if (_serialNumbers.length == 1) {
      _selectedSerialNumber = _serialNumbers.first;
    }

    // La respuesta de /orders ya puede venir enriquecida por Extensions.
    // Solo consultamos /rma/serials si la línea todavía no traía SN.
    if (_serialNumbers.isEmpty) {
      _serialLookupFuture = _loadSerialNumbersFromExtensions();
    }
  }

  List<String> _cleanSerialNumbers(Iterable<dynamic> values) {
    final result = <String>[];
    for (final value in values) {
      final serial = value?.toString().trim() ?? '';
      if (serial.isEmpty || result.contains(serial)) continue;
      result.add(serial);
    }
    return result;
  }

  Future<void> _loadSerialNumbersFromExtensions() async {
    if (_loadingSerialNumbers) return;

    // Esta primera consulta se lanza desde initState, antes del primer frame.
    // No necesitamos setState para marcar el estado inicial.
    _loadingSerialNumbers = true;

    try {
      final serials = await ApiService().getRmaSerialNumbers(
        orderId: widget.orderId,
        productId: widget.productId,
        lineItemId: widget.lineItemId,
        variationId: widget.variationId,
      );

      if (!mounted) return;

      final clean = _cleanSerialNumbers(serials);
      if (clean.isEmpty) return;

      setState(() {
        _serialNumbers = clean;
        if (clean.length == 1) {
          _selectedSerialNumber = clean.first;
          _quantity = 1;
        } else if (_selectedSerialNumber != null &&
            !clean.contains(_selectedSerialNumber)) {
          _selectedSerialNumber = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _loadingSerialNumbers = false);
      } else {
        _loadingSerialNumbers = false;
      }
    }
  }

  @override
  void dispose() {
    _motivoController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<String?> _getUserEmail() async {
    final appEmail = await ApiService().currentSessionEmail();
    if (appEmail != null && appEmail.isNotEmpty) return appEmail;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.get('email') as String?;
      }
    } catch (_) {}
    return user.email ?? user.providerData.firstOrNull?.email;
  }

  Future<void> _enviarRma() async {
    if (_isInWarranty == false) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Expanded(child: Text('GARANTÍA EXCEDIDA')),
            ],
          ),
          content: const Text(
            'Este producto está fuera del periodo de garantía de 2 años y no puede tramitarse por RMA.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CERRAR'),
            ),
          ],
        ),
      );
      return;
    }

    // Si el endpoint de Extensions todavía está resolviendo el SN, esperamos
    // esa única consulta antes de validar el formulario. Un 404 de modo pruebas
    // devuelve [] y el RMA clásico continúa sin cambios.
    final pendingSerialLookup = _serialLookupFuture;
    if (pendingSerialLookup != null && _loadingSerialNumbers) {
      await pendingSerialLookup;
      if (!mounted) return;
    }

    if (!_formKey.currentState!.validate()) return;
    final motivo = _selectedMotivo == 'Otro'
        ? _motivoController.text.trim()
        : (_selectedMotivo ?? '').trim();
    if (motivo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un motivo'), backgroundColor: Colors.red),
      );
      return;
    }

    final availableSerials = _serialNumbers;
    if (availableSerials.isNotEmpty &&
        (_selectedSerialNumber == null || _selectedSerialNumber!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona el SN del equipo'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final email = await _getUserEmail();
      if (email == null || email.trim().isEmpty) {
        throw Exception('No se pudo obtener tu email');
      }

      final response = await ApiService().crearRmaDetalle(
        email: email,
        orderId: widget.orderId,
        productId: widget.productId,
        lineItemId: widget.lineItemId,
        variationId: widget.variationId,
        quantity: _quantity,
        serialNumber: _selectedSerialNumber?.trim() ?? '',
        motivo: motivo,
        descripcion: _selectedSerialNumber == null
            ? _descripcionController.text.trim()
            : 'SN seleccionado: ${_selectedSerialNumber!.trim()}\n\n${_descripcionController.text.trim()}',
      );
      if (!mounted) return;

      ref.invalidate(rmaProvider);
      final rawRma = response['rma'] ?? response['data'];
      final rma = rawRma is Map
          ? Map<String, dynamic>.from(rawRma)
          : <String, dynamic>{};
      final rmaId = _asInt(rma['id'] ?? response['rma_id'] ?? response['id']);
      final customerEmailSent = response['customer_email_sent'] == true ||
          rma['customer_email_sent'] == true;

      final openHistory = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green),
              SizedBox(width: 10),
              Expanded(child: Text('RMA registrada')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rmaId > 0
                    ? 'Tu solicitud RMA #$rmaId ha quedado registrada.'
                    : 'Tu solicitud RMA ha quedado registrada.',
              ),
              const SizedBox(height: 12),
              Text('Pedido: #${widget.orderId}'),
              Text('Producto: ${widget.productName}'),
              if (widget.sku.trim().isNotEmpty) Text('SKU: ${widget.sku.trim()}'),
              if (_selectedSerialNumber != null && _selectedSerialNumber!.trim().isNotEmpty)
                Text('SN: ${_selectedSerialNumber!.trim()}'),
              Text('Cantidad: $_quantity'),
              const SizedBox(height: 12),
              Text(
                customerEmailSent
                    ? 'También hemos enviado una confirmación por email.'
                    : 'La solicitud queda guardada en Gestión de RMA aunque el email de confirmación no pueda entregarse.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CERRAR'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('VER MIS RMA'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (openHistory == true) {
        if (widget.onGoRma != null) {
          // Este formulario vive dentro del Navigator de la pestaña Pedidos.
          // Cerramos su pila local para que, al volver más tarde a Pedidos,
          // el usuario no regrese al formulario RMA ya enviado.
          Navigator.of(context).popUntil((route) => route.isFirst);

          // La pestaña RMA pertenece a MainScreen. El callback cambia el tab
          // principal al índice de RMA en lugar de abrir RmaPage dentro de
          // Pedidos (que era el comportamiento incorrecto).
          widget.onGoRma!();
          return;
        }

        // Fallback para usos aislados de RmaFormPage fuera de MainScreen.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RmaPage()),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ProfessionalPageAppBar(
        title: 'SOLICITAR RMA',
        subtitle: '',
        icon: Icons.handyman_outlined,
        onBack: () => Navigator.pop(context),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _productCard(),
              const SizedBox(height: 22),
              _quantityCard(),
              const SizedBox(height: 24),
              const Text(
                'MOTIVO DE LA DEVOLUCIÓN',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 0.8),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: _motivos.map((motivo) {
                    final selected = _selectedMotivo == motivo;
                    return InkWell(
                      onTap: () => setState(() => _selectedMotivo = motivo),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primary.withOpacity(0.05) : Colors.transparent,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 20,
                              color: selected ? AppColors.primary : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                motivo,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color: selected ? AppColors.primary : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (_selectedMotivo == 'Otro') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _motivoController,
                  decoration: _inputDecoration('Especifica el motivo'),
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Campo requerido' : null,
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'DESCRIPCIÓN DEL PROBLEMA',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 0.8),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcionController,
                maxLines: 5,
                decoration: _inputDecoration('Describe el problema que tienes con el producto...'),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _enviarRma,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('ENVIAR SOLICITUD', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productCard() {
    final warranty = _isInWarranty;
    final warrantyUntil = _warrantyUntil;
    final purchaseDate = widget.orderDate;
    final serials = _serialNumbers;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Producto seleccionado',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.productName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 7),
                    _infoLine(Icons.receipt_long_outlined, 'Pedido #${widget.orderId}'),
                    if (purchaseDate != null)
                      _infoLine(
                        Icons.calendar_today_outlined,
                        'Compra: ${DateFormat('dd/MM/yyyy').format(purchaseDate)}',
                      ),
                    if (widget.sku.trim().isNotEmpty)
                      _infoLine(Icons.qr_code_2_rounded, 'SKU: ${widget.sku.trim()}'),
                  ],
                ),
              ),
            ],
          ),
          if (warranty != null && warrantyUntil != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: warranty
                    ? Colors.green.withOpacity(0.08)
                    : Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: warranty
                      ? Colors.green.withOpacity(0.22)
                      : Colors.orange.withOpacity(0.22),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    warranty
                        ? Icons.verified_outlined
                        : Icons.info_outline_rounded,
                    size: 19,
                    color: warranty ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      warranty
                          ? 'En garantía hasta ${DateFormat('dd/MM/yyyy').format(warrantyUntil)}'
                          : 'Fuera del periodo de garantía de 2 años',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: warranty ? Colors.green.shade800 : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_loadingSerialNumbers && serials.isEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Comprobando número de serie del pedido…',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (serials.isNotEmpty) ...[
            const SizedBox(height: 14),
            _serialSelectorSection(serials),
          ],
        ],
      ),
    );
  }

  Widget _infoLine(
    IconData icon,
    String text, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serialSelectorSection(List<String> serials) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serials.length == 1
                ? 'N.º DE SERIE (SN)'
                : 'SELECCIONA EL N.º DE SERIE A DEVOLVER',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4B5563),
              letterSpacing: 0.45,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            serials.length == 1
                ? 'Esta unidad queda identificada automáticamente.'
                : 'El pedido contiene varias unidades. Elige exactamente cuál quieres tramitar en RMA.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.3,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(serials.length, (index) {
            final serial = serials[index];
            final selected = _selectedSerialNumber == serial;

            return Padding(
              padding: EdgeInsets.only(
                bottom: index == serials.length - 1 ? 0 : 7,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() {
                  _selectedSerialNumber = serial;
                  _quantity = 1;
                }),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withOpacity(0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: selected ? AppColors.primary : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              serials.length == 1
                                  ? 'Unidad'
                                  : 'Unidad ${index + 1}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'SN: $serial',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1A1A1A),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _quantityCard() {
    final hasSerials = _serialNumbers.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CANTIDAD PARA RMA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 0.7)),
                const SizedBox(height: 4),
                Text(
                  hasSerials
                      ? 'La unidad queda identificada por el SN seleccionado.'
                      : 'Indica cuántas unidades presentan el problema.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _quantityButton(Icons.remove, !hasSerials && _quantity > 1 ? () => setState(() => _quantity--) : null),
          SizedBox(width: 42, child: Text('$_quantity', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          _quantityButton(Icons.add, !hasSerials && _quantity < _maxQuantity ? () => setState(() => _quantity++) : null),
          const SizedBox(width: 8),
          Text(hasSerials ? '/ 1' : '/ $_maxQuantity', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _quantityButton(IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: onPressed == null ? Colors.grey.shade100 : AppColors.primary.withOpacity(0.08),
          foregroundColor: onPressed == null ? Colors.grey.shade400 : AppColors.primary,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String text) {
    return InputDecoration(
      hintText: text,
      labelText: _selectedMotivo == 'Otro' && text.startsWith('Especifica') ? text : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
    );
  }
}
