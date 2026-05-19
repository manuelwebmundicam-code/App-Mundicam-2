import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  int _selectedIndex = 0;
  bool _loadBadges = false;

  final List<bool> _loadedTabs = [
    true, // Inicio
    false, // Productos
    false, // Pedidos
    false, // Presupuestos
    false, // Carrito
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

    // Carga diferida de badges para que Inicio aparezca antes.
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

  void _onItemTapped(int index) {
    if (_selectedIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }

    setState(() {
      _selectedIndex = index;
      _loadedTabs[index] = true;

      // Si el usuario entra en presupuestos o carrito, cargamos badges ya.
      if (index == 3 || index == 4) {
        _loadBadges = true;
      }
    });
  }

  Future<bool> _onWillPop() async {
    final currentNavigator = _navigatorKeys[_selectedIndex].currentState;

    if (currentNavigator != null && currentNavigator.canPop()) {
      currentNavigator.pop();
      return false;
    }

    if (_selectedIndex != 0) {
      _onItemTapped(0);
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

  @override
  Widget build(BuildContext context) {
    final int cartItemCount = _loadBadges ? ref.watch(cartBadgeProvider) : 0;

    final int quoteCount = _loadBadges ? ref.watch(quoteBadgeProvider) : 0;

    final bottomPadding = MediaQuery.of(context).padding.bottom;

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
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _loadedTabs[0]
                ? _buildNavigator(0, const HomePage())
                : const SizedBox.shrink(),

            _loadedTabs[1]
                ? _buildNavigator(1, const ProductosPage())
                : const SizedBox.shrink(),

            _loadedTabs[2]
                ? _buildNavigator(
                    2,
                    OrdersPage(onGoHome: () => _onItemTapped(0)),
                  )
                : const SizedBox.shrink(),

            _loadedTabs[3]
                ? _buildNavigator(
                    3,
                    QuotesPage(onGoHome: () => _onItemTapped(0)),
                  )
                : const SizedBox.shrink(),

            _loadedTabs[4]
                ? _buildNavigator(4, CartPage(onGoHome: () => _onItemTapped(0)))
                : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: Container(
          padding: EdgeInsets.only(bottom: bottomPadding),
          decoration: BoxDecoration(
            color:
                Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
                Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
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

  Widget _buildNavigator(int index, Widget initialRoute) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(
          builder: (context) => initialRoute,
          settings: routeSettings,
        );
      },
    );
  }
}
