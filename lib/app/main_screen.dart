// main_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/providers/badge_provider.dart';
import 'package:mundicam/shared/widgets/badge_icon.dart';
import 'package:mundicam/features/home/presentation/pages/home_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_page.dart';
import 'package:mundicam/features/orders/presentation/pages/orders_page.dart';
import 'package:mundicam/features/quotes/presentation/pages/quotes_page.dart';
import 'package:mundicam/features/cart/presentation/pages/cart_page.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  static const String _confirmedQuoteIdsKey = 'mundicam_confirmed_quote_ids';

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
  List.generate(5, (_) => GlobalKey<NavigatorState>());

  int _selectedIndex = 0;
  bool _loadBadges = false;
  Set<String> _confirmedQuoteIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadConfirmedQuoteIds();

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _loadBadges = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadConfirmedQuoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList(_confirmedQuoteIdsKey) ?? <String>[];

    if (!mounted) return;

    setState(() {
      _confirmedQuoteIds = savedIds.toSet();
    });
  }

  Future<void> _registerConfirmedQuotes(Set<String> quoteIds) async {
    if (quoteIds.isEmpty) return;

    final updatedIds = <String>{
      ..._confirmedQuoteIds,
      ...quoteIds,
    };

    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      _confirmedQuoteIdsKey,
      updatedIds.toList(),
    );

    if (!mounted) return;

    setState(() {
      _confirmedQuoteIds = updatedIds;
      _loadBadges = true;
    });

    ref.invalidate(quoteBadgeProvider);
    ref.invalidate(cartBadgeProvider);
  }

  void _switchToTab(
      int index, {
        bool popToRoot = false,
      }) {
    if (index < 0 || index >= _navigatorKeys.length) return;

    setState(() {
      _selectedIndex = index;

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
      builder: (context) => AlertDialog(
        title: const Text('Salir'),
        content: const Text('¿Deseas salir de la aplicación?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  int _visibleQuoteBadgeCount(int rawQuoteCount) {
    if (rawQuoteCount <= 0) return 0;

    final visibleCount = rawQuoteCount - _confirmedQuoteIds.length;

    return visibleCount > 0 ? visibleCount : 0;
  }

  Widget _buildTabNavigator({
    required int index,
    required Widget child,
  }) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int cartItemCount = _loadBadges ? ref.watch(cartBadgeProvider) : 0;
    final int rawQuoteCount = _loadBadges ? ref.watch(quoteBadgeProvider) : 0;
    final int quoteCount = _visibleQuoteBadgeCount(rawQuoteCount);

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldExit = await _onWillPop();

        if (shouldExit && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
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
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: EdgeInsets.only(bottom: bottomPadding),
          decoration: BoxDecoration(
            color: Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
                Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: Colors.grey,
            selectedLabelStyle: const TextStyle(
              fontFamily: 'Oswald',
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            selectedFontSize: 12,
            unselectedFontSize: 11,
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
                ),
                activeIcon: BadgeIcon(
                  icon: Icons.description,
                  count: quoteCount,
                  isActive: true,
                ),
                label: 'Presupuestos',
              ),
              BottomNavigationBarItem(
                icon: BadgeIcon(
                  icon: Icons.shopping_cart_outlined,
                  count: cartItemCount,
                  isActive: _selectedIndex == 4,
                ),
                activeIcon: BadgeIcon(
                  icon: Icons.shopping_cart,
                  count: cartItemCount,
                  isActive: true,
                ),
                label: 'Carrito',
              ),
            ],
          ),
        ),
      ),
    );
  }
}