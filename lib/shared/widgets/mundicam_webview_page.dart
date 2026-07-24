import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:mundicam/shared/theme/app_theme.dart';

class MundiCamWebViewPage extends StatefulWidget {
  final String title;
  final Uri initialUri;

  const MundiCamWebViewPage({
    super.key,
    required this.title,
    required this.initialUri,
  });

  @override
  State<MundiCamWebViewPage> createState() => _MundiCamWebViewPageState();
}

class _MundiCamWebViewPageState extends State<MundiCamWebViewPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress.clamp(0, 100).toInt();
              if (progress < 100) {
                _hasError = false;
                _errorMessage = '';
              }
            });
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) return;
            setState(() {
              _hasError = true;
              _errorMessage = error.description;
            });
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            final scheme = uri?.scheme.toLowerCase() ?? '';

            if (scheme == 'http' || scheme == 'https') {
              return NavigationDecision.navigate;
            }

            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.initialUri);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _progress = 0;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontFamily: 'Oswald'),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_progress < 100)
              LinearProgressIndicator(
                value: _progress <= 0 ? null : _progress / 100,
                color: AppColors.primary,
                minHeight: 3,
              ),
            if (_hasError)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: AppColors.primary,
                      size: 46,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No se pudo cargar la página.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage.isEmpty
                          ? 'Comprueba la conexión e inténtalo de nuevo.'
                          : _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
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
