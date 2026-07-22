import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:mundicam/shared/theme/app_theme.dart';

class MundicamWebPage extends StatefulWidget {
  const MundicamWebPage({
    super.key,
    required this.title,
    required this.url,
    this.headerTitle,
    this.headerMessage,
  });

  final String title;
  final String url;
  final String? headerTitle;
  final String? headerMessage;

  @override
  State<MundicamWebPage> createState() => _MundicamWebPageState();
}

class _MundicamWebPageState extends State<MundicamWebPage> {
  late final WebViewController _controller;

  int _progress = 0;
  bool _hasError = false;
  bool _canGoBack = false;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (String url) async {
            if (!mounted) return;
            final canGoBack = await _controller.canGoBack();
            if (!mounted) return;
            setState(() {
              _hasError = false;
              _currentUrl = url;
              _canGoBack = canGoBack;
            });
          },
          onPageFinished: (String url) async {
            if (!mounted) return;
            final canGoBack = await _controller.canGoBack();
            if (!mounted) return;
            setState(() {
              _progress = 100;
              _currentUrl = url;
              _canGoBack = canGoBack;
            });
          },
          onWebResourceError: (WebResourceError error) {
            if (!mounted) return;
            setState(() => _hasError = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _handleBack() async {
    final canGoBack = await _controller.canGoBack();
    if (!mounted) return;

    if (canGoBack) {
      await _controller.goBack();
      final stillCanGoBack = await _controller.canGoBack();
      if (!mounted) return;
      setState(() => _canGoBack = stillCanGoBack);
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _progress = 0;
    });
    await _controller.reload();
  }

  Widget _buildHeader() {
    final title = widget.headerTitle?.trim() ?? '';
    final message = widget.headerMessage?.trim() ?? '';

    if (title.isEmpty && message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                color: AppColors.primary,
                fontFamily: 'Oswald',
                fontSize: 19,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (title.isNotEmpty && message.isNotEmpty)
            const SizedBox(height: 6),
          if (message.isNotEmpty)
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Oswald',
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFFF9FAFB),
        padding: const EdgeInsets.all(22),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.wifi_off_rounded,
                  color: AppColors.primary,
                  size: 44,
                ),
                const SizedBox(height: 14),
                const Text(
                  'No se pudo cargar la página',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _currentUrl.isEmpty
                      ? 'Comprueba tu conexión e inténtalo de nuevo.'
                      : 'Comprueba tu conexión e inténtalo de nuevo.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 16,
                    height: 1.25,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('REINTENTAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('VOLVER'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      textStyle: const TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _progress > 0 && _progress < 100;

    return WillPopScope(
      onWillPop: () async {
        await _handleBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            tooltip: _canGoBack ? 'Atrás en la página' : 'Volver',
            icon: const Icon(Icons.arrow_back_rounded, size: 30),
            onPressed: _handleBack,
          ),
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Oswald',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Recargar',
              icon: const Icon(Icons.refresh_rounded, size: 28),
              onPressed: _reload,
            ),
            IconButton(
              tooltip: 'Cerrar',
              icon: const Icon(Icons.close_rounded, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            _buildHeader(),
            if (isLoading)
              LinearProgressIndicator(
                value: _progress <= 0 ? null : _progress / 100,
                minHeight: 4,
                backgroundColor: const Color(0xFFF3F4F6),
                color: AppColors.primary,
              ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  WebViewWidget(controller: _controller),
                  if (_hasError) _buildError(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
