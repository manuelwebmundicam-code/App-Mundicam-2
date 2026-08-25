import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF667085);
const Color _border = Color(0xFFE3E8EF);
const Color _softBg = Color(0xFFF8FAFC);
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
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _SimpleCompanyCard(),
          ),
          const SizedBox(height: 26),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHeader(
              eyebrow: 'ENFOQUE PROFESIONAL',
              title: 'Valor para el profesional',
              subtitle:
                  'Producto especializado, acompañamiento técnico-comercial y una relación directa con el canal profesional.',
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _ProfessionalValueGrid(),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _ProfessionalCommitmentCard(),
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
          const SizedBox(height: 26),
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


class _SimpleCompanyCard extends StatelessWidget {
  const _SimpleCompanyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MUNDICAM',
            style: TextStyle(
              color: AppColors.primary,
              fontFamily: 'Oswald',
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'QUIÉNES SOMOS',
            style: TextStyle(
              color: _dark,
              fontFamily: 'Oswald',
              fontSize: 24,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'MundiCam Security Distribution está especializada en la distribución de sistemas de seguridad electrónica profesional.',
            style: TextStyle(
              color: _dark,
              fontSize: 13.4,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Formamos parte de VISIONA I GROUP, un grupo empresarial con experiencia en seguridad privada y seguridad electrónica profesional.',
            style: TextStyle(
              color: _muted,
              fontSize: 12.8,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 16),
          Divider(
            height: 1,
            thickness: 1,
            color: _border,
          ),
          SizedBox(height: 16),
          _SimpleInfoRow(
            icon: Icons.business_center_outlined,
            text: 'Distribución especializada para el canal profesional B2B.',
          ),
          SizedBox(height: 11),
          _SimpleInfoRow(
            icon: Icons.support_agent_outlined,
            text: 'Asesoramiento técnico y comercial para cada proyecto.',
          ),
          SizedBox(height: 11),
          _SimpleInfoRow(
            icon: Icons.inventory_2_outlined,
            text: 'Atención, logística y postventa orientadas al profesional.',
          ),
        ],
      ),
    );
  }
}

class _SimpleInfoRow extends StatelessWidget {
  const _SimpleInfoRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 17,
            color: AppColors.primary,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              text,
              style: TextStyle(
                color: _dark,
                fontSize: 12.4,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompanyHero extends StatelessWidget {
  const _CompanyHero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        height: 292,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _dark,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/banners/banner5.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: _dark),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _dark.withOpacity(0.40),
                    _dark.withOpacity(0.82),
                    _dark.withOpacity(0.98),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 20,
              top: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/logo.png',
                  height: 27,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) => const Text(
                    'MUNDICAM',
                    style: TextStyle(
                      color: _dark,
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'DISTRIBUCIÓN PROFESIONAL B2B',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Oswald',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 11),
                  const Text(
                    'Seguridad electrónica\npara el canal profesional',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Oswald',
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.02,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'MundiCam Security Distribution · Especialización, soporte y soluciones para profesionales.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 12.5,
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
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              eyebrow,
              style: const TextStyle(
                color: AppColors.primary,
                fontFamily: 'Oswald',
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: _dark,
            fontFamily: 'Oswald',
            fontSize: 23,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: const TextStyle(
            color: _muted,
            fontSize: 12.7,
            height: 1.42,
            fontWeight: FontWeight.w500,
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
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 7.8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/banners/banner2.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFFE9EDF2),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.76),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Text(
                    'Especialización técnica con visión comercial',
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
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MundiCam Security Distribution está especializada en la distribución de sistemas de seguridad electrónica profesional.',
                  style: TextStyle(
                    color: _dark,
                    fontSize: 13.5,
                    height: 1.48,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Formamos parte de VISIONA I GROUP, un grupo empresarial con experiencia en seguridad privada y seguridad electrónica profesional.',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12.8,
                    height: 1.46,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 16),
                _AudienceChips(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AudienceChips extends StatelessWidget {
  const _AudienceChips();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: const [
        _AudienceChip(
          icon: Icons.handyman_outlined,
          label: 'Instaladores',
        ),
        _AudienceChip(
          icon: Icons.hub_outlined,
          label: 'Integradores',
        ),
        _AudienceChip(
          icon: Icons.architecture_outlined,
          label: 'Ingenierías',
        ),
        _AudienceChip(
          icon: Icons.shield_outlined,
          label: 'Seguridad',
        ),
      ],
    );
  }
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: AppColors.primary,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _dark,
              fontSize: 11.4,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfessionalValueGrid extends StatelessWidget {
  const _ProfessionalValueGrid();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ProfessionalValueCard(
          number: '01',
          icon: Icons.support_agent_outlined,
          title: 'Asesoramiento especializado',
          text:
              'Apoyo técnico-comercial para seleccionar soluciones de seguridad electrónica adaptadas a cada proyecto.',
        ),
        SizedBox(height: 10),
        _ProfessionalValueCard(
          number: '02',
          icon: Icons.precision_manufacturing_outlined,
          title: 'Producto y fabricantes',
          text:
              'Trabajo directo con fabricantes para incorporar soluciones especializadas e innovación al canal profesional.',
        ),
        SizedBox(height: 10),
        _ProfessionalValueCard(
          number: '03',
          icon: Icons.groups_outlined,
          title: 'Equipo MundiCam',
          text:
              'Atención al cliente, soporte, logística y postventa orientados a acompañar al profesional antes y después de la compra.',
        ),
      ],
    );
  }
}

class _ProfessionalValueCard extends StatelessWidget {
  const _ProfessionalValueCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
  });

  final String number;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: _dark,
                          fontFamily: 'Oswald',
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                    ),
                    Text(
                      number,
                      style: TextStyle(
                        color: AppColors.primary.withOpacity(0.40),
                        fontFamily: 'Oswald',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12.4,
                    height: 1.42,
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

class _ProfessionalCommitmentCard extends StatelessWidget {
  const _ProfessionalCommitmentCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UN PARTNER PARA EL PROFESIONAL',
                      style: TextStyle(
                        color: _dark,
                        fontFamily: 'Oswald',
                        fontSize: 17.5,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Acompañamiento orientado a proyectos de seguridad electrónica.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11.8,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _CommitmentRow(
            icon: Icons.fact_check_outlined,
            text: 'Selección de soluciones y producto especializado',
          ),
          const SizedBox(height: 10),
          const _CommitmentRow(
            icon: Icons.forum_outlined,
            text: 'Soporte técnico-comercial para el canal profesional',
          ),
          const SizedBox(height: 10),
          const _CommitmentRow(
            icon: Icons.inventory_2_outlined,
            text: 'Atención, logística y postventa dentro del equipo MundiCam',
          ),
        ],
      ),
    );
  }
}

class _CommitmentRow extends StatelessWidget {
  const _CommitmentRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _softBg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 15,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              text,
              style: const TextStyle(
                color: _dark,
                fontSize: 12.3,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
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
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 19),
      decoration: const BoxDecoration(
        color: _footerBg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/logo.png',
            height: 23,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
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
          const SizedBox(height: 13),
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
          const SizedBox(height: 11),
          _FooterButton(
            label: 'Ir a web oficial',
            icon: Icons.language_outlined,
            onTap: onOpenWeb,
          ),
          const SizedBox(height: 13),
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
