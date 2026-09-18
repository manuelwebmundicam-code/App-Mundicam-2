import 'package:flutter/material.dart';
import 'package:mundicam/features/profile/presentation/pages/profile_page.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoHeight = (screenWidth * 0.108).clamp(42.0, 58.0).toDouble();
    final logoMaxWidth = (screenWidth * 0.52).clamp(160.0, 260.0).toDouble();
    final headerHeight = (logoHeight + 28).clamp(78.0, 94.0).toDouble();

    return Container(
      height: headerHeight,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Row(
        children: [
          Flexible(
            child: GestureDetector(
              onTap: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: logoMaxWidth),
                child: Image.asset(
                  'assets/logo.png',
                  height: logoHeight,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.security_rounded,
                    size: 30,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE6EAF0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppColors.primary,
                  size: 21,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
