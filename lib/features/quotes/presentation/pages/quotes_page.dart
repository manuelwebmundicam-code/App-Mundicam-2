import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/quotes/data/models/quote_model.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/cart/presentation/pages/cart_page.dart';
import 'package:mundicam/features/home/presentation/pages/home_page.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0xFFE5E7EB);
const Color _softCard = Color(0xFFFBFCFE);

class QuotesPage extends ConsumerStatefulWidget {
  final VoidCallback? onGoHome;

  const QuotesPage({super.key, this.onGoHome});

  @override
  ConsumerState<QuotesPage> createState() => _QuotesPageState();
}

class _QuotesPageState extends ConsumerState<QuotesPage> {
  bool _isLoadingAction = false;
  String? _processingQuoteId;

  final Set<String> _hiddenQuoteIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(quotesProvider);
    });
  }

  // ================================================================
  // ACEPTAR PRESUPUESTO → Añadir productos al carrito y abrir carrito
  // ================================================================
  Future<void> _aceptarPresupuesto(QuoteMundicam quote) async {
    if (_isLoadingAction) return;

    setState(() {
      _isLoadingAction = true;
      _processingQuoteId = quote.id;
    });

    try {
      final api = ApiService();

      final orderId = quote.id.replaceAll(RegExp(r'[^0-9]'), '');

      if (orderId.isEmpty) {
        throw Exception('No se pudo identificar el ID del presupuesto.');
      }

      final orden = await api.getOrdenCompleta(orderId);

      if (orden == null || orden['line_items'] == null) {
        throw Exception('No se pudieron cargar los productos del presupuesto.');
      }

      final items = orden['line_items'] as List;
      int productosAnadidos = 0;

      for (final item in items) {
        final dynamic rawProductId = item['product_id'];
        final dynamic rawQuantity = item['quantity'];

        final int productId = rawProductId is int
            ? rawProductId
            : int.tryParse(rawProductId.toString()) ?? 0;

        final int quantity = rawQuantity is int
            ? rawQuantity
            : int.tryParse(rawQuantity.toString()) ?? 1;

        if (productId <= 0) continue;

        final producto = await api.getProductoById(productId);

        if (producto != null) {
          ref.read(cartProvider.notifier).addProduct(producto, quantity);
          productosAnadidos++;
        }
      }

      if (!mounted) return;

      if (productosAnadidos == 0) {
        throw Exception('No se pudo añadir ningún producto al carrito.');
      }

      setState(() {
        _hiddenQuoteIds.add(quote.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Presupuesto #${quote.id} aceptado. Productos añadidos al carrito.',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CartPage()),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al aceptar el presupuesto: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAction = false;
          _processingQuoteId = null;
        });
      }
    }
  }

  void _goToHome() {
    if (widget.onGoHome != null) {
      widget.onGoHome!();
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(quotesProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: _goToHome,
        ),
        title: const Text(
          'MIS PRESUPUESTOS',
          style: TextStyle(
            fontFamily: 'Oswald',
            fontWeight: FontWeight.w900,
            fontSize: 19,
            letterSpacing: 0.7,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar presupuestos',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () => ref.invalidate(quotesProvider),
          ),
        ],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: quotesAsync.when(
        loading: () => const _QuotesLoadingState(),
        error: (err, stack) => _buildErrorState(ref),
        data: (allQuotes) {
          final quotes = allQuotes
              .where((quote) => !_hiddenQuoteIds.contains(quote.id))
              .toList();

          if (quotes.isEmpty) {
            return _buildEmptyState(context);
          }

          return Column(
            children: [
              _QuotesSummaryHeader(
                count: quotes.length,
                total: _formatearTotal(quotes),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    ref.invalidate(quotesProvider);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: quotes.length,
                    itemBuilder: (context, index) {
                      return _buildQuoteCard(quotes[index]);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatearTotal(List<QuoteMundicam> quotes) {
    final total = quotes.fold<double>(0, (sum, q) => sum + q.total);
    return '${total.toStringAsFixed(2)} €';
  }

  Widget _buildQuoteCard(QuoteMundicam quote) {
    final bool isUrgent = quote.daysLeft < 3;
    final bool isExpired = quote.daysLeft <= 0;
    final bool isProcessing = _processingQuoteId == quote.id;

    Color borderColor = _border;

    if (isExpired) {
      borderColor = Colors.red.shade200;
    } else if (isUrgent) {
      borderColor = Colors.orange.shade200;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: isExpired ? 1.4 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Presupuesto #${quote.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Oswald',
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            height: 1.1,
                            color: _dark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          quote.description.length > 56
                              ? '${quote.description.substring(0, 56)}...'
                              : quote.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildDaysBadge(quote.daysLeft),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusBadge(quote.status, quote.daysLeft),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: _softCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'IMPORTE TOTAL',
                              style: TextStyle(
                                fontSize: 10.8,
                                fontWeight: FontWeight.w900,
                                color: _muted,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${quote.total.toStringAsFixed(2)} €',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                                fontFamily: 'Oswald',
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (isProcessing)
                      Container(
                        height: 44,
                        width: 92,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _isLoadingAction
                              ? null
                              : () => _aceptarPresupuesto(quote),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'ACEPTAR',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontSize: 12.5,
                              fontFamily: 'Oswald',
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.45),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, int daysLeft) {
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    if (daysLeft <= 0) {
      bgColor = const Color(0xFFFFE8E8);
      textColor = const Color(0xFFDC2626);
      label = 'Expirado';
      icon = Icons.cancel_outlined;
    } else if (daysLeft < 3) {
      bgColor = const Color(0xFFFFF4E5);
      textColor = const Color(0xFFD97706);
      label = 'Urgente';
      icon = Icons.warning_amber_rounded;
    } else {
      bgColor = const Color(0xFFEAF2FF);
      textColor = const Color(0xFF1D4ED8);
      label = 'Pendiente';
      icon = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysBadge(int days) {
    final bool isUrgent = days < 3;
    final bool isExpired = days <= 0;

    final Color bgColor = isExpired
        ? const Color(0xFFFFE8E8)
        : isUrgent
        ? const Color(0xFFFFF4E5)
        : const Color(0xFFEAF2FF);

    final Color textColor = isExpired
        ? const Color(0xFFDC2626)
        : isUrgent
        ? const Color(0xFFD97706)
        : const Color(0xFF1D4ED8);

    final IconData icon = isExpired
        ? Icons.cancel_outlined
        : isUrgent
        ? Icons.warning_amber_rounded
        : Icons.access_time_rounded;

    return Container(
      constraints: const BoxConstraints(maxWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: textColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              isExpired ? 'Expirado' : 'Vence en $days días',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 10.6,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 42,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No tienes presupuestos pendientes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Añade productos al presupuesto desde el catálogo y aparecerán aquí automáticamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 38,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Error al cargar presupuestos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Comprueba tu conexión y vuelve a intentarlo.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => ref.invalidate(quotesProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'REINTENTAR',
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuotesSummaryHeader extends StatelessWidget {
  const _QuotesSummaryHeader({
    required this.count,
    required this.total,
  });

  final int count;
  final String total;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _pageBg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.description_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count presupuesto${count != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: _dark,
                  fontFamily: 'Oswald',
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.10),
                ),
              ),
              child: Text(
                'Total: $total',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Oswald',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotesLoadingState extends StatelessWidget {
  const _QuotesLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando presupuestos...',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}