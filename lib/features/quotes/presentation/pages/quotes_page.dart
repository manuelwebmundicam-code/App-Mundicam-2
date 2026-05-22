import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/quotes/data/models/quote_model.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/cart/presentation/pages/cart_page.dart';
import 'package:mundicam/features/home/presentation/pages/home_page.dart';

class QuotesPage extends ConsumerStatefulWidget {
  final VoidCallback? onGoHome;
  final VoidCallback? onGoCart;
  final Set<String> confirmedQuoteIds;
  final Future<void> Function(Set<String> quoteIds)? onQuotesConfirmed;

  const QuotesPage({
    super.key,
    this.onGoHome,
    this.onGoCart,
    this.confirmedQuoteIds = const <String>{},
    this.onQuotesConfirmed,
  });

  @override
  ConsumerState<QuotesPage> createState() => _QuotesPageState();
}

class _QuotesPageState extends ConsumerState<QuotesPage> {
  bool _isLoadingAction = false;
  String? _processingQuoteId;

  final Set<String> _hiddenQuoteIds = <String>{};

  @override
  void initState() {
    super.initState();

    _hiddenQuoteIds.addAll(widget.confirmedQuoteIds);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(quotesProvider);
    });
  }

  Future<void> _ocultarPresupuesto(QuoteMundicam quote) async {
    if (_isLoadingAction) return;

    final quoteId = quote.id.toString();

    HapticFeedback.lightImpact();

    setState(() {
      _hiddenQuoteIds.add(quoteId);
    });

    final callback = widget.onQuotesConfirmed;
    if (callback != null) {
      await callback(<String>{quoteId});
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Presupuesto #$quoteId eliminado de pendientes.'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _aceptarPresupuesto(QuoteMundicam quote) async {
    if (_isLoadingAction) return;

    final quoteId = quote.id.toString();

    setState(() {
      _isLoadingAction = true;
      _processingQuoteId = quoteId;
    });

    try {
      final api = ApiService();
      final orderId = quoteId.replaceAll(RegExp(r'[^0-9]'), '');

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
        _hiddenQuoteIds.add(quoteId);
      });

      final callback = widget.onQuotesConfirmed;
      if (callback != null) {
        await callback(<String>{quoteId});
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Presupuesto #$quoteId aceptado. Productos añadidos al carrito.',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

      if (widget.onGoCart != null) {
        widget.onGoCart!();
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CartPage()),
        );
      }
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
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: _goToHome,
        ),
        title: const Text(
          'MIS PRESUPUESTOS',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Oswald',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: () => ref.invalidate(quotesProvider),
          ),
        ],
      ),
      body: quotesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (_, __) => _buildErrorState(ref),
        data: (allQuotes) {
          final quotes = allQuotes.where((quote) {
            final quoteId = quote.id.toString();

            if (_hiddenQuoteIds.contains(quoteId)) return false;
            if (widget.confirmedQuoteIds.contains(quoteId)) return false;

            return true;
          }).toList();

          if (quotes.isEmpty) {
            return _buildEmptyState();
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: _buildSummaryCard(quotes),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    ref.invalidate(quotesProvider);
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
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

  Widget _buildSummaryCard(List<QuoteMundicam> quotes) {
    final total = quotes.fold<double>(0, (sum, q) => sum + q.total);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
              color: const Color(0xFFF8EAEA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: AppColors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${quotes.length} presupuesto${quotes.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFamily: 'Oswald',
              ),
            ),
          ),
          Text(
            'Total: ${total.toStringAsFixed(2)} €',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              fontFamily: 'Oswald',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard(QuoteMundicam quote) {
    final bool isProcessing = _processingQuoteId == quote.id.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatusBadgeCompact(quote),
              const Spacer(),
              _deleteButton(quote),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Presupuesto #${quote.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        fontFamily: 'Oswald',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quote.description.isEmpty
                          ? 'Presupuesto pendiente de confirmar'
                          : quote.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF7A7A7A),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${quote.total.toStringAsFixed(2)} €',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  fontFamily: 'Oswald',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: const Color(0xFFEDEDED),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildDaysBadge(quote.daysLeft)),
              const SizedBox(width: 12),
              isProcessing
                  ? Container(
                width: 50,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary,
                  ),
                ),
              )
                  : SizedBox(
                height: 46,
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
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Colors.white,
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
        ],
      ),
    );
  }

  Widget _deleteButton(QuoteMundicam quote) {
    return GestureDetector(
      onTap: _isLoadingAction ? null : () => _ocultarPresupuesto(quote),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFF8EAEA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF0D4D4)),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          size: 19,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildStatusBadgeCompact(QuoteMundicam quote) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    if (quote.daysLeft <= 0) {
      bgColor = const Color(0xFFFDECEC);
      textColor = const Color(0xFFD94A4A);
      icon = Icons.cancel_outlined;
      label = 'Expirado';
    } else if (quote.daysLeft < 3) {
      bgColor = const Color(0xFFFFF3E5);
      textColor = const Color(0xFFE58A00);
      icon = Icons.schedule;
      label = 'Urgente';
    } else {
      bgColor = const Color(0xFFEAF3FF);
      textColor = const Color(0xFF3A86D8);
      icon = Icons.description_outlined;
      label = 'Pendiente';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysBadge(int daysLeft) {
    final bool isExpired = daysLeft <= 0;
    final bool isUrgent = daysLeft > 0 && daysLeft < 3;

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String text;

    if (isExpired) {
      bgColor = const Color(0xFFFDECEC);
      borderColor = const Color(0xFFF7C6C6);
      textColor = const Color(0xFFD94A4A);
      icon = Icons.cancel_outlined;
      text = 'Expirado';
    } else if (isUrgent) {
      bgColor = const Color(0xFFFFF3E5);
      borderColor = const Color(0xFFFFD8A8);
      textColor = const Color(0xFFE58A00);
      icon = Icons.warning_amber_rounded;
      text = 'Vence en $daysLeft día${daysLeft == 1 ? '' : 's'}';
    } else {
      bgColor = const Color(0xFFEAF3FF);
      borderColor = const Color(0xFFB9D8FF);
      textColor = const Color(0xFF3A86D8);
      icon = Icons.access_time_rounded;
      text = 'Vence en $daysLeft días';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.description_outlined,
                size: 62,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'No tienes presupuestos pendientes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFamily: 'Oswald',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Cuando solicites un presupuesto desde el catálogo aparecerá aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8A8A8A),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 52,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Error al cargar presupuestos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFamily: 'Oswald',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comprueba tu conexión y vuelve a intentarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8A8A8A),
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(quotesProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REINTENTAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}