import 'package:flutter/material.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class ProfessionalPageAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;
  final String backTooltip;
  final String refreshTooltip;

  const ProfessionalPageAppBar({
    super.key,
    required this.title,
    this.subtitle = '',
    this.icon,
    required this.onBack,
    this.onRefresh,
    this.backTooltip = 'Volver',
    this.refreshTooltip = 'Actualizar',
  });

  @override
  Size get preferredSize => Size.fromHeight(
    subtitle.trim().isEmpty ? 92 : 112,
  );

  @override
  Widget build(BuildContext context) {
    final bool hasSubtitle = subtitle.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 4,
            right: 4,
            bottom: hasSubtitle ? 12 : 14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    _CircleButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onPressed: onBack,
                      tooltip: backTooltip,
                    ),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: 1.0,
                          color: Colors.white,
                          fontFamily: 'Oswald',
                          height: 1.15,
                        ),
                      ),
                    ),
                    _CircleButton(
                      icon: Icons.refresh_rounded,
                      onPressed: onRefresh,
                      tooltip: refreshTooltip,
                      visible: onRefresh != null,
                    ),
                  ],
                ),
              ),
              if (hasSubtitle) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            size: 11,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.8),
                            letterSpacing: 0.3,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool visible;

  const _CircleButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox(width: 52);
    }

    return SizedBox(
      width: 52,
      height: 48,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            splashColor: Colors.white.withOpacity(0.1),
            highlightColor: Colors.white.withOpacity(0.05),
            child: Icon(
              icon,
              size: 19,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
