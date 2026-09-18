import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/chatbox.dart';
import 'package:mundicam/features/home/presentation/widgets/header.dart';
import 'package:mundicam/features/home/presentation/widgets/search_bar.dart';
import 'package:mundicam/features/home/presentation/widgets/menu_bar.dart';
import 'package:mundicam/features/home/presentation/widgets/category_grid.dart';
import 'package:mundicam/features/home/presentation/widgets/brand_grid.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/cache/home_warmup_state.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/features/home/presentation/providers/banner_mix_provider.dart';
import 'package:mundicam/features/company/presentation/pages/empresa_page.dart';
import 'package:mundicam/features/promotions/presentation/providers/promotions_provider.dart';
import 'package:mundicam/features/promotions/presentation/widgets/promotions_banner.dart';
import 'package:mundicam/features/training/presentation/providers/academy_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const HomePage({
    super.key,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _showSecondaryContent = false;
  bool _showChatBox = false;
  bool _showBrands = false;

  final GlobalKey _homeStackKey = GlobalKey();
  final GlobalKey _footerKey = GlobalKey();
  final GlobalKey _footerTitleKey = GlobalKey();
  final ScrollController _homeScrollController = ScrollController();

  double _chatBottomOffset = 16;
  final ApiService _apiService = ApiService();
  String _managerName = '';
  String _managerEmail = '';
  String _managerPhone = '';
  bool _didLogFirstBuild = false;
  bool _academyPreloadStarted = false;

  // La pantalla completa de preparación se usa una sola vez por instalación.
  // En esa primera ejecución esperamos categorías, promociones y Academy. Cuando
  // las tres fuentes han terminado, se guarda un marcador local y los siguientes
  // arranques muestran Home directamente mientras cualquier refresco ocurre en
  // segundo plano.
  bool _initialHomeReady = HomeWarmupState.completed;
  bool _initialBootstrapRetryScheduled = false;
  int _initialBootstrapRetryCount = 0;
  static const int _maxInitialBootstrapRetries = 4;

  static const Color _pageBg = Colors.white;
  static const Color _footerBg = Color(0xFFEAF0F6);
  static const Color _footerBlack = Color(0xFF111827);
  static const Color _footerMuted = Color(0xFF5F6B7A);

  @override
  void initState() {
    super.initState();
    debugPrint('🍎 HOMEPAGE_INIT');
    _loadManagerContact();
    _homeScrollController.addListener(_handleHomeScroll);

    if (_initialHomeReady) {
      _startAcademyPreloadAfterHomeReady();
    }

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _showSecondaryContent = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateChatFooterLimit();
      });
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => _showChatBox = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateChatFooterLimit();
      });
    });
  }


  void _startAcademyPreloadAfterHomeReady() {
    if (_academyPreloadStarted) return;
    _academyPreloadStarted = true;

    // Academy se precarga solo DESPUÉS de que las categorías esenciales de
    // Inicio estén listas. Así nunca compite con la primera carga del catálogo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(academyProvider.notifier);
    });
  }

  void _handleHomeScroll() {
    if (!_homeScrollController.hasClients || !mounted) return;
    _updateChatFooterLimit();
  }

  void _updateChatFooterLimit() {
    if (!mounted) return;

    final stackContext = _homeStackKey.currentContext;
    final footerContext = _footerKey.currentContext;

    if (stackContext == null || footerContext == null) {
      if ((_chatBottomOffset - 16).abs() > 0.5) {
        setState(() => _chatBottomOffset = 16);
      }
      return;
    }

    final stackBox = stackContext.findRenderObject();
    final footerBox = footerContext.findRenderObject();

    if (stackBox is! RenderBox ||
        footerBox is! RenderBox ||
        !stackBox.hasSize ||
        !footerBox.hasSize) {
      return;
    }

    final stackTop = stackBox.localToGlobal(Offset.zero).dy;
    final footerTop = footerBox.localToGlobal(Offset.zero).dy;
    final footerTopInsideStack = footerTop - stackTop;

    // Cuando el footer entra en pantalla, el ChatBox se alinea con la fila
    // superior del footer (logo a la izquierda, chat a la derecha), igual que
    // en el diseño de referencia. Mantiene siempre 164x60 y nunca tapa el logo.
    const defaultBottom = 16.0;
    const chatHeight = 60.0;
    const footerTopInset = 12.0;

    final desiredChatTop = footerTopInsideStack + footerTopInset;
    final alignedBottom =
        stackBox.size.height - desiredChatTop - chatHeight;

    final footerIsVisible = footerTopInsideStack < stackBox.size.height;
    final nextBottom = footerIsVisible && alignedBottom > 0
        ? alignedBottom
        : defaultBottom;

    if ((nextBottom - _chatBottomOffset).abs() > 0.5) {
      setState(() => _chatBottomOffset = nextBottom);
    }
  }

  @override
  void dispose() {
    _homeScrollController.removeListener(_handleHomeScroll);
    _homeScrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshHome() async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(homeBrandsProvider);
    ref.invalidate(promotionsProvider);
    ref.invalidate(bannerMixProvider);
    await _loadManagerContact();
    await Future.delayed(const Duration(milliseconds: 350));
  }

  Future<void> _openFooterLink(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      debugPrint('No se pudo abrir: $uri');
    }
  }

  void _openCompanyPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const EmpresaPage(),
      ),
    );
  }

  void _scheduleInitialBootstrapRetry() {
    if (_initialHomeReady ||
        _initialBootstrapRetryScheduled ||
        _initialBootstrapRetryCount >= _maxInitialBootstrapRetries) {
      return;
    }

    _initialBootstrapRetryScheduled = true;
    final retryNumber = _initialBootstrapRetryCount + 1;

    Future.delayed(Duration(milliseconds: 900 * retryNumber), () {
      if (!mounted || _initialHomeReady) return;

      _initialBootstrapRetryScheduled = false;
      _initialBootstrapRetryCount = retryNumber;
      ref.invalidate(categoriesProvider);
      ref.invalidate(promotionsProvider);
      ref.read(academyProvider.notifier).retry();
    });
  }

  void _retryInitialHome() {
    _initialBootstrapRetryScheduled = false;
    _initialBootstrapRetryCount = 0;
    ref.invalidate(categoriesProvider);
    ref.invalidate(promotionsProvider);
    ref.read(academyProvider.notifier).retry();
    setState(() {});
  }

  void _completeInitialHomeWarmup() {
    if (_initialHomeReady) return;

    _initialHomeReady = true;
    _initialBootstrapRetryScheduled = false;
    HomeWarmupState.markComplete();
    _startAcademyPreloadAfterHomeReady();
  }

  Widget _buildInitialHomeLoading() {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 160,
                  child: Image(
                    image: AssetImage('assets/logo.png'),
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(height: 30),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialHomeRetry() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 160,
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Estamos preparando el inicio',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La conexión está tardando más de lo habitual.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5F6B7A),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _retryInitialHome,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: const Text('Reintentar'),
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
    if (!_didLogFirstBuild) {
      _didLogFirstBuild = true;
      debugPrint('🍎 HOMEPAGE_BUILD');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('🍎 HOMEPAGE_FIRST_FRAME');
      });
    }

    // Gate solo de la PRIMERA preparación de esta instalación.
    // Fase 1: categorías. Cuando están listas, arrancamos Promociones + Academy
    // sin competir con la consulta esencial del catálogo. Fase 2: esperamos a
    // que ambas fuentes terminen (pueden devolver listas vacías legítimamente).
    // Después se persiste el marcador y esta pantalla completa no vuelve a salir.
    if (!_initialHomeReady) {
      final categoriesAsync = ref.watch(categoriesProvider);
      final categories = categoriesAsync.asData?.value;
      final categoriesReady = categories != null && categories.isNotEmpty;

      if (!categoriesReady) {
        if (categoriesAsync.hasError) {
          _scheduleInitialBootstrapRetry();
        }

        return _initialBootstrapRetryCount < _maxInitialBootstrapRetries
            ? _buildInitialHomeLoading()
            : _buildInitialHomeRetry();
      }

      final promotionsAsync = ref.watch(promotionsProvider);
      final academyAsync = ref.watch(academyProvider);

      final promotionsReady = promotionsAsync.hasValue;
      final academyReady = academyAsync.hasValue;

      if (promotionsAsync.hasError || academyAsync.hasError) {
        _scheduleInitialBootstrapRetry();
      }

      if (!promotionsReady || !academyReady) {
        return _initialBootstrapRetryCount < _maxInitialBootstrapRetries
            ? _buildInitialHomeLoading()
            : _buildInitialHomeRetry();
      }

      _completeInitialHomeWarmup();
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            key: _homeStackKey,
            children: [
              RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _refreshHome,
                child: SingleChildScrollView(
                  controller: _homeScrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopPanel(),
                      const SizedBox(height: 22),
                      _buildCatalogSelector(),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _showBrands
                            ? BrandGrid(
                                key: const ValueKey('home-brands'),
                                onGoCart: widget.onGoCart,
                                onGoQuotes: widget.onGoQuotes,
                              )
                            : CategoryGrid(
                                key: const ValueKey('home-categories'),
                                onGoCart: widget.onGoCart,
                                onGoQuotes: widget.onGoQuotes,
                              ),
                      ),
                      if (_showSecondaryContent) ...[
                        const SizedBox(height: 22),
                        _buildNewsPanel(),
                        _buildMundicamFooter(),
                      ] else ...[
                        const SizedBox(height: 22),
                        _buildNewsSkeletonPanel(),
                        _buildSkeletonBlock(height: 150),
                      ],
                    ],
                  ),
                ),
              ),
              if (_showChatBox)
                ChatBox(
                  bottomOffset: _chatBottomOffset,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadManagerContact() async {
    try {
      final user = await _apiService.currentSessionUser();
      if (!mounted || user.isEmpty) return;

      final managerRaw = user['manager'];
      final manager = managerRaw is Map
          ? Map<String, dynamic>.from(managerRaw)
          : const <String, dynamic>{};

      String firstValid(Iterable<dynamic> values, {bool email = false}) {
        for (final value in values) {
          final clean = value?.toString().trim() ?? '';
          if (clean.isEmpty || clean == '—' || clean.toLowerCase() == 'null') {
            continue;
          }
          if (email && !clean.contains('@')) continue;
          return clean;
        }
        return '';
      }

      final managerName = firstValid([
        manager['name'],
        user['manager_name'],
        user['assigned_manager'],
        user['gestor_asignado'],
        user['wpuef_cid_c30'],
      ]);

      var managerEmail = firstValid([
        manager['email'],
        user['manager_email'],
        user['assigned_manager_email'],
        user['gestor_email'],
      ], email: true);

      var managerPhone = firstValid([
        manager['phone'],
        user['manager_phone'],
        user['assigned_manager_phone'],
        user['gestor_phone'],
      ]);

      if ((managerEmail.isEmpty || managerPhone.isEmpty) &&
          managerName.isNotEmpty) {
        final fallback = _localManagerContact(managerName);
        managerEmail =
            managerEmail.isNotEmpty ? managerEmail : (fallback?['email'] ?? '');
        managerPhone =
            managerPhone.isNotEmpty ? managerPhone : (fallback?['phone'] ?? '');
      }

      final normalizedManagerName = managerName.trim().toLowerCase();
      if (normalizedManagerName == 'ricardo') {
        managerPhone = '+34 968 629 383';
        managerEmail = 'pedidos@mundicam.com';
      }

      if (!mounted) return;
      setState(() {
        _managerName = managerName;
        _managerEmail = managerEmail;
        _managerPhone = managerPhone;
      });
    } catch (_) {
      // El contacto del gestor es informativo: un fallo puntual no bloquea Inicio.
    }
  }

  Map<String, String>? _localManagerContact(String managerName) {
    final key = managerName
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const contacts = <String, Map<String, String>>{
      'damian mateo': {
        'email': 'dmateo@mundicam.com',
        'phone': '633806898',
      },
      'juan garcia': {
        'email': 'jgarcia@mundicam.com',
        'phone': '622943654',
      },
      'manuel': {
        'email': 'mreynaldo@mundicam.com',
        'phone': '619078632',
      },
      'proshop murcia': {
        'email': 'proshop.murcia@mundicam.com',
        'phone': '616545669',
      },
      'ricardo': {
        'email': 'pedidos@mundicam.com',
        'phone': '+34 968 629 383',
      },
    };

    return contacts[key];
  }

  Widget _buildCatalogSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E8EE)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _catalogSelectorTab(
                label: 'CATEGORÍAS',
                selected: !_showBrands,
                onTap: () {
                  if (_showBrands) {
                    setState(() => _showBrands = false);
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _catalogSelectorTab(
                label: 'MARCAS',
                selected: _showBrands,
                onTap: () {
                  if (!_showBrands) {
                    setState(() => _showBrands = true);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogSelectorTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.055),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              color: selected ? Colors.white : Colors.black,
              fontSize: 14.5,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontFamily: 'Oswald',
              letterSpacing: 0.75,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Widget _buildTopPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const HomeHeader(),
          const SizedBox(height: 2),
          SearchBarWidget(
            onGoCart: widget.onGoCart,
            onGoQuotes: widget.onGoQuotes,
          ),
          const MenuBarWidget(),
        ],
      ),
    );
  }

  Widget _buildNewsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('PROMOCIONES'),
          const SizedBox(height: 12),
          const PromotionsBanner(),
        ],
      ),
    );
  }

  Widget _buildNewsSkeletonPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSectionTitle('PROMOCIONES'),
          const SizedBox(height: 12),
          _buildSkeletonBlock(height: 248),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: 1.1,
                fontFamily: 'Oswald',
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonBlock({required double height}) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
    );
  }

  Widget _buildMundicamFooter() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoHeight = (screenWidth * 0.108).clamp(42.0, 58.0).toDouble();
    final logoMaxWidth = (screenWidth * 0.52).clamp(160.0, 260.0).toDouble();

    return Container(
      key: _footerKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: const BoxDecoration(
        color: _footerBg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reservamos físicamente la zona derecha del ChatBox. Así, aunque
          // el dispositivo sea estrecho o tenga escalado de texto alto, el logo
          // de MundiCam nunca queda debajo del chat.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: logoMaxWidth),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(
                      'assets/logo.png',
                      height: logoHeight,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const SizedBox(
                width: 164,
                height: 60,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'MundiCam Security Distribution',
            key: _footerTitleKey,
            style: const TextStyle(
              fontFamily: 'Oswald',
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Distribución profesional de seguridad electrónica para instaladores, integradores e ingenierías.',
            style: TextStyle(
              fontSize: 12.2,
              height: 1.32,
              color: _footerMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 11),
          if (_managerName.isNotEmpty) ...[
            Text(
              'Tu gestor: ${_managerName.toUpperCase()}',
              style: const TextStyle(
                fontSize: 11.8,
                color: _footerMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
          ],
          _footerContactRow(
            icon: Icons.phone_outlined,
            text: _managerPhone.isNotEmpty
                ? _managerPhone
                : 'Teléfono disponible en tu perfil',
            color: _footerBlack,
            onTap: _managerPhone.isNotEmpty
                ? () => _openFooterLink(
                      Uri(scheme: 'tel', path: _managerPhone),
                    )
                : null,
          ),
          _footerContactRow(
            icon: Icons.email_outlined,
            text: _managerEmail.isNotEmpty
                ? _managerEmail
                : 'Email disponible en tu perfil',
            color: _footerBlack,
            onTap: _managerEmail.isNotEmpty
                ? () => _openFooterLink(
                      Uri(
                        scheme: 'mailto',
                        path: _managerEmail,
                        queryParameters: const <String, String>{
                          'subject': 'Consulta desde App MundiCam',
                        },
                      ),
                    )
                : null,
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _footerWebButton(
                  onTap: () => _openFooterLink(
                    Uri.parse('https://www.mundicam.com'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _footerCompanyButton(
                  onTap: _openCompanyPage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footerCompanyButton({required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD8E0E8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.business_outlined,
                size: 15,
                color: AppColors.textPrimary,
              ),
              SizedBox(width: 6),
              Text(
                'Empresa',
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerContactRow({
    IconData? icon,
    Widget? customIcon,
    required String text,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              customIcon ?? Icon(icon, size: 15, color: color),
              const SizedBox(width: 9),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.7,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerWebButton({required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.language_outlined,
                size: 14,
                color: Colors.white,
              ),
              SizedBox(width: 7),
              Text(
                'Ir a la web',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Oswald',
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.open_in_new_rounded,
                size: 13,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
