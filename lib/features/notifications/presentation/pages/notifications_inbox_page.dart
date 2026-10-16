import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/notifications/notification_inbox_store.dart';
import 'package:mundicam/core/notifications/notification_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/mundicam_webview_page.dart';

List<Map<String, dynamic>>? _remoteHistoryCache;
String? _remoteHistoryScope;
DateTime? _remoteHistoryCachedAt;
const Duration _remoteHistoryCacheTtl = Duration(minutes: 1);

Future<List<NotificationInboxEntry>> loadNotificationInboxEntries({
  bool forceRemoteRefresh = false,
}) async {
  final api = ApiService();
  final hasSession = await api.hasStoredAppSession();
  if (!hasSession) return const <NotificationInboxEntry>[];

  final wordpressId = await api.currentSessionWordPressId();
  final email = await api.currentSessionEmail();
  final scope = NotificationInboxStore.scopeForUser(
    wordpressId: wordpressId,
    email: email,
  );
  if (scope == null) return const <NotificationInboxEntry>[];

  final store = NotificationInboxStore.instance;

  final localEntriesFuture = store.load(scope: scope);
  final deletedIdsFuture = store.loadDeletedIds(scope: scope);
  final remoteHistoryFuture = _loadRemoteNotificationHistory(
    api: api,
    scope: scope,
    forceRefresh: forceRemoteRefresh,
  );

  final results = await Future.wait<dynamic>([
    localEntriesFuture,
    deletedIdsFuture,
    remoteHistoryFuture,
  ]);

  final localEntries =
      (results[0] as List<NotificationInboxEntry>)
          .where((entry) => !entry.isTestOrDiagnostic)
          .toList(growable: false);
  final deletedIds = results[1] as Set<String>;
  final remoteHistory = results[2] as List<Map<String, dynamic>>;

  final byId = <String, NotificationInboxEntry>{};

  for (final entry in localEntries) {
    if (!deletedIds.contains(entry.id)) {
      byId[entry.id] = entry;
    }
  }

  for (final raw in remoteHistory) {
    final remoteEntry = _historyEntryFromJson(raw);
    if (remoteEntry == null ||
        remoteEntry.isTestOrDiagnostic ||
        deletedIds.contains(remoteEntry.id)) {
      continue;
    }

    final local = byId[remoteEntry.id];
    if (local == null) {
      byId[remoteEntry.id] = remoteEntry;
      continue;
    }

    byId[remoteEntry.id] = NotificationInboxEntry(
      id: remoteEntry.id,
      title: remoteEntry.title,
      body: remoteEntry.body,
      event: remoteEntry.event,
      imageUrl: remoteEntry.imageUrl ?? local.imageUrl,
      targetUrl: remoteEntry.targetUrl ?? local.targetUrl,
      orderId: remoteEntry.orderId ?? local.orderId,
      orderNumber: remoteEntry.orderNumber ?? local.orderNumber,
      status: remoteEntry.status ?? local.status,
      receivedAt: remoteEntry.receivedAt,
      openedByUser: local.openedByUser,
    );
  }

  final entries = byId.values.toList(growable: false)
    ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  return entries;
}

Future<List<Map<String, dynamic>>> _loadRemoteNotificationHistory({
  required ApiService api,
  required String scope,
  required bool forceRefresh,
}) async {
  final now = DateTime.now();
  final cacheIsValid = !forceRefresh &&
      _remoteHistoryScope == scope &&
      _remoteHistoryCache != null &&
      _remoteHistoryCachedAt != null &&
      now.difference(_remoteHistoryCachedAt!) < _remoteHistoryCacheTtl;

  if (cacheIsValid) {
    return _remoteHistoryCache!;
  }

  final history = await api.getNotificationHistory(limit: 100);
  _remoteHistoryScope = scope;
  _remoteHistoryCache = history;
  _remoteHistoryCachedAt = now;
  return history;
}

NotificationInboxEntry? _historyEntryFromJson(Map<String, dynamic> json) {
  final event = _firstCleanString([
        json['event'],
        json['type'],
        'general',
      ]) ??
      'general';

  final id = _firstCleanString([
    json['event_id'],
    json['eventId'],
    json['notification_id'],
    json['communication_id'] == null
        ? null
        : "$event:${json['communication_id']}",
    json['id'] == null ? null : "$event:${json['id']}",
  ]);

  if (id == null) return null;

  final sentAt = _parseNotificationDate(
    json['sent_at'] ?? json['created_at'] ?? json['date'],
  );

  return NotificationInboxEntry(
    id: id,
    title: _firstCleanString([
          json['title'],
          json['titulo'],
        ]) ??
        'Aviso MundiCam',
    body: _firstCleanString([
          json['body'],
          json['message'],
          json['notification_body'],
          json['descripcion'],
        ]) ??
        'Tienes una nueva notificación.',
    event: event,
    imageUrl: _nullableCleanString(
      json['image_url'] ??
          json['notification_image_url'] ??
          json['image'] ??
          json['imagen_url'],
    ),
    targetUrl: _nullableCleanString(
      json['target_url'] ??
          json['url'] ??
          json['web_url'] ??
          json['link'],
    ),
    orderId: _parseNullableInt(json['order_id']),
    orderNumber: _nullableCleanString(json['order_number']),
    status: _nullableCleanString(json['status']),
    receivedAt: sentAt,
    // El historial remoto es archivo: no debe convertir de golpe todas las
    // comunicaciones antiguas en "no leídas". Si esta comunicación también
    // llegó por FCM a este dispositivo, el estado local prevalece en el merge.
    openedByUser: true,
  );
}

