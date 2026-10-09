import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/promotions/data/models/promotion_model.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

/// Muestra la página pública real de WordPress asociada a la promoción.
///
/// No reconstruye ni extrae el contenido del artículo. Se conserva el DOM
/// original de WordPress para que se vea igual que en la web (maquetación,
/// imágenes, botones, lazy-load y scripts). Solo se ocultan elementos externos
/// al artículo (cabecera/menús/sidebar/footer) y widgets flotantes como el chat.
class PromotionWebViewPage extends StatefulWidget {
  const PromotionWebViewPage({
    super.key,
    required this.promotion,
  });

  final PromotionModel promotion;

  @override
  State<PromotionWebViewPage> createState() => _PromotionWebViewPageState();
}

class _PromotionWebViewPageState extends State<PromotionWebViewPage> {
  late final WebViewController _controller;
  int _loadingProgress = 0;
  bool _contentReady = false;
  bool _styleRunning = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted && progress != _loadingProgress) {
              setState(() => _loadingProgress = progress);
            }

            // El tema de WordPress monta partes del DOM de forma progresiva.
            // Reaplicamos la limpieza sin tocar nunca el contenido del artículo.
            if (progress >= 5) {
              unawaited(_applyPromotionPresentation());
            }
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _contentReady = false;
              _loadingProgress = 0;
              _loadError = null;
            });
          },
          onPageFinished: (_) {
            unawaited(_finishPageLoad());
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (!mounted) return;
            setState(() {
              _loadError = 'No se ha podido cargar la promoción.';
            });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.prevent;
            }

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }

            unawaited(_openExternalScheme(uri));
            return NavigationDecision.prevent;
          },
        ),
      );

    unawaited(_resolveAndLoad());
  }

  Future<void> _resolveAndLoad() async {
    final uri = await ApiService().resolvePromotionWebUri(widget.promotion);

    if (!mounted) return;

    if (uri == null) {
      setState(() {
        _loadError = 'No se ha encontrado la página de esta promoción.';
      });
      return;
    }

    try {
      await _controller.loadRequest(uri);
    } catch (error) {
      if (!mounted) return;
      debugPrint('No se pudo abrir la promoción: $error');
      setState(() {
        _loadError = 'No se ha podido cargar la promoción.';
      });
    }
  }

  Future<void> _finishPageLoad() async {
    await _applyPromotionPresentation(forceReady: true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _applyPromotionPresentation(forceReady: true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _applyPromotionPresentation(forceReady: true);
  }

  Future<bool> _applyPromotionPresentation({bool forceReady = false}) async {
    if (_styleRunning) return false;
    _styleRunning = true;

    const script = r'''
      (function () {
        function hideNode(node) {
          if (!node || !node.style) return;
          node.style.setProperty('display', 'none', 'important');
          node.setAttribute('data-mundicam-app-hidden', '1');
        }

        function isInsideArticle(node, article) {
          return !!(article && node && (node === article || article.contains(node)));
        }

        function findPromotionArticle() {
          var selectors = [
            'article.post',
            'article.blog-post',
            'article',
            '.single-post .post-single',
            '.single-post .blog-post',
            '.single-post .type-post'
          ];

          var candidates = [];
          selectors.forEach(function (selector) {
            try {
              document.querySelectorAll(selector).forEach(function (node) {
                if (candidates.indexOf(node) === -1) candidates.push(node);
              });
            } catch (_) {}
          });

          var best = null;
          var bestScore = -1;

          candidates.forEach(function (node) {
            var text = (node.innerText || '').trim();
            var imageCount = 0;
            var headingCount = 0;
            try {
              imageCount = node.querySelectorAll('img').length;
              headingCount = node.querySelectorAll('h1,h2,h3').length;
            } catch (_) {}

            var score = text.length + (imageCount * 450) + (headingCount * 120);
            if (/promo|descuento|promoci/i.test(text)) score += 1200;

            if (score > bestScore) {
              best = node;
              bestScore = score;
            }
          });

          return best;
        }

        function hideOutsideChrome(article) {
          // Ocultamos elementos semánticos externos al artículo. Nunca usamos
          // selectores globales tipo "header {display:none}" porque algunas
          // plantillas usan header/nav dentro del propio contenido promocional.
          ['header', 'footer', 'aside', 'nav'].forEach(function (tag) {
            try {
              document.querySelectorAll(tag).forEach(function (node) {
                if (!isInsideArticle(node, article)) hideNode(node);
              });
            } catch (_) {}
          });

          var outsideSelectors = [
            '#wpadminbar',
            '#header',
            '.site-header',
            '.header-wrapper',
            '.header-main',
            '.main-header',
            '.mobile-header-wrapper',
            '.mobile-header',
            '.et-mobile-panel-wrapper',
            '.et-mobile-panel',
            '.et_b_header-menu',
            '.et_b_header-cart',
            '.et_b_header-account',
            '.et_b_header-search',
            '#sidebar',
            '.sidebar',
            '.sidebar-wrapper',
            '.widget-area',
            '.single-post-sidebar',
            '.blog-sidebar',
            '.site-footer',
            '.footer-wrapper',
            '.footer-main',
            '.main-footer',
            '.copyrights-wrapper',
            '.copyright',
            '.back-top',
            '.back-to-top',
            '.breadcrumbs',
            '.breadcrumb',
            '.post-navigation',
            '.comments-area',
            '#comments',
            '.related-posts',
            '.related-posts-wrapper',
            '.cky-consent-container',
            '#cmplz-cookiebanner-container',
            '.cmplz-cookiebanner',
            '#cookie-law-info-bar',
            '#cookie-notice',
            '.grecaptcha-badge'
          ];

          outsideSelectors.forEach(function (selector) {
            try {
              document.querySelectorAll(selector).forEach(function (node) {
                if (!isInsideArticle(node, article)) hideNode(node);
              });
            } catch (_) {}
          });
        }

        function hideArticleExtras(article) {
          if (!article) return;

          // Elementos que el usuario ya pidió quitar aunque estén dentro del
          // bloque del post: compartir, etiquetas y navegación de artículos.
          var selectors = [
            '.sharedaddy',
            '.share-links',
            '.share-link',
            '.share-post',
            '.post-share',
            '.post-sharing',
            '.social-share',
            '.social-sharing',
            '.share-buttons',
            '.etheme-social-links',
            '.elementor-widget-share-buttons',
            '.elementor-widget-social-icons',
            '.post-tags',
            '.tags-links',
            '.entry-tags'
          ];

          selectors.forEach(function (selector) {
            try {
              article.querySelectorAll(selector).forEach(hideNode);
            } catch (_) {}
          });

          // Fila de compartir que algunos templates generan sin clase estable.
          var shareSelector = [
            'a[href^="mailto:"]',
            'a[href*="linkedin.com/share"]',
            'a[href*="linkedin.com/sharing"]',
            'a[href*="wa.me/"]',
            'a[href*="whatsapp.com/"]'
          ].join(',');

          try {
            article.querySelectorAll(shareSelector).forEach(function (anchor) {
              var node = anchor.parentElement;
              var depth = 0;
              while (node && node !== article && depth < 5) {
                var shareCount = 0;
                var linkCount = 0;
                var text = '';
                try {
                  shareCount = node.querySelectorAll(shareSelector).length;
                  linkCount = node.querySelectorAll('a').length;
                  text = (node.innerText || '').trim();
                } catch (_) {}

                if (shareCount >= 2 && linkCount <= 10 && text.length < 220) {
                  hideNode(node);
                  break;
                }
                node = node.parentElement;
                depth++;
              }
            });
          } catch (_) {}
        }

        function hideChatRoot(node) {
          if (!node) return;

          var current = node;
          var candidate = node;
          var depth = 0;

          while (current && current !== document.body && depth < 8) {
            candidate = current;
            var style = null;
            try { style = window.getComputedStyle(current); } catch (_) {}

            if (style && (style.position === 'fixed' || style.position === 'sticky')) {
              hideNode(current);
              return;
            }

            if (current.parentElement === document.body) {
              hideNode(current);
              return;
            }

            current = current.parentElement;
            depth++;
          }

          hideNode(candidate);
        }

        function hideChat() {
          var selectors = [
            '.joinchat',
            '#joinchat',
            '[class*="joinchat"]',
            '[id*="joinchat"]',
            '[class*="chat-widget"]',
            '[id*="chat-widget"]',
            '[class*="chatbot"]',
            '[id*="chatbot"]',
            '[class*="assistant"]',
            '[id*="assistant"]',
            '[class*="asistente"]',
            '[id*="asistente"]',
            '[class*="tawk"]',
            '[id*="tawk"]',
            '[class*="crisp"]',
            '[id*="crisp"]',
            '[class*="intercom"]',
            '[id*="intercom"]',
            '[class*="tidio"]',
            '[id*="tidio"]',
            '[class*="jivo"]',
            '[id*="jivo"]',
            'iframe[src*="chat"]',
            'iframe[src*="tawk"]',
            'iframe[src*="crisp"]',
            'iframe[src*="intercom"]',
            'iframe[src*="tidio"]',
            'iframe[src*="jivo"]',
            'iframe[title*="chat" i]',
            '[aria-label*="chat" i]',
            '[title*="chat" i]'
          ];

          selectors.forEach(function (selector) {
            try {
              document.querySelectorAll(selector).forEach(hideChatRoot);
            } catch (_) {}
          });

          // El asistente de MundiCam puede no llevar una clase estable. Buscamos
          // su texto visible y ocultamos el contenedor flotante completo, incluido
          // el botón circular asociado.
          try {
            document.querySelectorAll('body > div, body > aside, body > section').forEach(function (node) {
              var text = (node.innerText || '').replace(/\s+/g, ' ').trim().toLowerCase();
              if (text.indexOf('asistente pro mundicam') !== -1) {
                hideChatRoot(node);
              }
            });
          } catch (_) {}

          // Fallback para widgets que llegan en un iframe flotante sin nombre.
          try {
            document.querySelectorAll('iframe').forEach(function (frame) {
              var style = null;
              var rect = null;
              try {
                style = window.getComputedStyle(frame);
                rect = frame.getBoundingClientRect();
              } catch (_) {}
              if (!style || !rect) return;

              var fixed = style.position === 'fixed' || style.position === 'sticky';
              var nearRight = rect.right >= (window.innerWidth - 32);
              var nearBottom = rect.bottom >= (window.innerHeight - 32);
              var widgetSize = rect.width > 0 && rect.width <= 520 && rect.height > 0 && rect.height <= 760;

              if (fixed && nearRight && nearBottom && widgetSize) {
                hideChatRoot(frame);
              }
            });
          } catch (_) {}
        }

        function installMinimalStyle() {
          var style = document.getElementById('mundicam-app-promotion-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'mundicam-app-promotion-style';
            (document.head || document.documentElement).appendChild(style);
          }

          style.textContent = `
            html, body {
              margin: 0 !important;
              padding: 0 !important;
              min-height: 100% !important;
              overflow-x: hidden !important;
            }

            [data-mundicam-app-hidden="1"] {
              display: none !important;
            }
          `;
        }

        function clean() {
          installMinimalStyle();
          var article = findPromotionArticle();
          hideOutsideChrome(article);
          hideArticleExtras(article);
          hideChat();

          if (!article) return false;
          var text = (article.innerText || '').trim();
          var images = 0;
          try { images = article.querySelectorAll('img').length; } catch (_) {}
          return text.length > 80 || images > 0;
        }

        var ready = clean();

        if (!window.__mundicamPromotionObserverInstalled && document.body) {
          window.__mundicamPromotionObserverInstalled = true;
          var timer = null;
          var observer = new MutationObserver(function () {
            if (timer) return;
            timer = setTimeout(function () {
              timer = null;
              clean();
            }, 80);
          });
          observer.observe(document.body, { childList: true, subtree: true });
        }

        return ready;
      })();
    ''';

    try {
      final result = await _controller.runJavaScriptReturningResult(script);
      final normalized = result.toString().replaceAll('"', '').toLowerCase();
      final hasContent = result == true || normalized == 'true';

      if (mounted && !_contentReady && (hasContent || forceReady)) {
        setState(() => _contentReady = true);
      }

      return hasContent;
    } catch (error) {
      debugPrint('No se pudo preparar la promoción para la app: $error');
      if (mounted && forceReady && !_contentReady) {
        setState(() => _contentReady = true);
      }
      return false;
    } finally {
      _styleRunning = false;
    }
  }

  Future<void> _openExternalScheme(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      debugPrint('No se pudo abrir el enlace externo: $uri');
    }
  }

  Widget _loadingView() {
    final imageUrl = widget.promotion.imageUrl.trim();

    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          if (imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, __) => const SizedBox(height: 150),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          const Spacer(),
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 12),
          const Text(
            'Cargando promoción…',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (!_contentReady)
                      Positioned.fill(child: _loadingView()),
                    if (_contentReady && _loadingProgress < 100)
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
      ),
    );
  }
}
