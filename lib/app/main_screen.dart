import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/providers/badge_provider.dart';
import 'package:mundicam/features/home/presentation/pages/home_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_page.dart';
import 'package:mundicam/features/orders/presentation/pages/orders_page.dart';
import 'package:mundicam/features/quotes/presentation/pages/quotes_page.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';
import 'package:mundicam/features/cart/presentation/pages/cart_page.dart';

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

  final Set<String> _confirmedQuoteIds = <String>{};

  final List<bool> _loadedTabs = [
    true,
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
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadConfirmedQuoteIdsFromPrefs();

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;

      setState(() {
        _loadBadges = true;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

    return quotesAsync.maybeWhen(
      data: (quotes) {
        return quotes.where((quote) {
          final quoteId = quote.id.toString();

          if (_confirmedQuoteIds.contains(quoteId)) return false;
          if (quote.total <= 0) return false;

          return true;
        }).length;
      },
      orElse: () {
        return math.max(0, rawQuoteCount - _confirmedQuoteIds.length);
      },
    );
  }

  void _switchToTab(int index, {bool popToRoot = false}) {
    if (index < 0 || index >= _navigatorKeys.length) return;

    if (index == 4 && _selectedIndex != 4) {
      _lastIndexBeforeCart = _selectedIndex;
    }

    setState(() {
      _selectedIndex = index;
      _loadedTabs[index] = true;

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
    final int cartItemCount = _loadBadges ? ref.watch(cartBadgeProvider) : 0;
    final int rawQuoteCount = _loadBadges ? ref.watch(quoteBadgeProvider) : 0;
    final int quoteCount =
    _loadBadges ? _visibleQuoteBadgeCount(rawQuoteCount) : 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await _onWillPop();

        if (shouldPop && mounted) {
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
                  label: 'Productos',
                  isSelected: _selectedIndex == 1,
                  onTap: () => _onItemTapped(1),
                ),
                _BottomTabItem(
                  icon: Icons.local_shipping_outlined,
                  activeIcon: Icons.local_shipping,
                  label: 'Pedidos',
                  isSelected: _selectedIndex == 2,
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

    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(
          builder: (context) => child,
          settings: routeSettings,
        );
      },
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