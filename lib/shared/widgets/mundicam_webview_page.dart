import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class MundiCamWebViewPage extends StatefulWidget {
  const MundiCamWebViewPage({
    super.key,
    required this.title,
    this.initialUri,
    this.url,
    this.focusRegistration = false,
    this.closeOnBack = false,
  }) : assert(
          initialUri != null || url != null,
          'Debe indicarse initialUri o url.',
        );

  final String title;
  final Uri? initialUri;
  final String? url;

  /// Cuando se abre desde Academy, mantiene toda la navegación dentro
  /// de la app y, al cargar la ficha del evento, baja hasta el formulario
  /// de inscripción real de mundicam.com si está presente.
  final bool focusRegistration;

  /// Si es true, la flecha de atrás y el botón físico/gesto de atrás
  /// cierran esta WebView y vuelven directamente a la pantalla Flutter
  /// que la abrió, sin recorrer el historial interno de la web.
  final bool closeOnBack;

  Uri get resolvedInitialUri => initialUri ?? Uri.parse(url!);

  @override
  State<MundiCamWebViewPage> createState() => _MundiCamWebViewPageState();
}

// Alias de compatibilidad con la primera versión del widget.
// Evita romper cualquier referencia que ya use MundicamWebViewPage.
typedef MundicamWebViewPage = MundiCamWebViewPage;

class _MundiCamWebViewPageState extends State<MundiCamWebViewPage> {
  late final WebViewController _controller;
  int _loadingProgress = 0;

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
            setState(() => _loadingProgress = progress);
          },
          onPageFinished: (_) {
            final normalizedTitle = widget.title.toUpperCase();
            final shouldFocusRegistration = widget.focusRegistration ||
                normalizedTitle.contains('INSCRIPCIÓN') ||
                normalizedTitle.contains('INSCRIPCION');
            if (shouldFocusRegistration) {
              _focusRegistrationForm();
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.prevent;
            }

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              // Academy, formularios de inscripción, registro y Noticias
              // permanecen dentro de la app.
              return NavigationDecision.navigate;
            }

            _openExternalScheme(uri);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.resolvedInitialUri);
  }

  Future<void> _focusRegistrationForm() async {
    if (!widget.focusRegistration) return;

    // La ficha Academy sigue siendo la web real de MundiCam, por lo que
    // el formulario, validaciones, RGPD y confirmaciones continúan siendo
    // responsabilidad de WordPress. Aquí solo llevamos al usuario hasta él.
    await Future<void>.delayed(const Duration(milliseconds: 350));

    const script = r'''
      (function () {
        var selectors = [
          '.wpcf7',
          '.wpforms-container',
          '.gform_wrapper',
          '[id*="inscri"]',
          '[class*="inscri"]'
        ];

        var target = null;

        for (var i = 0; i < selectors.length; i++) {
          target = document.querySelector(selectors[i]);
          if (target) break;
        }

        if (!target) {
          var candidates = Array.prototype.slice.call(
            document.querySelectorAll(
              'h1,h2,h3,h4,h5,strong,a,button,p'
            )
          );

          var marker = candidates.find(function (element) {
            var text = (element.innerText || '').trim().toLowerCase();
            return text.indexOf('inscríb') >= 0 ||
                   text.indexOf('inscrib') >= 0 ||
                   text.indexOf('preinscr') >= 0 ||
                   text.indexOf('reserva tu plaza') >= 0;
          });

          if (marker) {
            var parent = marker.closest('section,article,div');
            target = parent && parent.querySelector('form')
              ? parent.querySelector('form')
              : marker;
          }
        }

        if (target) {
          target.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
          });
          window.setTimeout(function () {
            window.scrollBy(0, -12);
          }, 250);
          return true;
        }

        return false;
      })();
    ''';

    try {
      await _controller.runJavaScript(script);
    } catch (_) {
      // Si la web cambia de maquetador, simplemente se mantiene la ficha
      // completa navegable; nunca se bloquea la inscripción.
    }
  }

  Future<void> _openExternalScheme(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      debugPrint('No se pudo abrir el enlace externo: $uri');
    }
  }

  Future<void> _handleBack() async {
    if (!mounted) return;

    if (widget.closeOnBack) {
      // En Academy no recorremos el historial de WordPress:
      // cerramos esta ruta WebView y volvemos a la Academy nativa.
      Navigator.of(context).pop();
      return;
    }

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
      // Academy/Inscripción puede cerrar la ruta Flutter normalmente.
      // El resto de WebViews mantiene canPop=false para poder consumir
      // primero su historial interno de navegación.
      canPop: widget.closeOnBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: ProfessionalPageAppBar(
          title: widget.title,
          onBack: _handleBack,
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loadingProgress < 100)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0
                      ? _loadingProgress / 100
                      : null,
                  minHeight: 2,
                  color: AppColors.primary,
                  backgroundColor: const Color(0xFFF1F3F5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
