import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class ContentRegistrationWebViewPage extends StatefulWidget {
  const ContentRegistrationWebViewPage({
    super.key,
    required this.title,
    required this.initialUri,
  });

  final String title;
  final Uri initialUri;

  @override
  State<ContentRegistrationWebViewPage> createState() =>
      _ContentRegistrationWebViewPageState();
}

class _ContentRegistrationWebViewPageState
    extends State<ContentRegistrationWebViewPage> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (!mounted) return;
            setState(() => _progress = value);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.prevent;
            }

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }

            _openExternalScheme(uri);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.initialUri);
  }

  Future<void> _openExternalScheme(Uri uri) async {
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }

    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _back();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: ProfessionalPageAppBar(
          title: widget.title,
          onBack: _back,
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_progress < 100)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress / 100 : null,
                  minHeight: 2,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
