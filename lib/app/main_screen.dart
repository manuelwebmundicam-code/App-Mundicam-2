import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/providers/badge_provider.dart';
import 'package:mundicam/shared/widgets/badge_icon.dart';
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

  int _visibleQuoteBadgeCount() {
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
        final rawQuoteCount = ref.watch(quoteBadgeProvider);
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
    final int quoteCount = _loadBadges ? _visibleQuoteBadgeCount() : 0;

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
        bottomNavigationBar: _buildBottomNavigationBar(
          context: context,
          cartItemCount: cartItemCount,
          quoteCount: quoteCount,
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar({
    required BuildContext context,
    required int cartItemCount,
    required int quoteCount,
  }) {
    final mediaQuery = MediaQuery.of(context);

    final double systemBottomInset = math.max(
      mediaQuery.padding.bottom,
      mediaQuery.viewPadding.bottom,
    );

    final double safeBottomPadding =
    systemBottomInset > 0 ? systemBottomInset + 4 : 10;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        maintainBottomViewPadding: true,
        child: Padding(
          padding: EdgeInsets.only(
            left: 0,
            right: 0,
            top: 4,
            bottom: safeBottomPadding,
          ),
          child: SizedBox(
            height: 58,
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              elevation: 0,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: const Color(0xFF7B8494),
              selectedLabelStyle: const TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.bold,
                fontSize: 11,
                height: 1.1,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w500,
                fontSize: 10.5,
                height: 1.1,
              ),
              selectedFontSize: 11,
              unselectedFontSize: 10.5,
              iconSize: 23,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Inicio',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.grid_view),
                  activeIcon: Icon(Icons.grid_view_rounded),
                  label: 'Productos',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.local_shipping_outlined),
                  activeIcon: Icon(Icons.local_shipping),
                  label: 'Pedidos',
                ),
                BottomNavigationBarItem(
                  icon: BadgeIcon(
                    icon: Icons.description_outlined,
                    count: quoteCount,
                    isActive: _selectedIndex == 3,
                    size: 23,
                  ),
                  activeIcon: BadgeIcon(
                    icon: Icons.description,
                    count: quoteCount,
                    isActive: true,
                    size: 23,
                  ),
                  label: 'Presupuestos',
                ),
                BottomNavigationBarItem(
                  icon: BadgeIcon(
                    icon: Icons.shopping_cart_outlined,
                    count: cartItemCount,
                    isActive: _selectedIndex == 4,
                    size: 23,
                  ),
                  activeIcon: BadgeIcon(
                    icon: Icons.shopping_cart,
                    count: cartItemCount,
                    isActive: true,
                    size: 23,
                  ),
                  label: 'Carrito',
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