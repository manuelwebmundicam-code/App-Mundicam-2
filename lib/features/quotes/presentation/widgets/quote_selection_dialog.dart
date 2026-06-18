import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
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
  ConsumerState<QuoteSelectionDialog> createState() => _QuoteSelectionDialogState();
}

class _QuoteSelectionDialogState extends ConsumerState<QuoteSelectionDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _creatingNew = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quotes = ref.watch(localQuotesProvider).where((quote) => !quote.isExpired).toList();
    final hasQuotes = quotes.isNotEmpty;
    final showForm = _creatingNew || !hasQuotes;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 430),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProductSummary(),
                    const SizedBox(height: 16),
                    if (!showForm) ...[
                      const Text(
                        'Elige un presupuesto existente',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: quotes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final quote = quotes[index];
                            return _QuoteOptionTile(
                              title: quote.nombre,
                              subtitle: '${quote.items.length} producto${quote.items.length == 1 ? '' : 's'} · ${_formatMoney(quote.total)}',
                              onTap: () {
                                Navigator.of(context).pop({
                                  'action': 'anadir_existente',
                                  'orderId': quote.orderId,
                                  'nombre': quote.nombre,
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _creatingNew = true),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('CREAR NUEVO PRESUPUESTO'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        hasQuotes ? 'Crear nuevo presupuesto' : 'Nombre del presupuesto',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameController,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _createAndAdd(),
                        decoration: InputDecoration(
                          hintText: 'Ej. Casa Juan (opcional)',
                          filled: true,
                          fillColor: const Color(0xFFF8F9FB),
                          prefixIcon: const Icon(Icons.edit_note_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFE1E4EA)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFE1E4EA)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Si lo dejas vacío, se creará con un número automático.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (hasQuotes) ...[
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: () => setState(() => _creatingNew = false),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textPrimary,
                                    side: const BorderSide(color: Color(0xFFD9DEE7)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: const Text('VOLVER'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            flex: hasQuotes ? 2 : 1,
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _createAndAdd,
                                icon: const Icon(Icons.add_task_rounded, size: 18),
                                label: const Text('CREAR Y AÑADIR'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
      decoration: const BoxDecoration(
        color: AppColors.primary,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.request_quote_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'AÑADIR A PRESUPUESTO',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Oswald',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.productName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.quantity} ud. · ${_formatMoney(widget.price)}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _createAndAdd() {
    Navigator.of(context).pop({
      'action': 'crear_y_anadir',
      'nombre': _nameController.text.trim(),
    });
  }

  String _formatMoney(double value) {
    if (value <= 0) return 'Bajo consulta';
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }
}

class _QuoteOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuoteOptionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E4EA)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.folder_copy_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
