import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mundicam/core/config/update_announcement_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

/// Muestra el aviso opcional una sola vez por versión objetivo durante
/// la sesión actual. Si el usuario pulsa "Más tarde", podrá seguir usando
/// la app y volverá a verlo en un próximo arranque si sigue desactualizado.
class UpdateAnnouncementGate extends StatefulWidget {
  final Widget child;

  const UpdateAnnouncementGate({
    super.key,
    required this.child,
  });

  @override
  State<UpdateAnnouncementGate> createState() =>
      _UpdateAnnouncementGateState();
}

class _UpdateAnnouncementGateState extends State<UpdateAnnouncementGate> {
  bool _dialogOpen = false;
  String _dismissedLatestVersion = '';

  @override
  void initState() {
    super.initState();
    UpdateAnnouncementService.instance.state.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  @override
  void dispose() {
    UpdateAnnouncementService.instance.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    _maybeShow();
  }

  void _maybeShow() {
    if (!mounted || _dialogOpen) return;

    final state = UpdateAnnouncementService.instance.state.value;
    if (!state.available) return;
    if (state.latestVersion == _dismissedLatestVersion) return;

    _dialogOpen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _dialogOpen = false;
        return;
      }

      final currentState = UpdateAnnouncementService.instance.state.value;
      if (!currentState.available ||
          currentState.latestVersion == _dismissedLatestVersion) {
        _dialogOpen = false;
        return;
      }

      await _showAnnouncement(currentState);

      if (mounted) {
        _dialogOpen = false;
      }
    });
  }

  Future<void> _showAnnouncement(UpdateAnnouncementState state) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: AppColors.primary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      state.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (state.points.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      ...state.points.map(
                        (point) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  point,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (state.moreText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        state.moreText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.tryParse(state.storeUrl);
                          if (uri == null) return;

                          final opened = await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );

                          if (!opened && dialogContext.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No se pudo abrir la tienda de aplicaciones.',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(
                          state.updateButtonLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () {
                        _dismissedLatestVersion = state.latestVersion;
                        Navigator.of(dialogContext).pop();
                      },
                      child: Text(
                        state.laterButtonLabel,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