DateTime _parseNotificationDate(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return DateTime.now();

  return DateTime.tryParse(raw) ??
      DateTime.tryParse(raw.replaceFirst(' ', 'T')) ??
      DateTime.now();
}

String? _firstCleanString(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return null;
}

String? _nullableCleanString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
}

int? _parseNullableInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
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

  Future<void> _loadEntries({
    bool showLoading = true,
    bool forceRemoteRefresh = false,
  }) async {
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }

    final entries = await loadNotificationInboxEntries(
      forceRemoteRefresh: forceRemoteRefresh,
    );

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
        onRefresh: () => _loadEntries(
          showLoading: false,
          forceRemoteRefresh: true,
        ),
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
                        'Los avisos de MundiCam y las actualizaciones de tus pedidos aparecerán aquí.',
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
          onTap: () => _openNotification(entry),
          onDelete: () => _confirmDelete(entry),
        );
      },
    );
  }

  Future<void> _openNotification(NotificationInboxEntry entry) async {
    final openedEntry = entry.openedByUser
        ? entry
        : entry.copyWith(openedByUser: true);

    if (!entry.openedByUser) {
      setState(() {
        _entries = _entries
            .map((item) => item.id == entry.id ? openedEntry : item)
            .toList(growable: false);
      });

      await _persistOpenedState(entry);
    }

    if (!mounted) return;

    final target = openedEntry.targetUrl?.trim() ?? '';
    final uri = Uri.tryParse(target);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MundiCamWebViewPage(
            title: 'NOTIFICACIÓN',
            initialUri: uri,
            closeOnBack: true,
          ),
        ),
      );
      return;
    }

    await _showNotificationDetails(openedEntry);
  }

  Future<void> _showNotificationDetails(NotificationInboxEntry entry) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final dialogWidth =
            (screen.width - 32).clamp(280.0, 480.0).toDouble();
        final maxDialogHeight = screen.height * 0.82;
        final imageWidth = (dialogWidth - 44).clamp(120.0, 436.0).toDouble();

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: maxDialogHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF20242A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((entry.imageUrl ?? '').isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: imageWidth,
                                child: Image.network(
                                  entry.imageUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
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
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(NotificationInboxEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar notificación'),
          content: const Text(
            'Esta notificación dejará de aparecer en tu buzón de esta app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Eliminar',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      final api = ApiService();
      final wordpressId = await api.currentSessionWordPressId();
      final email = await api.currentSessionEmail();
      final scope = NotificationInboxStore.scopeForUser(
        wordpressId: wordpressId,
        email: email,
      );
      if (scope == null) return;

      await NotificationInboxStore.instance.deleteEntry(
        scope: scope,
        id: entry.id,
      );

      if (!mounted) return;
      setState(() {
        _entries = _entries
            .where((item) => item.id != entry.id)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo eliminar la notificación.'),
        ),
      );
    }
  }

  Future<void> _persistOpenedState(NotificationInboxEntry entry) async {
    try {
      final api = ApiService();
      final wordpressId = await api.currentSessionWordPressId();
      final email = await api.currentSessionEmail();
      final scope = NotificationInboxStore.scopeForUser(
        wordpressId: wordpressId,
        email: email,
      );

      if (scope == null) return;

      await NotificationInboxStore.instance.markOpened(
        scope: scope,
        entry: entry,
      );
    } catch (_) {
      // El estado leído es visual/local y nunca debe bloquear la apertura.
    }
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationInboxEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationCard({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = entry.imageUrl?.trim() ?? '';
    final isUnread = !entry.openedByUser;
    final cardColor = isUnread ? const Color(0xFFE5E7EB) : Colors.white;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnread
                  ? const Color(0xFFD1D5DB)
                  : const Color(0xFFE8EBEF),
            ),
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
              const SizedBox(width: 6),
              SizedBox(
                width: 34,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: Color(0xFFB3B8C0),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      tooltip: 'Eliminar',
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: Color(0xFF9CA3AF),
                      ),
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

String _formatDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
