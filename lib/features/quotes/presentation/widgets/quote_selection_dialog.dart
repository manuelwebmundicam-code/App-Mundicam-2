import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../data/models/local_quote_model.dart';
import '../providers/local_quote_provider.dart';

class QuoteSelectionDialog extends ConsumerStatefulWidget {
  final String productName;
  final int productId;
  final double price;
  final int quantity;

  const QuoteSelectionDialog({
    super.key,
    required this.productName,
    required this.productId,
    required this.price,
    required this.quantity,
  });

  @override
  ConsumerState<QuoteSelectionDialog> createState() =>
      _QuoteSelectionDialogState();
}

class _QuoteSelectionDialogState extends ConsumerState<QuoteSelectionDialog> {
  final TextEditingController _nombreController = TextEditingController();
  bool _mostrandoFormulario = false;

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localQuotes = ref.watch(localQuotesProvider);
    final quotesActivos = localQuotes.where((q) => !q.isExpired).toList();
    final hayPresupuestos = quotesActivos.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: 16),

            // Info del producto
            _buildProductInfo(),
            const SizedBox(height: 20),

            // CONTENIDO: Lista O Formulario
            if (_mostrandoFormulario || !hayPresupuestos)
              _buildFormulario(hayPresupuestos)
            else
              _buildListaPresupuestos(quotesActivos),

            const SizedBox(height: 12),
            // Cancelar
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'CANCELAR',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.request_quote_outlined,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Añadir a presupuesto',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFamily: 'Oswald',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.quantity} x ${widget.price.toStringAsFixed(2)} € = ${(widget.price * widget.quantity).toStringAsFixed(2)} €',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
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

  // ═══════════════════════════════════════════════════
  // LISTA DE PRESUPUESTOS EXISTENTES
  // ═══════════════════════════════════════════════════

  Widget _buildListaPresupuestos(List<LocalQuote> quotes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'TUS PRESUPUESTOS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.grey,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        ...quotes.map((quote) => _buildQuoteTile(quote)),
        const SizedBox(height: 12),
        _buildBotonCrearNuevo(),
      ],
    );
  }

  Widget _buildQuoteTile(LocalQuote quote) {
    final totalItems = quote.items.fold<int>(0, (sum, i) => sum + i.quantity);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Simplemente devuelve los datos, el que llama decide
            Navigator.pop(context, {
              'action': 'anadir_existente',
              'orderId': quote.orderId,
              'nombre': quote.nombre,
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.folder_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalItems producto${totalItems != 1 ? 's' : ''} · ${quote.total.toStringAsFixed(2)} €',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.primary.withValues(alpha: 0.7),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBotonCrearNuevo() {
    return InkWell(
      onTap: () {
        setState(() {
          _mostrandoFormulario = true;
          _nombreController.clear();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'CREAR NUEVO PRESUPUESTO',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // FORMULARIO NUEVO PRESUPUESTO
  // ═══════════════════════════════════════════════════

  Widget _buildFormulario(bool hayPresupuestosPrevios) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text(
              'NOMBRE DEL PRESUPUESTO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.grey,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            if (hayPresupuestosPrevios)
              TextButton(
                onPressed: () {
                  setState(() {
                    _mostrandoFormulario = false;
                    _nombreController.clear();
                  });
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '← VOLVER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nombreController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Ej: Presupuesto Casa Mallorca',
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            prefixIcon: Icon(
              Icons.edit_note_rounded,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
            suffixIcon: _nombreController.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                _nombreController.clear();
                setState(() {});
              },
            )
                : null,
          ),
          onSubmitted: (_) => _confirmar(),
        ),
        const SizedBox(height: 4),
        Text(
          'Si no pones nombre, se usará el ID automáticamente.',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[500],
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _confirmar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 15),
              elevation: 0,
            ),
            child: const Text(
              'CREAR Y AÑADIR PRODUCTO',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmar() {
    final nombre = _nombreController.text.trim();
    // Si no pone nombre, se usará el ID en el provider
    Navigator.pop(context, {
      'action': 'crear_y_anadir',
      'nombre': nombre, // Puede ser vacío, el provider usará el ID
    });
  }
}