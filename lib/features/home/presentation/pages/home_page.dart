import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/chatbox.dart';
import 'package:mundicam/features/home/presentation/widgets/header.dart';
import 'package:mundicam/features/home/presentation/widgets/search_bar.dart';
import 'package:mundicam/features/home/presentation/widgets/menu_bar.dart';
import 'package:mundicam/features/home/presentation/widgets/category_grid.dart';
import 'package:mundicam/features/home/presentation/widgets/brand_grid.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/home/presentation/widgets/news_section.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/features/home/presentation/providers/noticias_provider.dart';
import 'package:mundicam/features/home/presentation/providers/banner_mix_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const HomePage({
    super.key,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _showSecondaryContent = false;
  bool _showChatBox = false;
  bool _showBrands = false;

  final ApiService _apiService = ApiService();
  String _managerName = '';
  String _managerEmail = '';
  String _managerPhone = '';
  bool _didLogFirstBuild = false;

  static const Color _pageBg = Colors.white;
  static const Color _footerBg = Color(0xFFEAF0F6);
  static const Color _footerBlack = Color(0xFF111827);
  static const Color _footerMuted = Color(0xFF5F6B7A);

  @override
  void initState() {
    super.initState();
    debugPrint('🍎 HOMEPAGE_INIT');
    _loadManagerContact();

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _showSecondaryContent = true);
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => _showChatBox = true);
    });
  }

  Future<void> _refreshHome() async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(homeBrandsProvider);
    ref.invalidate(noticiasProvider);
    ref.invalidate(bannerMixProvider);
    await _loadManagerContact();
    await Future.delayed(const Duration(milliseconds: 350));
  }

  Future<void> _openFooterLink(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      debugPrint('No se pudo abrir: $uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_didLogFirstBuild) {
      _didLogFirstBuild = true;
      debugPrint('🍎 HOMEPAGE_BUILD');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('🍎 HOMEPAGE_FIRST_FRAME');
      });
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _refreshHome,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopPanel(),
                      const SizedBox(height: 22),
                      _buildCatalogSelector(),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _showBrands
                            ? BrandGrid(
                                key: const ValueKey('home-brands'),
                                onGoCart: widget.onGoCart,
                                onGoQuotes: widget.onGoQuotes,
                              )
                            : CategoryGrid(
                                key: const ValueKey('home-categories'),
                                onGoCart: widget.onGoCart,
                                onGoQuotes: widget.onGoQuotes,
                              ),
                      ),
                      if (_showSecondaryContent) ...[
                        const SizedBox(height: 22),
                        _buildNewsPanel(),
                        _buildMundicamFooter(),
                      ] else ...[
                        const SizedBox(height: 22),
                        _buildNewsSkeletonPanel(),
                        _buildSkeletonBlock(height: 150),
                      ],
                    ],
                  ),
                ),
              ),
              if (_showChatBox) const ChatBox(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadManagerContact() async {
    try {
      final user = await _apiService.currentSessionUser();
      if (!mounted || user.isEmpty) return;

      final managerRaw = user['manager'];
      final manager = managerRaw is Map
          ? Map<String, dynamic>.from(managerRaw)
          : const <String, dynamic>{};

      String firstValid(Iterable<dynamic> values, {bool email = false}) {
        for (final value in values) {
          final clean = value?.toString().trim() ?? '';
          if (clean.isEmpty || clean == '—' || clean.toLowerCase() == 'null') {
            continue;
          }
          if (email && !clean.contains('@')) continue;
          return clean;
        }
        return '';
      }

      final managerName = firstValid([
        manager['name'],
        user['manager_name'],
        user['assigned_manager'],
        user['gestor_asignado'],
        user['wpuef_cid_c30'],
      ]);

      var managerEmail = firstValid([
        manager['email'],
        user['manager_email'],
        user['assigned_manager_email'],
        user['gestor_email'],
      ], email: true);

      var managerPhone = firstValid([
        manager['phone'],
        user['manager_phone'],
        user['assigned_manager_phone'],
        user['gestor_phone'],
      ]);

      if ((managerEmail.isEmpty || managerPhone.isEmpty) && managerName.isNotEmpty) {
        final fallback = _localManagerContact(managerName);
        managerEmail = managerEmail.isNotEmpty
            ? managerEmail
            : (fallback?['email'] ?? '');
        managerPhone = managerPhone.isNotEmpty
            ? managerPhone
            : (fallback?['phone'] ?? '');
      }

      if (!mounted) return;
      setState(() {
        _managerName = managerName;
        _managerEmail = managerEmail;
        _managerPhone = managerPhone;
      });
    } catch (_) {
      // El contacto del gestor es informativo: un fallo puntual no bloquea Inicio.
    }
  }

  Map<String, String>? _localManagerContact(String managerName) {
    final key = managerName
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const contacts = <String, Map<String, String>>{
      'damian mateo': {
        'email': 'dmateo@mundicam.com',
        'phone': '633806898',
      },
      'juan garcia': {
        'email': 'jgarcia@mundicam.com',
        'phone': '622943654',
      },
      'manuel': {
        'email': 'mreynaldo@mundicam.com',
        'phone': '619078632',
      },
      'proshop murcia': {
        'email': 'proshop.murcia@mundicam.com',
        'phone': '616545669',
      },
      'ricardo': {
        'email': 'rcano@mundicam.com',
        'phone': '606111983',
      },
    };

    return contacts[key];
  }

  Widget _buildCatalogSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E8EE)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _catalogSelectorTab(
                label: 'CATEGORÍAS',
                selected: !_showBrands,
                onTap: () {
                  if (_showBrands) {
                    setState(() => _showBrands = false);
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _catalogSelectorTab(
                label: 'MARCAS',
                selected: _showBrands,
                onTap: () {
                  if (!_showBrands) {
                    setState(() => _showBrands = true);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogSelectorTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.055),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              color: selected ? Colors.white : Colors.black,
              fontSize: 14.5,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontFamily: 'Oswald',
              letterSpacing: 0.75,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Widget _buildTopPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const HomeHeader(),
          const SizedBox(height: 2),
          SearchBarWidget(
            onGoCart: widget.onGoCart,
            onGoQuotes: widget.onGoQuotes,
          ),
          const MenuBarWidget(),
        ],
      ),
    );
  }

  Widget _buildNewsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('NOVEDADES'),
          const SizedBox(height: 12),
          const NewsBanner(),
        ],
      ),
    );
  }

  Widget _buildNewsSkeletonPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSectionTitle('NOVEDADES'),
          const SizedBox(height: 12),
          _buildSkeletonBlock(height: 205),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: 1.1,
                fontFamily: 'Oswald',
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonBlock({required double height}) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
    );
  }

  Widget _buildMundicamFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: const BoxDecoration(
        color: _footerBg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/logo.png',
            height: 21,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 10),
          const Text(
            'MundiCam Security Distribution',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Distribución profesional de seguridad electrónica para instaladores, integradores e ingenierías.',
            style: TextStyle(
              fontSize: 12.2,
              height: 1.32,
              color: _footerMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          _footerWebButton(
            onTap: () => _openFooterLink(
              Uri.parse('https://www.mundicam.com'),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '© MUNDICAM 2025-2026 · Todos los derechos reservados',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF7A8594),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerContactRow({
    IconData? icon,
    Widget? customIcon,
    required String text,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              customIcon ?? Icon(icon, size: 15, color: color),
              const SizedBox(width: 9),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.7,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerWebButton({required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.language_outlined,
                size: 14,
                color: Colors.white,
              ),
              SizedBox(width: 7),
              Text(
                'Ir a web oficial',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Oswald',
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.open_in_new_rounded,
                size: 13,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }


}