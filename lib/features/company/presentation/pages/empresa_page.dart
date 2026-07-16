import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0xFFE5E7EB);
const Color _footerBg = Color(0xFFEAF0F6);
const Color _whatsappGreen = Color(0xFF25D366);

class EmpresaPage extends StatelessWidget {
  const EmpresaPage({super.key});

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'SOBRE MUNDICAM',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: EdgeInsets.zero,
        children: [
          const _CompanyHero(),

          const SizedBox(height: 22),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHeader(
              title: 'Quiénes somos',
              subtitle:
              'Distribución profesional de seguridad electrónica para instaladores, integradores, ingenierías y empresas de seguridad.',
            ),
          ),

          const SizedBox(height: 14),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _CompanyStoryCard(),
          ),

          const SizedBox(height: 22),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHeader(
              title: 'Valor para el profesional',
              subtitle:
              'Acompañamiento técnico-comercial, producto especializado y trabajo directo con fabricantes.',
            ),
          ),

          const SizedBox(height: 14),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _ValueBlock(),
          ),

          const SizedBox(height: 22),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SupportContactCard(
              onPhone: () => _launchUrl('tel:+34968629383'),
              onWhatsApp: () => _launchUrl(
                'https://wa.me/34619078632?text=Hola%20MundiCam,%20necesito%20asesoramiento%20técnico%20o%20comercial%20para%20un%20proyecto.',
              ),
              onEmail: () => _launchUrl(
                'mailto:pedidos@mundicam.com?subject=Consulta%20técnico-comercial%20desde%20la%20App%20MundiCam',
              ),
            ),
          ),

          const SizedBox(height: 22),

          _CompanyFooter(
            onOpenWeb: () => _launchUrl('https://www.mundicam.com'),
            onPhone: () => _launchUrl('tel:+34968629383'),
            onWhatsApp: () => _launchUrl(
              'https://wa.me/34619078632?text=Hola%20MundiCam,%20necesito%20información%20sobre%20vuestras%20soluciones%20profesionales.',
            ),
            onEmail: () => _launchUrl(
              'mailto:pedidos@mundicam.com?subject=Consulta%20desde%20App%20MundiCam',
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyHero extends StatelessWidget {
  const _CompanyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _pageBg,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        height: 245,
        clipBehavior: Clip.antiAlias,
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/banners/banner5.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: _dark),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _dark.withOpacity(0.64),
                    _dark.withOpacity(0.96),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.24),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.domain_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MundiCam Security Distribution',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Oswald',
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Distribución profesional de seguridad electrónica para el canal B2B.',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
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
}

class _CompanyStoryCard extends StatelessWidget {
  const _CompanyStoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 8.5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/banners/banner2.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.72),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Text(
                    'Seguridad electrónica profesional con enfoque técnico-comercial',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Oswald',
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MundiCam Security Distribution es una compañía especializada en la distribución de sistemas de seguridad electrónica profesional.',
                  style: TextStyle(
                    color: _dark,
                    fontSize: 13.4,
                    height: 1.48,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Formamos parte de VISIONA I GROUP, un grupo empresarial con experiencia en seguridad privada y seguridad electrónica profesional.',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 13,
                    height: 1.45,
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

class _ValueBlock extends StatelessWidget {
  const _ValueBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ValueCard(
          icon: Icons.support_agent_outlined,
          title: 'Asesoramiento especializado',
          text:
          'El equipo profesional de MundiCam ofrece apoyo en materia de seguridad electrónica y selección de soluciones.',
        ),
        SizedBox(height: 10),
        _ValueCard(
          icon: Icons.precision_manufacturing_outlined,
          title: 'I+D+i y fabricantes',
          text:
          'Trabajo directo con fabricantes para incorporar producto innovador dentro de la seguridad electrónica profesional.',
        ),
        SizedBox(height: 10),
        _ValueCard(
          icon: Icons.groups_outlined,
          title: 'Equipo MundiCam',
          text:
          'Un equipo orientado a soporte, atención al cliente, logística, postventa y acompañamiento al canal profesional.',
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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 23,
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
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12.5,
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

class _SupportContactCard extends StatelessWidget {
  const _SupportContactCard({
    required this.onPhone,
    required this.onWhatsApp,
    required this.onEmail,
  });

  final VoidCallback onPhone;
  final VoidCallback onWhatsApp;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.support_agent_rounded,
                color: AppColors.primary,
                size: 27,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Soporte técnico y comercial',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Oswald',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Contacta con nuestro equipo para resolver dudas, preparar proyectos o solicitar asesoramiento profesional.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.76),
              fontSize: 12.8,
              height: 1.42,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SupportButton(
                  label: 'Llamar',
                  icon: Icons.phone_outlined,
                  background: AppColors.primary,
                  foreground: Colors.white,
                  onTap: onPhone,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SupportButton(
                  label: 'WhatsApp',
                  icon: Icons.chat_outlined,
                  background: _whatsappGreen,
                  foreground: Colors.white,
                  onTap: onWhatsApp,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SupportOutlineButton(
            label: 'Enviar email',
            icon: Icons.email_outlined,
            onTap: onEmail,
          ),
        ],
      ),
    );
  }
}

class _SupportButton extends StatelessWidget {
  const _SupportButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Oswald',
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}

class _SupportOutlineButton extends StatelessWidget {
  const _SupportOutlineButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Oswald',
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(
            color: Colors.white.withOpacity(0.22),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}

class _CompanyFooter extends StatelessWidget {
  const _CompanyFooter({
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
            'Distribución profesional de seguridad electrónica para instaladores, integradores e ingenierías.',
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
            color: _dark,
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
        color: _whatsappGreen,
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