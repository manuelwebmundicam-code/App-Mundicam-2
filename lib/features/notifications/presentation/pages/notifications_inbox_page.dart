import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/notifications/notification_inbox_store.dart';
import 'package:mundicam/core/notifications/notification_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

Future<List<NotificationInboxEntry>> loadNotificationInboxEntries() async {
  final api = ApiService();
  final hasSession = await api.hasStoredAppSession();
  if (!hasSession) return const <NotificationInboxEntry>[];

  final wordpressId = await api.currentSessionWordPressId();
  final email = await api.currentSessionEmail();
  final scope = NotificationInboxStore.scopeForUser(
    wordpressId: wordpressId,
    email: email,
  );

  final localEntries = scope == null
      ? const <NotificationInboxEntry>[]
      : await NotificationInboxStore.instance.load(scope: scope);

  final remoteRaw = await api.getNotificationHistory(limit: 100);
  final remoteEntries = remoteRaw
      .map(_notificationInboxEntryFromRemote)
      .whereType<NotificationInboxEntry>()
      .where((entry) => !entry.isTestOrDiagnostic)
      .toList();

  final merged = <String, NotificationInboxEntry>{};

  for (final entry in remoteEntries) {
    merged[entry.id] = entry;
  }

  for (final entry in localEntries) {
    merged[entry.id] = entry;
  }

  final entries = merged.values.toList()
    ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  return entries;
}

class NotificationsInboxPage extends StatefulWidget {
  const NotificationsInboxPage({super.key});

  @override
  State<NotificationsInboxPage> createState() => _NotificationsInboxPageState();
}

class _NotificationsInboxPageState extends State<NotificationsInboxPage> {
  List<NotificationInboxEntry> _entries = const <NotificationInboxEntry>[];
  bool _loading = true;
  StreamSubscription<MundiCamOrderNotification>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _notificationSubscription = NotificationService().orderNotifications.listen(
      (_) => Future<void>.delayed(
        const Duration(milliseconds: 150),
        () => _loadEntries(showLoading: false),
      ),
    );
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadEntries({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }

    final entries = await loadNotificationInboxEntries();

    if (!mounted) return;

    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Notificaciones'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadEntries(showLoading: false),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_entries.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.mail_outline_rounded,
                        size: 64,
                        color: Color(0xFFB0B6BF),
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Aún no hay notificaciones guardadas',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF20242A),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Las notificaciones enviadas por MundiCam aparecerán aquí.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Color(0xFF6F7782),
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

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _NotificationCard(
          entry: entry,
          onTap: () => _showNotificationDetails(entry),
        );
      },
    );
  }

  Future<void> _showNotificationDetails(NotificationInboxEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          title: Text(
            entry.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((entry.imageUrl ?? '').isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      entry.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  entry.body,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Color(0xFF33373D),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _formatDate(entry.receivedAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF818893),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationInboxEntry entry;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = entry.imageUrl?.trim() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8EBEF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotificationLeading(imageUrl: imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF20242A),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF5F6670),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      _formatDate(entry.receivedAt),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF9096A0),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Color(0xFFB3B8C0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationLeading extends StatelessWidget {
  final String imageUrl;

  const _NotificationLeading({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          imageUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(),
        ),
      );
    }

    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Image.asset(
          'assets/images/icon_mail.png',
          width: 24,
          height: 24,
          fit: BoxFit.contain,
          color: AppColors.primary,
          colorBlendMode: BlendMode.srcIn,
        ),
      ),
    );
  }
}


NotificationInboxEntry? _notificationInboxEntryFromRemote(
  Map<String, dynamic> json,
) {
  final eventId = json['event_id']?.toString().trim() ?? '';
  final communicationId = json['communication_id']?.toString().trim() ??
      json['id']?.toString().trim() ??
      '';

  final id = eventId.isNotEmpty
      ? eventId
      : (communicationId.isNotEmpty ? 'communication:$communicationId' : '');

  if (id.isEmpty) return null;

  return NotificationInboxEntry.fromJson(<String, dynamic>{
    'id': id,
    'title': json['title'],
    'body': json['body'],
    'event': json['event'] ?? json['type'],
    'image_url': json['image_url'],
    'received_at': json['sent_at'] ?? json['published_at'],
    'opened_by_user': false,
  });
}

String _formatDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
