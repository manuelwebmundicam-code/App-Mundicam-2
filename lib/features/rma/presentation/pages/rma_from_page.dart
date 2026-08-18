import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  const RmaFormPage({
    super.key,
    required this.orderId,
    required this.productId,
    required this.productName,
    this.lineItemId = 0,
    this.variationId = 0,
    this.maxQuantity = 1,
  });

  @override
  ConsumerState<RmaFormPage> createState() => _RmaFormPageState();
}

class _RmaFormPageState extends ConsumerState<RmaFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _motivoController = TextEditingController();
  final _descripcionController = TextEditingController();
  bool _isLoading = false;
  int _quantity = 1;

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
        motivo: motivo,
        descripcion: _descripcionController.text.trim(),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Producto seleccionado', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(widget.productName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 4),
                Text('Pedido #${widget.orderId}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CANTIDAD PARA RMA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 0.7)),
                SizedBox(height: 4),
                Text('Indica cuántas unidades presentan el problema.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _quantityButton(Icons.remove, _quantity > 1 ? () => setState(() => _quantity--) : null),
          SizedBox(width: 42, child: Text('$_quantity', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          _quantityButton(Icons.add, _quantity < _maxQuantity ? () => setState(() => _quantity++) : null),
          const SizedBox(width: 8),
          Text('/ $_maxQuantity', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
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
