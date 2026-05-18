import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/professional_page_app_bar.dart';
import '../theme.dart';
import '../providers/quote_provider.dart';
import '../providers/cart_provider.dart';
import '../models/quote_model.dart';
import '../services/api_service.dart';
import 'cart_page.dart';
import 'home_page.dart';

class QuotesPage extends ConsumerStatefulWidget {
  final VoidCallback? onGoHome;

  const QuotesPage({
    super.key,
    this.onGoHome,
  });

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
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ProfessionalPageAppBar(
        title: 'MIS PRESUPUESTOS',
        subtitle: 'Consulta y acepta presupuestos pendientes',
        icon: Icons.description_outlined,
        onBack: _goToHome,
        onRefresh: () => ref.invalidate(quotesProvider),
      ),
      body: quotesAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text(
                'Cargando presupuestos...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                color: Colors.white,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${quotes.length} presupuesto${quotes.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      'Total: ${_formatearTotal(quotes)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.primary,
                        fontFamily: 'Oswald',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    ref.invalidate(quotesProvider);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpired
              ? Colors.red.shade200
              : isUrgent
              ? Colors.orange.shade200
              : Colors.grey.shade200,
          width: isExpired ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Presupuesto #${quote.id}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        quote.description.length > 40
                            ? '${quote.description.substring(0, 40)}...'
                            : quote.description,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildDaysBadge(quote.daysLeft),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusBadge(quote.status, quote.daysLeft),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'IMPORTE TOTAL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${quote.total.toStringAsFixed(2)} €',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            fontFamily: 'Oswald',
                          ),
                        ),
                      ],
                    ),
                    if (isProcessing)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
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
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
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
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade700;
      label = 'Expirado';
      icon = Icons.cancel_outlined;
    } else if (daysLeft < 3) {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade700;
      label = 'Urgente';
      icon = Icons.warning_amber_rounded;
    } else {
      bgColor = Colors.blue.shade50;
      textColor = Colors.blue.shade700;
      label = 'Pendiente';
      icon = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isExpired
            ? Colors.red.shade50
            : isUrgent
            ? Colors.orange.shade50
            : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isExpired
              ? Colors.red.shade200
              : isUrgent
              ? Colors.orange.shade200
              : Colors.blue.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isExpired
                ? Icons.cancel_outlined
                : isUrgent
                ? Icons.warning_amber_rounded
                : Icons.access_time_rounded,
            size: 14,
            color: isExpired
                ? Colors.red
                : isUrgent
                ? Colors.orange.shade800
                : Colors.blue.shade800,
          ),
          const SizedBox(width: 5),
          Text(
            isExpired ? 'Expirado' : 'Vence en $days días',
            style: TextStyle(
              color: isExpired
                  ? Colors.red
                  : isUrgent
                  ? Colors.orange.shade800
                  : Colors.blue.shade800,
              fontSize: 11,
              fontWeight: FontWeight.bold,
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.description_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No tienes presupuestos pendientes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Añade productos al presupuesto desde el catálogo\ny aparecerán aquí automáticamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.5,
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Error al cargar presupuestos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comprueba tu conexión y vuelve a intentarlo.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(quotesProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REINTENTAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}