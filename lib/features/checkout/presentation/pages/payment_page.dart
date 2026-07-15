// pages/payment_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class PaymentPage extends StatefulWidget {
  final int orderId;
  final String orderKey;
  final String paymentUrl;
  final String? orderNumber;
  final double? amount;
  final String paymentMethodTitle;

  const PaymentPage({
    super.key,
    required this.orderId,
    required this.orderKey,
    required this.paymentUrl,
    this.orderNumber,
    this.amount,
    this.paymentMethodTitle = 'Pago con tarjeta',
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> with WidgetsBindingObserver {
  late final WebViewController _controller;

  int _progress = 0;

  bool _paymentStarted = false;
  bool _paymentSuccess = false;
  bool _paymentError = false;
  bool _checkingPayment = false;
  bool _openedExternalPayment = false;
  bool _waitingForConfirmation = false;

  String? _errorMessage;

  static const Set<String> _paidStatuses = {'processing', 'completed'};

  static const Set<String> _failedStatuses = {
    'failed',
    'cancelled',
    'refunded',
  };

  static const Set<String> _pendingStatuses = {'pending', 'on-hold'};

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
            _checkUrlForPaymentResult(url);
          },
          onPageFinished: (url) async {
            debugPrint('🌐 PaymentPage finished: $url');
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
                'El pago no se ha completado. Puedes intentarlo de nuevo o volver al pedido.',
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
      );
  }

  Future<void> _startSecurePayment() async {
    if (_paymentStarted) return;

    setState(() {
      _paymentStarted = true;
      _paymentError = false;
      _waitingForConfirmation = false;
      _openedExternalPayment = false;
      _errorMessage = null;
      _progress = 0;
    });

    await _controller.loadRequest(Uri.parse(widget.paymentUrl));
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
        lower.contains('thank-you') ||
        lower.contains('thankyou') ||
        lower.contains('pago-correcto') ||
        lower.contains('payment_success');
  }

  bool _isFailureUrl(String url) {
    final lower = url.toLowerCase();

    return lower.contains('cancel_order') ||
        lower.contains('payment_failed') ||
        lower.contains('pago-fallido') ||
        lower.contains('pago_fallido') ||
        lower.contains('redsys_ko') ||
        lower.contains('order_cancelled') ||
        lower.contains('cancelado');
  }

  bool _shouldOpenExternally(String url) {
    final lower = url.toLowerCase();

    if (lower.startsWith('about:blank')) return false;

    if (lower.startsWith('tel:') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('whatsapp:') ||
        lower.startsWith('intent:') ||
        lower.startsWith('market:')) {
      return true;
    }

    // Redsys, WooCommerce y los bancos trabajan por HTTPS: se quedan dentro
    // de la WebView para que el pago sea más limpio y profesional.
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return false;
    }

    return true;
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      final uri = Uri.parse(url);

      if (!mounted) return;

      setState(() {
        _openedExternalPayment = true;
        _paymentError = false;
        _waitingForConfirmation = true;
        _errorMessage = null;
      });

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _markPaymentError('No se pudo abrir la ventana externa solicitada por la pasarela.');
      }
    } catch (e) {
      debugPrint('❌ Error abriendo URL externa: $e');

      if (mounted) {
        _markPaymentError('No se pudo abrir la ventana externa solicitada por la pasarela.');
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
        'El pago no se ha completado. Puedes intentarlo de nuevo o volver al pedido.',
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

      final order = await ApiService().getOrderStatus(
        orderId: widget.orderId,
        orderKey: widget.orderKey,
      );

      if (!mounted) return;

      if (order == null) {
        setState(() {
          _checkingPayment = false;
          _paymentError = true;
          _errorMessage = 'No se pudo comprobar el estado del pedido. Intenta de nuevo.';
        });
        return;
      }

      final status = order['status']?.toString().toLowerCase().trim() ?? '';
      final isPaid = order['is_paid'] == true;
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
          _errorMessage = 'La verificación del pedido no coincide. Contacta con MundiCam.';
        });
        return;
      }

      if (isPaid || _paidStatuses.contains(status)) {
        _markPaymentSuccess();
        return;
      }

      if (_failedStatuses.contains(status)) {
        _markPaymentError('El pago aparece como no completado.');
        return;
      }

      if (_pendingStatuses.contains(status)) {
        setState(() {
          _checkingPayment = false;
          _waitingForConfirmation = showPendingAsWaiting;
          _paymentError = !showPendingAsWaiting;
          _errorMessage = showPendingAsWaiting
              ? null
              : 'El pedido todavía aparece pendiente de pago. Si acabas de pagar, espera unos segundos y pulsa “Comprobar pago”.';
        });
        return;
      }

      setState(() {
        _checkingPayment = false;
        _paymentError = true;
        _errorMessage =
            'El pago todavía no aparece confirmado. Si ya has pagado, pulsa “Comprobar pago” en unos segundos.';
      });
    } catch (e) {
      debugPrint('❌ Error verificando pago: $e');

      if (!mounted) return;

      setState(() {
        _checkingPayment = false;
        _paymentError = true;
        _errorMessage = 'No se pudo comprobar el estado del pago. Intenta de nuevo.';
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

  String _publicPaymentMessage(String message) {
    final limpio = message.trim();
    if (limpio.isEmpty) return 'No se pudo completar el pago.';

    final lower = limpio.toLowerCase();
    final esTecnico = lower.contains('backend') ||
        lower.contains('endpoint') ||
        lower.contains('woocommerce') ||
        lower.contains('wordpress') ||
        lower.contains('php') ||
        lower.contains('/order') ||
        lower.contains('/shipping') ||
        lower.contains('json') ||
        lower.contains('dioexception') ||
        lower.contains('exception:') ||
        lower.contains('app api');

    if (esTecnico) {
      debugPrint('Payment mensaje interno ocultado al cliente: $limpio');
      return 'No se pudo confirmar el pago en este momento. Inténtalo de nuevo o contacta con MundiCam.';
    }

    return limpio;
  }

  void _markPaymentError(String message) {
    if (!mounted || _paymentSuccess) return;

    setState(() {
      _paymentError = true;
      _checkingPayment = false;
      _waitingForConfirmation = false;
      _errorMessage = _publicPaymentMessage(message);
    });
  }

  Future<void> _reloadPaymentPage() async {
    setState(() {
      _paymentStarted = true;
      _paymentError = false;
      _errorMessage = null;
      _waitingForConfirmation = false;
      _checkingPayment = false;
      _progress = 0;
    });

    await _controller.loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<bool> _confirmExitPayment() async {
    if (!mounted) return true;

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salir del pago'),
        content: const Text(
          'El pedido ya está creado, pero el pago todavía no se ha confirmado. '
          'Podrás finalizarlo desde la web o contactando con MundiCam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir pagando'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  Future<bool> _handleBack() async {
    if (_paymentSuccess) {
      Navigator.of(context).pop(true);
      return false;
    }

    if (!_paymentStarted) {
      Navigator.of(context).pop(false);
      return false;
    }

    final canGoBack = await _controller.canGoBack();

    if (!mounted) return false;

    if (canGoBack) {
      await _controller.goBack();
      return false;
    }

    final shouldExit = await _confirmExitPayment();
    if (shouldExit && mounted) {
      Navigator.of(context).pop(false);
    }

    return false;
  }

  String _formatAmount(double? value) {
    if (value == null) return 'Pendiente de confirmar';
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  String get _orderLabel {
    final number = widget.orderNumber?.trim();
    if (number != null && number.isNotEmpty) return '#$number';
    return '#${widget.orderId}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'PAGO SEGURO',
            style: TextStyle(fontWeight: FontWeight.w800, fontFamily: 'Oswald'),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async => _handleBack(),
          ),
          actions: [
            if (_paymentStarted && !_paymentSuccess)
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
                onPressed: _checkingPayment
                    ? null
                    : () => _verifyOrderPaymentStatus(),
              ),
            if (_paymentStarted && !_paymentSuccess)
              IconButton(
                tooltip: 'Recargar pasarela',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _reloadPaymentPage,
              ),
          ],
        ),
        body: _paymentSuccess
            ? _buildSuccessState()
            : !_paymentStarted
                ? _buildIntroState()
                : _buildPaymentWebViewState(),
      ),
    );
  }

  Widget _buildIntroState() {
    return SafeArea(
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MundiCam',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Pago seguro con tarjeta',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  _formatAmount(widget.amount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pedido $_orderLabel · ${widget.paymentMethodTitle}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Antes de continuar',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSecurityBullet(
                  Icons.security_rounded,
                  'El pago se realiza en una pasarela bancaria segura.',
                ),
                _buildSecurityBullet(
                  Icons.credit_card_off_rounded,
                  'MundiCam no guarda ni procesa los datos de tu tarjeta en la app.',
                ),
                _buildSecurityBullet(
                  Icons.verified_user_outlined,
                  'Tu banco puede solicitar autenticación 3D Secure para confirmar la operación.',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startSecurePayment,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Pagar ahora'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Volver al checkout'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityBullet(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentWebViewState() {
    return Column(
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
          child: ClipRect(
            child: WebViewWidget(controller: _controller),
          ),
        ),
      ],
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
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pedido $_orderLabel · ${_formatAmount(widget.amount)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey),
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
              'El banco ha solicitado una ventana externa. Al terminar, vuelve a la app y pulsa “Comprobar pago”.',
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
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.hourglass_top_rounded,
            color: Colors.amber.shade800,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Estamos esperando la confirmación de la pasarela de pago. Si ya has pagado, pulsa “Comprobar pago”.',
              style: TextStyle(
                color: Colors.amber.shade900,
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
                      source: 'waiting_notice_button',
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
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 20),
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
            onPressed: _reloadPaymentPage,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green.shade700,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Pago confirmado',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'El pedido $_orderLabel se ha recibido correctamente. Te enviaremos la confirmación por email.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Volver al inicio'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
}
