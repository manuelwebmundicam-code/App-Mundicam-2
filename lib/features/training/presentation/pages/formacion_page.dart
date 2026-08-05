import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mundicam/features/training/data/models/cursos_model.dart';
import 'package:mundicam/features/training/presentation/providers/academy_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _footerBg = Color(0xFFEAF0F6);
const Color _whatsappGreen = Color(0xFF128C4A);

class FormacionPage extends ConsumerWidget {
  const FormacionPage({super.key});

  static const String _academyUrl = 'https://www.mundicam.com/academy/';

  Future<void> _launchUrl(String urlString) async {
    if (urlString.trim().isEmpty) return;
    try {
      await launchUrl(
        Uri.parse(urlString),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      debugPrint('No se pudo abrir $urlString');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    MundicamAnalyticsService.instance
        .trackScreenViewForRoute(context, 'academy');
    final academyAsync = ref.watch(academyProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'MUNDICAM ACADEMY',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: academyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, stack) => _buildErrorState(ref),
        data: (courses) {
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(academyProvider);
              await Future.delayed(const Duration(milliseconds: 350));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.zero,
              children: [
                _buildHeader(),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildSectionHeader(
                    title: 'Últimas formaciones',
                    subtitle: 'Contenido técnico publicado desde MundiCam Academy para instaladores, integradores y empresas de seguridad.',
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: courses.isEmpty
                      ? const _EmptyCoursesCard()
                      : Column(
                    children: courses.take(8).map((course) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _CourseCard(
                          course: course,
                          onTap: () => _launchUrl(course.url),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildSectionHeader(
                    title: 'Academy para profesionales',
                    subtitle: 'Formación práctica, producto real y enfoque técnico-comercial para el canal B2B.',
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: _ValueCards(),
                ),
                const SizedBox(height: 22),
                _AcademyFooter(
                  onOpenWeb: () => _launchUrl('https://www.mundicam.com'),
                  onPhone: () => _launchUrl('tel:968629383'),
                  onWhatsApp: () => _launchUrl(
                    'https://wa.me/34619078632?text=Hola%20MundiCam,%20necesito%20información%20sobre%20MundiCam%20Academy.',
                  ),
                  onEmail: () => _launchUrl(
                    'mailto:pedidos@mundicam.com?subject=Consulta%20desde%20App%20MundiCam',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: _pageBg,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
          color: _dark,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Text(
                    'Formación profesional para seguridad electrónica',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Oswald',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Webinars, jornadas presenciales y sesiones técnicas para instaladores, integradores, ingenierías y empresas de seguridad.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontSize: 13.2,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => _launchUrl(_academyUrl),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text(
                  'VER CALENDARIO ACADEMY',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 28,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: _dark,
                  fontFamily: 'Oswald',
                  fontSize: 21,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school_outlined,
                color: AppColors.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No se pudo cargar MundiCam Academy',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Oswald',
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: _dark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comprueba la conexión y vuelve a intentarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(academyProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REINTENTAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.onTap,
  });

  final CourseModel course;
  final VoidCallback onTap;

  String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#8211;', '–')
        .replaceAll('&#8217;', '’')
        .replaceAll('&#8220;', '“')
        .replaceAll('&#8221;', '”')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _description() {
    final title = _cleanText(course.title);
    final excerpt = _cleanText(course.excerpt);
    if (excerpt.isEmpty || excerpt == title) {
      return 'Accede a la publicación completa de MundiCam Academy.';
    }
    return excerpt;
  }

  @override
  Widget build(BuildContext context) {
    final title = _cleanText(course.title);
    final excerpt = _description();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: course.imageUrl.trim().isEmpty
                    ? const _ImageFallback()
                    : Image.network(
                  course.imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const _ImageFallback(loading: true);
                  },
                  errorBuilder: (context, error, stackTrace) => const _ImageFallback(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _dark,
                        fontFamily: 'Oswald',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12.5,
                        height: 1.38,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Ver formación',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontFamily: 'Oswald',
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF9CA3AF),
                          size: 25,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F4F6),
      child: Center(
        child: loading
            ? const CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        )
            : const Icon(
          Icons.image_not_supported_outlined,
          color: Color(0xFF9CA3AF),
          size: 34,
        ),
      ),
    );
  }
}

class _ValueCards extends StatelessWidget {
  const _ValueCards();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ValueCard(
          icon: Icons.settings_suggest_outlined,
          title: 'Configuración real',
          text: 'Sesiones orientadas a producto, instalación, puesta en marcha e integración.',
        ),
        SizedBox(height: 10),
        _ValueCard(
          icon: Icons.handshake_outlined,
          title: 'Enfoque profesional',
          text: 'Contenido pensado para instaladores, integradores, ingenierías y empresas de seguridad.',
        ),
        SizedBox(height: 10),
        _ValueCard(
          icon: Icons.trending_up_rounded,
          title: 'Nuevas oportunidades',
          text: 'Formación para detectar soluciones de valor y presentar mejores proyectos a clientes.',
        ),
      ],
    );
  }
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _dark,
                    fontFamily: 'Oswald',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12.4,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCoursesCard extends StatelessWidget {
  const _EmptyCoursesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.school_outlined,
            color: AppColors.primary,
            size: 38,
          ),
          SizedBox(height: 12),
          Text(
            'No hay formaciones disponibles',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _dark,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Cuando haya nuevas publicaciones en MundiCam Academy aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcademyFooter extends StatelessWidget {
  const _AcademyFooter({
    required this.onOpenWeb,
    required this.onEmail,
    required this.onPhone,
    required this.onWhatsApp,
  });

  final VoidCallback onOpenWeb;
  final VoidCallback onEmail;
  final VoidCallback onPhone;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
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
          const SizedBox(height: 11),
          const Text(
            'MundiCam Security Distribution',
            style: TextStyle(
              fontFamily: 'Oswald',
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: _dark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Formación técnica y distribución profesional de seguridad electrónica para el canal B2B.',
            style: TextStyle(
              fontSize: 12.2,
              height: 1.32,
              color: Color(0xFF5F6B7A),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _FooterLink(
            icon: Icons.phone_outlined,
            text: '+34 968 629 383',
            color: _dark,
            onTap: onPhone,
          ),
          _FooterLink(
            customIcon: const _WhatsAppDot(),
            text: '+34 619 078 632',
            color: _whatsappGreen,
            onTap: onWhatsApp,
          ),
          _FooterLink(
            icon: Icons.email_outlined,
            text: 'pedidos@mundicam.com',
            color: _dark,
            onTap: onEmail,
          ),
          const SizedBox(height: 10),
          _FooterButton(
            label: 'Ir a web oficial',
            icon: Icons.language_outlined,
            onTap: onOpenWeb,
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
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    this.icon,
    this.customIcon,
    required this.text,
    required this.color,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? customIcon;
  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                color: AppColors.primary.withOpacity(0.17),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Oswald',
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
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

class _WhatsAppDot extends StatelessWidget {
  const _WhatsAppDot();

  @override
  Widget build(BuildContext context) {
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