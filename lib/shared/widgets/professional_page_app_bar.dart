import 'package:flutter/material.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class ProfessionalPageAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;
  final String backTooltip;
  final String refreshTooltip;

  const ProfessionalPageAppBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
    this.onRefresh,
    this.backTooltip = 'Volver',
    this.refreshTooltip = 'Actualizar',
  });

  @override
  Size get preferredSize => const Size.fromHeight(86);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(30),
            bottomRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 86,
            child: Row(
              children: [
                const SizedBox(width: 4),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: onBack,
                    tooltip: backTooltip,
                    splashRadius: 22,
                  ),
                ),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.05,
                      color: Colors.white,
                      fontFamily: 'Oswald',
                      height: 1.05,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: onRefresh != null
                      ? IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: onRefresh,
                    tooltip: refreshTooltip,
                    splashRadius: 22,
                  )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}