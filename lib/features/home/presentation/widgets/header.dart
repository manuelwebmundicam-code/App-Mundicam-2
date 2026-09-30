import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mundicam/core/notifications/notification_service.dart';
import 'package:mundicam/features/notifications/presentation/pages/notifications_inbox_page.dart';
import 'package:mundicam/features/profile/presentation/pages/profile_page.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class HomeHeader extends StatefulWidget {
  const HomeHeader({super.key});

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  int _notificationCount = 0;
  StreamSubscription<MundiCamOrderNotification>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _refreshNotificationCount();

    _notificationSubscription = NotificationService().orderNotifications.listen(
      (_) => Future<void>.delayed(
        const Duration(milliseconds: 200),
        _refreshNotificationCount,
      ),
    );
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshNotificationCount() async {
    try {
      final entries = await loadNotificationInboxEntries();
      if (!mounted) return;
      setState(() => _notificationCount = entries.length);
    } catch (_) {
      // El contador es visual y nunca debe afectar al funcionamiento del home.
    }
  }

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
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsInboxPage(),
                  ),
                );
                await _refreshNotificationCount();
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
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/images/icon_mail.png',
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                      color: AppColors.primary,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    if (_notificationCount > 0)
                      Positioned(
                        right: -6,
                        top: -7,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 17,
                            minHeight: 17,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white,
                              width: 1.2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _notificationCount > 99
                                ? '99+'
                                : '$_notificationCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
