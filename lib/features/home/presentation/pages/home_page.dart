import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/chatbox.dart';
import 'package:mundicam/features/home/presentation/widgets/brands_banner.dart';
import 'package:mundicam/features/home/presentation/widgets/header.dart';
import 'package:mundicam/features/home/presentation/widgets/search_bar.dart';
import 'package:mundicam/features/home/presentation/widgets/menu_bar.dart';
import 'package:mundicam/features/home/presentation/widgets/category_grid.dart';
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

  static const Color _pageBg = Colors.white;
  static const Color _footerBg = Color(0xFFEAF0F6);
  static const Color _footerBlack = Color(0xFF111827);
  static const Color _footerMuted = Color(0xFF5F6B7A);
  static const Color _whatsappGreen = Color(0xFF128C4A);

  @override
  void initState() {
    super.initState();

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
    ref.invalidate(noticiasProvider);
    ref.invalidate(bannerMixProvider);
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
                      _buildSectionTitle('CATEGORÍAS'),
                      const SizedBox(height: 12),
                      const CategoryGrid(),
                      if (_showSecondaryContent) ...[
                        const SizedBox(height: 14),
                        const BrandsBanner(),
                        const SizedBox(height: 22),
                        _buildNewsPanel(),
                        _buildMundicamFooter(),
                      ] else ...[
                        const SizedBox(height: 18),
                        _buildSkeletonBlock(height: 66),
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
            color: Colors.black.withValues(alpha: 0.04),
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
            color: Colors.black.withValues(alpha: 0.035),
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
            color: Colors.black.withValues(alpha: 0.035),
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
          const SizedBox(height: 11),
          _footerContactRow(
            icon: Icons.phone_outlined,
            text: '+34 968 629 383',
            color: _footerBlack,
            onTap: () => _openFooterLink(Uri.parse('tel:968629383')),
          ),
          _footerContactRow(
            customIcon: _whatsAppIcon(),
            text: '+34 619 078 632',
            color: _whatsappGreen,
            onTap: () => _openFooterLink(
              Uri.parse('https://wa.me/34619078632'),
            ),
          ),
          _footerContactRow(
            icon: Icons.email_outlined,
            text: 'pedidos@mundicam.com',
            color: _footerBlack,
            onTap: () => _openFooterLink(
              Uri(
                scheme: 'mailto',
                path: 'pedidos@mundicam.com',
                query: 'subject=Consulta desde App MundiCam',
              ),
            ),
          ),
          const SizedBox(height: 9),
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
    required VoidCallback onTap,
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
                color: AppColors.primary.withValues(alpha: 0.18),
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

  Widget _whatsAppIcon() {
    return Container(
      width: 15,
      height: 15,
      decoration: const BoxDecoration(
        color: Color(0xFF25D366),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(
          Icons.phone_rounded,
          color: Colors.white,
          size: 9.5,
        ),
      ),
    );
  }
}