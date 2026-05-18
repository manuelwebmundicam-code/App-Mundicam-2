// pages/payment_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/api_service.dart';
import '../theme.dart';

class PaymentPage extends StatefulWidget {
  final int orderId;
  final String orderKey;
  final String paymentUrl;

  const PaymentPage({
    super.key,
    required this.orderId,
    required this.orderKey,
    required this.paymentUrl,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> with WidgetsBindingObserver {
  late final WebViewController _controller;

  int _progress = 0;

  bool _paymentSuccess = false;
  bool _paymentError = false;
  bool _checkingPayment = false;
  bool _openedExternalPayment = false;
  bool _waitingForConfirmation = false;

  String? _errorMessage;
  String? _currentUrl;

  static const Set<String> _paidStatuses = {
    'processing',
    'completed',
  };

  static const Set<String> _failedStatuses = {
    'failed',
    'cancelled',
    'refunded',
  };

  static const Set<String> _pendingStatuses = {
    'pending',
    'on-hold',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedExternalPayment) {
      _verifyOrderPaymentStatus(
        showPendingAsWaiting: true,
        source: 'app_resumed',
      );
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'MundiCamExternal',
        onMessageReceived: (JavaScriptMessage message) {
          final url = message.message.trim();

          if (url.isNotEmpty) {
            _openExternalUrl(url);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            debugPrint('🌐 PaymentPage started: $url');
            _currentUrl = url;
            _checkUrlForPaymentResult(url);
          },
          onPageFinished: (url) async {
            debugPrint('🌐 PaymentPage finished: $url');
            _currentUrl = url;

            await _injectWindowOpenHandler();
            _checkUrlForPaymentResult(url);
          },
          onNavigationRequest: (request) {
            final url = request.url;
            debugPrint('➡️ PaymentPage navigation: $url');

            if (_isSuccessUrl(url)) {
              _verifyOrderPaymentStatus(
                showPendingAsWaiting: true,
                source: 'success_url',
              );
              return NavigationDecision.prevent;
            }

            if (_isFailureUrl(url)) {
              _markPaymentError(
                'El pago no se ha completado. Puedes volver atrás e intentarlo de nuevo.',
              );
              return NavigationDecision.prevent;
            }

            if (_shouldOpenExternally(url)) {
              _openExternalUrl(url);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            debugPrint(
              '⚠️ PaymentPage web error: ${error.errorCode} - ${error.description}',
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<void> _injectWindowOpenHandler() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          if (window.__mundicamWindowOpenInjected) return;
          window.__mundicamWindowOpenInjected = true;

          var originalOpen = window.open;

          window.open = function(url, name, specs) {
            if (url) {
              try {
                var absoluteUrl = new URL(url, window.location.href).toString();
                MundiCamExternal.postMessage(absoluteUrl);
              } catch(e) {
                MundiCamExternal.postMessage(url.toString());
              }
              return null;
            }

            if (originalOpen) {
              return originalOpen.apply(window, arguments);
            }

            return null;
          };

          document.querySelectorAll('a[target="_blank"]').forEach(function(link) {
            link.addEventListener('click', function(event) {
              if (link.href) {
                event.preventDefault();
                MundiCamExternal.postMessage(link.href);
              }
            });
          });

          document.querySelectorAll('form[target="_blank"]').forEach(function(form) {
            form.removeAttribute('target');
          });
        })();
      ''');
    } catch (e) {
      debugPrint('⚠️ No se pudo inyectar JS para window.open: $e');
    }
  }

  bool _isSuccessUrl(String url) {
    final lower = url.toLowerCase();

    return lower.contains('/order-received/') ||
        lower.contains('order-received') ||
        lower.contains('pedido-recibido') ||
        lower.contains('gracias') ||
        lower.contains('thank-you') ||
        lower.contains('thankyou');
  }

  bool _isFailureUrl(String url) {
    final lower = url.toLowerCase();

    return lower.contains('cancel_order') ||
        lower.contains('payment_failed') ||
        lower.contains('pago-fallido') ||
        lower.contains('failed') ||
        lower.contains('cancelled') ||
        lower.contains('cancelado') ||
        lower.contains('ko');
  }

  bool _isMundicamUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();

      return host == 'www.mundicam.com' || host == 'mundicam.com';
    } catch (_) {
      return false;
    }
  }

  bool _shouldOpenExternally(String url) {
    final lower = url.toLowerCase();

    if (lower.startsWith('about:blank')) {
      return false;
    }

    if (lower.startsWith('tel:') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('whatsapp:') ||
        lower.startsWith('intent:') ||
        lower.startsWith('market:')) {
      return true;
    }

    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return true;
    }

    // Seguridad: la navegación principal de la app se queda solo en MundiCam.
    // Redsys, banco u otros dominios se abren fuera.
    if (!_isMundicamUrl(url)) {
      return true;
    }

    return false;
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);

      if (!mounted) return;

      setState(() {
        _openedExternalPayment = true;
        _paymentError = false;
        _errorMessage = null;
      });

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _markPaymentError('No se pudo abrir la pasarela externa de pago.');
      }
    } catch (e) {
      debugPrint('❌ Error abriendo URL externa: $e');

      if (mounted) {
        _markPaymentError('No se pudo abrir la pasarela externa de pago.');
      }
    }
  }

  void _checkUrlForPaymentResult(String url) {
    if (_paymentSuccess || _checkingPayment) return;

    if (_isSuccessUrl(url)) {
      _verifyOrderPaymentStatus(
        showPendingAsWaiting: true,
        source: 'success_url_check',
      );
      return;
    }

    if (_isFailureUrl(url)) {
      _markPaymentError(
        'El pago no se ha completado. Puedes volver atrás e intentarlo de nuevo.',
      );
    }
  }

  Future<void> _verifyOrderPaymentStatus({
    bool showPendingAsWaiting = false,
    String source = 'manual',
  }) async {
    if (_checkingPayment || _paymentSuccess) return;

    setState(() {
      _checkingPayment = true;
      _paymentError = false;
      _waitingForConfirmation = false;
      _errorMessage = null;
    });

    try {
      debugPrint('🔎 Verificando pago pedido #${widget.orderId} desde $source');

      final order = await ApiService().getOrdenCompleta(
        widget.orderId.toString(),
      );

      if (!mounted) return;

      if (order == null) {
        setState(() {
          _checkingPayment = false;
          _paymentError = true;
          _errorMessage =
          'No se pudo comprobar el estado del pedido. Intenta de nuevo.';
        });
        return;
      }

      final status = order['status']?.toString().toLowerCase().trim() ?? '';
      final remoteOrderKey = order['order_key']?.toString().trim();

      debugPrint('🔎 Estado pedido #${widget.orderId}: $status');
      debugPrint('🔑 Order key local: ${widget.orderKey}');
      debugPrint('🔑 Order key WooCommerce: $remoteOrderKey');

      if (remoteOrderKey != null &&
          remoteOrderKey.isNotEmpty &&
          remoteOrderKey != widget.orderKey) {
        setState(() {
          _checkingPayment = false;
          _paymentError = true;
          _errorMessage =
          'La verificación del pedido no coincide. Contacta con MundiCam.';
        });
        return;
      }

      if (_paidStatuses.contains(status)) {
        _markPaymentSuccess();
        return;
      }

      if (_failedStatuses.contains(status)) {
        _markPaymentError(
          'El pago aparece como no completado en WooCommerce.',
        );
        return;
      }

      if (_pendingStatuses.contains(status)) {
        setState(() {
          _checkingPayment = false;
          _waitingForConfirmation = showPendingAsWaiting;
          _paymentError = true;
          _errorMessage =
          'El pedido todavía aparece pendiente de pago. Si acabas de pagar, espera unos segundos y pulsa “Comprobar pago”.';
        });
        return;
      }

      setState(() {
        _checkingPayment = false;
        _paymentError = true;
        _errorMessage =
        'Estado actual del pedido: $status. Si el pago se ha realizado, pulsa “Comprobar pago” en unos segundos.';
      });
    } catch (e) {
      debugPrint('❌ Error verificando pago: $e');

      if (!mounted) return;

      setState(() {
        _checkingPayment = false;
        _paymentError = true;
        _errorMessage =
        'No se pudo comprobar el estado del pago. Intenta de nuevo.';
      });
    }
  }

  void _markPaymentSuccess() {
    if (!mounted || _paymentSuccess) return;

    setState(() {
      _paymentSuccess = true;
      _paymentError = false;
      _checkingPayment = false;
      _waitingForConfirmation = false;
      _errorMessage = null;
      _progress = 100;
    });
  }

  void _markPaymentError(String message) {
    if (!mounted || _paymentSuccess) return;

    setState(() {
      _paymentError = true;
      _checkingPayment = false;
      _waitingForConfirmation = false;
      _errorMessage = message;
    });
  }

  Future<void> _reloadPaymentPage() async {
    setState(() {
      _paymentError = false;
      _errorMessage = null;
      _waitingForConfirmation = false;
      _checkingPayment = false;
      _progress = 0;
    });

    await _controller.loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<bool> _handleBack() async {
    if (_paymentSuccess) {
      Navigator.of(context).pop(true);
      return false;
    }

    final canGoBack = await _controller.canGoBack();

    if (canGoBack) {
      await _controller.goBack();
      return false;
    }

    Navigator.of(context).pop(false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'PAGO CON TARJETA',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: 'Oswald',
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          actions: [
            IconButton(
              tooltip: 'Comprobar pago',
              icon: _checkingPayment
                  ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.verified_outlined),
              onPressed:
              _checkingPayment ? null : () => _verifyOrderPaymentStatus(),
            ),
            IconButton(
              tooltip: 'Recargar',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reloadPaymentPage,
            ),
          ],
        ),
        body: _paymentSuccess
            ? _buildSuccessState()
            : Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(
                value: _progress / 100,
                color: AppColors.primary,
                backgroundColor: Colors.orange.shade100,
                minHeight: 3,
              ),
            _buildPaymentHeader(),
            if (_openedExternalPayment) _buildExternalPaymentNotice(),
            if (_waitingForConfirmation) _buildWaitingNotice(),
            if (_paymentError) _buildErrorNotice(),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.credit_card_outlined,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pasarela segura Redsys',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pedido #${widget.orderId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildExternalPaymentNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.open_in_new_rounded,
            color: Colors.blue.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'La pasarela puede abrir una ventana externa. Cuando finalices el pago, vuelve a la app y pulsa “Comprobar pago”.',
              style: TextStyle(
                color: Colors.blue.shade800,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _checkingPayment
                ? null
                : () => _verifyOrderPaymentStatus(
              showPendingAsWaiting: true,
              source: 'external_notice_button',
            ),
            child: _checkingPayment
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Comprobar'),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.hourglass_top_rounded,
            color: Colors.orange.shade800,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Estamos esperando confirmación real de WooCommerce. No cierres la pantalla si acabas de pagar.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.red.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? 'No se pudo completar el pago.',
              style: TextStyle(
                color: Colors.red.shade800,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _checkingPayment
                ? null
                : () => _verifyOrderPaymentStatus(
              showPendingAsWaiting: true,
              source: 'error_notice_button',
            ),
            child: const Text('Comprobar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF059669),
                  size: 52,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Pago exitoso',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Oswald',
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'WooCommerce ha confirmado el pago del pedido #${widget.orderId}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'VOLVER A LA TIENDA',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}