import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/features/rma/presentation/providers/rma_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class RmaPage extends ConsumerStatefulWidget {
  final VoidCallback? onGoHome;
  final VoidCallback? onGoOrders;

  const RmaPage({
    super.key,
    this.onGoHome,
    this.onGoOrders,
  });

  @override
  ConsumerState<RmaPage> createState() => _RmaPageState();
}

class _RmaPageState extends ConsumerState<RmaPage> {
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    MundicamAnalyticsService.instance.trackScreenViewForRoute(context, 'rma');
    final rmaAsync = ref.watch(rmaProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ProfessionalPageAppBar(
        title: 'GESTIÓN DE RMA',
        subtitle: '',
        icon: Icons.assignment_return_outlined,
        onBack: widget.onGoHome ?? () => Navigator.pop(context),
        onRefresh: () => ref.invalidate(rmaProvider),
      ),
      body: rmaAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, stack) => _buildErrorState(err),
        data: (rmas) {
          if (rmas.isEmpty) {
            return _buildEmptyState();
          }

          final counts = _buildCounts(rmas);
          final filtered = rmas.where(_matchesSelectedFilter).toList();

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(rmaProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _buildOverviewCard(rmas.length, counts),
                const SizedBox(height: 12),
                _buildHowToCard(),
                const SizedBox(height: 16),
                _buildFilterBar(counts),
                const SizedBox(height: 14),
                if (filtered.isEmpty)
                  _buildNoFilteredResults()
                else
                  ...filtered.map(_buildRmaCard),
              ],
            ),
          );
        },
      ),
    );
  }

  Map<String, int> _buildCounts(List<Map<String, dynamic>> rmas) {
    var pending = 0;
    var processing = 0;
    var completed = 0;
    var other = 0;

    for (final rma in rmas) {
      switch (_statusGroup(_text(rma['status'], fallback: 'pending'))) {
        case 'pending':
          pending++;
          break;
        case 'processing':
          processing++;
          break;
        case 'completed':
          completed++;
          break;
        default:
          other++;
      }
    }

    return {
      'all': rmas.length,
      'pending': pending,
      'processing': processing,
      'completed': completed,
      'other': other,
    };
  }

  bool _matchesSelectedFilter(Map<String, dynamic> rma) {
    if (_selectedFilter == 'all') return true;
    return _statusGroup(_text(rma['status'], fallback: 'pending')) ==
        _selectedFilter;
  }

  Widget _buildOverviewCard(int total, Map<String, int> counts) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.assignment_return_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tus solicitudes RMA',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$total solicitud${total == 1 ? '' : 'es'} registrada${total == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                  label: 'Pendientes',
                  count: counts['pending'] ?? 0,
                  icon: Icons.schedule_rounded,
                  color: Colors.orange.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryTile(
                  label: 'En proceso',
                  count: counts['processing'] ?? 0,
                  icon: Icons.sync_rounded,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryTile(
                  label: 'Completadas',
                  count: counts['completed'] ?? 0,
                  icon: Icons.check_circle_outline_rounded,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.065),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 5),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowToCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F7),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: AppColors.primary,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Para abrir una nueva RMA, entra en Pedidos y selecciona el producto correspondiente.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.onGoOrders != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: widget.onGoOrders,
              tooltip: 'Ir a Pedidos',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar(Map<String, int> counts) {
    final filters = <_RmaFilterData>[
      _RmaFilterData('all', 'Todas', counts['all'] ?? 0),
      _RmaFilterData('pending', 'Pendientes', counts['pending'] ?? 0),
      _RmaFilterData('processing', 'En proceso', counts['processing'] ?? 0),
      _RmaFilterData('completed', 'Completadas', counts['completed'] ?? 0),
    ];

    if ((counts['other'] ?? 0) > 0) {
      filters.add(_RmaFilterData('other', 'Otros', counts['other'] ?? 0));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 9),
          child: Text(
            'HISTORIAL',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF667085),
              letterSpacing: 0.8,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters.map((filter) {
              final selected = _selectedFilter == filter.key;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() => _selectedFilter = filter.key),
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : const Color(0xFFE2E5EA),
                      ),
                    ),
                    child: Text(
                      '${filter.label} · ${filter.count}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : const Color(0xFF475467),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRmaCard(Map<String, dynamic> rma) {
    final id = _text(rma['id'] ?? rma['rma_id'], fallback: '—');
    final status = _text(rma['status'], fallback: 'pending').toLowerCase();
    final statusData = _statusData(status, _text(rma['status_label']));
    final productName = _text(rma['product_name'], fallback: 'Producto');
    final sku = _text(rma['product_sku'] ?? rma['sku']);
    final orderNumber =
        _text(rma['order_number'] ?? rma['order_id'], fallback: '—');
    final quantity = _int(rma['quantity'], fallback: 1);
    final purchasedQuantity = _int(rma['purchased_quantity'], fallback: quantity);
    final reason = _text(rma['reason']);
    final description = _text(rma['description']);
    final dateCreated =
        _formatDate(_text(rma['created_at'] ?? rma['date_created']));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E9EE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.028),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusData.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'RMA #$id',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15.5,
                                    color: Color(0xFF101828),
                                  ),
                                ),
                                if (dateCreated.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    dateCreated,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF98A2B3),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _statusBadge(statusData),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Text(
                        productName,
                        style: const TextStyle(
                          color: Color(0xFF344054),
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (sku.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'SKU: $sku',
                          style: const TextStyle(
                            color: Color(0xFF98A2B3),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          Expanded(
                            child: _detailBox(
                              icon: Icons.receipt_long_outlined,
                              label: 'Pedido',
                              value: '#$orderNumber',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _detailBox(
                              icon: Icons.inventory_2_outlined,
                              label: 'Cantidad',
                              value: purchasedQuantity > quantity
                                  ? '$quantity de $purchasedQuantity'
                                  : '$quantity',
                            ),
                          ),
                        ],
                      ),
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MOTIVO',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF98A2B3),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                reason,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF344054),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667085),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(_RmaStatusData statusData) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: statusData.color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusData.icon, size: 13, color: statusData.color),
          const SizedBox(width: 5),
          Text(
            statusData.label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              color: statusData.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailBox({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFC),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFEEF0F3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: const Color(0xFF667085)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xFF98A2B3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF344054),
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

  Widget _buildNoFilteredResults() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E9EE)),
      ),
      child: const Column(
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 34, color: Color(0xFF98A2B3)),
          SizedBox(height: 10),
          Text(
            'No hay solicitudes en este estado',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475467),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(rmaProvider),
      child: ListView(
        padding: const EdgeInsets.all(24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 70),
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.assignment_return_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'No tienes solicitudes RMA',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Cuando necesites tramitar una incidencia, entra en Pedidos, abre el pedido correspondiente y selecciona el producto.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: Color(0xFF667085),
              height: 1.5,
            ),
          ),
          if (widget.onGoOrders != null) ...[
            const SizedBox(height: 24),
            Center(
              child: FilledButton.icon(
                onPressed: widget.onGoOrders,
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('IR A PEDIDOS'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
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
              'No se pudo cargar el historial RMA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(rmaProvider),
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

  static String _statusGroup(String rawStatus) {
    final status = rawStatus.trim().toLowerCase().replaceAll('wc-', '');

    if (status == 'pending' || status == 'pendiente') {
      return 'pending';
    }
    if (status == 'processing' ||
        status == 'in-progress' ||
        status == 'in_progress' ||
        status == 'en-proceso' ||
        status == 'en proceso') {
      return 'processing';
    }
    if (status == 'completed' ||
        status == 'complete' ||
        status == 'completado' ||
        status == 'completada') {
      return 'completed';
    }
    return 'other';
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  static int _int(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed == null) return raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} · ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  static _RmaStatusData _statusData(String status, String serverLabel) {
    switch (_statusGroup(status)) {
      case 'completed':
        return _RmaStatusData(
          Colors.green.shade700,
          serverLabel.isEmpty ? 'Completado' : serverLabel,
          Icons.check_circle_outline,
        );
      case 'processing':
        return _RmaStatusData(
          Colors.blue.shade700,
          serverLabel.isEmpty ? 'En proceso' : serverLabel,
          Icons.sync_rounded,
        );
      case 'pending':
        return _RmaStatusData(
          Colors.orange.shade700,
          serverLabel.isEmpty ? 'Pendiente' : serverLabel,
          Icons.schedule_rounded,
        );
      default:
        if (status == 'cancelled' || status == 'rejected') {
          return _RmaStatusData(
            Colors.red.shade700,
            serverLabel.isEmpty ? 'Cancelado' : serverLabel,
            Icons.cancel_outlined,
          );
        }
        return _RmaStatusData(
          Colors.grey.shade700,
          serverLabel.isEmpty ? status.toUpperCase() : serverLabel,
          Icons.info_outline,
        );
    }
  }
}

class _RmaFilterData {
  final String key;
  final String label;
  final int count;

  const _RmaFilterData(this.key, this.label, this.count);
}

class _RmaStatusData {
  final Color color;
  final String label;
  final IconData icon;

  const _RmaStatusData(this.color, this.label, this.icon);
}
