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

class _HomeHeaderState extends State<HomeHeader>
    with WidgetsBindingObserver {
  int _unreadNotifications = 0;
  StreamSubscription<MundiCamOrderNotification>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUnreadCount();

    _notificationSubscription =
        NotificationService().orderNotifications.listen((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _loadUnreadCount();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUnreadCount();
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final entries = await loadNotificationInboxEntries();
      final unread = entries.where((entry) => !entry.openedByUser).length;

      if (!mounted || unread == _unreadNotifications) return;

      setState(() {
        _unreadNotifications = unread;
      });
    } catch (_) {
      // El contador es informativo y nunca debe bloquear el Home.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const NotificationsInboxPage(),
      ),
    );

    if (!mounted) return;
    await _loadUnreadCount();
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
          _HeaderActionButton(
            onTap: _openNotifications,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(
                  child: Icon(
                    Icons.mail_outline_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                if (_unreadNotifications > 0)
                  Positioned(
                    top: -7,
                    right: -7,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 19,
                        minHeight: 19,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _unreadNotifications > 99
                            ? '99+'
                            : _unreadNotifications.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HeaderActionButton(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.primary,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _HeaderActionButton({
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
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
          child: child,
        ),
      ),
    );
  }
}
