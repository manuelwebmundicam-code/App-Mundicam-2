import 'dart:async';

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
  static const Duration _loadTimeout = Duration(seconds: 18);

  late final WebViewController _controller;
  Timer? _timeoutTimer;

  int _progress = 0;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _beginLoading();
          },
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress.clamp(0, 100).toInt();
            });
          },
          onPageFinished: (_) {
            unawaited(_handlePageFinished());
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            _showLoadError(
              error.description.trim().isEmpty
                  ? 'La web de registro no respondió correctamente.'
                  : error.description.trim(),
            );
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
      );

    _beginLoading();
    unawaited(_controller.loadRequest(widget.initialUri));
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _beginLoading() {
    _timeoutTimer?.cancel();
    final int generation = ++_loadGeneration;

    if (mounted) {
      setState(() {
        _progress = 0;
        _isLoading = true;
        _hasError = false;
        _errorMessage = '';
      });
    }

    _timeoutTimer = Timer(_loadTimeout, () {
      if (!mounted || generation != _loadGeneration || !_isLoading) return;
      _showLoadError(
        'La página de registro está tardando demasiado en responder.',
      );
    });
  }

  Future<void> _handlePageFinished() async {
    final int generation = _loadGeneration;

    // Algunas webs de WordPress notifican el fin de carga antes de terminar
    // de construir el formulario mediante JavaScript.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (!mounted || generation != _loadGeneration) return;

    final bool hasUsableContent = await _hasUsablePageContent();
    if (!mounted || generation != _loadGeneration) return;

    if (!hasUsableContent) {
      _showLoadError(
        'La web se abrió, pero el formulario de registro no llegó a mostrarse.',
      );
      return;
    }

    _timeoutTimer?.cancel();
    setState(() {
      _progress = 100;
      _isLoading = false;
      _hasError = false;
      _errorMessage = '';
    });
  }

  Future<bool> _hasUsablePageContent() async {
    try {
      final Object result = await _controller.runJavaScriptReturningResult(
        '''
        (() => {
          const body = document.body;
          if (!body) return 0;

          const textLength = (body.innerText || '').trim().length;
          const interactiveElements = document.querySelectorAll(
            'form, input, select, textarea, button, a'
          ).length;

          return textLength + (interactiveElements * 100);
        })();
        ''',
      );

      final String raw = result.toString().replaceAll('"', '').trim();
      final num? score = num.tryParse(raw);

      // Si la plataforma devuelve un formato que no podemos interpretar,
      // no bloqueamos una página que visualmente puede haberse cargado bien.
      if (score == null) return true;

      return score >= 120;
    } catch (error) {
      debugPrint('⚠️ No se pudo verificar el contenido del registro: $error');
      return true;
    }
  }

  void _showLoadError(String message) {
    _timeoutTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _hasError = true;
      _errorMessage = message;
    });
  }

  Future<void> _reload() async {
    _beginLoading();

    try {
      await _controller.loadRequest(
        widget.initialUri.replace(
          queryParameters: <String, String>{
            ...widget.initialUri.queryParameters,
            'app_retry': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        ),
      );
    } catch (error) {
      _showLoadError('No se pudo volver a cargar la página: $error');
    }
  }

  Future<void> _openInBrowser() async {
    try {
      final bool opened = await launchUrl(
        widget.initialUri,
        mode: LaunchMode.inAppBrowserView,
      );

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la web de registro.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir la web de registro: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _hasError,
                child: WebViewWidget(controller: _controller),
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Cargando solicitud de registro…',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Oswald',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _progress > 0
                                ? 'Progreso: $_progress %'
                                : 'Conectando con MundiCam',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextButton.icon(
                            onPressed: _openInBrowser,
                            icon: const Icon(Icons.open_in_browser_rounded),
                            label: const Text('ABRIR REGISTRO SEGURO'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_hasError)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.language_rounded,
                              color: AppColors.primary,
                              size: 52,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No se pudo mostrar el formulario dentro de la app.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Oswald',
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _errorMessage.isEmpty
                                  ? 'Puedes volver a intentarlo o continuar directamente en la web segura de MundiCam.'
                                  : _errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.4,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _reload,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('REINTENTAR'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _openInBrowser,
                                icon: const Icon(Icons.open_in_browser_rounded),
                                label: const Text('ABRIR REGISTRO EN MUNDICAM'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!_hasError && !_isLoading && _progress < 100)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress / 100,
                  color: AppColors.primary,
                  minHeight: 3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
