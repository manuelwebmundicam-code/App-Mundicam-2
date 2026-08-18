import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/providers/badge_provider.dart';
import 'package:mundicam/shared/providers/order_badge_provider.dart';
import 'package:mundicam/core/notifications/notification_service.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/features/orders/presentation/providers/order_provider.dart';
import 'package:mundicam/features/home/presentation/pages/home_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_page.dart';
import 'package:mundicam/features/orders/presentation/pages/orders_page.dart';
import 'package:mundicam/features/quotes/presentation/pages/quotes_page.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';
import 'package:mundicam/features/cart/presentation/pages/cart_page.dart';
import 'package:mundicam/features/rma/presentation/pages/rma_page.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  static const String _confirmedQuoteIdsKey = 'mundicam_confirmed_quote_ids';

  int _selectedIndex = 0;
  int _lastIndexBeforeCart = 0;
  bool _loadBadges = false;
  bool _showingOrderNotificationDialog = false;
  bool _didLogFirstBuild = false;
  StreamSubscription<MundiCamOrderNotification>? _orderNotificationSub;

  final Set<String> _confirmedQuoteIds = <String>{};

  final List<bool> _loadedTabs = [
    true,
    false,
    false,
    false,
    false,
    false,
  ];

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('🍎 MAINSCREEN_INIT');
    WidgetsBinding.instance.addObserver(this);
    unawaited(MundicamAnalyticsService.instance.screenView('home'));

    unawaited(
      _loadConfirmedQuoteIdsFromPrefs().catchError((Object error, StackTrace stack) {
        debugPrint('⚠️ No se pudieron cargar badges iniciales: $error');
        debugPrintStack(stackTrace: stack);
      }),
    );

    try {
      _listenOrderNotifications();
    } catch (error, stack) {
      debugPrint('⚠️ Listener de notificaciones no crítico: $error');
      debugPrintStack(stackTrace: stack);
    }

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;

      setState(() {
        _loadBadges = true;
      });
    });
  }

  @override
  void dispose() {
    _orderNotificationSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _listenOrderNotifications() {
    final pending = NotificationService().takePendingOrderNotifications();

    if (pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        for (final notification in pending) {
          if (!mounted) return;
          await _handleOrderNotification(notification);
        }
      });
    }

    _orderNotificationSub = NotificationService()
        .orderNotifications
        .listen(_handleOrderNotification);
  }

  Future<void> _handleOrderNotification(
      MundiCamOrderNotification notification,
      ) async {
    if (!mounted) return;

    final bool isGeneralNotification = notification.isGeneralNotification;

    if (!isGeneralNotification) {
      ref.invalidate(ordersProvider);
      ref.read(newOrderBadgeProvider.notifier).state++;
    }

    if (notification.openedByUser) {
      if (!isGeneralNotification) {
        _openOrdersFromNotification();
      }
      return;
    }

    // El aviso ya se ha mostrado como notificación del sistema. En primer plano
    // solo actualizamos pedidos y badges; no abrimos pantallas sin una pulsación.
    if (!notification.showPopup) return;

    if (_showingOrderNotificationDialog) return;
    _showingOrderNotificationDialog = true;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _NotificationLogoIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    notification.title,
                    style: const TextStyle(
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      height: 1.05,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              notification.body,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: Color(0xFF374151),
                fontWeight: FontWeight.w500,
              ),
            ),
            actions: isGeneralNotification
                ? [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Entendido'),
              ),
            ]
                : [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openOrdersFromNotification();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: const Text('Ver pedidos'),
              ),
            ],
          );
        },
      );
    } finally {
      _showingOrderNotificationDialog = false;
    }
  }

  void _openOrdersFromNotification() {
    ref.read(newOrderBadgeProvider.notifier).state = 0;
    ref.invalidate(ordersProvider);
    _switchToTab(2, popToRoot: true);
  }

  Future<void> _loadConfirmedQuoteIdsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList(_confirmedQuoteIdsKey) ?? <String>[];

    if (!mounted) return;

    setState(() {
      _confirmedQuoteIds
        ..clear()
        ..addAll(savedIds);
      _loadBadges = true;
    });

    ref.invalidate(quoteBadgeProvider);
    ref.invalidate(quotesProvider);
  }

  Future<void> _registerConfirmedQuotes(Set<String> quoteIds) async {
    if (quoteIds.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList(_confirmedQuoteIdsKey) ?? <String>[];

    final updatedIds = <String>{
      ...savedIds,
      ...quoteIds,
    };

    await prefs.setStringList(
      _confirmedQuoteIdsKey,
      updatedIds.toList(),
    );

    if (!mounted) return;

    setState(() {
      _confirmedQuoteIds
        ..clear()
        ..addAll(updatedIds);
      _loadBadges = true;
    });

    ref.invalidate(quotesProvider);
    ref.invalidate(quoteBadgeProvider);
    ref.invalidate(cartBadgeProvider);
  }

  int _visibleQuoteBadgeCount(int rawQuoteCount) {
    final quotesAsync = ref.watch(quotesProvider);
    final localQuotes = ref.watch(localQuotesProvider);
    final localCount = localQuotes.where((quote) => !quote.isExpired).length;

    return quotesAsync.maybeWhen(
      data: (quotes) {
        final webCount = quotes.where((quote) {
          final quoteId = quote.id.toString();

          if (_confirmedQuoteIds.contains(quoteId)) return false;
          if (quote.total <= 0) return false;

          return true;
        }).length;

        return localCount + webCount;
      },
      orElse: () {
        return math.max(0, rawQuoteCount - _confirmedQuoteIds.length);
      },
    );
  }

  void _switchToTab(int index, {bool popToRoot = false}) {
    if (index < 0 || index >= _navigatorKeys.length) return;

    const analyticsScreenNames = <String>[
      'home',
      'catalog',
      'orders',
      'quotes',
      'cart',
      'rma',
    ];
    unawaited(
      MundicamAnalyticsService.instance.screenView(
        analyticsScreenNames[index],
      ),
    );

    if (index == 4 && _selectedIndex != 4) {
      _lastIndexBeforeCart = _selectedIndex;
    }

    setState(() {
      _selectedIndex = index;
      _loadedTabs[index] = true;

      if (index == 2) {
        ref.read(newOrderBadgeProvider.notifier).state = 0;
      }

      if (index == 3 || index == 4) {
        _loadBadges = true;
      }
    });

    if (popToRoot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = _navigatorKeys[index].currentState;

        if (navigator != null && navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  void _goBackFromCart() {
    final targetIndex = _lastIndexBeforeCart;

    if (targetIndex == 4) {
      _switchToTab(0);
      return;
    }

    _switchToTab(targetIndex);
  }

  void _onItemTapped(int index) {
    if (index == 2) {
      ref.read(newOrderBadgeProvider.notifier).state = 0;
      ref.invalidate(ordersProvider);
    }

    if (_selectedIndex == index) {
      final navigator = _navigatorKeys[index].currentState;

      if (navigator != null && navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }

      return;
    }

    _switchToTab(index);
  }

  Future<bool> _onWillPop() async {
    final currentNavigator = _navigatorKeys[_selectedIndex].currentState;

    if (currentNavigator != null && currentNavigator.canPop()) {
      currentNavigator.pop();
      return false;
    }

    if (_selectedIndex != 0) {
      _switchToTab(0);
      return false;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salir'),
        content: const Text('¿Deseas salir de la aplicación?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_didLogFirstBuild) {
      _didLogFirstBuild = true;
      debugPrint('🍎 MAINSCREEN_BUILD');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('🍎 MAINSCREEN_FIRST_FRAME');
      });
    }

    final int cartItemCount = _loadBadges ? ref.watch(cartBadgeProvider) : 0;
    final int orderCount = _loadBadges ? ref.watch(newOrderBadgeProvider) : 0;
    final int rawQuoteCount = _loadBadges ? ref.watch(quoteBadgeProvider) : 0;
    final int quoteCount =
    _loadBadges ? _visibleQuoteBadgeCount(rawQuoteCount) : 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await _onWillPop();

        if (!context.mounted) return;

        if (shouldPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        extendBody: false,
        resizeToAvoidBottomInset: false,
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildTabNavigator(
              index: 0,
              child: HomePage(
                onGoCart: () => _switchToTab(4, popToRoot: true),
                onGoQuotes: () => _switchToTab(3, popToRoot: true),
              ),
            ),
            _buildTabNavigator(
              index: 1,
              child: ProductosPage(
                onGoHome: () => _switchToTab(0, popToRoot: true),
                onGoCart: () => _switchToTab(4, popToRoot: true),
                onGoQuotes: () => _switchToTab(3, popToRoot: true),
              ),
            ),
            _buildTabNavigator(
              index: 2,
              child: OrdersPage(
                onGoHome: () => _switchToTab(0, popToRoot: true),
              ),
            ),
            _buildTabNavigator(
              index: 3,
              child: QuotesPage(
                onGoHome: () => _switchToTab(0, popToRoot: true),
                onGoCart: () => _switchToTab(4, popToRoot: true),
                confirmedQuoteIds: _confirmedQuoteIds,
                onQuotesConfirmed: _registerConfirmedQuotes,
              ),
            ),
            _buildTabNavigator(
              index: 4,
              child: CartPage(
                onGoHome: () => _switchToTab(0, popToRoot: true),
                onGoBack: _goBackFromCart,
                onGoQuotes: () => _switchToTab(3, popToRoot: true),
              ),
            ),
            _buildTabNavigator(
              index: 5,
              child: RmaPage(
                onGoHome: () => _switchToTab(0, popToRoot: true),
                onGoOrders: () => _switchToTab(2, popToRoot: true),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: EdgeInsets.zero,
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                _BottomTabItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Inicio',
                  isSelected: _selectedIndex == 0,
                  onTap: () => _onItemTapped(0),
                ),
                _BottomTabItem(
                  icon: Icons.grid_view,
                  activeIcon: Icons.grid_view_rounded,
                  label: 'Categorías',
                  isSelected: _selectedIndex == 1,
                  onTap: () => _onItemTapped(1),
                ),
                _BottomTabItem(
                  icon: Icons.assignment_return_outlined,
                  activeIcon: Icons.assignment_return_rounded,
                  label: 'RMA',
                  isSelected: _selectedIndex == 5,
                  onTap: () => _onItemTapped(5),
                ),
                _BottomTabItem(
                  icon: Icons.local_shipping_outlined,
                  activeIcon: Icons.local_shipping,
                  label: 'Pedidos',
                  isSelected: _selectedIndex == 2,
                  badgeCount: orderCount,
                  onTap: () => _onItemTapped(2),
                ),
                _BottomTabItem(
                  icon: Icons.description_outlined,
                  activeIcon: Icons.description,
                  label: 'Presupuestos',
                  isSelected: _selectedIndex == 3,
                  badgeCount: quoteCount,
                  onTap: () => _onItemTapped(3),
                ),
                _BottomTabItem(
                  icon: Icons.shopping_cart_outlined,
                  activeIcon: Icons.shopping_cart,
                  label: 'Carrito',
                  isSelected: _selectedIndex == 4,
                  badgeCount: cartItemCount,
                  onTap: () => _onItemTapped(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabNavigator({
    required int index,
    required Widget child,
  }) {
    if (!_loadedTabs[index]) {
      return const SizedBox.shrink();
    }

    Route<void> buildRootRoute(RouteSettings settings) {
      return MaterialPageRoute<void>(
        builder: (context) => KeyedSubtree(
          key: ValueKey<String>('tab_root_$index'),
          child: child,
        ),
        settings: settings,
      );
    }

    return Navigator(
      key: _navigatorKeys[index],
      initialRoute: '/tab/$index',
      onGenerateInitialRoutes: (navigator, initialRoute) => <Route<void>>[
        buildRootRoute(RouteSettings(name: initialRoute)),
      ],
      onGenerateRoute: buildRootRoute,
      onUnknownRoute: buildRootRoute,
    );
  }
}

class _NotificationLogoIcon extends StatelessWidget {
  const _NotificationLogoIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Image.asset(
          'assets/images/mundicam_notification_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 23,
            );
          },
        ),
      ),
    );
  }
}

class _BottomTabItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;

  const _BottomTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected ? AppColors.primary : Colors.grey.shade500;
    final bool showBadge = badgeCount > 0;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          highlightColor: AppColors.primary.withValues(alpha: 0.04),
          child: SizedBox(
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        isSelected ? activeIcon : icon,
                        size: 21,
                        color: color,
                      ),
                      if (showBadge)
                        Positioned(
                          right: -12,
                          top: -5,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 13,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontSize: isSelected ? 10.5 : 9.5,
                        fontWeight:
                        isSelected ? FontWeight.w800 : FontWeight.w500,
                        fontFamily: isSelected ? 'Oswald' : null,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}