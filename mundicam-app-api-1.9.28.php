<?php
/**
 * Plugin Name: MundiCam App API
 * Description: API puente completa para la app MundiCam. Versión fusionada segura con roles reales y prioridad de comerciales antes de capacidades admin/gestión. v1.9.0: precio efectivo por rol en creación de pedidos, validación expected_total, idempotencia y endurecimiento de estados (preview/status).
 * Version: 1.9.28-presupuestos-pago-redsys-envio-350
 * Author: MundiCam
 */

if (!defined('ABSPATH')) {
    exit;
}

final class Mundicam_App_API {
    const VERSION = '1.9.28-presupuestos-pago-redsys-envio-350';
    const NAMESPACE = 'mundicam-app/v1';
    const ORDER_IDEMPOTENCY_META_KEY = '_mundicam_app_idempotency_key';
    const ORDER_LOCK_OPTION_PREFIX = 'mundicam_app_order_lock_';
    const ORDER_LOCK_TTL = 60; // Segundos: un lock más viejo se considera huérfano.
    const ORDER_TOTAL_TOLERANCE = 0.03; // Tolerancia máxima app vs WooCommerce en euros.
    const TOKEN_META_KEY = '_mundicam_app_tokens_v1';
    const TOKEN_INDEX_OPTION = 'mundicam_app_token_index_v1';
    const TOKEN_TTL = 2592000; // 30 días.
    const TOKEN_TRANSIENT_PREFIX = 'mundicam_app_token_';
    const ACCOUNT_DELETION_PENDING_META = '_mundicam_account_deletion_pending';
    const ACCOUNT_DELETION_REQUEST_META = '_mundicam_account_deletion_request_v1';
    const CART_META_KEY = '_mundicam_app_cart_v1';
    const QUOTE_CART_META_KEY = '_mundicam_app_quote_cart_v1';
    const LOGIN_RATE_LIMIT_PREFIX = 'mundicam_app_login_';
    const LOGIN_RATE_LIMIT_TTL = 900; // 15 minutos.
    const LOGIN_RATE_LIMIT_MAX = 8;
    const FREE_SHIPPING_MIN_AMOUNT = 350.0;
    const APP_PAYMENT_BRIDGE_TRANSIENT_PREFIX = 'mundicam_app_payment_bridge_';
    const APP_PAYMENT_BRIDGE_TTL = 600; // 10 minutos.

    /**
     * Usuario real autenticado por el token de la app durante la petición REST.
     * Se usa para resolver precios por rol sin depender de sesiones/cachés de WooCommerce.
     */
    private static $current_app_user_id = 0;

    public static function init() {
        add_action('rest_api_init', [__CLASS__, 'register_routes']);
        add_action('template_redirect', [__CLASS__, 'handle_app_payment_bridge'], 0);
        add_action('wp_footer', [__CLASS__, 'render_app_autopay_script'], 99);
        self::init_deletion_hooks();
        add_action('mundicam_account_deletion_email_retry', [__CLASS__, 'retry_account_deletion_email'], 10, 2);
    }

    public static function register_routes() {
        register_rest_route(self::NAMESPACE, '/login', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'login'],
            'permission_callback' => '__return_true',
        ]);

        register_rest_route(self::NAMESPACE, '/logout', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'logout'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/me', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'me'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/categories', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'categories'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/brands', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'brands'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route('mundicam/v1', '/brands', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'brands'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/products', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'products'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/products/(?P<id>\d+)', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'product_detail'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.9: búsqueda eficiente rankeada por relevancia (SKU exacto -> título
        // -> marca/categoría -> parcial). Una sola pasada, sin sobre-expansión.
        register_rest_route(self::NAMESPACE, '/products/search', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'products_search'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/cart/add', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'cart_add'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/cart', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'cart_get'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/cart/update', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'cart_update'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/cart/remove', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'cart_remove'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/cart/clear', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'cart_clear'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/quote/add', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'quote_add'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/quote', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'quote_get'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/quote/update', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'quote_update'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/quote/remove', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'quote_remove'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/quote/clear', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'quote_clear'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/quote/create', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'quote_create'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.27: Aceptar y pagar presupuesto (genera URL de pago sin sacar de /quotes).
        register_rest_route(self::NAMESPACE, '/quote/accept-and-pay', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'quote_accept_and_pay'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/payment-methods', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'payment_methods'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/orders', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'orders'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/quotes', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'quotes'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/order/create', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'order_create'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/order/payment-url', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'order_payment_url'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.0: previsualización de totales (subtotal, IVA, total) con el precio
        // efectivo del rol, ANTES de crear el pedido. Flutter debe usar este total
        // como expected_total en /order/create.
        register_rest_route(self::NAMESPACE, '/order/preview', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'order_preview'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.0: estado real de un pedido concreto tras el pago. La app no debe
        // deducir el estado listando pedidos ni decidirlo por su cuenta.
        register_rest_route(self::NAMESPACE, '/order/status', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'order_status'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.26: detalle completo de pedido/presupuesto (tipo Amazon).
        register_rest_route(self::NAMESPACE, '/order/detail', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'order_detail'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.8: métodos de envío reales de WooCommerce para una dirección/zona.
        register_rest_route(self::NAMESPACE, '/shipping/methods', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'shipping_methods'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.18: validación de cupón contra el carrito, sin crear pedido.
        register_rest_route(self::NAMESPACE, '/cart/coupon/validate', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'coupon_validate'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.22: diagnóstico de envío de correo (aísla PHP vs servidor SMTP).
        register_rest_route(self::NAMESPACE, '/email/test', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'email_test'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // v1.9.27: solicitud de eliminación de cuenta (requerido por Apple).
        register_rest_route(self::NAMESPACE, '/account/delete-request', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'account_delete_request'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/customers', [
            'methods' => 'POST',
            'callback' => [__CLASS__, 'customer_create'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/health', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'health'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // Alias público de diagnóstico rápido. No sustituye a /health usado por la app.
        register_rest_route(self::NAMESPACE, '/status', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'status_public'],
            'permission_callback' => '__return_true',
        ]);

        // Diagnóstico de usuario para comprobar rol real, grupo de precio efectivo y permisos.
        // Protegido: no debe exponer roles/datos de usuario por wp_user_id sin app_token.
        register_rest_route(self::NAMESPACE, '/user-context', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'user_context_public'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        register_rest_route(self::NAMESPACE, '/debug/product-price', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'debug_product_price'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);

        // Alias compatible con el bridge anterior: product_id/wp_user_id.
        // Protegido: devuelve precios por usuario/producto y no debe ser público.
        register_rest_route(self::NAMESPACE, '/debug-price', [
            'methods' => 'GET',
            'callback' => [__CLASS__, 'debug_price_public'],
            'permission_callback' => [__CLASS__, 'permission_app_user'],
        ]);
    }


    public static function health(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_user_by('id', $user_id);

        return rest_ensure_response([
            'success' => true,
            'plugin' => 'MundiCam App API',
            'version' => self::VERSION,
            'namespace' => self::NAMESPACE,
            'user_id' => $user_id,
            'user_login' => $user instanceof WP_User ? $user->user_login : '',
            'roles' => $user instanceof WP_User ? array_values((array) $user->roles) : [],
            'woocommerce_loaded' => function_exists('WC') && function_exists('wc_get_product'),
            'current_user_id' => get_current_user_id(),
        ]);
    }

    public static function status_public(WP_REST_Request $request) {
        return rest_ensure_response([
            'ok' => true,
            'success' => true,
            'plugin' => 'MundiCam App API - Fusionada Admin 52 Compat',
            'version' => self::VERSION,
            'namespace' => self::NAMESPACE,
            'admin_price_group' => '52',
            'woocommerce_active' => class_exists('WooCommerce') && function_exists('wc_get_product'),
            'routes_included' => [
                'login', 'me', 'categories', 'brands', 'products', 'product_detail',
                'cart', 'quote', 'orders', 'payment_methods', 'health', 'debug-price', 'compat-aliases'
            ],
        ]);
    }

    public static function user_context_public(WP_REST_Request $request) {
        $request_user_id = (int) $request->get_param('_mundicam_user_id');
        $request_user = $request_user_id > 0 ? get_user_by('id', $request_user_id) : null;

        $user_id = absint($request->get_param('wp_user_id'));
        if ($user_id <= 0) {
            $user_id = absint($request->get_param('user_id'));
        }
        if ($user_id <= 0) {
            return new WP_Error('mundicam_missing_user', 'Falta wp_user_id.', ['status' => 400]);
        }

        $user = get_user_by('id', $user_id);
        if (!($user instanceof WP_User)) {
            return new WP_Error('mundicam_user_not_found', 'Usuario WordPress no encontrado.', ['status' => 404]);
        }

        if ($request_user_id !== $user_id && !self::can_create_customers($request_user) && !self::can_view_internal_stock($request_user)) {
            return new WP_Error('mundicam_forbidden_user_context', 'No tienes permisos para consultar el contexto de otro usuario.', ['status' => 403]);
        }

        $effective = self::effective_price_role_payload($user);

        return rest_ensure_response([
            'ok' => true,
            'success' => true,
            'wp_user_id' => $user_id,
            'user_login' => $user->user_login,
            'real_roles' => array_values((array) $user->roles),
            'effective_price_group' => isset($effective['forced_price_group']) ? (string) $effective['forced_price_group'] : self::extract_percentage_from_role_payload($effective),
            'effective_price_role' => $effective,
            'can_view_stock' => self::can_view_internal_stock($user),
            'permissions' => self::permissions_payload($user),
            'rule' => 'Admin/Gestor => precio cliente_52_69; Cliente X = Comercial X usando roles reales; permisos separados del precio.',
        ]);
    }

    public static function debug_price_public(WP_REST_Request $request) {
        $request_user_id = (int) $request->get_param('_mundicam_user_id');
        $request_user = $request_user_id > 0 ? get_user_by('id', $request_user_id) : null;
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = absint($request->get_param('wp_user_id'));
        if ($user_id <= 0) {
            $user_id = absint($request->get_param('user_id'));
        }

        $product_id = absint($request->get_param('product_id'));
        if ($product_id <= 0) {
            $product_id = absint($request->get_param('id'));
        }

        if ($user_id <= 0 || $product_id <= 0) {
            return new WP_Error('mundicam_missing_params', 'Faltan wp_user_id y product_id.', ['status' => 400]);
        }

        $user = get_user_by('id', $user_id);
        if (!($user instanceof WP_User)) {
            return new WP_Error('mundicam_user_not_found', 'Usuario WordPress no encontrado.', ['status' => 404]);
        }

        if ($request_user_id !== $user_id && !self::can_create_customers($request_user) && !self::can_view_internal_stock($request_user)) {
            return new WP_Error('mundicam_forbidden_debug_price', 'No tienes permisos para consultar precios de otro usuario.', ['status' => 403]);
        }

        $product = wc_get_product($product_id);
        if (!($product instanceof WC_Product)) {
            return new WP_Error('mundicam_product_not_found', 'Producto no encontrado.', ['status' => 404]);
        }

        $previous_app_user_id = self::$current_app_user_id;
        $previous_current_user_id = get_current_user_id();

        self::$current_app_user_id = $user_id;
        wp_set_current_user($user_id);

        try {
            $price_data = self::resolve_product_price_data($product);
            $payload = self::product_payload($product, self::can_view_internal_stock($user));
        } finally {
            self::$current_app_user_id = $previous_app_user_id;
            if ($previous_current_user_id > 0) {
                wp_set_current_user($previous_current_user_id);
            } else {
                wp_set_current_user(0);
            }
        }

        return rest_ensure_response([
            'ok' => true,
            'success' => true,
            'version' => self::VERSION,
            'wp_user_id' => $user_id,
            'product_id' => $product_id,
            'context' => [
                'wp_user_id' => $user_id,
                'user_login' => $user->user_login,
                'real_roles' => array_values((array) $user->roles),
                'can_view_stock' => self::can_view_internal_stock($user),
            ],
            'effective_price_role' => self::effective_price_role_payload($user),
            'price_data' => $price_data,
            'payload_price' => [
                'price' => $payload['price'] ?? '',
                'regular_price' => $payload['regular_price'] ?? '',
                'display_price' => $payload['display_price'] ?? '',
                'raw_price' => $payload['raw_price'] ?? '',
                'price_html' => $payload['price_html'] ?? '',
                'price_context' => $payload['price_context'] ?? '',
                'price_source' => $payload['price_source'] ?? '',
            ],
            'rule' => 'Admin/Gestor => precio cliente_52_69; Cliente X = Comercial X usando roles reales; permisos separados del precio.',
        ]);
    }

    public static function debug_product_price(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $product_id = absint($request->get_param('id'));
        $sku = sanitize_text_field((string) $request->get_param('sku'));

        if ($product_id <= 0 && $sku !== '') {
            $ids = self::find_product_ids_by_sku($sku);
            if (!empty($ids[0])) {
                $product_id = (int) $ids[0];
            }
        }

        if ($product_id <= 0) {
            return new WP_Error('mundicam_debug_product_missing', 'Indica id o sku de producto.', ['status' => 400]);
        }

        $product = wc_get_product($product_id);
        if (!($product instanceof WC_Product)) {
            return new WP_Error('mundicam_debug_product_not_found', 'Producto no encontrado.', ['status' => 404]);
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_user_by('id', $user_id);
        $can_view_stock = self::can_view_internal_stock($user);
        $price_data = self::resolve_product_price_data($product);
        $payload = self::product_payload($product, $can_view_stock);

        return rest_ensure_response([
            'success' => true,
            'version' => self::VERSION,
            'user_id' => $user_id,
            'roles' => $user instanceof WP_User ? array_values((array) $user->roles) : [],
            'effective_price_role' => self::effective_price_role_payload($user),
            'current_user_id' => get_current_user_id(),
            'product_id' => $product->get_id(),
            'sku' => $product->get_sku(),
            'name' => $product->get_name(),
            'price_data' => $price_data,
            'payload_price' => [
                'price' => $payload['price'] ?? '',
                'regular_price' => $payload['regular_price'] ?? '',
                'display_price' => $payload['display_price'] ?? '',
                'raw_price' => $payload['raw_price'] ?? '',
                'price_html' => $payload['price_html'] ?? '',
                'price_context' => $payload['price_context'] ?? '',
                'price_source' => $payload['price_source'] ?? '',
                'is_purchasable' => $payload['is_purchasable'] ?? false,
                'can_add_to_cart' => $payload['can_add_to_cart'] ?? false,
                'can_request_quote' => $payload['can_request_quote'] ?? false,
            ],
        ]);
    }

    // =============================================================
    // LOGIN / TOKEN APP
    // =============================================================

    public static function login(WP_REST_Request $request) {
        // v1.5.2 LOGIN ULTRA-SAFE + PRECIOS POR ROL
        // Este endpoint NO inicializa WooCommerce, NO carga carrito, NO llama a endpoints internos
        // y NO construye WC_Customer durante el login. Solo autentica WordPress y devuelve token.
        // Objetivo: evitar 503/fatal errors provocados por plugins externos durante /login.
        try {
            $login = sanitize_text_field($request->get_param('email') ?: $request->get_param('username'));
            $password = (string) $request->get_param('password');

            if (empty($login) || empty($password)) {
                return new WP_Error('mundicam_missing_credentials', 'Introduce usuario/email y contraseña.', ['status' => 400]);
            }

            $rate_limit = self::check_login_rate_limit($login);
            if (is_wp_error($rate_limit)) {
                return $rate_limit;
            }

            $user = wp_authenticate($login, $password);

            if (is_wp_error($user)) {
                self::increase_login_rate_limit($login);
                return new WP_Error('mundicam_bad_credentials', 'Usuario o contraseña incorrectos.', ['status' => 401]);
            }

            if (!($user instanceof WP_User) || empty($user->ID)) {
                self::increase_login_rate_limit($login);
                return new WP_Error('mundicam_bad_user', 'Usuario no válido.', ['status' => 401]);
            }

            $roles = array_values((array) $user->roles);
            $is_blocked = false;
            foreach ($roles as $role) {
                $normalized = self::normalize_role($role);
                if ($normalized === 'blockedcustomer' || $normalized === 'blocked') {
                    $is_blocked = true;
                    break;
                }
            }

            if ($is_blocked) {
                self::increase_login_rate_limit($login);
                return new WP_Error('mundicam_blocked_user', 'Cuenta pendiente de validación o bloqueada.', ['status' => 403]);
            }

            // v1.9.27 Bloquear login si la cuenta tiene eliminación pendiente.
            if (get_user_meta($user->ID, self::ACCOUNT_DELETION_PENDING_META, true) === '1') {
                return new WP_Error('mundicam_account_deletion_pending', 'Esta cuenta tiene una solicitud de eliminación pendiente y no puede iniciar sesión.', ['status' => 403]);
            }

            self::clear_login_rate_limit($login);

            $token = self::create_app_token((int) $user->ID);

            if (function_exists('wp_set_current_user')) {
                wp_set_current_user((int) $user->ID);
            }

            $can_view_stock = false;
            $can_create_customers = false;
            foreach ($roles as $role) {
                $normalized = self::normalize_role($role);
                if ($normalized === 'admin' || $normalized === 'administrator' || $normalized === 'administrador' || $normalized === 'shopmanager' || $normalized === 'gestordelatienda' || strpos($normalized, 'comercial') === 0) {
                    $can_view_stock = true;
                }
                if ($normalized === 'admin' || $normalized === 'administrator' || $normalized === 'administrador' || $normalized === 'shopmanager' || $normalized === 'gestordelatienda' || strpos($normalized, 'comercial') === 0) {
                    $can_create_customers = true;
                }
            }

            // user_can puede activar lógica de plugins, por eso se ejecuta dentro de try/catch y no es imprescindible.
            try {
                if (user_can($user, 'manage_options') || user_can($user, 'manage_woocommerce')) {
                    $can_view_stock = true;
                    $can_create_customers = true;
                }
            } catch (Throwable $e) {
                // Ignorar: el rol textual ya cubre admin/comercial.
            }

            $cif_nif = '';
            try {
                $cif_nif = self::get_user_cif_nif((int) $user->ID);
            } catch (Throwable $e) {
                $cif_nif = '';
            }

            $response = [
                'success' => true,
                'message' => 'Login correcto.',
                'app_token' => $token,
                'cart_token' => $token,
                'session' => [
                    'app_token' => $token,
                    'cart_token' => $token,
                ],
                'user' => [
                    'id' => (int) $user->ID,
                    'wordpress_id' => (int) $user->ID,
                    'woocommerce_id' => (int) $user->ID,
                    'email' => (string) $user->user_email,
                    'name' => (string) $user->display_name,
                    'display_name' => (string) $user->display_name,
                    'first_name' => (string) get_user_meta((int) $user->ID, 'first_name', true),
                    'last_name' => (string) get_user_meta((int) $user->ID, 'last_name', true),
                    'role' => isset($roles[0]) ? (string) $roles[0] : '',
                    'roles' => $roles,
                    'billing_nif' => $cif_nif,
                    'cif_nif' => $cif_nif,
                    'nif' => $cif_nif,
                    'customer_tax_id' => $cif_nif,
                    'billing' => [
                        'email' => (string) $user->user_email,
                        'billing_nif' => $cif_nif,
                        'cif_nif' => $cif_nif,
                    ],
                    'shipping' => [],
                    'meta_data' => [],
                ],
                'permissions' => [
                    'can_view_prices' => true,
                    'can_buy' => true,
                    'can_create_quotes' => true,
                    'can_view_stock_details' => $can_view_stock,
                    'can_view_stock' => $can_view_stock,
                    'can_create_customers' => $can_create_customers,
                    'is_blocked' => false,
                ],
                'credit' => self::credit_payload((int) $user->ID),
                'woocommerce' => [
                    'app_token' => $token,
                    'cart_token' => $token,
                ],
                'api_version' => self::VERSION,
                'login_mode' => 'ultra_safe',
            ];

            /*
             * Firebase opcional sin depender del plugin mundicam-firebase-auth.
             * No inicializa WooCommerce ni llama al endpoint legado durante /login.
             */
            try {
                $firebase_token = self::create_firebase_custom_token_for_user($user);
                if (!empty($firebase_token)) {
                    $response['firebase_token'] = $firebase_token;
                    $response['firebase_mode'] = 'direct_custom_token';
                } else {
                    $response['firebase_mode'] = 'not_configured';
                }
            } catch (Throwable $e) {
                $response['firebase_mode'] = 'error';
                if (function_exists('error_log')) {
                    error_log('[MundiCam App API] Firebase directo omitido: ' . $e->getMessage());
                }
            }

            $rest_response = rest_ensure_response($response);
            if ($rest_response instanceof WP_REST_Response) {
                $rest_response->header('Cache-Control', 'no-store, no-cache, must-revalidate');
                $rest_response->header('Pragma', 'no-cache');
            }

            return $rest_response;
        } catch (Throwable $e) {
            if (function_exists('error_log')) {
                error_log('[MundiCam App API] Login ultra-safe error: ' . $e->getMessage());
            }

            return new WP_Error(
                'mundicam_login_server_error',
                'Error interno en login App API: ' . $e->getMessage(),
                ['status' => 500]
            );
        }
    }

    public static function logout(WP_REST_Request $request) {
        $token = self::get_request_token($request);
        $user_id = (int) $request->get_param('_mundicam_user_id');

        // v1.9.21 Si la app envía su fcm_token al cerrar sesión, se retira el
        // dispositivo antes de revocar la sesión para dejar de recibir pushes de
        // los pedidos de esta cuenta en ese móvil.
        $fcm_token = sanitize_text_field((string) $request->get_param('fcm_token'));
        if ($fcm_token !== '' && $user_id > 0 && function_exists('mundicam_fcm_detach_token')) {
            mundicam_fcm_detach_token($fcm_token, $user_id);
            if (function_exists('mundicam_fcm_index_remove')) {
                mundicam_fcm_index_remove($fcm_token);
            }
        }

        if (!empty($token) && $user_id > 0) {
            self::revoke_app_token($user_id, $token);
        }

        return rest_ensure_response([
            'success' => true,
            'message' => 'Sesión cerrada correctamente.',
        ]);
    }

    private static function check_login_rate_limit($login) {
        $key = self::login_rate_limit_key($login);
        $data = get_transient($key);

        if (is_array($data) && isset($data['count']) && (int) $data['count'] >= self::LOGIN_RATE_LIMIT_MAX) {
            return new WP_Error(
                'mundicam_login_rate_limited',
                'Demasiados intentos de acceso. Espera unos minutos antes de volver a intentarlo.',
                ['status' => 429]
            );
        }

        return true;
    }

    private static function increase_login_rate_limit($login) {
        $key = self::login_rate_limit_key($login);
        $data = get_transient($key);
        if (!is_array($data)) {
            $data = ['count' => 0, 'first' => time()];
        }
        $data['count'] = (int) $data['count'] + 1;
        set_transient($key, $data, self::LOGIN_RATE_LIMIT_TTL);
    }

    private static function clear_login_rate_limit($login) {
        delete_transient(self::login_rate_limit_key($login));
    }

    private static function login_rate_limit_key($login) {
        $ip = isset($_SERVER['REMOTE_ADDR']) ? sanitize_text_field(wp_unslash($_SERVER['REMOTE_ADDR'])) : 'unknown';
        return self::LOGIN_RATE_LIMIT_PREFIX . md5(strtolower(trim((string) $login)) . '|' . $ip);
    }

    private static function get_firebase_token_from_existing_endpoint($login, $password) {
        // Reutiliza el endpoint que ya tenéis para generar custom token Firebase.
        // Si no existe o falla, la app podrá usar Firebase con el flujo que ya tenga definido.
        if (!function_exists('rest_do_request')) {
            return '';
        }

        // Si el endpoint legado no existe, no bloqueamos el login de la app.
        try {
            if (function_exists('rest_get_server')) {
                $routes = rest_get_server()->get_routes();
                if (!is_array($routes) || !isset($routes['/mundicam/v1/firebase-login'])) {
                    return '';
                }
            }
        } catch (Throwable $e) {
            return '';
        }

        $internal = new WP_REST_Request('POST', '/mundicam/v1/firebase-login');
        $internal->set_body_params([
            'email' => $login,
            'username' => $login,
            'password' => $password,
        ]);

        try {
            $result = rest_do_request($internal);
        } catch (Throwable $e) {
            if (function_exists('error_log')) {
                error_log('[MundiCam App API] Firebase login interno omitido: ' . $e->getMessage());
            }
            return '';
        }

        if ($result instanceof WP_Error) {
            return '';
        }

        if (!($result instanceof WP_REST_Response)) {
            return '';
        }

        $data = $result->get_data();
        if (!is_array($data)) {
            return '';
        }

        return isset($data['firebase_token']) ? sanitize_text_field($data['firebase_token']) : '';
    }

    private static function create_app_token($user_id) {
        try {
            $plain = bin2hex(random_bytes(32));
        } catch (Throwable $e) {
            $plain = wp_generate_password(64, false, false) . wp_generate_uuid4();
        }

        $hash = hash('sha256', $plain);
        $now = time();
        $expires = $now + self::TOKEN_TTL;

        $tokens = get_user_meta($user_id, self::TOKEN_META_KEY, true);
        if (!is_array($tokens)) {
            $tokens = [];
        }

        $tokens = array_values(array_filter($tokens, function($item) use ($now) {
            return is_array($item) && !empty($item['hash']) && !empty($item['expires']) && (int) $item['expires'] > $now;
        }));

        $tokens[] = [
            'hash' => $hash,
            'created' => $now,
            'expires' => $expires,
            'user_agent' => isset($_SERVER['HTTP_USER_AGENT']) ? sanitize_text_field(wp_unslash($_SERVER['HTTP_USER_AGENT'])) : '',
        ];

        if (count($tokens) > 5) {
            $tokens = array_slice($tokens, -5);
        }

        update_user_meta($user_id, self::TOKEN_META_KEY, $tokens);
        set_transient(self::TOKEN_TRANSIENT_PREFIX . $hash, (int) $user_id, self::TOKEN_TTL);

        $index = get_option(self::TOKEN_INDEX_OPTION, []);
        if (!is_array($index)) {
            $index = [];
        }

        $index[$hash] = [
            'user_id' => (int) $user_id,
            'expires' => (int) $expires,
        ];

        if (count($index) > 5000) {
            $index = array_filter($index, static function($item) use ($now) {
                return is_array($item)
                    && !empty($item['expires'])
                    && (int) $item['expires'] > $now;
            });
        }

        update_option(self::TOKEN_INDEX_OPTION, $index, false);

        return $plain;
    }

    private static function revoke_app_token($user_id, $token) {
        $hash = hash('sha256', trim((string) $token));
        delete_transient(self::TOKEN_TRANSIENT_PREFIX . $hash);

        $index = get_option(self::TOKEN_INDEX_OPTION, []);
        if (is_array($index) && isset($index[$hash])) {
            unset($index[$hash]);
            update_option(self::TOKEN_INDEX_OPTION, $index, false);
        }

        $tokens = get_user_meta($user_id, self::TOKEN_META_KEY, true);
        if (!is_array($tokens)) {
            return;
        }

        $tokens = array_values(array_filter($tokens, function($item) use ($hash) {
            return !(is_array($item) && !empty($item['hash']) && hash_equals((string) $item['hash'], $hash));
        }));

        update_user_meta($user_id, self::TOKEN_META_KEY, $tokens);
    }

    private static function validate_app_token($token) {
        $token = trim((string) $token);
        if (empty($token) || strlen($token) < 40) {
            return 0;
        }

        $hash = hash('sha256', $token);
        $now = time();

        $cached_user_id = (int) get_transient(self::TOKEN_TRANSIENT_PREFIX . $hash);
        if ($cached_user_id > 0 && self::user_has_valid_token_hash($cached_user_id, $hash, $now)) {
            return $cached_user_id;
        }

        $index = get_option(self::TOKEN_INDEX_OPTION, []);
        if (is_array($index) && isset($index[$hash]) && is_array($index[$hash])) {
            $user_id = (int) ($index[$hash]['user_id'] ?? 0);
            $expires = (int) ($index[$hash]['expires'] ?? 0);

            if ($user_id > 0 && $expires > $now && self::user_has_valid_token_hash($user_id, $hash, $now)) {
                set_transient(self::TOKEN_TRANSIENT_PREFIX . $hash, $user_id, min(self::TOKEN_TTL, $expires - $now));
                return $user_id;
            }

            unset($index[$hash]);
            update_option(self::TOKEN_INDEX_OPTION, $index, false);
        }

        return 0;
    }

    private static function user_has_valid_token_hash($user_id, $hash, $now = null) {
        $now = $now ?: time();
        $tokens = get_user_meta($user_id, self::TOKEN_META_KEY, true);
        if (!is_array($tokens)) {
            return false;
        }

        $changed = false;
        $valid = false;
        $clean_tokens = [];

        foreach ($tokens as $item) {
            if (!is_array($item) || empty($item['hash']) || empty($item['expires'])) {
                $changed = true;
                continue;
            }

            if ((int) $item['expires'] < $now) {
                $changed = true;
                delete_transient(self::TOKEN_TRANSIENT_PREFIX . (string) $item['hash']);
                continue;
            }

            if (hash_equals((string) $item['hash'], $hash)) {
                $valid = true;
            }

            $clean_tokens[] = $item;
        }

        if ($changed) {
            update_user_meta($user_id, self::TOKEN_META_KEY, $clean_tokens);
        }

        return $valid;
    }

    public static function permission_app_user(WP_REST_Request $request) {
        $user_id = self::resolve_request_user_id($request);
        if ($user_id <= 0) {
            return new WP_Error('mundicam_app_unauthorized', 'Sesión de app no válida. Vuelve a iniciar sesión.', ['status' => 401]);
        }

        $user = get_user_by('id', $user_id);
        if (!($user instanceof WP_User) || self::is_blocked_user($user)) {
            return new WP_Error('mundicam_app_forbidden', 'Cuenta bloqueada o sin permisos para usar la app.', ['status' => 403]);
        }

        self::$current_app_user_id = (int) $user_id;
        self::bootstrap_user_context($user_id);
        $request->set_param('_mundicam_user_id', $user_id);

        return true;
    }

    private static function resolve_request_user_id(WP_REST_Request $request) {
        return self::validate_app_token(self::get_request_token($request));
    }

    private static function get_request_token(WP_REST_Request $request) {
        $auth = $request->get_header('authorization');
        $token = '';

        if (!empty($auth) && preg_match('/Bearer\s+(.+)/i', $auth, $matches)) {
            $token = trim($matches[1]);
        }

        if (empty($token)) {
            $token = trim((string) $request->get_header('x-mundicam-app-token'));
        }

        // Permitido para pruebas, pero en Flutter debe usarse Authorization: Bearer.
        if (empty($token)) {
            $token = trim((string) $request->get_param('app_token'));
        }

        return $token;
    }

    private static function bootstrap_user_context($user_id) {
        self::$current_app_user_id = (int) $user_id;
        wp_set_current_user($user_id);

        if (!function_exists('WC') || !WC()) {
            return;
        }

        if (function_exists('wc_maybe_define_constant')) {
            wc_maybe_define_constant('WOOCOMMERCE_CART', true);
        }

        try {
            WC()->customer = new WC_Customer($user_id, true);
        } catch (Throwable $e) {
            // Si falla el cliente, no rompemos el endpoint; WooCommerce seguirá con current_user.
        }

        if (null === WC()->session && class_exists('WC_Session_Handler')) {
            WC()->session = new WC_Session_Handler();
            WC()->session->init();
        }

        if (function_exists('wc_load_cart')) {
            try {
                wc_load_cart();
            } catch (Throwable $e) {
                // Evitamos romper productos/precios si el carrito no puede cargarse en REST.
            }
        }
    }

    private static function ensure_woocommerce() {
        if (!function_exists('WC') || !function_exists('wc_get_product') || !function_exists('wc_get_products')) {
            return new WP_Error('mundicam_woocommerce_missing', 'WooCommerce no está disponible.', ['status' => 500]);
        }

        return true;
    }

    // =============================================================
    // USER / ROLES / PERMISSIONS
    // =============================================================

    public static function me(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_user_by('id', $user_id);

        // v1.9.27 Correo del gestor / comercial / técnico asignado al usuario.
        $manager_email = sanitize_email((string) get_user_meta($user_id, 'wpuef_cid_c30', true));
        if (!is_email($manager_email)) {
            $manager_email = '';
        }

        return rest_ensure_response([
            'success' => true,
            'user' => self::user_payload($user),
            'permissions' => self::permissions_payload($user),
            'can_view_stock' => self::can_view_internal_stock($user),
            'credit' => self::credit_payload($user_id),
            'manager_email' => $manager_email,
            'wpuef_cid_c30' => $manager_email,
        ]);
    }

    /**
     * v1.9.10 Crédito / pago aplazado (giro). Lee el user_meta 'credit_limit' que
     * usa la web y calcula el crédito usado (pedidos abiertos no pagados con pago
     * aplazado) y el disponible. Se expone en login y /me para que Flutter pueda
     * ofrecer el método Giro / pago aplazado cuando haya crédito suficiente.
     */
    private static function credit_payload($user_id) {
        $user_id = (int) $user_id;
        $default = [
            'credit_limit' => 0.0,
            'credit_used' => 0.0,
            'credit_available' => 0.0,
            'payment_terms_enabled' => false,
        ];
        if ($user_id <= 0) {
            return $default;
        }

        $raw_limit = get_user_meta($user_id, 'credit_limit', true);
        $credit_limit = is_numeric($raw_limit) ? (float) $raw_limit : 0.0;
        if ($credit_limit <= 0) {
            if (function_exists('error_log')) {
                error_log('[MundiCam App API] Crédito: usuario ' . $user_id . ' credit_limit=' . var_export($raw_limit, true) . ' (0 o no numérico).');
            }
            return $default;
        }

        $credit_used = self::calculate_credit_used($user_id);
        $credit_available = max(0.0, $credit_limit - $credit_used);

        if (function_exists('error_log')) {
            error_log(sprintf(
                '[MundiCam App API] Crédito user=%d limit=%.2f used=%.2f available=%.2f',
                $user_id, $credit_limit, $credit_used, $credit_available
            ));
        }

        return [
            'credit_limit' => round($credit_limit, 2),
            'credit_used' => round($credit_used, 2),
            'credit_available' => round($credit_available, 2),
            'payment_terms_enabled' => ($credit_limit > 0),
        ];
    }

    /**
     * v1.9.10 Crédito usado: suma de totales de pedidos del cliente con método de
     * pago aplazado/giro que aún no están pagados/cancelados (pending, on-hold,
     * processing). Los completed ya pagados y los cancelled/refunded no cuentan.
     */
    private static function calculate_credit_used($user_id) {
        $user_id = (int) $user_id;
        if ($user_id <= 0 || !function_exists('wc_get_orders')) {
            return 0.0;
        }

        $used = 0.0;
        try {
            $orders = wc_get_orders([
                'customer_id' => $user_id,
                'limit' => -1,
                'status' => ['pending', 'on-hold', 'processing'],
            ]);
            foreach ((array) $orders as $order) {
                if (!($order instanceof WC_Order)) {
                    continue;
                }
                $method = self::normalize_app_payment_method($order->get_payment_method());
                // 'cheque' agrupa giro/aplazado en normalize_app_payment_method.
                if ($method === 'cheque' || $order->get_meta('_mundicam_app_credit_order') === '1') {
                    $used += (float) $order->get_total();
                }
            }
        } catch (Throwable $e) {
            return 0.0;
        }

        return $used;
    }

    /**
     * v1.9.10 ¿Es el método de pago un giro / pago aplazado (usa crédito)?
     */
    private static function is_credit_payment_method($payment_method) {
        $normalized = self::normalize_app_payment_method($payment_method);
        // 'cheque' es el canónico de giro/aplazado según normalize_app_payment_method.
        return $normalized === 'cheque';
    }

    private static function user_payload($user) {
        if (!($user instanceof WP_User)) {
            return [];
        }

        $billing = [];
        $shipping = [];
        $cif_nif = self::get_user_cif_nif($user->ID);

        if (class_exists('WC_Customer')) {
            try {
                $customer = new WC_Customer($user->ID);
                $billing = [
                    'first_name' => $customer->get_billing_first_name(),
                    'last_name' => $customer->get_billing_last_name(),
                    'company' => $customer->get_billing_company(),
                    'address_1' => $customer->get_billing_address_1(),
                    'address_2' => $customer->get_billing_address_2(),
                    'city' => $customer->get_billing_city(),
                    'state' => $customer->get_billing_state(),
                    'postcode' => $customer->get_billing_postcode(),
                    'country' => $customer->get_billing_country(),
                    'email' => $customer->get_billing_email(),
                    'phone' => $customer->get_billing_phone(),
                    // Campo fiscal personalizado de WooCommerce/WordPress.
                    // Se añade también en raíz del usuario para que Flutter lo encuentre de forma directa.
                    'billing_nif' => $cif_nif,
                    'cif_nif' => $cif_nif,
                ];
                $shipping = [
                    'first_name' => $customer->get_shipping_first_name(),
                    'last_name' => $customer->get_shipping_last_name(),
                    'company' => $customer->get_shipping_company(),
                    'address_1' => $customer->get_shipping_address_1(),
                    'address_2' => $customer->get_shipping_address_2(),
                    'city' => $customer->get_shipping_city(),
                    'state' => $customer->get_shipping_state(),
                    'postcode' => $customer->get_shipping_postcode(),
                    'country' => $customer->get_shipping_country(),
                ];
            } catch (Throwable $e) {
                // Perfil básico disponible aunque WooCommerce Customer falle.
            }
        }

        if (!empty($cif_nif)) {
            $billing['billing_nif'] = $cif_nif;
            $billing['cif_nif'] = $cif_nif;
        }

        $roles = array_values((array) $user->roles);

        return [
            'id' => (int) $user->ID,
            'wordpress_id' => (int) $user->ID,
            'woocommerce_id' => (int) $user->ID,
            'email' => $user->user_email,
            'name' => $user->display_name,
            'display_name' => $user->display_name,
            'first_name' => get_user_meta($user->ID, 'first_name', true),
            'last_name' => get_user_meta($user->ID, 'last_name', true),
            'role' => isset($roles[0]) ? $roles[0] : '',
            'roles' => $roles,
            // CIF/NIF expuesto en varias claves para máxima compatibilidad con la app.
            'billing_nif' => $cif_nif,
            'cif_nif' => $cif_nif,
            'nif' => $cif_nif,
            'customer_tax_id' => $cif_nif,
            'billing' => $billing,
            'shipping' => $shipping,
            'meta_data' => self::user_meta_payload_with_credit($user->ID, $cif_nif),
        ];
    }

    private static function customer_tax_meta_keys() {
        return [
            'billing_nif',
            '_billing_nif',
            'cif_nif',
            '_cif_nif',
            'cifNif',
            'billing_cif',
            '_billing_cif',
            'shipping_nif',
            '_shipping_nif',
            'cif',
            'nif',
            'vat_number',
            '_vat_number',
            'billing_vat',
            '_billing_vat',
            'company_vat',
            'tax_id',
            '_tax_id',
            'customer_vat',
            'dni',
            'document_number',
        ];
    }

    private static function clean_tax_value($value) {
        if (is_array($value) || is_object($value)) {
            return '';
        }

        $value = trim(wp_strip_all_tags((string) $value));

        if ($value === '' || strtolower($value) === 'null' || strtolower($value) === 'false') {
            return '';
        }

        return sanitize_text_field($value);
    }

    private static function get_user_cif_nif($user_id) {
        $user_id = (int) $user_id;
        if ($user_id <= 0) {
            return '';
        }

        foreach (self::customer_tax_meta_keys() as $key) {
            $value = self::clean_tax_value(get_user_meta($user_id, $key, true));
            if ($value !== '') {
                return $value;
            }
        }

        return '';
    }

    /**
     * v1.9.11 meta_data del usuario incluyendo el crédito con las claves exactas
     * que la app Flutter ya busca (credit_limit / credit_used / credit_available /
     * payment_terms_enabled). Así el checkout activa el giro sin tocar Flutter.
     */
    private static function user_meta_payload_with_credit($user_id, $cif_nif = '') {
        $meta = self::user_tax_meta_payload($user_id, $cif_nif);

        $credit = self::credit_payload((int) $user_id);
        $meta[] = ['key' => 'credit_limit', 'value' => (string) $credit['credit_limit']];
        $meta[] = ['key' => 'credit_used', 'value' => (string) $credit['credit_used']];
        $meta[] = ['key' => 'credit_available', 'value' => (string) $credit['credit_available']];
        $meta[] = ['key' => 'payment_terms_enabled', 'value' => $credit['payment_terms_enabled'] ? '1' : '0'];

        return $meta;
    }

    private static function user_tax_meta_payload($user_id, $cif_nif = '') {
        $payload = [];
        $seen = [];

        foreach (self::customer_tax_meta_keys() as $key) {
            $value = self::clean_tax_value(get_user_meta((int) $user_id, $key, true));
            if ($value === '') {
                continue;
            }

            $payload[] = [
                'key' => $key,
                'value' => $value,
            ];
            $seen[$key] = true;
        }

        $cif_nif = self::clean_tax_value($cif_nif);
        if ($cif_nif !== '') {
            foreach (['billing_nif', 'cif_nif', 'nif', 'customer_tax_id'] as $canonical_key) {
                if (empty($seen[$canonical_key])) {
                    $payload[] = [
                        'key' => $canonical_key,
                        'value' => $cif_nif,
                    ];
                    $seen[$canonical_key] = true;
                }
            }
        }

        return $payload;
    }

    private static function permissions_payload($user) {
        $can_view_stock = self::can_view_internal_stock($user);
        $can_create_customers = self::can_create_customers($user);
        $is_blocked = self::is_blocked_user($user);

        return [
            'can_view_prices' => !$is_blocked,
            'can_buy' => !$is_blocked,
            'can_create_quotes' => !$is_blocked,
            'can_view_stock_details' => $can_view_stock,
            'can_view_stock' => $can_view_stock,
            'can_create_customers' => $can_create_customers,
            'is_blocked' => $is_blocked,
        ];
    }

    private static function normalize_role($role) {
        $role = strtolower((string) $role);
        $map = [
            'á' => 'a', 'à' => 'a', 'ä' => 'a', 'â' => 'a',
            'é' => 'e', 'è' => 'e', 'ë' => 'e', 'ê' => 'e',
            'í' => 'i', 'ì' => 'i', 'ï' => 'i', 'î' => 'i',
            'ó' => 'o', 'ò' => 'o', 'ö' => 'o', 'ô' => 'o',
            'ú' => 'u', 'ù' => 'u', 'ü' => 'u', 'û' => 'u',
            'ñ' => 'n',
        ];
        $role = strtr($role, $map);
        return preg_replace('/[^a-z0-9]+/', '', $role);
    }


    /**
     * Mapeo cerrado de grupos de precio MundiCam.
     *
     * Regla:
     * - Administrador/Gestor mantiene permisos reales, pero a nivel de PRECIO se fuerza a grupo 52%.
     * - Cliente X% y Comercial X% deben ver el mismo precio final de WooCommerce/B2B.
     * - La app NO calcula descuentos; solo muestra el precio final devuelto por este endpoint.
     */
    private static function price_group_role_map() {
        return [
            '25' => ['cliente' => 'cliente_25',     'comercial' => 'comercial_25'],
            '30' => ['cliente' => 'cliente_30',     'comercial' => 'comercial_30'],
            '35' => ['cliente' => 'cliente_35_60',  'comercial' => 'comercial_35_60'],
            '40' => ['cliente' => 'cliente_40',     'comercial' => 'comercial_40'],
            '42' => ['cliente' => 'cliente_42_65',  'comercial' => 'comercial_42_65'],
            '45' => ['cliente' => 'cliente_45_665', 'comercial' => 'comercial_45_665'],
            '50' => ['cliente' => 'cliente_50_68',  'comercial' => 'comercial_50_68'],
            '52' => ['cliente' => 'cliente_52_69',  'comercial' => 'comercial_52_69'],
            '53' => ['cliente' => 'cliente_53_70',  'comercial' => 'comercial_53_70'],
            '54' => ['cliente' => 'cliente_54_71',  'comercial' => 'comercial_54_71'],
            '55' => ['cliente' => 'cliente_55',     'comercial' => 'comercial_55'],
            '57' => ['cliente' => 'cliente_57',     'comercial' => 'comercial_57'],
            'pvp' => ['cliente' => 'cliente_pvp',   'comercial' => ''],
        ];
    }


    private static function extract_price_group_from_role($role) {
        $slug = self::normalize_role_slug($role);
        $compact = self::normalize_role($role);
        $map = self::price_group_role_map();

        // Primero comprobación exacta por roles reales.
        foreach ($map as $group => $pair) {
            foreach ($pair as $role_key) {
                if ($role_key === '') {
                    continue;
                }

                $role_slug = self::normalize_role_slug($role_key);
                $role_compact = self::normalize_role($role_key);

                if ($slug === $role_slug || $compact === $role_compact) {
                    return (string) $group;
                }
            }
        }

        // Después patrones flexibles para nombres con espacios, guiones o porcentajes.
        foreach (array_keys($map) as $group) {
            if ($group === 'pvp') {
                continue;
            }

            if (
                preg_match('/(^|_)' . preg_quote($group, '/') . '($|_)/', $slug)
                || strpos($compact, 'cliente' . $group) !== false
                || strpos($compact, 'comercial' . $group) !== false
            ) {
                return (string) $group;
            }
        }

        if ($slug === 'cliente_pvp' || $compact === 'clientepvp') {
            return 'pvp';
        }

        return '';
    }

    private static function resolve_existing_price_role($group, $preferred_type = 'cliente', $fallback = '') {
        $group = (string) $group;
        $map = self::price_group_role_map();
        if (!isset($map[$group])) {
            return $fallback !== '' ? $fallback : '';
        }

        $preferred_type = ($preferred_type === 'comercial') ? 'comercial' : 'cliente';
        $opposite_type = ($preferred_type === 'comercial') ? 'cliente' : 'comercial';

        $candidate_labels = [
            $map[$group][$preferred_type],
            ucfirst($preferred_type) . ' ' . $group . '%',
            ucfirst($preferred_type) . '_' . $group,
            strtolower($preferred_type) . '_' . $group,
            $map[$group][$opposite_type],
            ucfirst($opposite_type) . ' ' . $group . '%',
            ucfirst($opposite_type) . '_' . $group,
            strtolower($opposite_type) . '_' . $group,
        ];

        if (function_exists('wp_roles')) {
            $roles_object = wp_roles();
            $wp_roles = ($roles_object && isset($roles_object->roles) && is_array($roles_object->roles)) ? $roles_object->roles : [];

            foreach ($candidate_labels as $candidate) {
                $candidate_key = sanitize_key($candidate);
                if (isset($wp_roles[$candidate])) {
                    return (string) $candidate;
                }
                if (isset($wp_roles[$candidate_key])) {
                    return (string) $candidate_key;
                }
            }

            foreach (array_keys($wp_roles) as $role_key) {
                $role_group = self::extract_price_group_from_role($role_key);
                if ($role_group !== $group) {
                    continue;
                }

                $normalized = self::normalize_role($role_key);
                if ($preferred_type === 'comercial' && strpos($normalized, 'comercial') === 0) {
                    return (string) $role_key;
                }
                if ($preferred_type === 'cliente' && (strpos($normalized, 'cliente') === 0 || $normalized === 'customer')) {
                    return (string) $role_key;
                }
            }
        }

        return $fallback !== '' ? $fallback : $map[$group][$preferred_type];
    }

    private static function price_payload_for_group($group, $real_role, $context, $source, array $roles = []) {
        $group = (string) $group;
        $preferred = ($context === 'comercial') ? 'comercial' : 'cliente';
        $price_role = self::resolve_existing_price_role($group, $preferred, $preferred . '_' . $group);

        return [
            'context' => $preferred,
            'role' => (string) $real_role,
            'normalized_role' => self::normalize_role($real_role),
            'role_slug' => self::normalize_role_slug($real_role),
            'price_role' => $price_role,
            'price_group' => $group,
            'forced_price_group' => $group,
            'all_roles' => $roles,
            'source' => $source,
        ];
    }

    private static function is_blocked_user($user) {
        if (!($user instanceof WP_User)) {
            return true;
        }

        foreach ((array) $user->roles as $role) {
            $normalized = self::normalize_role($role);
            if ($normalized === 'blockedcustomer' || $normalized === 'blocked') {
                return true;
            }
        }

        return false;
    }

    private static function can_view_internal_stock($user) {
        if (!($user instanceof WP_User)) {
            return false;
        }

        if (user_can($user, 'manage_options') || user_can($user, 'manage_woocommerce')) {
            return true;
        }

        foreach ((array) $user->roles as $role) {
            $normalized = self::normalize_role($role);
            if ($normalized === 'admin' || $normalized === 'administrator' || $normalized === 'administrador') {
                return true;
            }
            if (strpos($normalized, 'comercial') === 0) {
                return true;
            }
            if ($normalized === 'shopmanager' || $normalized === 'gestordelatienda') {
                return true;
            }
        }

        return false;
    }

    private static function can_create_customers($user) {
        if (!($user instanceof WP_User)) {
            return false;
        }

        if (user_can($user, 'manage_options') || user_can($user, 'manage_woocommerce')) {
            return true;
        }

        foreach ((array) $user->roles as $role) {
            if (strpos(self::normalize_role($role), 'comercial') === 0) {
                return true;
            }
        }

        return false;
    }

    // =============================================================
    // CATEGORIES
    // =============================================================

    public static function categories(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $hide_empty = (int) $request->get_param('hide_empty') === 1;
        $parent_only = (int) $request->get_param('parent_only') === 1;
        $parent = $request->get_param('parent');

        $args = [
            'taxonomy' => 'product_cat',
            'hide_empty' => $hide_empty,
            'orderby' => 'name',
            'order' => 'ASC',
        ];

        if ($parent !== null && $parent !== '') {
            $args['parent'] = max(0, (int) $parent);
        } elseif ($parent_only) {
            $args['parent'] = 0;
        }

        $terms = get_terms($args);
        if (is_wp_error($terms)) {
            return new WP_Error('mundicam_categories_error', $terms->get_error_message(), ['status' => 500]);
        }

        $categories = [];
        foreach ($terms as $term) {
            if (!($term instanceof WP_Term)) {
                continue;
            }

            $normalized_name = self::normalize_role($term->name);
            if ($normalized_name === 'sincategoria' || $normalized_name === 'uncategorized') {
                continue;
            }

            $thumbnail_id = (int) get_term_meta($term->term_id, 'thumbnail_id', true);
            $image = $thumbnail_id > 0 ? wp_get_attachment_image_url($thumbnail_id, 'woocommerce_thumbnail') : '';

            $categories[] = [
                'id' => (int) $term->term_id,
                'name' => html_entity_decode($term->name, ENT_QUOTES, 'UTF-8'),
                'slug' => $term->slug,
                'parent' => (int) $term->parent,
                'count' => (int) $term->count,
                'image' => $image ?: null,
            ];
        }

        return rest_ensure_response([
            'success' => true,
            'categories' => $categories,
            'data' => $categories,
            'total' => count($categories),
        ]);
    }

    public static function brands(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $taxonomy_used = '';
        $terms = [];

        foreach (self::brand_taxonomies() as $taxonomy) {
            if (!taxonomy_exists($taxonomy)) {
                continue;
            }

            $found = get_terms([
                'taxonomy' => $taxonomy,
                'hide_empty' => true,
                'orderby' => 'name',
                'order' => 'ASC',
            ]);

            if (!is_wp_error($found) && !empty($found)) {
                $taxonomy_used = $taxonomy;
                $terms = $found;
                break;
            }
        }

        $brands = [];
        foreach ($terms as $term) {
            if (!($term instanceof WP_Term)) {
                continue;
            }

            $thumbnail_id = (int) get_term_meta($term->term_id, 'thumbnail_id', true);
            if ($thumbnail_id <= 0) {
                $thumbnail_id = (int) get_term_meta($term->term_id, 'brand_thumbnail_id', true);
            }
            if ($thumbnail_id <= 0) {
                $thumbnail_id = (int) get_term_meta($term->term_id, 'pwb_brand_image', true);
            }

            $image = $thumbnail_id > 0 ? wp_get_attachment_image_url($thumbnail_id, 'woocommerce_thumbnail') : '';

            $brands[] = [
                'id' => (int) $term->term_id,
                'name' => html_entity_decode($term->name, ENT_QUOTES, 'UTF-8'),
                'slug' => $term->slug,
                'count' => (int) $term->count,
                'taxonomy' => $taxonomy_used,
                'image' => $image ?: null,
            ];
        }

        return rest_ensure_response([
            'success' => true,
            'brands' => $brands,
            'data' => $brands,
            'total' => count($brands),
            'taxonomy' => $taxonomy_used,
        ]);
    }

    // =============================================================
    // PRODUCTS
    // =============================================================

    public static function products(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_user_by('id', $user_id);
        $can_view_stock = self::can_view_internal_stock($user);

        $page = max(1, (int) $request->get_param('page'));
        $per_page = (int) $request->get_param('per_page');
        if ($per_page <= 0) {
            $per_page = 30;
        }
        $per_page = min(100, max(1, $per_page));

        $orderby_raw = $request->get_param('orderby') ?: $request->get_param('orderBy');

        $query_args = [
            'status' => 'publish',
            'limit' => $per_page,
            'page' => $page,
            'paginate' => true,
            'orderby' => self::map_orderby($orderby_raw),
            'order' => self::map_order($orderby_raw, $request->get_param('order')),
            'return' => 'objects',
        ];

        $search = sanitize_text_field($request->get_param('search'));
        if (!empty($search)) {
            $query_args['s'] = $search;
        }

        // v1.9.16 BÚSQUEDA INTELIGENTE (OPT-IN). Solo se activa si la app manda
        // smart_search=1 (el lib v13 ya lo envía junto con search_tokens, brand_guess,
        // etc.). Si el parámetro no viene, NO se ejecuta nada de esto y el flujo
        // original de /products queda exactamente igual que antes: riesgo cero para
        // cualquier cliente/versión que no lo use.
        // Si la búsqueda inteligente no puede resolver, devuelve null y también se
        // cae al flujo original (fallback seguro).
        if (!empty($search) && (int) $request->get_param('smart_search') === 1) {
            $smart_response = self::smart_search_products_response($request, $search, $page, $per_page, $can_view_stock);
            if ($smart_response !== null) {
                return $smart_response;
            }
        }

        // Búsqueda exacta/compatible por SKU.
        // Si la app llega desde una categoría pero el texto parece una referencia,
        // no limitamos por categoría: la referencia debe encontrar el producto global.
        $sku_search = sanitize_text_field((string) $request->get_param('sku'));
        if ($sku_search === '' && !empty($search) && self::looks_like_sku($search)) {
            $sku_search = $search;
        }

        if ($sku_search !== '') {
            $sku_ids = self::find_product_ids_by_sku($sku_search);
            if (empty($sku_ids)) {
                return rest_ensure_response([
                    'success' => true,
                    'products' => [],
                    'data' => [],
                    'page' => $page,
                    'per_page' => $per_page,
                    'total' => 0,
                    'total_pages' => 1,
                    'can_view_stock' => $can_view_stock,
                    'sku_search' => true,
                ]);
            }

            unset($query_args['s']);
            $query_args['include'] = array_values($sku_ids);
            $query_args['orderby'] = 'include';
            $query_args['order'] = 'ASC';
        }

        $category_param = $request->get_param('category');
        if ($category_param === null || $category_param === '') {
            $category_param = $request->get_param('category_id');
        }

        $category_id = absint($category_param);
        if ($category_id <= 0 && is_string($category_param) && trim($category_param) !== '') {
            $category_text = sanitize_text_field($category_param);
            $category_term = get_term_by('slug', sanitize_title($category_text), 'product_cat');
            if (!$category_term) {
                $category_term = get_term_by('name', $category_text, 'product_cat');
            }
            if ($category_term instanceof WP_Term) {
                $category_id = (int) $category_term->term_id;
            }
        }

        $tax_query = [];

        // Catálogo app: cuando se abre una categoría padre, el cliente espera ver
        // también los productos publicados dentro de sus subcategorías.
        // Con WC_Product_Query['category'] por slug se quedaban fuera muchos
        // productos hijos y los filtros devolvían resultados parciales.
        if ($category_id > 0 && empty($sku_search)) {
            $term = get_term($category_id, 'product_cat');
            if ($term && !is_wp_error($term)) {
                $tax_query[] = [
                    'taxonomy' => 'product_cat',
                    'field' => 'term_id',
                    'terms' => [$category_id],
                    'operator' => 'IN',
                    'include_children' => true,
                ];
            }
        }

        $brand_param = $request->get_param('brand');
        $brand_id = absint($request->get_param('brand_id'));
        if ($brand_id <= 0) {
            $brand_id = absint($request->get_param('brandId'));
        }

        $brand_text_param = $request->get_param('brand_name');
        if ($brand_text_param === null || $brand_text_param === '') {
            $brand_text_param = $request->get_param('brandName');
        }
        if ($brand_text_param === null || $brand_text_param === '') {
            $brand_text_param = $request->get_param('manufacturer');
        }
        if ($brand_text_param === null || $brand_text_param === '') {
            $brand_text_param = $brand_param;
        }

        if ($brand_id <= 0 && is_numeric($brand_param)) {
            $brand_id = absint($brand_param);
            $brand_text = '';
        } else {
            $brand_text = sanitize_text_field((string) $brand_text_param);
        }

        $brand_filter = self::build_brand_tax_query($brand_id, $brand_text);
        if (!empty($brand_filter)) {
            $tax_query[] = $brand_filter;
        }

        $attribute_terms_raw = $request->get_param('attribute_terms');
        if ($attribute_terms_raw === null || $attribute_terms_raw === '') {
            $attribute_terms_raw = $request->get_param('attributeTerms');
        }
        if ($attribute_terms_raw === null || $attribute_terms_raw === '') {
            $attribute_terms_raw = $request->get_param('attributes');
        }
        $attribute_terms = self::decode_json_map($attribute_terms_raw);
        foreach ($attribute_terms as $taxonomy => $term_ids) {
            $taxonomy = sanitize_key((string) $taxonomy);
            if (!taxonomy_exists($taxonomy)) {
                continue;
            }

            if (!is_array($term_ids)) {
                $term_ids = [$term_ids];
            }

            $term_ids = array_values(array_unique(array_filter(array_map('absint', $term_ids))));
            if (!empty($term_ids)) {
                $tax_query[] = [
                    'taxonomy' => $taxonomy,
                    'field' => 'term_id',
                    'terms' => $term_ids,
                    'operator' => 'IN',
                ];
            }
        }

        if (!empty($tax_query) && empty($sku_search)) {
            $query_args['tax_query'] = count($tax_query) > 1 ? array_merge(['relation' => 'AND'], $tax_query) : $tax_query;
        }

        // WooCommerce puede devolver total > 0 pero items vacíos con orderby=price
        // en instalaciones B2B con precios ocultos/vacíos. Para ordenar por precio
        // cargamos IDs del contexto y ordenamos en PHP, manteniendo productos sin precio al final.
        $orderby_key = sanitize_key((string) $orderby_raw);
        if (in_array($orderby_key, ['price_asc', 'price_desc'], true) && empty($sku_search)) {
            return self::products_price_asc_response(
                $page,
                $per_page,
                $search,
                $category_id,
                $tax_query,
                $can_view_stock,
                $orderby_key === 'price_desc' ? 'DESC' : 'ASC'
            );
        }

        // Fix 1.4.7: para catálogo y categorías usamos IDs reales de WP_Query.
        // En algunas instalaciones B2B, WC_Product_Query puede informar total=14
        // pero entregar solo 1 producto cuando hay tax_query/categorías hijas.
        // WP_Query con post IDs evita esa incoherencia y después hidratamos cada
        // producto con product_payload(), que calcula precio/stock como usuario real.
        return self::products_wp_query_response(
            $page,
            $per_page,
            $search,
            $category_id,
            $tax_query,
            $can_view_stock,
            $orderby_raw,
            $request->get_param('order'),
            !empty($sku_search) ? $sku_ids : []
        );
    }

    private static function products_wp_query_response($page, $per_page, $search, $category_id, array $tax_query, $can_view_stock, $orderby_raw = '', $order_raw = '', array $include_ids = []) {
        $page = max(1, (int) $page);
        $per_page = min(100, max(1, (int) $per_page));

        $args = [
            'post_type' => 'product',
            'post_status' => 'publish',
            'posts_per_page' => $per_page,
            'paged' => $page,
            'fields' => 'ids',
            'no_found_rows' => false,
        ];

        if (!empty($include_ids)) {
            $args['post__in'] = array_values(array_unique(array_map('absint', $include_ids)));
            $args['orderby'] = 'post__in';
        } else {
            if (!empty($search)) {
                $args['s'] = $search;
            }

            if (!empty($tax_query)) {
                $args['tax_query'] = count($tax_query) > 1 ? array_merge(['relation' => 'AND'], $tax_query) : $tax_query;
            }

            $orderby_key = sanitize_key((string) $orderby_raw);
            switch ($orderby_key) {
                case 'name':
                case 'nombre':
                    $args['orderby'] = 'title';
                    $args['order'] = 'ASC';
                    break;
                case 'menu_order':
                    $args['orderby'] = ['menu_order' => 'ASC', 'title' => 'ASC'];
                    break;
                case 'date':
                default:
                    $args['orderby'] = 'date';
                    $args['order'] = self::map_order($orderby_raw, $order_raw);
                    break;
            }
        }

        $query = new WP_Query($args);
        $products = [];

        foreach ($query->posts as $product_id) {
            $product = wc_get_product($product_id);
            if ($product instanceof WC_Product && $product->get_status() === 'publish' && $product->get_catalog_visibility() !== 'hidden') {
                $products[] = self::product_payload($product, $can_view_stock);
            }
        }

        $total = (int) $query->found_posts;
        $pages = (int) $query->max_num_pages;

        return rest_ensure_response([
            'success' => true,
            'products' => $products,
            'data' => $products,
            'page' => $page,
            'per_page' => $per_page,
            'total' => $total > 0 ? $total : count($products),
            'total_pages' => max(1, $pages),
            'can_view_stock' => $can_view_stock,
            'query_engine' => 'wp_query_ids_152',
        ]);
    }

    public static function product_detail(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_user_by('id', $user_id);
        $can_view_stock = self::can_view_internal_stock($user);

        $product_id = (int) $request->get_param('id');
        $product = wc_get_product($product_id);

        if (!($product instanceof WC_Product) || $product->get_status() !== 'publish') {
            return new WP_Error('mundicam_product_not_found', 'Producto no encontrado.', ['status' => 404]);
        }

        $payload = self::product_payload($product, $can_view_stock);

        return rest_ensure_response([
            'success' => true,
            'product' => $payload,
            'data' => $payload,
            'can_view_stock' => $can_view_stock,
        ]);
    }

    /**
     * v1.9.9 GET /products/search — búsqueda eficiente rankeada por relevancia.
     *
     * Orden de prioridad (relevancia):
     *   1. SKU exacto
     *   2. Título que empieza por el término
     *   3. Título que contiene el término
     *   4. SKU parcial
     *   5. Marca / categoría
     *
     * Rápida: usa unas pocas WP_Query acotadas (no carga todo el catálogo, no
     * expande a decenas de términos). Stock correcto vía product_payload
     * (stock_status de WooCommerce). Paginación real.
     *
     * Params: search|q (texto), page, per_page, category (opcional), brand (opcional).
     */
    public static function products_search(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_user_by('id', $user_id);
        $can_view_stock = self::can_view_internal_stock($user);

        $term = trim((string) ($request->get_param('search') ?: $request->get_param('q') ?: $request->get_param('sku')));
        $page = max(1, (int) $request->get_param('page'));
        $per_page = (int) $request->get_param('per_page');
        if ($per_page <= 0) { $per_page = 30; }
        $per_page = min(50, max(1, $per_page));

        if ($term === '' || mb_strlen($term) < 2) {
            return rest_ensure_response([
                'success' => true,
                'products' => [],
                'data' => [],
                'page' => $page,
                'per_page' => $per_page,
                'total' => 0,
                'total_pages' => 1,
                'can_view_stock' => $can_view_stock,
                'query_engine' => 'relevance_search_199',
            ]);
        }

        // Filtro de categoría opcional (por id).
        $category_id = absint($request->get_param('category') ?: $request->get_param('category_id'));
        $cat_tax_query = [];
        if ($category_id > 0) {
            $cat_tax_query[] = [
                'taxonomy' => 'product_cat',
                'field' => 'term_id',
                'terms' => [$category_id],
                'operator' => 'IN',
                'include_children' => true,
            ];
        }

        // Ranking por buckets de relevancia. Cada bucket añade IDs no vistos aún,
        // preservando el orden de prioridad. Consultas acotadas (LIMIT bajo).
        $ranked = [];   // product_id => rank (menor = más relevante)
        $rank = 0;

        $push = function(array $ids) use (&$ranked, &$rank) {
            foreach ($ids as $id) {
                $id = (int) $id;
                if ($id > 0 && !isset($ranked[$id])) {
                    $ranked[$id] = $rank;
                    $rank++;
                }
            }
        };

        // ---- Bucket 1: SKU exacto (y variantes) ----
        $sku_exact_ids = [];
        foreach (self::sku_variants($term) as $variant) {
            $exact = wc_get_product_id_by_sku($variant);
            if ($exact > 0) {
                $p = wc_get_product($exact);
                $target = ($p instanceof WC_Product && $p->is_type('variation')) ? $p->get_parent_id() : $exact;
                if ($target > 0) { $sku_exact_ids[] = $target; }
            }
        }
        $push($sku_exact_ids);

        // ---- Bucket 2: título empieza por el término ----
        $title_starts = self::search_ids_by_title($term, 'starts', $per_page * 2, $cat_tax_query);
        $push($title_starts);

        // ---- Bucket 3: título contiene el término ----
        $title_contains = self::search_ids_by_title($term, 'contains', $per_page * 3, $cat_tax_query);
        $push($title_contains);

        // ---- Bucket 4: SKU parcial (LIKE) ----
        $sku_partial = self::search_ids_by_sku_like($term, $per_page * 2);
        $push($sku_partial);

        // ---- Bucket 5: marca / categoría por nombre ----
        $tax_ids = self::search_ids_by_taxonomy($term, $per_page * 2, $cat_tax_query);
        $push($tax_ids);

        // ---- Bucket 6 (fallback ligero): búsqueda estándar de WordPress ----
        if (count($ranked) < $per_page) {
            $std = self::search_ids_by_title($term, 'wp_s', $per_page * 2, $cat_tax_query);
            $push($std);
        }

        $all_ids = array_keys($ranked);
        $total = count($all_ids);

        if ($total === 0) {
            return rest_ensure_response([
                'success' => true,
                'products' => [],
                'data' => [],
                'page' => $page,
                'per_page' => $per_page,
                'total' => 0,
                'total_pages' => 1,
                'can_view_stock' => $can_view_stock,
                'query_engine' => 'relevance_search_199',
            ]);
        }

        // Paginación sobre el ranking ya ordenado por relevancia.
        $offset = ($page - 1) * $per_page;
        $page_ids = array_slice($all_ids, $offset, $per_page);

        $products = [];
        foreach ($page_ids as $product_id) {
            $product = wc_get_product($product_id);
            if ($product instanceof WC_Product
                && $product->get_status() === 'publish'
                && $product->get_catalog_visibility() !== 'hidden') {
                $products[] = self::product_payload($product, $can_view_stock);
            }
        }

        return rest_ensure_response([
            'success' => true,
            'products' => $products,
            'data' => $products,
            'page' => $page,
            'per_page' => $per_page,
            'total' => $total,
            'total_pages' => max(1, (int) ceil($total / $per_page)),
            'can_view_stock' => $can_view_stock,
            'query_engine' => 'relevance_search_199',
        ]);
    }

    /**
     * v1.9.16 Búsqueda inteligente con ranking en servidor (OPT-IN: smart_search=1).
     *
     * Resuelve búsquedas multi-palabra tipo "camara 4mpx dahua", que con la búsqueda
     * estándar de WordPress ('s') dan resultados pobres o vacíos porque busca la
     * frase completa. Aquí se tokeniza y se rankea por relevancia:
     *
     *   1. SKU exacto (incluidas variantes con/sin guiones)
     *   2. Todos los tokens presentes en el título (AND) — la coincidencia más fuerte
     *   3. SKU parcial
     *   4. Marca + al menos un token en título
     *   5. Algunos tokens en título (OR)
     *   6. Marca / categoría / etiqueta / atributo por nombre
     *   7. Fallback: búsqueda estándar de WordPress
     *
     * No rompe SKUs con guiones (se buscan tal cual antes de tokenizar).
     * Consultas acotadas con LIMIT: no carga el catálogo entero.
     *
     * @return WP_REST_Response|null null si no aplica (se cae al flujo original).
     */
    private static function smart_search_products_response(WP_REST_Request $request, $search, $page, $per_page, $can_view_stock) {
        $search = trim((string) $search);
        if ($search === '' || mb_strlen($search) < 2) {
            return null;
        }

        // Tokens: preferimos los que ya calcula la app (search_tokens en JSON);
        // si no vienen, tokenizamos aquí.
        $tokens = [];
        $raw_tokens = $request->get_param('search_tokens');
        if (!empty($raw_tokens)) {
            $decoded = json_decode((string) $raw_tokens, true);
            if (is_array($decoded)) {
                foreach ($decoded as $t) {
                    $t = sanitize_text_field((string) $t);
                    if ($t !== '') {
                        $tokens[] = $t;
                    }
                }
            }
        }
        if (empty($tokens)) {
            $tokens = self::smart_search_tokenize($search);
        }
        if (empty($tokens)) {
            return null;
        }

        $category_id = absint($request->get_param('category') ?: $request->get_param('category_id'));
        $cat_tax_query = [];
        if ($category_id > 0) {
            $cat_tax_query[] = [
                'taxonomy' => 'product_cat',
                'field' => 'term_id',
                'terms' => [$category_id],
                'operator' => 'IN',
                'include_children' => true,
            ];
        }

        $limit_hint = max(60, (int) $per_page * 4);

        $ranked = [];
        $rank = 0;
        $push = function(array $ids) use (&$ranked, &$rank) {
            foreach ($ids as $id) {
                $id = (int) $id;
                if ($id > 0 && !isset($ranked[$id])) {
                    $ranked[$id] = $rank;
                    $rank++;
                }
            }
        };

        // --- 1. SKU exacto (respeta guiones: se busca la cadena tal cual) ---
        $sku_exact = [];
        foreach (self::sku_variants($search) as $variant) {
            $exact = wc_get_product_id_by_sku($variant);
            if ($exact > 0) {
                $p = wc_get_product($exact);
                $target = ($p instanceof WC_Product && $p->is_type('variation')) ? $p->get_parent_id() : $exact;
                if ($target > 0) {
                    $sku_exact[] = $target;
                }
            }
        }
        $push($sku_exact);

        // --- 2. TODOS los tokens en el título (AND): la señal más fuerte ---
        $push(self::search_ids_by_tokens($tokens, 'and', $limit_hint, $cat_tax_query));

        // --- 3. SKU parcial ---
        $push(self::search_ids_by_sku_like($search, $limit_hint));

        // --- 4. Marca detectada por la app + algún token ---
        $brand_guess = sanitize_text_field((string) ($request->get_param('brand_guess') ?: ''));
        if ($brand_guess !== '') {
            $brand_tokens = array_values(array_filter($tokens, function($t) use ($brand_guess) {
                return self::normalize_role($t) !== self::normalize_role($brand_guess);
            }));
            $push(self::search_ids_by_brand_and_tokens($brand_guess, $brand_tokens, $limit_hint, $cat_tax_query));
        }

        // --- 5. Algunos tokens en el título (OR) ---
        $push(self::search_ids_by_tokens($tokens, 'or', $limit_hint, $cat_tax_query));

        // --- 6. Marca / categoría / etiqueta por nombre ---
        $push(self::search_ids_by_taxonomy($search, $limit_hint, $cat_tax_query));

        // --- 7. Fallback: búsqueda estándar de WordPress (título + descripción) ---
        if (count($ranked) < (int) $per_page) {
            $push(self::search_ids_by_title($search, 'wp_s', $limit_hint, $cat_tax_query));
        }

        $all_ids = array_keys($ranked);
        $total = count($all_ids);

        if ($total === 0) {
            // Sin resultados: devolvemos null para que el flujo original lo intente
            // con la búsqueda estándar (nunca dejamos la app peor que antes).
            return null;
        }

        $offset = (max(1, (int) $page) - 1) * (int) $per_page;
        $page_ids = array_slice($all_ids, $offset, (int) $per_page);

        $products = [];
        foreach ($page_ids as $product_id) {
            $product = wc_get_product($product_id);
            if ($product instanceof WC_Product
                && $product->get_status() === 'publish'
                && $product->get_catalog_visibility() !== 'hidden') {
                $products[] = self::product_payload($product, $can_view_stock);
            }
        }

        return rest_ensure_response([
            'success' => true,
            'products' => $products,
            'data' => $products,
            'page' => (int) $page,
            'per_page' => (int) $per_page,
            'total' => $total,
            'total_pages' => max(1, (int) ceil($total / max(1, (int) $per_page))),
            'can_view_stock' => $can_view_stock,
            'query_engine' => 'smart_search_relevance_196',
            'smart_search' => true,
        ]);
    }

    /**
     * v1.9.16 Tokeniza la búsqueda: minúsculas, sin acentos, sin stopwords,
     * tokens de 2+ caracteres. "camara 4mpx dahua" -> ['camara','4mpx','dahua'].
     */
    private static function smart_search_tokenize($search) {
        $search = self::normalize_role((string) $search); // minúsculas + sin acentos
        $search = preg_replace('/[^a-z0-9\-\s]/', ' ', $search);
        $parts = preg_split('/\s+/', trim((string) $search));
        if (!is_array($parts)) {
            return [];
        }

        $stopwords = ['de', 'la', 'el', 'los', 'las', 'con', 'para', 'por', 'y', 'o', 'del', 'un', 'una', 'en'];
        $tokens = [];
        foreach ($parts as $p) {
            $p = trim($p);
            if ($p === '' || mb_strlen($p) < 2 || in_array($p, $stopwords, true)) {
                continue;
            }
            $tokens[] = $p;
        }

        return array_values(array_unique($tokens));
    }

    /**
     * v1.9.16 IDs de producto cuyo título contiene los tokens.
     * mode 'and': todos los tokens. mode 'or': al menos uno.
     */
    private static function search_ids_by_tokens(array $tokens, $mode, $limit, array $cat_tax_query = []) {
        global $wpdb;
        if (empty($tokens)) {
            return [];
        }
        $limit = max(1, (int) $limit);
        $glue = ($mode === 'and') ? ' AND ' : ' OR ';

        $conditions = [];
        $params = [];
        foreach ($tokens as $t) {
            $conditions[] = 'p.post_title LIKE %s';
            $params[] = '%' . $wpdb->esc_like($t) . '%';
        }
        $where_tokens = '(' . implode($glue, $conditions) . ')';

        $cat_join = '';
        $cat_where = '';
        if (!empty($cat_tax_query[0]['terms'][0])) {
            $cat_id = (int) $cat_tax_query[0]['terms'][0];
            $descendants = get_term_children($cat_id, 'product_cat');
            $cat_ids = array_map('intval', array_merge([$cat_id], is_array($descendants) ? $descendants : []));
            $cat_ids_sql = implode(',', $cat_ids);
            $cat_join = "INNER JOIN {$wpdb->term_relationships} tr ON tr.object_id = p.ID";
            $cat_where = "AND tr.term_taxonomy_id IN ($cat_ids_sql)";
        }

        $params[] = $limit;

        $sql = $wpdb->prepare(
            "SELECT DISTINCT p.ID FROM {$wpdb->posts} p
             $cat_join
             WHERE p.post_type = 'product'
               AND p.post_status = 'publish'
               AND $where_tokens
               $cat_where
             ORDER BY p.post_title ASC
             LIMIT %d",
            $params
        );

        $ids = $wpdb->get_col($sql);
        return array_map('intval', (array) $ids);
    }

    /**
     * v1.9.16 IDs de producto de una marca concreta que además contienen alguno de
     * los tokens en el título. Para búsquedas tipo "camara 4mpx dahua".
     */
    private static function search_ids_by_brand_and_tokens($brand, array $tokens, $limit, array $cat_tax_query = []) {
        $brand = trim((string) $brand);
        if ($brand === '') {
            return [];
        }
        $limit = max(1, (int) $limit);

        $brand_term_ids = [];
        $brand_taxonomies = [];
        foreach (self::brand_taxonomies() as $taxonomy) {
            if (!taxonomy_exists($taxonomy)) {
                continue;
            }
            $found = get_terms([
                'taxonomy' => $taxonomy,
                'hide_empty' => true,
                'search' => $brand,
                'number' => 3,
                'fields' => 'ids',
            ]);
            if (!is_wp_error($found) && !empty($found)) {
                foreach ($found as $tid) {
                    $brand_term_ids[] = (int) $tid;
                    $brand_taxonomies[$taxonomy] = true;
                }
            }
        }

        if (empty($brand_term_ids)) {
            return [];
        }

        $tax_query = ['relation' => 'OR'];
        foreach (array_keys($brand_taxonomies) as $taxonomy) {
            $tax_query[] = [
                'taxonomy' => $taxonomy,
                'field' => 'term_id',
                'terms' => $brand_term_ids,
                'operator' => 'IN',
            ];
        }

        $args = [
            'post_type' => 'product',
            'post_status' => 'publish',
            'posts_per_page' => $limit,
            'fields' => 'ids',
            'no_found_rows' => true,
            'tax_query' => $tax_query,
        ];

        if (!empty($cat_tax_query)) {
            $args['tax_query'] = ['relation' => 'AND', $cat_tax_query[0], $tax_query];
        }

        // Si hay tokens además de la marca, filtramos por ellos en el título.
        if (!empty($tokens)) {
            $args['s'] = implode(' ', $tokens);
        }

        $q = new WP_Query($args);
        return array_map('intval', (array) $q->posts);
    }

    /**
     * v1.9.9 IDs de producto por título. mode: 'starts' | 'contains' | 'wp_s'.
     * Consulta acotada por LIMIT. No carga todo el catálogo.
     */
    private static function search_ids_by_title($term, $mode, $limit, array $cat_tax_query = []) {
        global $wpdb;
        $term = trim((string) $term);
        if ($term === '') { return []; }
        $limit = max(1, (int) $limit);

        // Para 'wp_s' delegamos en WP_Query (búsqueda estándar), útil como fallback.
        if ($mode === 'wp_s') {
            $args = [
                'post_type' => 'product',
                'post_status' => 'publish',
                'posts_per_page' => $limit,
                'fields' => 'ids',
                'no_found_rows' => true,
                's' => $term,
            ];
            if (!empty($cat_tax_query)) {
                $args['tax_query'] = $cat_tax_query;
            }
            $q = new WP_Query($args);
            return array_map('intval', (array) $q->posts);
        }

        // 'starts' / 'contains' contra post_title directamente (rápido, indexable).
        $like = ($mode === 'starts')
            ? $wpdb->esc_like($term) . '%'
            : '%' . $wpdb->esc_like($term) . '%';

        // Restricción de categoría (si aplica) vía subconsulta de term_relationships.
        $cat_join = '';
        $cat_where = '';
        if (!empty($cat_tax_query[0]['terms'][0])) {
            $cat_id = (int) $cat_tax_query[0]['terms'][0];
            $descendants = get_term_children($cat_id, 'product_cat');
            $cat_ids = array_map('intval', array_merge([$cat_id], is_array($descendants) ? $descendants : []));
            $cat_ids_sql = implode(',', $cat_ids);
            $cat_join = "INNER JOIN {$wpdb->term_relationships} tr ON tr.object_id = p.ID";
            $cat_where = "AND tr.term_taxonomy_id IN ($cat_ids_sql)";
        }

        $sql = $wpdb->prepare(
            "SELECT DISTINCT p.ID FROM {$wpdb->posts} p
             $cat_join
             WHERE p.post_type = 'product'
               AND p.post_status = 'publish'
               AND p.post_title LIKE %s
               $cat_where
             ORDER BY p.post_title ASC
             LIMIT %d",
            $like,
            $limit
        );

        $ids = $wpdb->get_col($sql);
        return array_map('intval', (array) $ids);
    }

    /**
     * v1.9.9 IDs de producto por SKU parcial (LIKE), acotado por LIMIT.
     * Devuelve el producto padre para variaciones.
     */
    private static function search_ids_by_sku_like($term, $limit) {
        global $wpdb;
        $term = trim((string) $term);
        if ($term === '') { return []; }
        $limit = max(1, (int) $limit);
        $like = '%' . $wpdb->esc_like($term) . '%';

        $rows = $wpdb->get_col($wpdb->prepare(
            "SELECT pm.post_id FROM {$wpdb->postmeta} pm
             INNER JOIN {$wpdb->posts} p ON p.ID = pm.post_id
             WHERE pm.meta_key = '_sku'
               AND pm.meta_value LIKE %s
               AND p.post_type IN ('product','product_variation')
               AND p.post_status = 'publish'
             LIMIT %d",
            $like,
            $limit
        ));

        $ids = [];
        foreach ((array) $rows as $pid) {
            $product = wc_get_product((int) $pid);
            if (!($product instanceof WC_Product)) { continue; }
            $target = $product->is_type('variation') ? $product->get_parent_id() : (int) $pid;
            if ($target > 0) { $ids[$target] = $target; }
        }
        return array_values($ids);
    }

    /**
     * v1.9.9 IDs de producto por coincidencia en marca o categoría (nombre/slug).
     */
    private static function search_ids_by_taxonomy($term, $limit, array $cat_tax_query = []) {
        $term = trim((string) $term);
        if ($term === '' || mb_strlen($term) < 3) { return []; }
        $limit = max(1, (int) $limit);

        $taxonomies = array_merge(['product_cat'], self::brand_taxonomies());
        $matched_term_ids = [];
        $matched_taxonomies = [];

        foreach ($taxonomies as $taxonomy) {
            if (!taxonomy_exists($taxonomy)) { continue; }
            $found = get_terms([
                'taxonomy' => $taxonomy,
                'hide_empty' => true,
                'search' => $term,
                'number' => 5,
                'fields' => 'ids',
            ]);
            if (!is_wp_error($found) && !empty($found)) {
                foreach ($found as $tid) {
                    $matched_term_ids[] = (int) $tid;
                    $matched_taxonomies[$taxonomy] = true;
                }
            }
        }

        if (empty($matched_term_ids)) { return []; }

        $tax_query = ['relation' => 'OR'];
        foreach (array_keys($matched_taxonomies) as $taxonomy) {
            $tax_query[] = [
                'taxonomy' => $taxonomy,
                'field' => 'term_id',
                'terms' => $matched_term_ids,
                'operator' => 'IN',
                'include_children' => ($taxonomy === 'product_cat'),
            ];
        }

        $args = [
            'post_type' => 'product',
            'post_status' => 'publish',
            'posts_per_page' => $limit,
            'fields' => 'ids',
            'no_found_rows' => true,
            'tax_query' => $tax_query,
        ];

        // Intersección con la categoría del contexto, si se pidió.
        if (!empty($cat_tax_query)) {
            $args['tax_query'] = ['relation' => 'AND', $cat_tax_query[0], $tax_query];
        }

        $q = new WP_Query($args);
        return array_map('intval', (array) $q->posts);
    }


    public static function app_product_payload(WC_Product $product, $can_view_stock = false) {
        return self::product_payload($product, $can_view_stock);
    }

    /**
     * v1.9.7 STOCK WEB: WooCommerce stock_status es la única autoridad comercial
     * para permitir compra. Los metadatos internos stock-gen/stock-tie/General/Murcia
     * son informativos y no bloquean carrito, preview ni creación de pedido.
     */
    private static function app_stock_status(WC_Product $product) {
        $status = (string) $product->get_stock_status();

        if ($status === '') {
            $status = (string) get_post_meta($product->get_id(), '_stock_status', true);
        }

        if (!in_array($status, ['instock', 'outofstock', 'onbackorder'], true)) {
            $status = 'outofstock';
        }

        return $status;
    }

    /**
     * v1.9.7 STOCK WEB: permite comprar/reservar si WooCommerce dice
     * instock u onbackorder; bloquea únicamente outofstock.
     */
    private static function app_product_available_by_stock_status(WC_Product $product) {
        $status = self::app_stock_status($product);
        return in_array($status, ['instock', 'onbackorder'], true);
    }

    private static function product_payload(WC_Product $product, $can_view_stock = false) {
        $product_id = $product->get_id();
        $price_data = self::resolve_product_price_data($product);

        $display_price = $price_data['display_price'];
        $display_regular = $price_data['display_regular_price'];
        $raw_price = $price_data['raw_price'];

        $image_id = $product->get_image_id();
        $image = $image_id ? wp_get_attachment_image_url($image_id, 'woocommerce_thumbnail') : wc_placeholder_img_src('woocommerce_thumbnail');
        $image_full = $image_id ? wp_get_attachment_image_url($image_id, 'full') : $image;

        $gallery = [];
        foreach ($product->get_gallery_image_ids() as $gallery_id) {
            $url = wp_get_attachment_image_url($gallery_id, 'woocommerce_thumbnail');
            $full = wp_get_attachment_image_url($gallery_id, 'full');
            if ($url) {
                $gallery[] = ['src' => $url, 'full_src' => $full ?: $url];
            }
        }

        $categories = [];
        foreach (wp_get_post_terms($product_id, 'product_cat') as $term) {
            if ($term instanceof WP_Term) {
                $categories[] = [
                    'id' => (int) $term->term_id,
                    'name' => html_entity_decode($term->name, ENT_QUOTES, 'UTF-8'),
                    'slug' => $term->slug,
                ];
            }
        }

        $attributes = [];
        foreach ($product->get_attributes() as $attribute) {
            if (!($attribute instanceof WC_Product_Attribute)) {
                continue;
            }

            $name = wc_attribute_label($attribute->get_name());
            $taxonomy = $attribute->get_name();
            $options = [];

            if ($attribute->is_taxonomy()) {
                foreach ($attribute->get_terms() as $term) {
                    if ($term instanceof WP_Term) {
                        $options[] = html_entity_decode($term->name, ENT_QUOTES, 'UTF-8');
                    }
                }
            } else {
                $options = array_map('wc_clean', $attribute->get_options());
            }

            if (!empty($name) && !empty($options)) {
                $attributes[] = [
                    'name' => $name,
                    'slug' => $taxonomy,
                    'options' => array_values($options),
                ];
            }
        }

        $stock_gen = (int) get_post_meta($product_id, 'stock-gen', true);
        $stock_tie = (int) get_post_meta($product_id, 'stock-tie', true);
        $stock_locations = [];
        $meta_data = [];

        if ($can_view_stock) {
            $stock_locations[] = [
                'name' => 'General',
                'quantity' => $stock_gen,
            ];
            $stock_locations[] = [
                'name' => 'Murcia',
                'quantity' => $stock_tie,
            ];
            $meta_data[] = ['key' => 'stock-gen', 'value' => $stock_gen];
            $meta_data[] = ['key' => 'stock-tie', 'value' => $stock_tie];
        }

        $stock_status = self::app_stock_status($product);
        $is_in_stock = self::app_product_available_by_stock_status($product);
        $has_price = (bool) $price_data['has_price'];
        $is_purchasable_raw = $product->is_purchasable();
        $can_add_to_cart = $is_purchasable_raw && $has_price && $is_in_stock;

        $brand_name = self::get_product_brand_name($product_id, $attributes);
        $formatted_price = $has_price ? wc_format_decimal($display_price, 2) : '0.00';
        $formatted_regular = $display_regular !== '' && is_numeric($display_regular)
            ? wc_format_decimal($display_regular, 2)
            : $formatted_price;

        return [
            'id' => $product_id,
            'type' => $product->get_type(),
            'name' => html_entity_decode($product->get_name(), ENT_QUOTES, 'UTF-8'),
            'sku' => $product->get_sku(),
            'price' => $formatted_price,
            'regular_price' => $formatted_regular,
            'display_price' => $formatted_price,
            'display_regular_price' => $formatted_regular,
            'role_price' => $formatted_price,
            'raw_price' => $raw_price === '' ? '' : (string) $raw_price,
            'sale_price' => ($price_data['price_context'] ?? self::current_price_context()) === 'admin'
                ? (string) self::raw_product_meta($product_id, '_sale_price')
                : (string) $product->get_sale_price(),
            'price_html' => !empty($price_data['price_html']) ? $price_data['price_html'] : '',
            'can_view_prices' => true,
            'price_source' => $price_data['source'],
            'price_context' => $price_data['price_context'] ?? self::current_price_context(),
            'role_price_context' => $price_data['price_context'] ?? self::current_price_context(),
            'role_price_key' => self::current_role_price_key(),
            'effective_price_group' => isset($price_data['effective_price_role']['price_group']) ? (string) $price_data['effective_price_role']['price_group'] : self::extract_percentage_from_role_payload($price_data['effective_price_role'] ?? []),
            'effective_price_role' => $price_data['effective_price_role'] ?? [],
            'app_user_id' => (int) self::$current_app_user_id,
            'debug_roles' => self::current_app_user_roles(),
            'prices' => [
                'price' => $has_price ? (string) round(((float) $formatted_price) * 100) : '0',
                'regular_price' => $has_price ? (string) round(((float) $formatted_regular) * 100) : '0',
                'currency_minor_unit' => 2,
                'currency_code' => function_exists('get_woocommerce_currency') ? get_woocommerce_currency() : 'EUR',
                'currency_symbol' => function_exists('get_woocommerce_currency_symbol') ? get_woocommerce_currency_symbol() : '€',
            ],
            'has_price' => $has_price,
            'images' => array_merge([['src' => $image, 'full_src' => $image_full ?: $image]], $gallery),
            'image' => $image,
            'stock_status' => $stock_status,
            'stock_quantity' => $can_view_stock ? (int) $product->get_stock_quantity() : 0,
            'is_in_stock' => $is_in_stock,
            'is_purchasable' => $can_add_to_cart,
            'purchasable' => $can_add_to_cart,
            'on_sale' => $product->is_on_sale(),
            'short_description' => wp_strip_all_tags($product->get_short_description()),
            'description' => wp_kses_post($product->get_description()),
            'categories' => $categories,
            'attributes' => $attributes,
            'brand_name' => $brand_name,
            'brand' => $brand_name,
            'stock_locations' => $stock_locations,
            'meta_data' => $meta_data,
            'can_add_to_cart' => $can_add_to_cart,
            // En B2B el presupuesto debe estar disponible aunque falte precio/stock directo.
            'can_request_quote' => true,
            'permalink' => get_permalink($product_id),
        ];
    }

    /**
     * Resuelve el precio que debe ver la app según el rol real del usuario autenticado.
     *
     * Regla v1.5.2:
     * - Administrador / gestor de tienda: precio base/admin de WooCommerce (_price / _sale_price / _regular_price).
     * - Comercial: precio que WooCommerce/plugin B2B calcule para su rol comercial.
     * - Cliente: precio que WooCommerce/plugin B2B calcule para ese cliente.
     *
     * No se unifican precios entre roles.
     */
    private static function resolve_product_price_data(WC_Product $product) {
        /**
         * v1.6.0 FINAL ROLES/PRECIOS:
         * - El usuario válido es el autenticado por app_token, no wp_get_current_user()
         *   si WordPress lo devuelve vacío en REST.
         * - Admin/gestor NUNCA acepta precio filtrado de cliente. Lee precio base RAW
         *   de WooCommerce directamente desde wp_postmeta.
         * - Cliente/comercial calculan con rol efectivo único para evitar mezclas de roles.
         */
        $user = self::current_app_user();
        $effective = self::effective_price_role_payload($user);
        $price_context = isset($effective['context']) ? (string) $effective['context'] : 'cliente';
        $effective_role = isset($effective['price_role']) && (string) $effective['price_role'] !== '' ? (string) $effective['price_role'] : (isset($effective['role']) ? (string) $effective['role'] : '');

        if ($price_context === 'admin') {
            $effective = self::price_payload_for_group('52', $effective_role, 'cliente', 'admin_context_guard_forced_cliente_52_69_181', isset($effective['all_roles']) ? (array) $effective['all_roles'] : []);
            $price_context = 'cliente';
            $effective_role = isset($effective['price_role']) ? (string) $effective['price_role'] : 'cliente_52_69';
        }

        $role_price = self::resolve_role_filtered_price_data($product, $price_context, $effective_role);
        $role_price['effective_price_role'] = $effective;
        return $role_price;
    }

    private static function current_price_context($user = null) {
        if ((!($user instanceof WP_User) || empty($user->ID)) && !empty(self::$current_app_user_id)) {
            $user = get_user_by('id', (int) self::$current_app_user_id);
        }

        if (!($user instanceof WP_User) || empty($user->ID)) {
            $user = self::current_app_user();
        }

        $effective = self::effective_price_role_payload($user);
        return isset($effective['context']) ? (string) $effective['context'] : 'cliente';
    }

    private static function current_app_user() {
        if (!empty(self::$current_app_user_id)) {
            $user = get_user_by('id', (int) self::$current_app_user_id);
            if ($user instanceof WP_User && !empty($user->ID)) {
                return $user;
            }
        }

        $current_id = get_current_user_id();
        if ($current_id > 0) {
            $user = get_user_by('id', (int) $current_id);
            if ($user instanceof WP_User && !empty($user->ID)) {
                return $user;
            }
        }

        $user = wp_get_current_user();
        return ($user instanceof WP_User && !empty($user->ID)) ? $user : null;
    }

    private static function price_group_candidates() {
        /**
         * Grupos reales de tarifa B2B que definen precio.
         *
         * Regla MundiCam v1.7.7:
         * En roles tipo "Cliente 52% (69)" o "comercial_52_69", el grupo de precio es 52.
         * Lo que aparece entre paréntesis o detrás del segundo número NO se usa para tarifa.
         */
        return [
            '25',
            '30',
            '35',
            '40',
            '42',
            '45',
            '50',
            '52',
            '53',
            '54',
            '55',
            '57',
        ];
    }

    private static function normalize_role_slug($role) {
        $role = strtolower((string) $role);
        $map = [
            'á' => 'a', 'à' => 'a', 'ä' => 'a', 'â' => 'a',
            'é' => 'e', 'è' => 'e', 'ë' => 'e', 'ê' => 'e',
            'í' => 'i', 'ì' => 'i', 'ï' => 'i', 'î' => 'i',
            'ó' => 'o', 'ò' => 'o', 'ö' => 'o', 'ô' => 'o',
            'ú' => 'u', 'ù' => 'u', 'ü' => 'u', 'û' => 'u',
            'ñ' => 'n',
        ];
        $role = strtr($role, $map);
        $role = str_replace('-', '_', $role);
        return trim(preg_replace('/[^a-z0-9_]+/', '_', $role), '_');
    }

    private static function extract_price_group_from_role_slug($role) {
        $slug = self::normalize_role_slug($role);
        if ($slug === '') {
            return '';
        }

        /**
         * Regla principal MundiCam:
         * - cliente_25       => 25
         * - comercial_52_69  => 52
         * - cliente_42_65    => 42
         *
         * El número posterior no forma parte de la tarifa que debe aplicar la app.
         */
        if (preg_match('/^(cliente|comercial)_([0-9]{2,3})(?:_|$)/', $slug, $m)) {
            return (string) $m[2];
        }

        foreach (self::price_group_candidates() as $group) {
            if (preg_match('/(^|_)' . preg_quote($group, '/') . '($|_)/', $slug)) {
                return (string) $group;
            }
        }

        // Fallback para labels donde el separador no venga como guion bajo.
        $compact = self::normalize_role($role);
        foreach (self::price_group_candidates() as $group) {
            if (preg_match('/(?:^|[^0-9])' . preg_quote($group, '/') . '(?:[^0-9]|$)/', $compact)) {
                return (string) $group;
            }
        }

        return '';
    }

    private static function effective_price_role_payload($user = null) {
        if (!($user instanceof WP_User)) {
            $user = self::current_app_user();
        }

        $roles = $user instanceof WP_User ? array_values((array) $user->roles) : [];

        /*
         * v1.8.1 PRIORIDAD CORRECTA:
         * 1) Comercial real X% primero.
         * 2) Admin/Gestor/capacidades WooCommerce después.
         * 3) Cliente real X% después.
         *
         * Motivo: algunos comerciales tienen capacidades auxiliares de gestión.
         * Si comprobamos user_can(manage_woocommerce) antes que el rol comercial,
         * un Comercial 35% puede caer erróneamente en grupo 52.
         */

        // 1) Comercial X%: precio del grupo comercial correspondiente.
        foreach ($roles as $role) {
            $n = self::normalize_role($role);
            if (strpos($n, 'comercial') === 0) {
                $group = self::extract_price_group_from_role($role);
                if ($group !== '') {
                    return self::price_payload_for_group($group, $role, 'comercial', 'mapped_comercial_group_' . $group . '_181', $roles);
                }
            }
        }

        // 2) Admin/Gestor: mantiene permisos reales, pero PRECIO = cliente_52_69.
        foreach ($roles as $role) {
            $n = self::normalize_role($role);
            if (in_array($n, [
                'administrator',
                'administrador',
                'admin',
                'shopmanager',
                'shopmanagers',
                'gestordelatienda',
                'gestortienda',
                'storemanager',
                'woocommerceadministrator',
            ], true)) {
                return self::price_payload_for_group('52', $role, 'cliente', 'admin_forced_cliente_52_69_181', $roles);
            }
        }

        try {
            if ($user instanceof WP_User && (user_can($user, 'manage_options') || user_can($user, 'manage_woocommerce') || user_can($user, 'edit_others_shop_orders'))) {
                $role = !empty($roles[0]) ? (string) $roles[0] : 'administrator';
                return self::price_payload_for_group('52', $role, 'cliente', 'admin_capability_forced_cliente_52_69_181', $roles);
            }
        } catch (Throwable $e) {
            // Seguimos con roles textuales.
        }

        // 3) Cliente X%: precio del grupo cliente correspondiente. No tocar clientes.
        foreach ($roles as $role) {
            $n = self::normalize_role($role);
            if (strpos($n, 'cliente') === 0 || $n === 'customer') {
                $group = self::extract_price_group_from_role($role);
                if ($group !== '') {
                    return self::price_payload_for_group($group, $role, 'cliente', 'mapped_cliente_group_' . $group . '_181', $roles);
                }
            }
        }

        // 4) Fallback: si el rol contiene un porcentaje válido, lo usamos como cliente.
        foreach ($roles as $role) {
            $group = self::extract_price_group_from_role($role);
            if ($group !== '') {
                return self::price_payload_for_group($group, $role, 'cliente', 'mapped_any_group_' . $group . '_181', $roles);
            }
        }

        $fallback = !empty($roles[0]) ? (string) $roles[0] : '';
        return [
            'context' => 'cliente',
            'role' => $fallback,
            'normalized_role' => self::normalize_role($fallback),
            'role_slug' => self::normalize_role_slug($fallback),
            'price_role' => self::resolve_existing_price_role('52', 'cliente', 'cliente_52_69'),
            'price_group' => '52',
            'forced_price_group' => '52',
            'all_roles' => $roles,
            'source' => 'fallback_price_group_52_181',
        ];
    }

    private static function with_effective_price_role($user, $effective_role, callable $callback) {
        if (!($user instanceof WP_User) || $effective_role === '') {
            return $callback();
        }

        $current = wp_get_current_user();
        $saved_user_id = $current instanceof WP_User ? (int) $current->ID : 0;

        wp_set_current_user((int) $user->ID);
        $wp_user = wp_get_current_user();

        $saved_roles = $wp_user instanceof WP_User ? $wp_user->roles : [];
        $saved_caps = $wp_user instanceof WP_User ? $wp_user->caps : [];
        $saved_allcaps = $wp_user instanceof WP_User ? $wp_user->allcaps : [];

        try {
            if ($wp_user instanceof WP_User) {
                $wp_user->roles = [$effective_role];
                $wp_user->caps = [$effective_role => true];
                // Recalcular capacidades para que plugins B2B lean un único rol efectivo.
                if (method_exists($wp_user, 'get_role_caps')) {
                    $wp_user->get_role_caps();
                }
            }

            if (function_exists('WC') && WC() && class_exists('WC_Customer')) {
                try {
                    WC()->customer = new WC_Customer((int) $user->ID, true);
                } catch (Throwable $e) {
                    // No bloqueamos precio por fallo de customer.
                }
            }

            return $callback();
        } finally {
            if ($wp_user instanceof WP_User) {
                $wp_user->roles = $saved_roles;
                $wp_user->caps = $saved_caps;
                $wp_user->allcaps = $saved_allcaps;
            }
            if ($saved_user_id > 0) {
                wp_set_current_user($saved_user_id);
            }
        }
    }

    private static function is_admin_price_context($user) {
        if (!($user instanceof WP_User)) {
            return false;
        }

        try {
            if (user_can($user, 'manage_options') || user_can($user, 'manage_woocommerce') || user_can($user, 'edit_others_shop_orders')) {
                return true;
            }
        } catch (Throwable $e) {
            // Continuamos con comprobación por rol textual.
        }

        foreach ((array) $user->roles as $role) {
            $normalized = self::normalize_role($role);
            if (in_array($normalized, [
                'admin',
                'administrator',
                'administrador',
                'shopmanager',
                'shopmanagers',
                'gestordelatienda',
                'gestortienda',
                'storemanager',
                'woocommerceadministrator',
            ], true)) {
                return true;
            }
        }

        return false;
    }


    private static function current_app_user_roles() {
        $user = self::current_app_user();
        return $user instanceof WP_User ? array_values((array) $user->roles) : [];
    }

    private static function current_role_price_key() {
        $effective = self::effective_price_role_payload(self::current_app_user());
        $context = isset($effective['context']) ? (string) $effective['context'] : 'cliente';
        $role = isset($effective['price_role']) && (string) $effective['price_role'] !== ''
            ? (string) $effective['price_role']
            : (isset($effective['role']) ? (string) $effective['role'] : '');
        return $context . '|' . ($role !== '' ? self::normalize_role_slug($role) : 'sinrol');
    }

    public static function app_current_user_can_view_internal_stock() {
        return self::can_view_internal_stock(self::current_app_user());
    }

    public static function app_catalog_cache_identity() {
        $user = self::current_app_user();
        $user_id = $user instanceof WP_User ? (int) $user->ID : 0;
        return 'user:' . $user_id . '|role:' . self::current_role_price_key();
    }

    public static function app_product_price_number(WC_Product $product) {
        $price_data = self::resolve_product_price_data($product);
        return (!empty($price_data['has_price']) && is_numeric($price_data['display_price'])) ? (float) $price_data['display_price'] : null;
    }

    private static function resolve_admin_base_price_data(WC_Product $product) {
        /**
         * v1.5.6 HARD FIX ADMIN:
         * Para admin/gestor NO usamos get_price(), get_regular_price(), get_price_html()
         * ni wc_get_price_to_display(), porque algunos plugins B2B pueden filtrar esos
         * valores en REST y devolver precio de cliente aunque el usuario tenga rol admin.
         *
         * Leemos directamente el precio base de WooCommerce desde wp_postmeta y devolvemos
         * ese número como price/display_price/regular_price/price_html del payload de la app.
         */
        $raw_price = self::base_meta_price_for_product($product);
        $regular_price = self::base_regular_meta_price_for_product($product);

        if (($regular_price === '' || $regular_price === null || !is_numeric($regular_price))) {
            $regular_price = $raw_price;
        }

        $display_price = '';
        $display_regular = '';

        if ($raw_price !== '' && $raw_price !== null && is_numeric($raw_price)) {
            $display_price = (float) $raw_price;
        }

        if ($regular_price !== '' && $regular_price !== null && is_numeric($regular_price)) {
            $display_regular = (float) $regular_price;
        }

        $price_html = '';
        if ($display_price !== '' && is_numeric($display_price)) {
            $price_html = function_exists('wc_price') ? wc_price((float) $display_price) : number_format((float) $display_price, 2, ',', '.') . ' €';
        }

        return [
            'raw_price' => ($raw_price === null ? '' : $raw_price),
            'raw_regular_price' => ($regular_price === null ? '' : $regular_price),
            'display_price' => $display_price,
            'display_regular_price' => $display_regular,
            'has_price' => ($display_price !== '' && is_numeric($display_price) && (float) $display_price > 0),
            'source' => 'admin_raw_postmeta_no_filters_160',
            'price_context' => 'admin',
            'price_html' => $price_html,
        ];
    }

    private static function base_meta_price_for_product(WC_Product $product) {
        if ($product->is_type('variable')) {
            $prices = [];
            foreach ($product->get_children() as $variation_id) {
                $variation = wc_get_product($variation_id);
                if (!($variation instanceof WC_Product)) {
                    continue;
                }
                $candidate = self::first_numeric_product_meta_price($variation->get_id(), ['_price', '_sale_price', '_regular_price']);
                if ($candidate !== '' && $candidate !== null && is_numeric($candidate) && (float) $candidate > 0) {
                    $prices[] = (float) $candidate;
                }
            }
            if (!empty($prices)) {
                return min($prices);
            }
        }

        return self::first_numeric_product_meta_price($product->get_id(), ['_price', '_sale_price', '_regular_price']);
    }

    private static function base_regular_meta_price_for_product(WC_Product $product) {
        if ($product->is_type('variable')) {
            $prices = [];
            foreach ($product->get_children() as $variation_id) {
                $candidate = self::raw_product_meta((int) $variation_id, '_regular_price');
                if ($candidate !== '' && $candidate !== null && is_numeric($candidate) && (float) $candidate > 0) {
                    $prices[] = (float) $candidate;
                }
            }
            if (!empty($prices)) {
                return min($prices);
            }
        }

        $regular = self::raw_product_meta($product->get_id(), '_regular_price');
        if ($regular !== '' && $regular !== null && is_numeric($regular)) {
            return $regular;
        }

        return self::base_meta_price_for_product($product);
    }

    private static function first_numeric_product_meta_price($product_id, array $keys) {
        foreach ($keys as $meta_key) {
            $meta_price = self::raw_product_meta((int) $product_id, $meta_key);
            if ($meta_price !== '' && $meta_price !== null && is_numeric($meta_price)) {
                return $meta_price;
            }
        }

        return '';
    }

    /**
     * Lee postmeta directamente desde la base de datos, sin pasar por get_post_meta().
     * Algunos plugins B2B filtran get_price()/get_post_meta() según rol y pueden devolver
     * precio de cliente incluso para admin en REST. Para admin necesitamos el precio base real.
     */
    private static function raw_product_meta($product_id, $meta_key) {
        global $wpdb;

        $product_id = (int) $product_id;
        $meta_key = (string) $meta_key;
        if ($product_id <= 0 || $meta_key === '' || !isset($wpdb->postmeta)) {
            return '';
        }

        $value = $wpdb->get_var($wpdb->prepare(
            "SELECT meta_value FROM {$wpdb->postmeta} WHERE post_id = %d AND meta_key = %s ORDER BY meta_id DESC LIMIT 1",
            $product_id,
            $meta_key
        ));

        if ($value === null) {
            return '';
        }

        $value = maybe_unserialize($value);
        if (is_array($value) || is_object($value)) {
            return '';
        }

        return trim((string) $value);
    }

    private static function role_discount_percent_from_group($group) {
        $group = trim((string) $group);
        if ($group === '' || strtolower($group) === 'pvp' || strtolower($group) === 'admin') {
            return null;
        }

        if (!in_array($group, self::price_group_candidates(), true)) {
            return null;
        }

        return is_numeric($group) ? (float) $group : null;
    }

    private static function price_values_are_same($a, $b, $precision = 0.005) {
        if ($a === '' || $a === null || $b === '' || $b === null || !is_numeric($a) || !is_numeric($b)) {
            return false;
        }

        return abs((float) $a - (float) $b) <= (float) $precision;
    }

    private static function role_price_meta_candidates(WC_Product $product, array $effective) {
        $product_id = (int) $product->get_id();
        if ($product_id <= 0) {
            return [];
        }

        $role = isset($effective['role']) ? (string) $effective['role'] : '';
        $price_role = isset($effective['price_role']) ? (string) $effective['price_role'] : '';
        $context = isset($effective['context']) ? (string) $effective['context'] : '';
        $group = isset($effective['price_group']) ? (string) $effective['price_group'] : '';

        $needles = array_unique(array_filter([
            self::normalize_role_slug($role),
            self::normalize_role_slug($price_role),
            self::normalize_role_slug($context . '_' . $group),
            self::normalize_role($role),
            self::normalize_role($price_role),
        ]));

        if (empty($needles)) {
            return [];
        }

        $meta = get_post_meta($product_id);
        if (empty($meta) || !is_array($meta)) {
            return [];
        }

        $matches = [];
        foreach ($meta as $key => $values) {
            $key_string = (string) $key;
            $key_slug = self::normalize_role_slug($key_string);
            $key_compact = self::normalize_role($key_string);

            if (strpos($key_slug, 'price') === false && strpos($key_slug, 'precio') === false && strpos($key_slug, 'regular') === false && strpos($key_slug, 'sale') === false) {
                continue;
            }

            $matches_role = false;
            foreach ($needles as $needle) {
                if ($needle !== '' && (strpos($key_slug, $needle) !== false || strpos($key_compact, str_replace('_', '', $needle)) !== false)) {
                    $matches_role = true;
                    break;
                }
            }

            if (!$matches_role) {
                continue;
            }

            foreach ((array) $values as $value) {
                $value = maybe_unserialize($value);
                if (is_array($value)) {
                    $iterator = new RecursiveIteratorIterator(new RecursiveArrayIterator($value));
                    foreach ($iterator as $nested_value) {
                        if (is_scalar($nested_value) && is_numeric((string) $nested_value) && (float) $nested_value > 0) {
                            $matches[] = [
                                'key' => $key_string,
                                'value' => (float) $nested_value,
                            ];
                        }
                    }
                    continue;
                }

                if (is_scalar($value) && is_numeric((string) $value) && (float) $value > 0) {
                    $matches[] = [
                        'key' => $key_string,
                        'value' => (float) $value,
                    ];
                }
            }
        }

        return $matches;
    }

    private static function best_role_meta_price(WC_Product $product, array $effective) {
        $matches = self::role_price_meta_candidates($product, $effective);
        if (empty($matches)) {
            return null;
        }

        // Priorizamos claves que parezcan precio final/sale frente a regular/base.
        usort($matches, static function($a, $b) {
            $ka = strtolower((string) ($a['key'] ?? ''));
            $kb = strtolower((string) ($b['key'] ?? ''));

            $score = static function($key) {
                $score = 0;
                if (strpos($key, 'sale') !== false || strpos($key, 'price') !== false || strpos($key, 'precio') !== false) {
                    $score += 20;
                }
                if (strpos($key, 'regular') !== false || strpos($key, 'base') !== false) {
                    $score -= 10;
                }
                return $score;
            };

            return $score($kb) <=> $score($ka);
        });

        return $matches[0];
    }

    /**
     * v1.9.13 Precio con descuentos de CARRITO aplicados (plugin "Reglas de
     * descuento" / Advanced Woo Discount Rules, dynamic pricing, etc.).
     *
     * El problema: estos plugins aplican su descuento (p.ej. 10,5% adicional al
     * 52% del rol) al PRECIO DEL PRODUCTO en el carrito, NO en el <ins> de la ficha.
     * Por eso el parseo del HTML no lo ve. Aquí le pedimos a WooCommerce/plugin el
     * precio final para este producto y este usuario, del mismo modo que lo haría
     * el carrito, para el usuario logueado actual (ya fijado por bootstrap_user_context).
     *
     * Devuelve el precio final (float) o null si no hay un descuento adicional
     * aplicable por encima del $base_price ya resuelto.
     *
     * @param WC_Product $product   Producto.
     * @param float      $base_price Precio ya resuelto (rol) sobre el que el plugin
     *                               aplicaría su descuento adicional.
     */
    private static function cart_rules_discounted_price(WC_Product $product, $base_price) {
        $base_price = (float) $base_price;
        if ($base_price <= 0) {
            return null;
        }

        $best = null;

        $consider = function($candidate) use (&$best, $base_price) {
            if (is_numeric($candidate) && (float) $candidate > 0 && (float) $candidate < $base_price - 0.0005) {
                if ($best === null || (float) $candidate < $best) {
                    $best = (float) $candidate;
                }
            }
        };

        // Discount Rules for WooCommerce (Flycart, versión FREE) y Advanced Woo
        // Discount Rules (PRO) comparten base. Probamos las funciones/objetos de
        // ambas variantes sin acoplarnos a una sola.
        try {
            $engine = null;
            if (function_exists('advanced_woo_discount_rules')) {
                $engine = advanced_woo_discount_rules();          // PRO
            } elseif (function_exists('wdr_get_discount')) {
                $engine = null;                                    // FREE (helper suelto)
            } elseif (class_exists('\Wdr\App\Controllers\ManageDiscount')) {
                $engine = null;                                    // FREE (namespaced)
            }

            if (is_object($engine)) {
                foreach (['get_product_discount_price', 'getProductDiscountPrice', 'calculate_discount'] as $m) {
                    if (method_exists($engine, $m)) {
                        $p = $engine->{$m}($product, 1, $base_price);
                        $consider($p);
                    }
                }
            }
        } catch (Throwable $e) {
            // Ignorar: probamos filtros genéricos abajo.
        }

        // Filtros genéricos que exponen ambas variantes de Flycart y otros plugins
        // de precios dinámicos. Pasamos el precio base de rol y recogemos el rebajado.
        foreach ([
            'advanced_woo_discount_rules_get_product_discount_price',
            'woo_discount_rules_get_product_discount_price',
            'wdr_product_discounted_price',
        ] as $filter_name) {
            try {
                $filtered = apply_filters($filter_name, $base_price, $product, 1, 'discounted_price', true);
                $consider($filtered);
            } catch (Throwable $e) {
                // Continuar con el siguiente filtro.
            }
        }

        if ($best !== null && $best > 0 && $best < $base_price - 0.0005) {
            return round($best, 4);
        }

        // Respaldo robusto: el filtro estándar que aplican casi todos los plugins de
        // precios dinámicos sobre el precio del producto. Le pasamos el precio de rol
        // como base y vemos si algún plugin lo rebaja. Es el mismo hook que WooCommerce
        // usa al leer el precio, por lo que el plugin de Flycart engancha aquí.
        try {
            $filtered = apply_filters('woocommerce_product_get_price', $base_price, $product);
            if (is_numeric($filtered) && (float) $filtered > 0 && (float) $filtered < $base_price - 0.0005) {
                return round((float) $filtered, 4);
            }
        } catch (Throwable $e) {
            // Ignorar.
        }

        return null;
    }

    private static function calculate_php_role_price(WC_Product $product, array $effective) {
        $group = isset($effective['price_group']) ? (string) $effective['price_group'] : '';
        $discount = self::role_discount_percent_from_group($group);
        if ($discount === null) {
            return null;
        }

        $base = self::base_regular_meta_price_for_product($product);
        if ($base === '' || $base === null || !is_numeric($base) || (float) $base <= 0) {
            $base = self::base_meta_price_for_product($product);
        }

        if ($base === '' || $base === null || !is_numeric($base) || (float) $base <= 0) {
            return null;
        }

        $price = (float) $base * (1 - ((float) $discount / 100));
        if ($price <= 0) {
            return null;
        }

        return [
            'base' => (float) $base,
            'discount' => (float) $discount,
            'price' => round($price, 4),
        ];
    }

    private static function resolve_role_filtered_price_data(WC_Product $product, $price_context = 'cliente', $effective_role = '') {
        $user_for_price = self::current_app_user();
        return self::with_effective_price_role($user_for_price, (string) $effective_role, function() use ($product, $price_context, $effective_role) {
            $fresh_product = wc_get_product($product->get_id());
            if ($fresh_product instanceof WC_Product) {
                $product = $fresh_product;
            }
        $raw_price = $product->get_price();
        $regular_price = $product->get_regular_price();
        $source = 'role_filtered_get_price_152';

        // Productos variables: usar precio mínimo visible si el padre no devuelve precio directo.
        if (($raw_price === '' || $raw_price === null || !is_numeric($raw_price)) && $product->is_type('variable')) {
            $variation_price = $product->get_variation_price('min', true);
            if ($variation_price !== '' && $variation_price !== null && is_numeric($variation_price)) {
                $raw_price = $variation_price;
                $source = 'role_filtered_variation_min_price_154';
            }

            $variation_regular = $product->get_variation_regular_price('min', true);
            if (($regular_price === '' || $regular_price === null || !is_numeric($regular_price)) && $variation_regular !== '' && $variation_regular !== null && is_numeric($variation_regular)) {
                $regular_price = $variation_regular;
            }
        }

        // Fallback controlado a meta WooCommerce. No inventa precio; solo rescata _price si WooCommerce lo tiene guardado.
        if (($raw_price === '' || $raw_price === null || !is_numeric($raw_price))) {
            foreach (['_price', '_sale_price', '_regular_price'] as $meta_key) {
                $meta_price = get_post_meta($product->get_id(), $meta_key, true);
                if ($meta_price !== '' && $meta_price !== null && is_numeric($meta_price)) {
                    $raw_price = $meta_price;
                    $source = 'fallback_meta_' . $meta_key . '_154';
                    break;
                }
            }
        }

        if (($regular_price === '' || $regular_price === null || !is_numeric($regular_price))) {
            $meta_regular = get_post_meta($product->get_id(), '_regular_price', true);
            if ($meta_regular !== '' && $meta_regular !== null && is_numeric($meta_regular)) {
                $regular_price = $meta_regular;
            } else {
                $regular_price = $raw_price;
            }
        }

        $display_price = '';
        $display_regular = '';

        if ($raw_price !== '' && $raw_price !== null && is_numeric($raw_price)) {
            $display_price = wc_get_price_to_display($product, ['price' => (float) $raw_price]);
        }

        if ($regular_price !== '' && $regular_price !== null && is_numeric($regular_price)) {
            $display_regular = wc_get_price_to_display($product, ['price' => (float) $regular_price]);
        }

        // Algunos plugins B2B no modifican get_price(), pero sí get_price_html().
        // En servidor sí podemos usar el HTML como fuente de validación para devolver
        // campos numéricos limpios a Flutter. Flutter NO debe parsear HTML.
        $html_price = self::parse_price_from_html($product->get_price_html());

        // v1.9.12 ¿El HTML tiene un <ins>? Eso indica OFERTA/PROMOCIÓN real (precio
        // tachado + precio final). Solo en ese caso el precio del HTML es la fuente
        // de verdad con todos los descuentos encadenados y debemos evitar el
        // recálculo manual. Si NO hay <ins>, el HTML puede ser el PVP sin filtrar y
        // el descuento de rol se resuelve por meta/cálculo como siempre.
        $html_has_ins = (bool) preg_match('/<ins\b/i', (string) $product->get_price_html());

        // v1.9.15 Ratio de descuento extra (Flycart) desde el HTML (ins/del). Se
        // calcula aquí arriba porque condiciona los bloques siguientes.
        $extra_discount_ratio = self::extra_discount_ratio_from_html($product->get_price_html());
        $has_extra_discount = ($extra_discount_ratio !== null);

        // v1.9.3 Guard de cordura: un precio de rol/tarifa NUNCA puede superar el
        // PVP regular del producto. Si el precio parseado del HTML se dispara por
        // encima del PVP (síntoma de un parseo defectuoso), se descarta y se deja
        // que el precio lo resuelva el cálculo PHP por descuento de grupo, que es
        // determinista. Referencia PVP: regular del producto o meta base.
        $reference_regular = null;
        foreach ([$regular_price, $display_regular, $product->get_regular_price(), self::base_meta_price_for_product($product)] as $candidate_regular) {
            if ($candidate_regular !== '' && $candidate_regular !== null && is_numeric($candidate_regular) && (float) $candidate_regular > 0) {
                $reference_regular = (float) $candidate_regular;
                break;
            }
        }
        if ($html_price !== null && $reference_regular !== null && $html_price > ($reference_regular * 1.05 + 0.01)) {
            // Precio de HTML incoherente (mayor que el PVP). Se ignora.
            $html_price = null;
        }

        if ($html_price !== null && $html_price > 0) {
            if (($display_price === '' || !is_numeric($display_price) || (float) $display_price <= 0)) {
                // No teníamos precio: usamos el del HTML como último recurso.
                $display_price = $html_price;
                if ($raw_price === '' || $raw_price === null || !is_numeric($raw_price)) {
                    $raw_price = $html_price;
                }
                $source = 'price_html_parsed_175';
            } elseif (!$has_extra_discount && $html_has_ins && in_array($price_context, ['cliente', 'comercial'], true) && (float) $html_price < (float) $display_price - 0.005) {
                // v1.9.17 Solo se sustituye si el HTML aporta un precio MENOR (es
                // decir, añade descuento). Antes bastaba con que difiriera, y como el
                // HTML en REST no lleva el descuento de rol, podía SUBIR el precio y
                // dejar prácticamente el regular_price. Ahora ese caso es imposible.
                $display_price = $html_price;
                $raw_price = $html_price;
                $source = 'price_html_ins_role_price_175';
            }

            if ($display_regular === '' || !is_numeric($display_regular) || (float) $display_regular <= 0) {
                $display_regular = $html_price;
            }
        }

        // v1.9.15 DESCUENTOS ENCADENADOS (rol + Reglas de descuento / Flycart).
        //
        // Hallazgo clave: el get_price_html() generado en contexto REST NO es igual
        // al de la web. En REST, Flycart SÍ aplica su descuento pero el descuento de
        // ROL no se aplica. Ejemplo real (producto 199160, PVP 68,48):
        //     Web  (con rol): <del>32,87</del> <ins>29,42</ins>
        //     REST (sin rol): <del>68,48</del> <ins>61,29</ins>
        // Por eso coger el <ins> tal cual devolvía 61,29 (solo el 10,5%, perdiendo
        // el 52% del rol), que es justo el bug reportado.
        //
        // PERO el RATIO ins/del es IDÉNTICO en ambos (0,895 = descuento del 10,5%).
        // El ratio ya se calculó arriba ($extra_discount_ratio) y se aplica al final
        // sobre el precio de rol -> 32,87 x 0,895 = 29,42 (52% + 10,5% encadenados).

        $effective_payload = self::effective_price_role_payload($user_for_price);
        $admin_base_price = self::base_meta_price_for_product($product);
        $admin_display_price = ($admin_base_price !== '' && $admin_base_price !== null && is_numeric($admin_base_price))
            ? wc_get_price_to_display($product, ['price' => (float) $admin_base_price])
            : null;

        // v1.9.12 Solo evitamos el recálculo manual cuando el precio del HTML viene
        // de un <ins> (oferta real con descuentos ya aplicados). Si no hay <ins>, el
        // HTML puede ser el PVP sin filtrar por rol, y ENTONCES sí hay que recalcular
        // el descuento de rol (si no, saldría el regular_price sin descuento: el bug).
        $html_gave_price = ($html_price !== null && (float) $html_price > 0 && $html_has_ins);

        // v1.9.15 Flag: true solo si el precio de rol se recalculó limpio (sin el
        // descuento de Flycart dentro). Condición para aplicar el ratio sin duplicar.
        $role_price_is_clean = false;

        // v1.9.15 Cuando hay descuento extra (Flycart), get_price() y el HTML vienen
        // contaminados por ese descuento y NO coinciden con el precio admin base, por
        // lo que looks_unfiltered no se dispararía y nos quedaríamos sin el rol.
        // Forzamos el cálculo limpio del precio de rol en ese caso.
        $looks_unfiltered = !$html_gave_price
            && in_array($price_context, ['cliente', 'comercial'], true)
            && $admin_display_price !== null
            && self::price_values_are_same($display_price, $admin_display_price);

        if ($looks_unfiltered || $has_extra_discount) {
            $meta_price = self::best_role_meta_price($product, $effective_payload);
            if (is_array($meta_price) && isset($meta_price['value']) && is_numeric($meta_price['value']) && (float) $meta_price['value'] > 0) {
                $raw_price = (float) $meta_price['value'];
                $display_price = wc_get_price_to_display($product, ['price' => (float) $raw_price]);
                $source = 'role_meta_price_' . sanitize_key((string) $meta_price['key']) . '_177';
                $role_price_is_clean = true;
            } else {
                $manual = self::calculate_php_role_price($product, $effective_payload);
                if (is_array($manual) && isset($manual['price']) && is_numeric($manual['price']) && (float) $manual['price'] > 0) {
                    $raw_price = (float) $manual['price'];
                    $display_price = wc_get_price_to_display($product, ['price' => (float) $raw_price]);
                    $regular_price = $manual['base'];
                    $display_regular = wc_get_price_to_display($product, ['price' => (float) $manual['base']]);
                    $source = 'php_role_discount_calculated_' . sanitize_key((string) $manual['discount']) . '_177';
                    $role_price_is_clean = true;
                }
            }
        }

        // v1.9.15 Aplicar el descuento EXTRA (Flycart) SOBRE el precio de rol ya
        // resuelto. El ratio sale del HTML (ins/del) y es fiable aunque su base no
        // lleve el rol. Ejemplo 199160: precio_rol 32,87 x 0,895 = 29,42 (52%+10,5%).
        // El tachado que verá la app pasa a ser el precio de rol (32,87), como la web.
        //
        // IMPORTANTE (evitar doble descuento): solo se aplica si el precio base es un
        // precio de ROL recalculado limpio ($role_price_is_clean). Si no se pudo
        // recalcular (p.ej. cliente sin descuento de rol), get_price() ya trae el
        // descuento de Flycart aplicado y volver a multiplicar lo descontaría dos veces.
        if ($has_extra_discount && $role_price_is_clean
            && $raw_price !== '' && $raw_price !== null && is_numeric($raw_price) && (float) $raw_price > 0) {
            $role_only_price = (float) $raw_price;
            $final_price = round($role_only_price * $extra_discount_ratio, 4);

            if ($final_price > 0 && $final_price < $role_only_price - 0.0005) {
                // El precio "anterior" (tachado) es el precio con rol, sin la oferta.
                $regular_price = $role_only_price;
                $display_regular = wc_get_price_to_display($product, ['price' => $role_only_price]);

                $raw_price = $final_price;
                $display_price = wc_get_price_to_display($product, ['price' => $final_price]);
                $source = 'role_plus_extra_discount_' . str_replace('.', '_', (string) round((1 - $extra_discount_ratio) * 100, 2)) . 'pct_181';
            }
        }

        return [
            'raw_price' => ($raw_price === null ? '' : $raw_price),
            'raw_regular_price' => ($regular_price === null ? '' : $regular_price),
            'display_price' => $display_price,
            'display_regular_price' => $display_regular,
            'has_price' => ($display_price !== '' && is_numeric($display_price) && (float) $display_price > 0),
            'source' => $source . ($effective_role !== '' ? '_effective_' . sanitize_key($effective_role) . '_177' : '_177'),
            'price_context' => $price_context,
            'effective_role' => $effective_role,
            'price_html' => $product->get_price_html(),
        ];
        });
    }

    /**
     * v1.9.15 Ratio de descuento EXTRA (plugin "Reglas de descuento" / Flycart) a
     * partir del HTML de precio: ratio = ins / del.
     *
     * Por qué el ratio y no el precio del <ins> directamente: el HTML generado en
     * contexto REST puede NO llevar el descuento de rol aplicado (sí lleva el de
     * Flycart). Sus importes absolutos son entonces incorrectos, pero la PROPORCIÓN
     * entre tachado y final es la misma que en la web, porque es el descuento que
     * Flycart aplica. Ejemplo (producto 199160):
     *     Web  (con rol): 32,87 -> 29,42   ratio = 0,895
     *     REST (sin rol): 68,48 -> 61,29   ratio = 0,895   (idéntico)
     * Así podemos aplicar ese 10,5% sobre el precio de rol correcto y encadenar.
     *
     * @return float|null Ratio en (0,1) si hay descuento extra; null si no lo hay.
     */
    private static function extra_discount_ratio_from_html($html) {
        $html = (string) $html;
        if ($html === '' || stripos($html, '<ins') === false || stripos($html, '<del') === false) {
            return null;
        }

        $ins_price = self::parse_price_from_ins($html);
        $del_price = self::parse_price_from_del($html);

        if ($ins_price === null || $del_price === null) {
            return null;
        }
        if ($del_price <= 0 || $ins_price <= 0 || $ins_price >= $del_price) {
            return null;
        }

        $ratio = $ins_price / $del_price;

        // v1.9.17 Cordura: descartar solo lo absurdo (descuento > 95%). El límite
        // superior anterior (ratio >= 0.999) DESCARTABA descuentos pequeños legítimos:
        // la regla #159 "TAG NoPromo - DAHUA-LITE" aplica un 0,05%, cuyo ratio es
        // 0,9994 -> se ignoraba y el producto perdía también el descuento de rol.
        // La condición $ins_price < $del_price de arriba ya garantiza ratio < 1.
        if ($ratio <= 0.05) {
            return null;
        }

        // v1.9.17 Precisión: los importes del HTML vienen redondeados a 2 decimales,
        // así que el ratio crudo arrastra error (con un 0,05% desviaba 1 céntimo).
        // Los descuentos configurados en el plugin son valores limpios (0,05 / 10,5 /
        // 5...), por lo que redondeamos el PORCENTAJE detectado a 2 decimales y
        // reconstruimos el ratio exacto a partir de él.
        //   0,0477% -> 0,05%  ->  50,35 x 0,9995 = 50,32 ✔ (igual que la web)
        //  10,4959% -> 10,5%  ->  32,87 x 0,8950 = 29,42 ✔
        $discount_pct = round((1 - $ratio) * 100, 2);
        if ($discount_pct <= 0) {
            // Descuento imperceptible tras redondeo: no hay nada que aplicar.
            return null;
        }

        return 1 - ($discount_pct / 100);
    }

    /**
     * v1.9.14 Extrae el precio del <ins> (precio FINAL con todos los descuentos
     * encadenados). Devuelve float o null si no hay <ins>.
     */
    private static function parse_price_from_ins($html) {
        $html = (string) $html;
        if ($html === '' || stripos($html, '<ins') === false) {
            return null;
        }
        if (preg_match('/<ins\b[^>]*>(.*?)<\/ins>/is', $html, $m)) {
            return self::parse_price_from_html($m[1]);
        }
        return null;
    }

    /**
     * v1.9.14 Extrae el precio del <del> (precio anterior tachado; en MundiCam, el
     * precio con rol antes de la oferta). Devuelve float o null.
     */
    private static function parse_price_from_del($html) {
        $html = (string) $html;
        if ($html === '' || stripos($html, '<del') === false) {
            return null;
        }
        if (preg_match('/<del\b[^>]*>(.*?)<\/del>/is', $html, $m)) {
            return self::parse_price_from_html($m[1]);
        }
        return null;
    }

    private static function parse_price_from_html($html) {
        $html = (string) $html;
        if ($html === '') {
            return null;
        }

        // v1.9.11 PRECIO CON DESCUENTOS ENCADENADOS (rol + promoción):
        // Cuando la web muestra precio tachado, el HTML lleva <del>PVP</del><ins>final</ins>.
        // El precio CORRECTO (con todos los descuentos ya aplicados: rol 52% +
        // promoción 10% + lo que sea) es el del <ins>. Si existe <ins>, parseamos
        // SOLO su contenido; así nunca cogemos el tachado ni recalculamos a mano.
        $ins_html = '';
        if (preg_match('/<ins\b[^>]*>(.*?)<\/ins>/is', $html, $ins_match)) {
            $ins_html = $ins_match[1];
        }

        // v1.9.3 CORRECCIÓN CRÍTICA (bug cámara 10.185,55 €):
        // NO parsear todo el texto visible. La descripción del producto contiene
        // números (medidas "2,8 mm", "IK10", "IP67", resoluciones...) que al quitar
        // las etiquetas quedaban pegados al precio. Ejemplo real: "...IK10." seguido
        // de "185,55 €" se unía como "IK10.185,55" y el "10." se leía como separador
        // de miles → 10.185,55 €.
        //
        // WooCommerce siempre envuelve el importe en <span class="...Price-amount...">.
        // Extraemos SOLO el contenido de ese/esos span(s). Si hay <ins>, extraemos
        // solo dentro del <ins> (precio final con todos los descuentos).
        $scope_html = ($ins_html !== '') ? $ins_html : $html;
        $candidate_html = '';
        if (preg_match_all('/<span[^>]*class="[^"]*woocommerce-Price-amount[^"]*"[^>]*>(.*?)<\/span>/is', $scope_html, $amount_matches)) {
            $candidate_html = implode(' ', $amount_matches[1]);
        }

        // Fallback: si no hubiera span de precio (HTML atípico), se usa el texto
        // completo pero se filtrará por el símbolo de moneda más abajo.
        $use_currency_filter = ($candidate_html === '');
        $source_html = $use_currency_filter ? $scope_html : $candidate_html;

        $text = html_entity_decode(wp_strip_all_tags($source_html), ENT_QUOTES, 'UTF-8');
        $text = preg_replace('/\s+/', ' ', $text);
        if ($text === '') {
            return null;
        }

        if (!preg_match_all('/\d{1,3}(?:[\.\s]\d{3})*(?:,\d{1,4})|\d+(?:[\.,]\d{1,4})?/', $text, $matches)) {
            return null;
        }

        $values = [];
        foreach ($matches[0] as $raw) {
            $raw = trim((string) $raw);
            if ($raw === '') {
                continue;
            }

            $normalized = str_replace(' ', '', $raw);
            if (strpos($normalized, ',') !== false) {
                $normalized = str_replace('.', '', $normalized);
                $normalized = str_replace(',', '.', $normalized);
            }

            if (is_numeric($normalized)) {
                $value = (float) $normalized;
                if ($value > 0) {
                    $values[] = $value;
                }
            }
        }

        if (empty($values)) {
            return null;
        }

        // En HTML de oferta suele aparecer primero el precio tachado y después el precio actual.
        return (float) end($values);
    }

    private static function get_product_brand_name($product_id, array $attributes = []) {
        foreach ($attributes as $attribute) {
            $name = isset($attribute['name']) ? self::normalize_role($attribute['name']) : '';
            $slug = isset($attribute['slug']) ? self::normalize_role($attribute['slug']) : '';
            if (in_array($slug, ['pamarcas', 'pamarca', 'pafabricante'], true) || strpos($name, 'marca') !== false || strpos($name, 'fabricante') !== false || strpos($name, 'brand') !== false) {
                if (!empty($attribute['options'][0])) {
                    return (string) $attribute['options'][0];
                }
            }
        }

        foreach (self::brand_taxonomies() as $taxonomy) {
            if (!taxonomy_exists($taxonomy)) {
                continue;
            }
            $terms = wp_get_post_terms($product_id, $taxonomy);
            if (!is_wp_error($terms) && !empty($terms[0]) && $terms[0] instanceof WP_Term) {
                return html_entity_decode($terms[0]->name, ENT_QUOTES, 'UTF-8');
            }
        }

        return '';
    }

    private static function looks_like_sku($value) {
        $raw = trim((string) $value);
        if ($raw === '') {
            return false;
        }

        $compact = preg_replace('/[^A-Z0-9]/', '', strtoupper($raw));
        if (strlen($compact) < 5 || !preg_match('/\d/', $compact)) {
            return false;
        }

        if (strpos($raw, '-') !== false || strpos($raw, '_') !== false || preg_match('/[A-Z]{2,}\d|\d[A-Z]{2,}/i', $raw)) {
            return true;
        }

        return false;
    }

    private static function sku_variants($sku) {
        $sku = trim((string) $sku);
        if ($sku === '') {
            return [];
        }

        $variants = [
            $sku,
            strtoupper($sku),
            strtolower($sku),
            str_replace(' ', '-', $sku),
            str_replace('-', ' ', $sku),
            preg_replace('/[\s\-_]+/', '', $sku),
        ];

        $clean = [];
        foreach ($variants as $variant) {
            $variant = trim((string) $variant);
            if ($variant !== '') {
                $clean[$variant] = $variant;
            }
        }

        return array_values($clean);
    }

    private static function find_product_ids_by_sku($sku) {
        $ids = [];

        foreach (self::sku_variants($sku) as $variant) {
            $exact_id = wc_get_product_id_by_sku($variant);
            if ($exact_id > 0) {
                $ids[$exact_id] = $exact_id;
            }
        }

        $like = trim((string) $sku);
        if ($like !== '') {
            $query = new WP_Query([
                'post_type' => ['product', 'product_variation'],
                'post_status' => ['publish', 'private'],
                'fields' => 'ids',
                'posts_per_page' => 20,
                'no_found_rows' => true,
                'meta_query' => [[
                    'key' => '_sku',
                    'value' => $like,
                    'compare' => 'LIKE',
                ]],
            ]);

            foreach ($query->posts as $product_id) {
                $product_id = (int) $product_id;
                $product = wc_get_product($product_id);
                if (!($product instanceof WC_Product)) {
                    continue;
                }

                $target_id = $product->is_type('variation') ? $product->get_parent_id() : $product_id;
                if ($target_id > 0) {
                    $ids[$target_id] = $target_id;
                }
            }
        }

        return array_values($ids);
    }

    private static function products_price_asc_response($page, $per_page, $search, $category_id, array $tax_query, $can_view_stock, $direction = 'ASC') {
        $price_tax_query = [];
        $seen_tax_filters = [];

        foreach ($tax_query as $filter) {
            if (!is_array($filter) || empty($filter['taxonomy'])) {
                continue;
            }

            $signature = md5(wp_json_encode([
                'taxonomy' => $filter['taxonomy'] ?? '',
                'field' => $filter['field'] ?? '',
                'terms' => $filter['terms'] ?? [],
                'operator' => $filter['operator'] ?? 'IN',
            ]));

            if (isset($seen_tax_filters[$signature])) {
                continue;
            }

            $seen_tax_filters[$signature] = true;
            $price_tax_query[] = $filter;
        }

        if ($category_id > 0) {
            $has_category_filter = false;
            foreach ($price_tax_query as $filter) {
                if (($filter['taxonomy'] ?? '') === 'product_cat') {
                    $has_category_filter = true;
                    break;
                }
            }

            if (!$has_category_filter) {
                $term = get_term($category_id, 'product_cat');
                if ($term && !is_wp_error($term)) {
                    $price_tax_query[] = [
                        'taxonomy' => 'product_cat',
                        'field' => 'term_id',
                        'terms' => [$category_id],
                        'operator' => 'IN',
                        'include_children' => true,
                    ];
                }
            }
        }

        /*
         * No usamos meta_query obligatoria sobre _price.
         * En instalaciones B2B / roles cliente puede haber productos con precio vacío,
         * oculto o calculado por reglas. Si obligamos _price != '' WooCommerce puede
         * devolver total > 0 pero items = 0. Aquí cargamos los IDs del contexto y
         * ordenamos en PHP por precio numérico, dejando productos sin precio al final.
         */
        $ids_query_args = [
            'post_type' => 'product',
            'post_status' => 'publish',
            'posts_per_page' => -1,
            'fields' => 'ids',
            'no_found_rows' => true,
            'orderby' => 'ID',
            'order' => 'ASC',
        ];

        $search = trim((string) $search);
        if ($search !== '') {
            $ids_query_args['s'] = $search;
        }

        if (!empty($price_tax_query)) {
            $ids_query_args['tax_query'] = count($price_tax_query) > 1
                ? array_merge(['relation' => 'AND'], $price_tax_query)
                : $price_tax_query;
        }

        $ids = array_values(array_unique(array_map('absint', get_posts($ids_query_args))));

        if (empty($ids)) {
            return rest_ensure_response([
                'success' => true,
                'products' => [],
                'data' => [],
                'page' => $page,
                'per_page' => $per_page,
                'total' => 0,
                'total_pages' => 1,
                'can_view_stock' => $can_view_stock,
                'price_sort_fix' => true,
            'query_engine' => 'price_sort_wp_query_152',
            ]);
        }

        $sortable = [];
        foreach ($ids as $product_id) {
            $product = wc_get_product($product_id);
            if (!($product instanceof WC_Product) || $product->get_status() !== 'publish') {
                continue;
            }

            $price_data = self::resolve_product_price_data($product);
            $price_value = ($price_data['has_price'] && is_numeric($price_data['display_price'])) ? (float) $price_data['display_price'] : null;

            $sortable[] = [
                'id' => $product_id,
                'price' => $price_value,
                'has_price' => $price_data['has_price'],
                'date' => get_post_time('U', true, $product_id),
                'name' => $product->get_name(),
            ];
        }

        $direction = strtoupper((string) $direction) === 'DESC' ? 'DESC' : 'ASC';
        usort($sortable, static function($a, $b) use ($direction) {
            // Primero productos con precio numérico real; los sin precio quedan visibles al final.
            if ($a['has_price'] !== $b['has_price']) {
                return $a['has_price'] ? -1 : 1;
            }

            if ($a['has_price'] && $b['has_price']) {
                if ((float) $a['price'] === (float) $b['price']) {
                    return strcasecmp((string) $a['name'], (string) $b['name']);
                }
                if ($direction === 'DESC') {
                    return ((float) $a['price'] > (float) $b['price']) ? -1 : 1;
                }
                return ((float) $a['price'] < (float) $b['price']) ? -1 : 1;
            }

            // Si no hay precio, mantenemos una salida estable y útil.
            if ((int) $a['date'] === (int) $b['date']) {
                return strcasecmp((string) $a['name'], (string) $b['name']);
            }
            return ((int) $a['date'] > (int) $b['date']) ? -1 : 1;
        });

        $total = count($sortable);
        $pages = max(1, (int) ceil($total / max(1, $per_page)));
        $offset = max(0, ($page - 1) * $per_page);
        $slice = array_slice($sortable, $offset, $per_page);

        $products = [];
        foreach ($slice as $entry) {
            $product = wc_get_product((int) $entry['id']);
            if ($product instanceof WC_Product) {
                $products[] = self::product_payload($product, $can_view_stock);
            }
        }

        return rest_ensure_response([
            'success' => true,
            'products' => $products,
            'data' => $products,
            'page' => $page,
            'per_page' => $per_page,
            'total' => $total,
            'total_pages' => $pages,
            'can_view_stock' => $can_view_stock,
            'price_sort_fix' => true,
        ]);
    }

    private static function map_orderby($orderby) {
        $orderby = sanitize_key((string) $orderby);
        switch ($orderby) {
            case 'price_asc':
            case 'price_desc':
            case 'price':
                return 'price';
            case 'name':
                return 'name';
            case 'menu_order':
                return 'menu_order';
            case 'date':
            default:
                return 'date';
        }
    }

    private static function map_order($orderby, $explicit_order = '') {
        $orderby = sanitize_key((string) $orderby);
        $explicit_order = strtoupper(sanitize_text_field((string) $explicit_order));

        if (in_array($explicit_order, ['ASC', 'DESC'], true)) {
            return $explicit_order;
        }

        if ($orderby === 'price_asc' || $orderby === 'name' || $orderby === 'menu_order') {
            return 'ASC';
        }

        return 'DESC';
    }

    private static function brand_taxonomies() {
        return ['pa_marcas', 'product_brand', 'pa_marca', 'pa_fabricante', 'marca', 'brand'];
    }

    private static function build_brand_tax_query($brand_id, $brand_text) {
        $brand_id = absint($brand_id);
        $brand_text = trim((string) $brand_text);

        foreach (self::brand_taxonomies() as $taxonomy) {
            if (!taxonomy_exists($taxonomy)) {
                continue;
            }

            if ($brand_id > 0) {
                $term = get_term($brand_id, $taxonomy);
                if ($term && !is_wp_error($term)) {
                    return [
                        'taxonomy' => $taxonomy,
                        'field' => 'term_id',
                        'terms' => [$brand_id],
                        'operator' => 'IN',
                    ];
                }
            }

            if ($brand_text !== '') {
                $candidates = array_values(array_unique(array_filter([
                    $brand_text,
                    sanitize_title($brand_text),
                    str_replace(' ', '-', $brand_text),
                    str_replace('-', ' ', $brand_text),
                    strtoupper($brand_text),
                    strtolower($brand_text),
                ])));

                foreach ($candidates as $candidate) {
                    $term = get_term_by('slug', sanitize_title($candidate), $taxonomy);
                    if (!$term) {
                        $term = get_term_by('name', sanitize_text_field($candidate), $taxonomy);
                    }
                    if ($term && !is_wp_error($term)) {
                        return [
                            'taxonomy' => $taxonomy,
                            'field' => 'term_id',
                            'terms' => [(int) $term->term_id],
                            'operator' => 'IN',
                        ];
                    }
                }
            }
        }

        return [];
    }

    private static function decode_json_map($raw) {
        if (empty($raw)) {
            return [];
        }

        if (is_array($raw)) {
            return $raw;
        }

        $decoded = json_decode(wp_unslash((string) $raw), true);
        return is_array($decoded) ? $decoded : [];
    }

    // =============================================================
    // CART / QUOTE
    // =============================================================

    public static function cart_get(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        return rest_ensure_response(self::cart_response($user_id, self::CART_META_KEY));
    }

    public static function cart_add(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $product_id = (int) $request->get_param('product_id');
        $variation_id = max(0, (int) $request->get_param('variation_id'));
        $quantity = max(1, (int) $request->get_param('quantity'));

        $product = wc_get_product($variation_id > 0 ? $variation_id : $product_id);
        if (!($product instanceof WC_Product)) {
            return new WP_Error('mundicam_product_not_found', 'Producto no encontrado.', ['status' => 404]);
        }

        $validation = self::validate_direct_purchase_product($product, $quantity);
        if (is_wp_error($validation)) {
            return $validation;
        }

        $cart = self::get_persistent_cart($user_id, self::CART_META_KEY);
        $key = self::cart_item_key($product_id, $variation_id);
        $cart[$key] = [
            'product_id' => $product_id,
            'variation_id' => $variation_id,
            'quantity' => isset($cart[$key]) ? ((int) $cart[$key]['quantity'] + $quantity) : $quantity,
        ];

        self::save_persistent_cart($user_id, self::CART_META_KEY, $cart);
        return rest_ensure_response(self::cart_response($user_id, self::CART_META_KEY));
    }

    public static function cart_update(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $product_id = (int) $request->get_param('product_id');
        $variation_id = max(0, (int) $request->get_param('variation_id'));
        $quantity = (int) $request->get_param('quantity');
        $key = self::cart_item_key($product_id, $variation_id);
        $cart = self::get_persistent_cart($user_id, self::CART_META_KEY);

        if (!isset($cart[$key])) {
            return new WP_Error('mundicam_cart_item_not_found', 'El producto no está en el carrito.', ['status' => 404]);
        }

        if ($quantity <= 0) {
            unset($cart[$key]);
        } else {
            $product = wc_get_product($variation_id > 0 ? $variation_id : $product_id);
            if (!($product instanceof WC_Product)) {
                return new WP_Error('mundicam_product_not_found', 'Producto no encontrado.', ['status' => 404]);
            }
            $validation = self::validate_direct_purchase_product($product, $quantity);
            if (is_wp_error($validation)) {
                return $validation;
            }
            $cart[$key]['quantity'] = $quantity;
        }

        self::save_persistent_cart($user_id, self::CART_META_KEY, $cart);
        return rest_ensure_response(self::cart_response($user_id, self::CART_META_KEY));
    }

    public static function cart_remove(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        $product_id = (int) $request->get_param('product_id');
        $variation_id = max(0, (int) $request->get_param('variation_id'));
        $cart = self::get_persistent_cart($user_id, self::CART_META_KEY);
        unset($cart[self::cart_item_key($product_id, $variation_id)]);
        self::save_persistent_cart($user_id, self::CART_META_KEY, $cart);
        return rest_ensure_response(self::cart_response($user_id, self::CART_META_KEY));
    }

    public static function cart_clear(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        delete_user_meta($user_id, self::CART_META_KEY);
        return rest_ensure_response(self::cart_response($user_id, self::CART_META_KEY));
    }

    public static function quote_get(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        return rest_ensure_response(self::cart_response($user_id, self::QUOTE_CART_META_KEY, true));
    }

    public static function quote_add(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $product_id = (int) $request->get_param('product_id');
        $variation_id = max(0, (int) $request->get_param('variation_id'));
        $quantity = max(1, (int) $request->get_param('quantity'));
        $product = wc_get_product($variation_id > 0 ? $variation_id : $product_id);

        if (!($product instanceof WC_Product)) {
            return new WP_Error('mundicam_product_not_found', 'Producto no encontrado.', ['status' => 404]);
        }

        $quote = self::get_persistent_cart($user_id, self::QUOTE_CART_META_KEY);
        $key = self::cart_item_key($product_id, $variation_id);
        $quote[$key] = [
            'product_id' => $product_id,
            'variation_id' => $variation_id,
            'quantity' => isset($quote[$key]) ? ((int) $quote[$key]['quantity'] + $quantity) : $quantity,
        ];
        self::save_persistent_cart($user_id, self::QUOTE_CART_META_KEY, $quote);

        return rest_ensure_response(self::cart_response($user_id, self::QUOTE_CART_META_KEY, true));
    }

    public static function quote_update(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        $product_id = (int) $request->get_param('product_id');
        $variation_id = max(0, (int) $request->get_param('variation_id'));
        $quantity = (int) $request->get_param('quantity');
        $key = self::cart_item_key($product_id, $variation_id);
        $quote = self::get_persistent_cart($user_id, self::QUOTE_CART_META_KEY);

        if (!isset($quote[$key])) {
            return new WP_Error('mundicam_quote_item_not_found', 'El producto no está en el presupuesto.', ['status' => 404]);
        }

        if ($quantity <= 0) {
            unset($quote[$key]);
        } else {
            $quote[$key]['quantity'] = $quantity;
        }

        self::save_persistent_cart($user_id, self::QUOTE_CART_META_KEY, $quote);
        return rest_ensure_response(self::cart_response($user_id, self::QUOTE_CART_META_KEY, true));
    }

    public static function quote_remove(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        $product_id = (int) $request->get_param('product_id');
        $variation_id = max(0, (int) $request->get_param('variation_id'));
        $quote = self::get_persistent_cart($user_id, self::QUOTE_CART_META_KEY);
        unset($quote[self::cart_item_key($product_id, $variation_id)]);
        self::save_persistent_cart($user_id, self::QUOTE_CART_META_KEY, $quote);
        return rest_ensure_response(self::cart_response($user_id, self::QUOTE_CART_META_KEY, true));
    }

    public static function quote_clear(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        delete_user_meta($user_id, self::QUOTE_CART_META_KEY);
        return rest_ensure_response(self::cart_response($user_id, self::QUOTE_CART_META_KEY, true));
    }

    public static function quote_create(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $items = self::get_persistent_cart($user_id, self::QUOTE_CART_META_KEY);
        if (empty($items)) {
            return new WP_Error('mundicam_empty_quote', 'No hay productos para solicitar presupuesto.', ['status' => 400]);
        }

        try {
            $order = wc_create_order(['customer_id' => $user_id]);
            if (is_wp_error($order)) {
                return $order;
            }

            // v1.9.4 Cliente para resolver tarifas de IVA por línea (igual que
            // order_create/order_preview).
            $customer_for_tax = null;
            try {
                $customer_for_tax = new WC_Customer($user_id);
            } catch (Throwable $e) {
                $customer_for_tax = null;
            }

            // v1.9.26 Acumuladores propios: el total se calcula desde AQUÍ (precios
            // de rol resueltos para el usuario autenticado), no desde calculate_totals().
            $mundicam_items_total = 0.0;
            $mundicam_items_tax = 0.0;
            $mundicam_tax_totals = [];

            foreach ($items as $item) {
                $product = wc_get_product(!empty($item['variation_id']) ? (int) $item['variation_id'] : (int) $item['product_id']);
                if (!($product instanceof WC_Product)) {
                    continue;
                }

                $quantity = max(1, (int) $item['quantity']);

                // v1.9.26 Precio efectivo del usuario autenticado: respeta rol,
                // tarifa, descuento comercial, reglas B2B y descuentos encadenados
                // (Flycart). Es el mismo resolve que usa order_create y order_preview.
                $price_data = self::resolve_product_price_data($product);
                $display_price = (!empty($price_data['has_price']) && is_numeric($price_data['display_price'])) ? (float) $price_data['display_price'] : 0;
                $unit_price_for_order = self::resolve_order_unit_price_for_item($product, $price_data);

                $line_total = ($unit_price_for_order > 0) ? $unit_price_for_order * $quantity : 0.0;

                // IVA de línea vía helper unificado (mismo que order_create).
                $line_tax = 0.0;
                $tax_data = ['total' => [], 'subtotal' => []];
                if ($line_total > 0) {
                    list($line_tax, $tax_data) = self::resolve_line_tax($line_total, $product, $customer_for_tax);
                }

                // v1.9.26 Construcción MANUAL del item (no add_product). add_product
                // dispara lógica interna de WooCommerce/plugins B2B que reintroduce
                // el PVP. Mismo patrón que order_create desde la v1.9.5.
                $item_obj = new WC_Order_Item_Product();
                $item_obj->set_product($product);
                $item_obj->set_name($product->get_name());
                $item_obj->set_quantity($quantity);
                $item_obj->set_subtotal($line_total);
                $item_obj->set_total($line_total);
                $item_obj->set_subtotal_tax($line_tax);
                $item_obj->set_total_tax($line_tax);
                $item_obj->set_taxes($tax_data);

                if ($unit_price_for_order > 0) {
                    $item_obj->add_meta_data('_mundicam_app_display_price', wc_format_decimal($display_price, 2), true);
                    $item_obj->add_meta_data('_mundicam_app_order_unit_price', wc_format_decimal($unit_price_for_order, 6), true);
                    $item_obj->add_meta_data('_mundicam_app_price_source', (string) ($price_data['source'] ?? ''), true);
                    $item_obj->add_meta_data('_mundicam_app_price_context', (string) ($price_data['price_context'] ?? ''), true);
                }
                $order->add_item($item_obj);

                $mundicam_items_total += $line_total;
                $mundicam_items_tax += $line_tax;
                self::accumulate_order_tax_totals($mundicam_tax_totals, $tax_data);
            }

            if (count($order->get_items()) <= 0) {
                $order->delete(true);
                return new WP_Error('mundicam_empty_quote_after_validation', 'No hay productos válidos para el presupuesto.', ['status' => 400]);
            }

            $customer = new WC_Customer($user_id);
            $order->set_address(self::customer_billing_address($customer), 'billing');
            $order->set_address(self::customer_shipping_address($customer), 'shipping');
            $order->update_meta_data('_mundicam_app_quote', '1');
            $order->update_meta_data('_ywraq_order_quote', 'yes');
            $order->update_meta_data('ywraq_raq', 'yes');

            // v1.9.26 Totales fijados a mano (mismo patrón que order_create).
            // No se usa calculate_totals() porque recalcula desde get_price() y
            // reintroduce el PVP.
            $order->set_discount_total(0);
            $order->set_discount_tax(0);
            $order->set_shipping_total(0);
            $order->set_shipping_tax(0);
            $order->set_cart_tax($mundicam_items_tax);
            self::attach_order_tax_lines($order, $mundicam_tax_totals);
            $order->set_total(round($mundicam_items_total + $mundicam_items_tax, wc_get_price_decimals()));

            $order->set_status('ywraq-pending');
            $order->add_order_note('Presupuesto pendiente creado desde la app MundiCam.');
            $order->save();

            delete_user_meta($user_id, self::QUOTE_CART_META_KEY);

            // v1.9.26 Respuesta con desglose completo (lo que pidieron los técnicos).
            return rest_ensure_response([
                'success' => true,
                'quote' => self::order_detail_payload($order),
                'quote_id' => $order->get_id(),
                'status' => $order->get_status(),
                'message' => 'Presupuesto pendiente creado correctamente.',
            ]);
        } catch (Throwable $e) {
            return new WP_Error('mundicam_quote_create_error', 'No se pudo crear el presupuesto.', ['status' => 500]);
        }
    }

    private static function validate_direct_purchase_product(WC_Product $product, $quantity) {
        $price_data = self::resolve_product_price_data($product);
        $display_price = (!empty($price_data['has_price']) && is_numeric($price_data['display_price'])) ? (float) $price_data['display_price'] : 0;

        if (!$product->is_purchasable() || !self::app_product_available_by_stock_status($product) || (float) $display_price <= 0) {
            return new WP_Error('mundicam_product_not_purchasable', 'Producto no disponible para compra directa. Usa presupuesto.', ['status' => 400]);
        }

        // v1.9.7 STOCK WEB: no bloqueamos por has_enough_stock()/stock_quantity
        // cuando WooCommerce stock_status permite comprar o reservar.
        return true;
    }

    private static function cart_item_key($product_id, $variation_id = 0) {
        return (int) $product_id . ':' . (int) $variation_id;
    }

    private static function get_persistent_cart($user_id, $meta_key) {
        $cart = get_user_meta((int) $user_id, $meta_key, true);
        return is_array($cart) ? $cart : [];
    }

    private static function save_persistent_cart($user_id, $meta_key, array $cart) {
        if (empty($cart)) {
            delete_user_meta((int) $user_id, $meta_key);
            return;
        }
        update_user_meta((int) $user_id, $meta_key, $cart);
    }

    private static function cart_response($user_id, $meta_key, $is_quote = false) {
        $raw = self::get_persistent_cart($user_id, $meta_key);
        $items = [];
        $subtotal = 0.0;
        $count = 0;

        foreach ($raw as $key => $item) {
            $product_id = (int) ($item['product_id'] ?? 0);
            $variation_id = (int) ($item['variation_id'] ?? 0);
            $quantity = max(1, (int) ($item['quantity'] ?? 1));
            $product = wc_get_product($variation_id > 0 ? $variation_id : $product_id);

            if (!($product instanceof WC_Product)) {
                continue;
            }

            $price_data = self::resolve_product_price_data($product);
            $unit_price = (!empty($price_data['has_price']) && is_numeric($price_data['display_price'])) ? (float) $price_data['display_price'] : 0.0;
            $line_total = $unit_price * $quantity;
            $subtotal += $line_total;
            $count += $quantity;

            $items[] = [
                'key' => $key,
                'product_id' => $product_id,
                'variation_id' => $variation_id,
                'id' => $product_id,
                'sku' => $product->get_sku(),
                'name' => html_entity_decode($product->get_name(), ENT_QUOTES, 'UTF-8'),
                'quantity' => $quantity,
                'unit_price' => wc_format_decimal($unit_price, 2),
                'price' => wc_format_decimal($unit_price, 2),
                'line_total' => wc_format_decimal($line_total, 2),
                'image' => wp_get_attachment_image_url($product->get_image_id(), 'woocommerce_thumbnail') ?: wc_placeholder_img_src('woocommerce_thumbnail'),
                'stock_status' => self::app_stock_status($product),
                'is_in_stock' => self::app_product_available_by_stock_status($product),
                'is_purchasable' => $product->is_purchasable() && self::app_product_available_by_stock_status($product),
                'can_add_to_cart' => $product->is_purchasable() && self::app_product_available_by_stock_status($product),
            ];
        }

        return [
            'success' => true,
            $is_quote ? 'quote_items' : 'cart_items' => $items,
            'items' => $items,
            'count' => $count,
            'subtotal' => wc_format_decimal($subtotal, 2),
            'currency' => get_woocommerce_currency(),
        ];
    }

    private static function ensure_cart_loaded() {
        if (function_exists('wc_load_cart')) {
            try {
                wc_load_cart();
            } catch (Throwable $e) {
                // Continuamos con inicialización manual.
            }
        }

        if (function_exists('WC') && WC()) {
            if (null === WC()->session && class_exists('WC_Session_Handler')) {
                WC()->session = new WC_Session_Handler();
                WC()->session->init();
            }
            if (null === WC()->cart && class_exists('WC_Cart')) {
                WC()->cart = new WC_Cart();
            }
        }
    }

    private static function add_to_yith_quote($product_id, $quantity) {
        $item = [
            'product_id' => $product_id,
            'variation_id' => 0,
            'quantity' => $quantity,
            'variations' => [],
        ];

        if (function_exists('YITH_Request_Quote')) {
            $raq = YITH_Request_Quote();
            if (is_object($raq)) {
                foreach (['add_item', 'add'] as $method) {
                    if (method_exists($raq, $method)) {
                        try {
                            $result = $raq->{$method}($item);
                            return $result !== false;
                        } catch (Throwable $e) {
                            // Probamos siguiente método/fallback.
                        }
                    }
                }
            }
        }

        if (function_exists('WC') && WC() && WC()->session) {
            $items = WC()->session->get('yith_ywraq_items');
            if (!is_array($items)) {
                $items = [];
            }

            $key = md5($product_id . ':0');
            if (isset($items[$key]) && is_array($items[$key])) {
                $items[$key]['quantity'] = max(1, (int) $items[$key]['quantity']) + $quantity;
            } else {
                $items[$key] = $item;
            }

            WC()->session->set('yith_ywraq_items', $items);
            WC()->session->save_data();
            return true;
        }

        return false;
    }

    public static function payment_methods(WP_REST_Request $request) {
        self::bootstrap_user_context((int) $request->get_param('_mundicam_user_id'));

        if (!function_exists('WC') || !WC() || !WC()->payment_gateways()) {
            return new WP_Error('mundicam_gateways_unavailable', 'No se pueden cargar los métodos de pago.', ['status' => 500]);
        }

        $available = WC()->payment_gateways()->get_available_payment_gateways();
        $methods = [];

        foreach ($available as $id => $gateway) {
            if (!is_object($gateway)) {
                continue;
            }
            $methods[] = [
                'id' => (string) $id,
                'title' => wp_strip_all_tags(method_exists($gateway, 'get_title') ? $gateway->get_title() : ($gateway->title ?? $id)),
                'description' => wp_strip_all_tags(method_exists($gateway, 'get_description') ? $gateway->get_description() : ''),
            ];
        }

        return rest_ensure_response([
            'success' => true,
            'payment_methods' => $methods,
            'data' => $methods,
        ]);
    }

    // =============================================================
    // ORDERS / QUOTES
    // =============================================================

    public static function orders(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $page = max(1, (int) $request->get_param('page'));
        $per_page = min(50, max(1, (int) ($request->get_param('per_page') ?: 20)));

        $orders = wc_get_orders([
            'customer_id' => $user_id,
            'limit' => $per_page,
            'paged' => $page,
            'orderby' => 'date',
            'order' => 'DESC',
            'status' => array_keys(wc_get_order_statuses()),
        ]);

        $data = [];
        foreach ($orders as $order) {
            if ($order instanceof WC_Order) {
                // v1.9.27 Un pedido técnico creado desde "Aceptar y pagar" que AÚN
                // no está pagado no debe verse como pedido final en /orders (el
                // presupuesto sigue siendo la referencia hasta que se confirme el pago).
                $from_quote = (int) $order->get_meta('_mundicam_app_from_quote');
                if ($from_quote > 0 && $order->needs_payment()) {
                    continue;
                }
                $data[] = self::order_detail_payload($order);
            }
        }

        return rest_ensure_response([
            'success' => true,
            'orders' => $data,
            'data' => $data,
            'page' => $page,
            'per_page' => $per_page,
        ]);
    }

    /**
     * v1.9.27 POST /quote/accept-and-pay
     *
     * Genera una URL de pago para un presupuesto pendiente SIN sacarlo de /quotes.
     * Crea un pedido técnico pending vinculado al presupuesto (idempotente: no
     * duplica si el usuario pulsa varias veces). Cuando el pago se confirme (hook
     * woocommerce_order_status_changed), el presupuesto se marca como pagado y
     * deja de aparecer en /quotes, pasando a /orders.
     */
    public static function quote_accept_and_pay(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $quote_id = absint($request->get_param('quote_id') ?: $request->get_param('id'));
        if ($quote_id <= 0) {
            return new WP_Error('mundicam_quote_pay_missing_id', 'Falta el identificador del presupuesto.', ['status' => 400]);
        }

        $quote = wc_get_order($quote_id);
        if (!($quote instanceof WC_Order)) {
            return new WP_Error('mundicam_quote_pay_not_found', 'Presupuesto no encontrado.', ['status' => 404]);
        }

        if (!self::user_can_access_order($quote, $user_id)) {
            return new WP_Error('mundicam_quote_pay_forbidden', 'No tienes permisos para este presupuesto.', ['status' => 403]);
        }

        // Idempotencia: si ya existe un pedido técnico pendiente para este presupuesto,
        // se reutiliza en vez de crear otro.
        $existing_order_id = (int) $quote->get_meta('_mundicam_quote_pending_order_id');
        if ($existing_order_id > 0) {
            $existing_order = wc_get_order($existing_order_id);
            if ($existing_order instanceof WC_Order && $existing_order->needs_payment()) {
                self::ensure_order_card_gateway($existing_order);
                $existing_order->save();
                $payment_url = self::create_app_payment_bridge_url($existing_order, $user_id);
                return rest_ensure_response([
                    'success' => true,
                    'quote_id' => $quote_id,
                    'pending_order_id' => $existing_order_id,
                    'status' => $quote->get_status(),
                    'status_label' => 'Presupuesto pendiente',
                    'payment_url' => $payment_url,
                    'can_pay' => true,
                    'is_paid' => false,
                ]);
            }
            // Si el pedido ya está pagado, el presupuesto ya no debería estar aquí.
            if ($existing_order instanceof WC_Order && !$existing_order->needs_payment()) {
                return rest_ensure_response([
                    'success' => true,
                    'quote_id' => $quote_id,
                    'pending_order_id' => $existing_order_id,
                    'status' => $existing_order->get_status(),
                    'status_label' => wc_get_order_status_name($existing_order->get_status()),
                    'can_pay' => false,
                    'is_paid' => true,
                ]);
            }
        }

        // Crear pedido técnico pendiente a partir del presupuesto.
        try {
            $customer_for_tax = null;
            try { $customer_for_tax = new WC_Customer($user_id); } catch (Throwable $e) {}

            $new_order = wc_create_order(['customer_id' => $user_id]);
            if (is_wp_error($new_order)) {
                return $new_order;
            }

            // Copiar líneas del presupuesto con los precios del usuario.
            foreach ($quote->get_items() as $q_item) {
                if (!($q_item instanceof WC_Order_Item_Product)) {
                    continue;
                }
                $product = $q_item->get_product();
                $quantity = (int) $q_item->get_quantity();
                $line_subtotal = (float) $q_item->get_subtotal();
                $line_total = (float) $q_item->get_total();

                $item = new WC_Order_Item_Product();
                $item->set_product($product);
                $item->set_name($q_item->get_name());
                $item->set_quantity($quantity);
                $item->set_subtotal($line_subtotal);
                $item->set_total($line_total);

                if ($product instanceof WC_Product) {
                    list($tax, $tax_data) = self::resolve_line_tax($line_total, $product, $customer_for_tax);
                    $item->set_subtotal_tax($tax);
                    $item->set_total_tax($tax);
                    $item->set_taxes($tax_data);
                }
                $new_order->add_item($item);
            }

            $customer = new WC_Customer($user_id);
            $new_order->set_address(self::customer_billing_address($customer), 'billing');
            $new_order->set_address(self::customer_shipping_address($customer), 'shipping');
            self::ensure_order_card_gateway($new_order);
            $new_order->update_meta_data('_mundicam_app_order', '1');
            $new_order->update_meta_data('_mundicam_app_from_quote', (string) $quote_id);

            // Totales
            $items_total = 0.0;
            $items_tax = 0.0;
            foreach ($new_order->get_items() as $it) {
                if ($it instanceof WC_Order_Item_Product) {
                    $items_total += (float) $it->get_total();
                    $items_tax += (float) $it->get_total_tax();
                }
            }
            $new_order->set_discount_total(0);
            $new_order->set_discount_tax(0);
            $new_order->set_shipping_total(0);
            $new_order->set_shipping_tax(0);
            $new_order->set_cart_tax($items_tax);
            $new_order->set_total(round($items_total + $items_tax, wc_get_price_decimals()));
            $new_order->set_status('pending');
            $new_order->add_order_note('Pedido técnico creado desde presupuesto #' . $quote_id . ' vía "Aceptar y pagar".');
            $new_order->save();

            // Vincular al presupuesto.
            $quote->update_meta_data('_mundicam_quote_pending_order_id', $new_order->get_id());
            $quote->save();

            $payment_url = self::create_app_payment_bridge_url($new_order, $user_id);

            return rest_ensure_response([
                'success' => true,
                'quote_id' => $quote_id,
                'pending_order_id' => $new_order->get_id(),
                'status' => 'ywraq-pending',
                'status_label' => 'Presupuesto pendiente',
                'payment_url' => $payment_url,
                'can_pay' => true,
                'is_paid' => false,
            ]);
        } catch (Throwable $e) {
            return new WP_Error('mundicam_quote_pay_error', 'No se pudo generar el pago: ' . $e->getMessage(), ['status' => 500]);
        }
    }

    public static function quotes(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_user_by('id', $user_id);
        $email = $user instanceof WP_User ? $user->user_email : '';

        $orders = wc_get_orders([
            'customer_id' => $user_id,
            'billing_email' => $email,
            'limit' => 50,
            'orderby' => 'date',
            'order' => 'DESC',
            'status' => [
                'checkout-draft', 'wc-checkout-draft', 'pending',
                // v1.9.24 Estados propios de YITH Request a Quote: el plugin
                // cambia el estado del pedido-presupuesto a uno propio (ywraq-new,
                // ywraq-pending, etc.) que antes no se listaba.
                'ywraq-new', 'ywraq-pending', 'ywraq-accepted', 'ywraq-rejected',
                'wc-ywraq-new', 'wc-ywraq-pending', 'wc-ywraq-accepted', 'wc-ywraq-rejected',
            ],
            'meta_query' => [
                'relation' => 'OR',
                [
                    'key' => '_mundicam_app_quote',
                    'value' => '1',
                    'compare' => '=',
                ],
                [
                    'key' => '_ywraq_order_quote',
                    'compare' => 'EXISTS',
                ],
            ],
        ]);

        $data = [];
        foreach ($orders as $order) {
            if ($order instanceof WC_Order) {
                // v1.9.27 Un presupuesto ya pagado (a través de su pedido técnico)
                // deja de listarse aquí: a partir de ahora se ve en /orders.
                if ((string) $order->get_meta('_mundicam_quote_paid') === '1') {
                    continue;
                }
                $data[] = self::order_detail_payload($order);
            }
        }

        return rest_ensure_response([
            'success' => true,
            'quotes' => $data,
            'data' => $data,
        ]);
    }

    public static function order_create(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $line_items = $request->get_param('line_items');
        if (!is_array($line_items) || empty($line_items)) {
            $line_items = array_values(self::get_persistent_cart($user_id, self::CART_META_KEY));
        }

        if (empty($line_items)) {
            return new WP_Error('mundicam_empty_order', 'No hay productos para crear el pedido.', ['status' => 400]);
        }

        // v1.9.0 Guardia de composición de carrito. Si Flutter envía el cart_hash
        // recibido en /order/preview, se recalcula sobre las líneas que se van a
        // usar. Si no coincide, el carrito cambió entre preview y create (p.ej.
        // se quitó un ítem que no llegó a sincronizarse en el servidor) y el
        // pedido se rechaza para que la app recargue el preview.
        $expected_cart_hash = sanitize_text_field((string) $request->get_param('cart_hash'));
        if ($expected_cart_hash !== '') {
            $actual_cart_hash = self::compute_cart_hash($line_items);
            if (!hash_equals($expected_cart_hash, $actual_cart_hash)) {
                return new WP_Error(
                    'mundicam_order_cart_changed',
                    'El carrito ha cambiado desde la previsualización. Vuelve a revisar el pedido antes de confirmar.',
                    [
                        'status' => 409,
                        'expected_cart_hash' => $expected_cart_hash,
                        'actual_cart_hash' => $actual_cart_hash,
                    ]
                );
            }
        }

        // v1.9.8 Envío OBLIGATORIO: sin método seleccionado no se crea el pedido.
        $chosen_shipping_method = sanitize_text_field((string) $request->get_param('shipping_method_id'));
        if ($chosen_shipping_method === '') {
            return new WP_Error(
                'mundicam_order_shipping_required',
                'Debes seleccionar un método de envío antes de confirmar el pedido.',
                ['status' => 400]
            );
        }

        // v1.9.0 Idempotencia: Flutter envía un idempotency_key único por intento
        // de checkout (param o cabecera Idempotency-Key). Si llega una segunda
        // petición con la misma clave (doble clic, reintento de red), se devuelve
        // el pedido ya creado en lugar de crear uno nuevo.
        $idempotency_key = self::get_request_idempotency_key($request);

        if ($idempotency_key !== '') {
            $existing_order = self::find_order_by_idempotency_key($user_id, $idempotency_key);
            if ($existing_order instanceof WC_Order) {
                return self::order_create_response($existing_order, $user_id, true);
            }

            if (!self::acquire_order_lock($user_id, $idempotency_key)) {
                // Otra petición con la misma clave está en curso ahora mismo.
                $existing_order = self::find_order_by_idempotency_key($user_id, $idempotency_key);
                if ($existing_order instanceof WC_Order) {
                    return self::order_create_response($existing_order, $user_id, true);
                }
                return new WP_Error(
                    'mundicam_order_in_progress',
                    'Ya hay una creación de pedido en curso para esta operación. Espera unos segundos y consulta /order/status.',
                    ['status' => 409]
                );
            }
        }

        try {
            $order = wc_create_order(['customer_id' => $user_id]);
            if (is_wp_error($order)) {
                return $order;
            }

            // v1.9.2 Cliente para resolver las tarifas de IVA por línea (según su
            // ubicación fiscal), del mismo modo que /order/preview.
            $customer_for_tax = null;
            try {
                $customer_for_tax = new WC_Customer($user_id);
            } catch (Throwable $e) {
                $customer_for_tax = null;
            }

            // v1.9.5 Acumuladores propios: el total del pedido se calcula desde
            // AQUÍ (precios de rol resueltos por nosotros), no desde lo que devuelva
            // calculate_totals(), que en producción seguía arrastrando el PVP (algún
            // hook de WooCommerce/plugin B2B recalcula la línea desde get_price()).
            $mundicam_items_total = 0.0;
            $mundicam_items_tax = 0.0;
            // v1.9.6 Gmail/Email IVA: acumulamos impuestos por rate_id para
            // crear líneas fiscales reales de WooCommerce. Sin estas líneas,
            // algunos emails solo muestran el total y no el desglose IVA 21%.
            $mundicam_tax_totals = [];
            $line_debug = [];

            foreach ($line_items as $raw_item) {
                if (!is_array($raw_item)) {
                    continue;
                }

                $product_id = isset($raw_item['product_id']) ? (int) $raw_item['product_id'] : (int) ($raw_item['id'] ?? 0);
                $variation_id = (int) ($raw_item['variation_id'] ?? 0);
                $quantity = max(1, (int) ($raw_item['quantity'] ?? 1));
                $product = wc_get_product($variation_id > 0 ? $variation_id : $product_id);

                if (!($product instanceof WC_Product)) {
                    continue;
                }

                // El pedido se crea SIEMPRE con el precio efectivo del usuario/rol
                // (el mismo que ve en app/carrito/checkout y que calcula /order/preview).
                $price_data = self::resolve_product_price_data($product);
                $display_price = (!empty($price_data['has_price']) && is_numeric($price_data['display_price'])) ? (float) $price_data['display_price'] : 0;
                $unit_price_for_order = self::resolve_order_unit_price_for_item($product, $price_data);
                if (!$product->is_purchasable() || !self::app_product_available_by_stock_status($product) || $display_price <= 0 || $unit_price_for_order <= 0) {
                    $order->delete(true);
                    return new WP_Error('mundicam_order_invalid_product', 'Uno de los productos no está disponible para compra directa.', ['status' => 400]);
                }

                // v1.9.7 STOCK WEB: no usamos has_enough_stock()/stock_quantity como bloqueo final.
                // La autoridad comercial es stock_status: instock/onbackorder permiten compra; outofstock bloquea arriba.

                $line_total = $unit_price_for_order * $quantity;

                // v1.9.6 IVA de línea vía helper unificado (con fallback a tarifas
                // base de la tienda). Idéntico en preview, create y quote.
                list($line_tax, $tax_data) = self::resolve_line_tax($line_total, $product, $customer_for_tax);
                self::accumulate_order_tax_totals($mundicam_tax_totals, $tax_data);

                // v1.9.5 Construcción MANUAL del item (no add_product). add_product
                // dispara lógica interna de WooCommerce/plugins B2B que reintroduce
                // el PVP. Creando el item a mano y usando add_item evitamos esa ruta.
                $item = new WC_Order_Item_Product();
                $item->set_product($product);
                $item->set_name($product->get_name());
                $item->set_quantity($quantity);
                $item->set_subtotal($line_total);
                $item->set_total($line_total);
                $item->set_subtotal_tax($line_tax);
                $item->set_total_tax($line_tax);
                $item->set_taxes($tax_data);
                $item->add_meta_data('_mundicam_app_display_price', wc_format_decimal($display_price, 2), true);
                $item->add_meta_data('_mundicam_app_order_unit_price', wc_format_decimal($unit_price_for_order, 6), true);
                $item->add_meta_data('_mundicam_app_price_source', (string) ($price_data['source'] ?? ''), true);
                $item->add_meta_data('_mundicam_app_price_context', (string) ($price_data['price_context'] ?? ''), true);
                $order->add_item($item);

                $mundicam_items_total += $line_total;
                $mundicam_items_tax += $line_tax;

                // Debug temporal (solo se devuelve si hay mismatch).
                $line_debug[] = [
                    'product_id' => (int) $product->get_id(),
                    'quantity' => $quantity,
                    'preview_unit_price' => wc_format_decimal($unit_price_for_order, 6),
                    'display_price' => wc_format_decimal($display_price, 2),
                    'line_total_set' => wc_format_decimal($line_total, 6),
                    'line_tax_set' => wc_format_decimal($line_tax, 6),
                    'product_get_price' => wc_format_decimal((float) $product->get_price(), 6),
                    'price_source' => (string) ($price_data['source'] ?? ''),
                ];
            }

            if (count($order->get_items()) <= 0) {
                $order->delete(true);
                return new WP_Error('mundicam_empty_order_after_validation', 'No hay productos válidos para crear el pedido.', ['status' => 400]);
            }

            // v1.9.18 CUPÓN. Se valida SIEMPRE en servidor con el motor de WooCommerce
            // (WC_Discounts), así que respeta todas sus reglas. La app no decide nada:
            // si el cupón no es válido, el pedido se bloquea y no se crea.
            //
            // El descuento se reparte entre las líneas de forma proporcional a su
            // subtotal (criterio de WooCommerce para porcentaje e importe fijo de
            // carrito) y se recalcula el IVA sobre la base ya descontada. NO se usa
            // $order->apply_coupon(), que recalcularía los totales y reintroduciría
            // el PVP (el bug histórico).
            $coupon_code_param = sanitize_text_field((string) $request->get_param('coupon_code'));
            $applied_coupon = null;
            $coupon_discount = 0.0;
            $mundicam_items_total_after_discount = $mundicam_items_total;

            if ($coupon_code_param !== '') {
                list($applied_coupon, $coupon_per_item, $coupon_discount, $coupon_error)
                    = self::resolve_coupon_discounts($order, $coupon_code_param, $user_id);

                if ($coupon_error instanceof WP_Error) {
                    $order->delete(true);
                    return $coupon_error;
                }

                if ($applied_coupon instanceof WC_Coupon && $coupon_discount > 0) {
                    // El descuento no puede superar el subtotal de productos.
                    $coupon_discount = min($coupon_discount, $mundicam_items_total);

                    $mundicam_items_tax = 0.0;
                    $mundicam_tax_totals = [];
                    $mundicam_items_total_after_discount = 0.0;
                    $distributed = 0.0;

                    $product_items = [];
                    foreach ($order->get_items() as $item_key => $item_obj) {
                        if ($item_obj instanceof WC_Order_Item_Product) {
                            $product_items[$item_key] = $item_obj;
                        }
                    }
                    // v1.9.22 Sin array_key_last (PHP 7.3+): compatible con 7.2.
                    $last_key = null;
                    if (!empty($product_items)) {
                        $item_keys_tmp = array_keys($product_items);
                        $last_key = end($item_keys_tmp);
                    }

                    foreach ($product_items as $item_key => $item_obj) {
                        $line_subtotal = (float) $item_obj->get_subtotal();

                        // Reparto proporcional; la última línea absorbe el redondeo
                        // para que la suma cuadre exactamente con el descuento total.
                        if ($item_key === $last_key) {
                            $line_discount = round($coupon_discount - $distributed, wc_get_price_decimals());
                        } else {
                            $share = ($mundicam_items_total > 0) ? ($line_subtotal / $mundicam_items_total) : 0;
                            $line_discount = round($coupon_discount * $share, wc_get_price_decimals());
                            $distributed += $line_discount;
                        }
                        $line_discount = max(0, min($line_discount, $line_subtotal));

                        $line_total_after = max(0, round($line_subtotal - $line_discount, wc_get_price_decimals()));
                        $item_obj->set_total($line_total_after);

                        $line_product = $item_obj->get_product();
                        if ($line_product instanceof WC_Product) {
                            list($tax_after, $tax_data_after) = self::resolve_line_tax($line_total_after, $line_product, $customer_for_tax);
                            list($tax_before, $tax_data_before) = self::resolve_line_tax($line_subtotal, $line_product, $customer_for_tax);

                            // subtotal_tax = IVA antes del cupón; total_tax = después.
                            $item_obj->set_subtotal_tax($tax_before);
                            $item_obj->set_total_tax($tax_after);
                            $item_obj->set_taxes([
                                'total' => $tax_data_after['total'],
                                'subtotal' => $tax_data_before['total'],
                            ]);

                            $mundicam_items_tax += $tax_after;
                            self::accumulate_order_tax_totals($mundicam_tax_totals, [
                                'total' => $tax_data_after['total'],
                                'subtotal' => $tax_data_before['total'],
                            ]);
                        }

                        $mundicam_items_total_after_discount += $line_total_after;
                    }

                    // Línea de cupón real: WooCommerce la muestra en el admin y la
                    // factura, y contabiliza el uso del cupón al guardar el pedido.
                    $coupon_item = new WC_Order_Item_Coupon();
                    $coupon_item->set_code($applied_coupon->get_code());
                    $coupon_item->set_discount($coupon_discount);
                    $coupon_item->set_discount_tax(0);
                    $order->add_item($coupon_item);

                    $order->update_meta_data('_mundicam_app_coupon_code', $applied_coupon->get_code());
                    $order->update_meta_data('_mundicam_app_coupon_discount', wc_format_decimal($coupon_discount, 2));
                }
            }

            $customer = new WC_Customer($user_id);
            $order->set_address(self::customer_billing_address($customer), 'billing');

            // v1.9.8 FALLO #3: la dirección de ENVÍO del pedido es la elegida por la
            // app (destino real de entrega), no solo la guardada del perfil. Así el
            // pedido, el email, el almacén y la etiqueta llevan la dirección correcta.
            $shipping_address_param = $request->get_param('shipping_address');
            if (!is_array($shipping_address_param)) {
                $shipping_address_param = [];
            }
            $order->set_address(self::resolve_order_shipping_address($user_id, $shipping_address_param), 'shipping');

            // v1.9.8 Envío: resolver la tarifa elegida con el motor real de WooCommerce.
            list($shipping_cost, $shipping_tax, $shipping_taxes, $shipping_rate)
                = self::resolve_chosen_shipping_rate($user_id, $line_items, $shipping_address_param, $chosen_shipping_method);

            if (!($shipping_rate instanceof WC_Shipping_Rate)) {
                $order->delete(true);
                return new WP_Error(
                    'mundicam_order_shipping_invalid',
                    'El método de envío seleccionado no está disponible para esta dirección.',
                    ['status' => 400]
                );
            }

            // Línea de envío real en el pedido (para admin, factura y email).
            $ship_item = new WC_Order_Item_Shipping();
            $ship_item->set_method_title(html_entity_decode(wp_strip_all_tags((string) $shipping_rate->get_label()), ENT_QUOTES, 'UTF-8'));
            $ship_item->set_method_id((string) $shipping_rate->get_method_id());
            if (method_exists($ship_item, 'set_instance_id')) {
                $ship_item->set_instance_id((int) $shipping_rate->get_instance_id());
            }
            $ship_item->set_total($shipping_cost);
            $ship_item->set_taxes(['total' => is_array($shipping_taxes) ? $shipping_taxes : []]);
            $order->add_item($ship_item);

            // IVA de envío acumulado SEPARADO (shipping_tax_total en líneas fiscales).
            $mundicam_shipping_tax_totals = [];
            self::accumulate_order_tax_totals($mundicam_shipping_tax_totals, [
                'total' => is_array($shipping_taxes) ? $shipping_taxes : [],
                'subtotal' => is_array($shipping_taxes) ? $shipping_taxes : [],
            ]);

            $payment_method = self::normalize_app_payment_method($request->get_param('payment_method'));
            $payment_title = sanitize_text_field((string) $request->get_param('payment_method_title'));
            if (!empty($payment_method)) {
                $order->set_payment_method($payment_method);
                $order->set_payment_method_title($payment_title ?: self::payment_method_default_title($payment_method));
            }

            $customer_note = sanitize_textarea_field((string) $request->get_param('customer_note'));
            if (!empty($customer_note)) {
                $order->set_customer_note($customer_note);
            }

            // v1.9.5 Totales fijados desde NUESTROS acumuladores, no desde
            // calculate_totals(). En producción, calculate_totals() (incluso con
            // false) seguía devolviendo el PVP porque un hook de WooCommerce/plugin
            // recalculaba la línea desde get_price(). Al fijar el total del pedido
            // directamente desde los precios de rol que ya resolvimos, el importe es
            // inmune a esos hooks y coincide con /order/preview por construcción.
            // v1.9.18 Descuento del cupón en los totales del pedido.
            $order->set_discount_total($coupon_discount);
            $order->set_discount_tax(0);
            // v1.9.8 Envío incluido en los totales, con su IVA separado.
            $order->set_shipping_total($shipping_cost);
            $order->set_shipping_tax($shipping_tax);
            $order->set_cart_tax($mundicam_items_tax);
            self::attach_order_tax_lines($order, $mundicam_tax_totals, $mundicam_shipping_tax_totals);
            // Total = productos (ya con el cupón descontado) + IVA + envío + IVA envío.
            $order->set_total(round($mundicam_items_total_after_discount + $mundicam_items_tax + $shipping_cost + $shipping_tax, wc_get_price_decimals()));

            // Validación App vs backend. Con el total fijado desde el precio de rol,
            // esto debe coincidir siempre; se mantiene como red de seguridad ante
            // cualquier discrepancia inesperada (p.ej. IVA por ubicación fiscal).
            $expected_total = (float) $request->get_param('expected_total');
            $calculated_total = (float) $order->get_total();
            if ($expected_total > 0 && abs($calculated_total - $expected_total) > self::ORDER_TOTAL_TOLERANCE) {
                // v1.9.16 Desglose por línea al error_log del servidor (ya no se
                // expone al cliente). Sigue disponible para depurar un mismatch.
                if (function_exists('error_log')) {
                    error_log(sprintf(
                        '[MundiCam App API] Total mismatch user=%d esperado=%s calculado=%s items=%s iva=%s lineas=%s',
                        $user_id,
                        wc_format_decimal($expected_total, 2),
                        wc_format_decimal($calculated_total, 2),
                        wc_format_decimal($mundicam_items_total, 6),
                        wc_format_decimal($mundicam_items_tax, 6),
                        wp_json_encode($line_debug)
                    ));
                }
                $order->add_order_note(
                    'Pedido bloqueado por diferencia de total App/WooCommerce. '
                    . 'Esperado app: ' . wc_format_decimal($expected_total, 2)
                    . ' | Calculado backend: ' . wc_format_decimal($calculated_total, 2)
                );
                $order->delete(true);
                return new WP_Error(
                    'mundicam_order_total_mismatch',
                    'El total del pedido no coincide con el precio mostrado en la app. Pedido bloqueado por seguridad.',
                    [
                        'status' => 409,
                        'expected_total' => wc_format_decimal($expected_total, 2),
                        'calculated_total' => wc_format_decimal($calculated_total, 2),
                        // v1.9.16 El desglose por línea ya NO se expone en la respuesta
                        // (contenía price_source y detalles internos). Se registra en el
                        // error_log del servidor, donde sigue siendo útil para depurar.
                    ]
                );
            }

            // v1.9.10 Validación de crédito en SERVIDOR para giro / pago aplazado.
            // No se fía de Flutter: si el método usa crédito, comprueba que el
            // cliente tenga crédito disponible suficiente para el total del pedido.
            if (self::is_credit_payment_method($payment_method)) {
                $credit = self::credit_payload($user_id);
                $order_total_for_credit = (float) $order->get_total();
                if (function_exists('error_log')) {
                    error_log(sprintf(
                        '[MundiCam App API] Crédito checkout user=%d total=%.2f available=%.2f enabled=%s',
                        $user_id, $order_total_for_credit, $credit['credit_available'], $credit['payment_terms_enabled'] ? 'yes' : 'no'
                    ));
                }
                if (empty($credit['payment_terms_enabled']) || $credit['credit_available'] + self::ORDER_TOTAL_TOLERANCE < $order_total_for_credit) {
                    $order->delete(true);
                    return new WP_Error(
                        'mundicam_order_insufficient_credit',
                        'No tienes crédito suficiente para el pago aplazado / giro de este pedido.',
                        [
                            'status' => 409,
                            'credit_available' => wc_format_decimal((float) $credit['credit_available'], 2),
                            'order_total' => wc_format_decimal($order_total_for_credit, 2),
                        ]
                    );
                }
                // Marcar el pedido como de crédito para el cálculo de crédito usado.
                $order->update_meta_data('_mundicam_app_credit_order', '1');
            }

            // v1.9.24 Estados al crear pedido:
            // - Tarjeta/Redsys: pending hasta que Redsys confirme.
            // - Transferencia/giro/aplazado: processing (decisión de negocio de
            //   Ricardo: se prepara el pedido directamente).
            $is_card_payment = self::is_card_payment_method($payment_method);
            $status = $is_card_payment ? 'pending' : 'processing';

            if (method_exists($order, 'set_created_via')) {
                $order->set_created_via('mundicam_app');
            }

            $order->update_meta_data('_mundicam_app_order', '1');
            $order->update_meta_data('_mundicam_app_payment_method', $payment_method);
            if ($idempotency_key !== '') {
                $order->update_meta_data(self::ORDER_IDEMPOTENCY_META_KEY, $idempotency_key);
            }
            if ($expected_total > 0) {
                $order->update_meta_data('_mundicam_app_expected_total', wc_format_decimal($expected_total, 2));
            }
            $order->update_status($status, 'Pedido creado desde app MundiCam.', true);
            $order->save();
            self::send_order_emails($order);

            delete_user_meta($user_id, self::CART_META_KEY);

            return self::order_create_response($order, $user_id, false);
        } catch (Throwable $e) {
            return new WP_Error('mundicam_order_create_error', 'No se pudo crear el pedido: ' . $e->getMessage(), ['status' => 500]);
        } finally {
            if ($idempotency_key !== '') {
                self::release_order_lock($user_id, $idempotency_key);
            }
        }
    }

    /**
     * v1.9.6 Gmail/Email IVA: acumula importes por tipo de impuesto.
     * WooCommerce necesita líneas WC_Order_Item_Tax reales para que sus emails
     * muestren "IVA 21%" con importe, además de que la línea tenga set_taxes().
     */
    private static function accumulate_order_tax_totals(array &$accumulator, array $tax_data) {
        $totals = isset($tax_data['total']) && is_array($tax_data['total']) ? $tax_data['total'] : [];
        $subtotals = isset($tax_data['subtotal']) && is_array($tax_data['subtotal']) ? $tax_data['subtotal'] : [];

        foreach ($totals as $rate_id => $amount) {
            $rate_id = absint($rate_id);
            if ($rate_id <= 0 || !is_numeric($amount)) {
                continue;
            }

            if (!isset($accumulator[$rate_id])) {
                $accumulator[$rate_id] = ['total' => 0.0, 'subtotal' => 0.0];
            }

            $accumulator[$rate_id]['total'] += (float) $amount;
            $accumulator[$rate_id]['subtotal'] += isset($subtotals[$rate_id]) && is_numeric($subtotals[$rate_id])
                ? (float) $subtotals[$rate_id]
                : (float) $amount;
        }
    }

    /**
     * v1.9.6 Gmail/Email IVA: crea líneas fiscales reales en el pedido.
     * Esto permite que los emails de WooCommerce/Gmail enseñen Subtotal, IVA 21%
     * y Total como en los pedidos creados desde la web.
     */
    private static function attach_order_tax_lines(WC_Order $order, array $tax_totals, array $shipping_tax_totals = []) {
        // v1.9.8 Une rate_id de IVA de producto y de envío. Producto -> tax_total;
        // envío -> shipping_tax_total (separado), para desglose en email/factura.
        $rate_ids = array_unique(array_merge(array_keys($tax_totals), array_keys($shipping_tax_totals)));
        if (empty($rate_ids)) {
            return;
        }

        // Evita duplicar líneas si una llamada idempotente/algún hook ya las añadió.
        foreach ($order->get_items('tax') as $existing_tax_item_id => $existing_tax_item) {
            $order->remove_item($existing_tax_item_id);
        }

        foreach ($rate_ids as $rate_id) {
            $rate_id = absint($rate_id);
            if ($rate_id <= 0) {
                continue;
            }

            $tax_total = isset($tax_totals[$rate_id]['total']) && is_numeric($tax_totals[$rate_id]['total'])
                ? (float) $tax_totals[$rate_id]['total'] : 0.0;
            $ship_tax_total = isset($shipping_tax_totals[$rate_id]['total']) && is_numeric($shipping_tax_totals[$rate_id]['total'])
                ? (float) $shipping_tax_totals[$rate_id]['total'] : 0.0;

            if ($tax_total <= 0 && $ship_tax_total <= 0) {
                continue;
            }

            $tax_item = new WC_Order_Item_Tax();
            $tax_item->set_rate_id($rate_id);
            $tax_item->set_tax_total($tax_total);
            $tax_item->set_shipping_tax_total($ship_tax_total);

            if (method_exists('WC_Tax', 'get_rate_code')) {
                $tax_item->set_rate_code((string) WC_Tax::get_rate_code($rate_id));
            }
            if (method_exists('WC_Tax', 'get_rate_label')) {
                $tax_item->set_label((string) WC_Tax::get_rate_label($rate_id));
            }
            if (method_exists('WC_Tax', 'get_rate_percent')) {
                $tax_item->set_rate_percent((float) WC_Tax::get_rate_percent($rate_id));
            }

            $order->add_item($tax_item);
        }
    }

    /**
     * v1.9.6 Cálculo de IVA de línea, unificado para preview, create y quote.
     *
     * Resuelve las tarifas primero por la ubicación fiscal del cliente y, si no hay
     * (caso habitual: el cliente no tiene dirección de facturación completa cargada,
     * por lo que WC_Tax::get_rates(clase, cliente) devuelve vacío), cae a las tarifas
     * base de la tienda. En una tienda española de B2B doméstico esto da el 21% de
     * IVA correcto, en vez de 0. Devuelve [line_tax, tax_data] listo para set_taxes().
     */
    private static function resolve_line_tax($line_total, WC_Product $product, $customer = null) {
        $empty = [0.0, ['total' => [], 'subtotal' => []]];

        $tax_enabled = function_exists('wc_tax_enabled') ? wc_tax_enabled() : ('yes' === get_option('woocommerce_calc_taxes'));
        if (!$tax_enabled || !$product->is_taxable()) {
            return $empty;
        }

        $tax_class = $product->get_tax_class();
        $rates = [];

        try {
            if ($customer instanceof WC_Customer) {
                $rates = WC_Tax::get_rates($tax_class, $customer);
            }
        } catch (Throwable $e) {
            $rates = [];
        }

        // Fallback a tarifas base de la tienda si el cliente no resuelve tarifas.
        if (empty($rates) || !is_array($rates)) {
            try {
                $rates = WC_Tax::get_base_tax_rates($tax_class);
            } catch (Throwable $e) {
                $rates = [];
            }
        }

        if (empty($rates) || !is_array($rates)) {
            return $empty;
        }

        try {
            $taxes = WC_Tax::calc_tax($line_total, $rates, false);
            if (is_array($taxes)) {
                return [(float) array_sum($taxes), ['total' => $taxes, 'subtotal' => $taxes]];
            }
        } catch (Throwable $e) {
            return $empty;
        }

        return $empty;
    }

    /**
     * v1.9.0 Respuesta unificada de creación de pedido. Se usa tanto para pedidos
     * recién creados como para devoluciones idempotentes (misma idempotency_key).
     * Para pedidos ya pagados no se devuelve URL de pago.
     */
    private static function order_create_response(WC_Order $order, $user_id, $idempotent = false) {
        $payment_method = self::normalize_app_payment_method($order->get_payment_method());
        $is_card_payment = self::is_card_payment_method($payment_method);

        $payment_payload = [];
        try {
            if ($is_card_payment && $order->needs_payment()) {
                $payment_payload = self::secure_order_payment_payload($order, $user_id, $order->get_order_key(), false);
            }
        } catch (Throwable $e) {
            $payment_payload = [];
        }

        return rest_ensure_response(array_merge([
            'success' => true,
            'order' => self::order_payload($order),
            'order_id' => $order->get_id(),
            'order_key' => $order->get_order_key(),
            'status' => $order->get_status(),
            'is_card_payment' => $is_card_payment,
            'idempotent' => (bool) $idempotent,
        ], is_array($payment_payload) ? $payment_payload : []));
    }

    /**
     * v1.9.1 Resuelve el precio unitario NETO (sin IVA) para crear la línea del
     * pedido.
     *
     * Modelo de datos MundiCam: el resolver de rol calcula el descuento sobre el
     * precio base neto y devuelve display_price = raw_price = precio neto de línea
     * (verificado vía /debug-price: producto 162387, rol cliente_52_69 →
     * raw_price = display_price = 0,0528 = 0,11 × 0,48). Las líneas de pedido de
     * WooCommerce se guardan SIN impuestos; calculate_totals() añade el IVA.
     *
     * Por tanto el precio de línea correcto es directamente el precio efectivo del
     * rol. Se prioriza display_price (lo que vio el usuario) y se usa raw_price
     * solo como respaldo si display no viniera. NO se aplica wc_get_price_to_display
     * porque en este modelo display_price ya es neto: convertirlo introduciría un
     * factor de IVA espurio.
     */
    private static function resolve_order_unit_price_for_item(WC_Product $product, array $price_data) {
        $display_price = (!empty($price_data['has_price']) && isset($price_data['display_price']) && is_numeric($price_data['display_price']))
            ? (float) $price_data['display_price']
            : 0.0;

        $raw_price = (isset($price_data['raw_price']) && $price_data['raw_price'] !== '' && is_numeric($price_data['raw_price']))
            ? (float) $price_data['raw_price']
            : 0.0;

        if ($display_price > 0) {
            return round($display_price, 6);
        }

        if ($raw_price > 0) {
            return round($raw_price, 6);
        }

        return 0.0;
    }

    /**
     * v1.9.0 Clave de idempotencia: parámetro idempotency_key o cabeceras
     * Idempotency-Key / X-Idempotency-Key. Se sanea y se limita en longitud.
     */
    private static function get_request_idempotency_key(WP_REST_Request $request) {
        $key = (string) $request->get_param('idempotency_key');
        if ($key === '') {
            $key = (string) $request->get_header('idempotency-key');
        }
        if ($key === '') {
            $key = (string) $request->get_header('x-idempotency-key');
        }

        $key = sanitize_text_field($key);
        if ($key === '') {
            return '';
        }

        return substr($key, 0, 100);
    }

    /**
     * v1.9.0 Busca un pedido existente del usuario con la misma idempotency_key.
     * Verificación defensiva doble: aunque la consulta ignorase meta_query en
     * alguna versión de WooCommerce, se comprueba el meta y el cliente reales
     * antes de devolver el pedido.
     */
    private static function find_order_by_idempotency_key($user_id, $idempotency_key) {
        $user_id = (int) $user_id;
        $idempotency_key = (string) $idempotency_key;
        if ($user_id <= 0 || $idempotency_key === '') {
            return null;
        }

        try {
            $orders = wc_get_orders([
                'customer_id' => $user_id,
                'limit' => 5,
                'orderby' => 'date',
                'order' => 'DESC',
                'meta_query' => [
                    [
                        'key' => self::ORDER_IDEMPOTENCY_META_KEY,
                        'value' => $idempotency_key,
                    ],
                ],
            ]);

            if (is_array($orders)) {
                foreach ($orders as $order) {
                    if (!($order instanceof WC_Order)) {
                        continue;
                    }
                    if ((int) $order->get_customer_id() !== $user_id) {
                        continue;
                    }
                    if ((string) $order->get_meta(self::ORDER_IDEMPOTENCY_META_KEY) === $idempotency_key) {
                        return $order;
                    }
                }
            }
        } catch (Throwable $e) {
            // Sin bloqueo: si la búsqueda falla, el lock evita el duplicado inmediato.
        }

        return null;
    }

    private static function order_lock_option_name($user_id, $idempotency_key) {
        return self::ORDER_LOCK_OPTION_PREFIX . (int) $user_id . '_' . md5((string) $idempotency_key);
    }

    /**
     * v1.9.0 Lock atómico por usuario+clave vía add_option (índice UNIQUE de
     * option_name en wp_options: solo una petición concurrente lo consigue).
     * Un lock más viejo que ORDER_LOCK_TTL se considera huérfano y se reemplaza.
     */
    private static function acquire_order_lock($user_id, $idempotency_key) {
        $name = self::order_lock_option_name($user_id, $idempotency_key);

        if (add_option($name, (string) time(), '', 'no')) {
            return true;
        }

        $existing = get_option($name);
        if (is_numeric($existing) && (time() - (int) $existing) > self::ORDER_LOCK_TTL) {
            update_option($name, (string) time(), 'no');
            return true;
        }

        return false;
    }

    private static function release_order_lock($user_id, $idempotency_key) {
        delete_option(self::order_lock_option_name($user_id, $idempotency_key));
    }

    /**
     * v1.9.0 Hash del carrito. Se calcula sobre las líneas normalizadas
     * (product_id + variation_id + quantity, ordenadas) para que /order/preview
     * y /order/create obtengan el mismo hash SOLO si valoran el mismo carrito.
     * No incluye precios: el objetivo es detectar cambios de composición del
     * carrito entre la previsualización y la creación del pedido.
     */
    private static function compute_cart_hash(array $line_items) {
        $normalized = [];

        foreach ($line_items as $raw_item) {
            if (!is_array($raw_item)) {
                continue;
            }
            $product_id = isset($raw_item['product_id']) ? (int) $raw_item['product_id'] : (int) ($raw_item['id'] ?? 0);
            $variation_id = (int) ($raw_item['variation_id'] ?? 0);
            $quantity = max(1, (int) ($raw_item['quantity'] ?? 1));
            if ($product_id <= 0) {
                continue;
            }
            $normalized[] = $product_id . ':' . $variation_id . ':' . $quantity;
        }

        if (empty($normalized)) {
            return '';
        }

        sort($normalized, SORT_STRING);
        return md5(implode('|', $normalized));
    }

    /**
     * v1.9.0 POST /order/preview
     * Calcula subtotal, IVA y total con el precio efectivo del rol del usuario,
     * SIN crear ningún pedido. Flutter debe mostrar estos importes en el checkout
     * y reenviar totals.total como expected_total en /order/create.
     *
     * Nota: replica el cálculo de /order/create (líneas sin impuestos + IVA por
     * clase fiscal y ubicación del cliente). No incluye gastos de envío porque
     * /order/create tampoco los añade.
     */
    // v1.9.27 Bloqueo de login estándar de WordPress para cuentas con eliminación pendiente.
    public static function init_deletion_hooks() {
        add_filter('wp_authenticate_user', [__CLASS__, 'deny_pending_deletion_login'], 30, 2);
    }

    public static function deny_pending_deletion_login($user, $password) {
        if (is_wp_error($user)) {
            return $user;
        }
        if (get_user_meta($user->ID, self::ACCOUNT_DELETION_PENDING_META, true) === '1') {
            return new WP_Error('mundicam_account_deletion_pending', 'Esta cuenta tiene una solicitud de eliminación pendiente y no puede iniciar sesión.');
        }
        return $user;
    }

    /**
     * v1.9.27 POST /account/delete-request
     * Solicitud de eliminación de cuenta (requerido por Apple App Store).
     * Bloquea la cuenta, revoca tokens y sesiones, y avisa a RGPD.
     */
    public static function account_delete_request(WP_REST_Request $request) {
        $confirm = $request->get_param('confirm');
        if ($confirm !== true && $confirm !== 'true' && $confirm !== 1 && $confirm !== '1') {
            return new WP_Error('mundicam_deletion_not_confirmed', 'Debes confirmar expresamente la eliminación de la cuenta.', ['status' => 400]);
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_userdata($user_id);
        if (!($user instanceof WP_User)) {
            return new WP_Error('mundicam_deletion_user_not_found', 'Usuario no encontrado.', ['status' => 404]);
        }

        // Idempotente: si ya hay solicitud pendiente, devolver la referencia existente.
        $existing = get_user_meta($user_id, self::ACCOUNT_DELETION_REQUEST_META, true);
        if (is_array($existing) && !empty($existing['request_id']) && ($existing['status'] ?? '') === 'pending') {
            return rest_ensure_response([
                'success' => true,
                'already_requested' => true,
                'access_blocked' => true,
                'request_id' => (string) $existing['request_id'],
                'message' => 'La eliminación ya está solicitada y el acceso permanece bloqueado.',
            ]);
        }

        $request_id = wp_generate_uuid4();
        $manager_email = sanitize_email((string) get_user_meta($user_id, 'wpuef_cid_c30', true));
        if (!is_email($manager_email)) {
            $manager_email = '';
        }
        $billing_company = sanitize_text_field((string) get_user_meta($user_id, 'billing_company', true));

        $request_data = [
            'request_id' => $request_id,
            'user_id' => $user_id,
            'email' => sanitize_email($user->user_email),
            'display_name' => sanitize_text_field($user->display_name),
            'roles' => array_values(array_map('sanitize_key', (array) $user->roles)),
            'manager_email' => $manager_email,
            'requested_at_utc' => current_time('mysql', true),
            'status' => 'pending',
            'rgpd_email_sent' => false,
            'rgpd_email_retry_count' => 0,
        ];

        // 1. Guardar solicitud y marcar como pendiente de eliminación.
        update_user_meta($user_id, self::ACCOUNT_DELETION_REQUEST_META, $request_data);
        update_user_meta($user_id, self::ACCOUNT_DELETION_PENDING_META, '1');

        // 2. Revocar TODOS los tokens MundiCam del usuario.
        self::revoke_all_user_tokens($user_id);

        // 3. Eliminar tokens FCM del usuario.
        self::remove_all_user_fcm_tokens($user_id);

        // 4. Revocar sesiones de WordPress.
        if (class_exists('WP_Session_Tokens')) {
            try {
                WP_Session_Tokens::get_instance($user_id)->destroy_all();
            } catch (Throwable $e) {
                error_log('[MundiCam] No se pudieron revocar las sesiones del usuario ' . absint($user_id));
            }
        }

        // 5. Correo al equipo RGPD.
        $rgpd_sent = self::send_rgpd_deletion_email($user_id, $request_data, $billing_company);
        $request_data['rgpd_email_sent'] = $rgpd_sent;
        if ($rgpd_sent) {
            $request_data['rgpd_email_sent_at_utc'] = current_time('mysql', true);
        }
        update_user_meta($user_id, self::ACCOUNT_DELETION_REQUEST_META, $request_data);

        $email_retry_scheduled = false;
        if (!$rgpd_sent) {
            $request_data['rgpd_email_retry_count'] = 1;
            update_user_meta($user_id, self::ACCOUNT_DELETION_REQUEST_META, $request_data);
            wp_schedule_single_event(time() + 300, 'mundicam_account_deletion_email_retry', [$user_id, $request_id]);
            $email_retry_scheduled = true;
        }

        // 6. Correo de confirmación al usuario (best effort).
        $user_email = sanitize_email($user->user_email);
        if ($user_email !== '' && is_email($user_email)) {
            wp_mail(
                $user_email,
                'Solicitud de eliminación de cuenta MundiCam recibida',
                "Hemos recibido tu solicitud de eliminación.\n\n"
                . "El acceso a la aplicación ha quedado bloqueado.\n\n"
                . "Nuestro equipo de privacidad tramitará la eliminación o anonimización de los datos, "
                . "conservando únicamente aquellos que deban mantenerse por obligación legal.\n\n"
                . "Referencia: " . $request_id . "\n",
                ['Content-Type: text/plain; charset=UTF-8']
            );
        }

        return rest_ensure_response([
            'success' => true,
            'request_id' => $request_id,
            'access_blocked' => true,
            'rgpd_email_sent' => $rgpd_sent,
            'email_retry_scheduled' => $email_retry_scheduled,
            'message' => $rgpd_sent
                ? 'Solicitud registrada. El acceso ha quedado bloqueado y el equipo de privacidad tramitará la eliminación.'
                : 'Solicitud registrada y acceso bloqueado. El aviso al equipo de privacidad se reintentará automáticamente.',
        ]);
    }

    /**
     * v1.9.27 Revoca TODOS los tokens MundiCam de un usuario.
     */
    private static function revoke_all_user_tokens($user_id) {
        $user_id = (int) $user_id;
        $tokens = get_user_meta($user_id, self::TOKEN_META_KEY, true);
        if (!is_array($tokens)) {
            return;
        }
        $index = get_option(self::TOKEN_INDEX_OPTION, []);
        if (!is_array($index)) {
            $index = [];
        }
        $changed = false;
        foreach ($tokens as $hash => $data) {
            delete_transient(self::TOKEN_TRANSIENT_PREFIX . $hash);
            if (isset($index[$hash]) && (int) $index[$hash] === $user_id) {
                unset($index[$hash]);
                $changed = true;
            }
        }
        if ($changed) {
            update_option(self::TOKEN_INDEX_OPTION, $index, false);
        }
        delete_user_meta($user_id, self::TOKEN_META_KEY);
    }

    /**
     * v1.9.27 Elimina todos los tokens FCM de un usuario.
     */
    private static function remove_all_user_fcm_tokens($user_id) {
        $user_id = (int) $user_id;
        $fcm_meta = defined('MUNDICAM_FCM_TOKENS_META') ? MUNDICAM_FCM_TOKENS_META : '_mundicam_fcm_tokens_v1';
        $tokens = get_user_meta($user_id, $fcm_meta, true);
        if (is_array($tokens) && function_exists('mundicam_fcm_index_remove')) {
            foreach (array_keys($tokens) as $token) {
                mundicam_fcm_index_remove($token);
            }
        }
        delete_user_meta($user_id, $fcm_meta);
    }

    /**
     * v1.9.27 Envía el correo RGPD.
     */
    private static function send_rgpd_deletion_email($user_id, array $data, $billing_company = '') {
        $subject = '[RGPD MundiCam] Solicitud de eliminación de cuenta ' . ($data['request_id'] ?? '');
        $body = "Referencia: " . ($data['request_id'] ?? '') . "\n"
            . "Fecha UTC: " . ($data['requested_at_utc'] ?? '') . "\n"
            . "ID WordPress/WooCommerce: " . absint($user_id) . "\n"
            . "Nombre: " . ($data['display_name'] ?? '') . "\n"
            . "Empresa: " . ($billing_company !== '' ? $billing_company : '') . "\n"
            . "Correo: " . ($data['email'] ?? '') . "\n"
            . "Roles: " . implode(', ', (array) ($data['roles'] ?? [])) . "\n"
            . "Gestor asignado: " . ($data['manager_email'] ?? '') . "\n\n"
            . "Acciones automáticas realizadas:\n"
            . "- Acceso a la aplicación bloqueado.\n"
            . "- Nuevos inicios de sesión bloqueados.\n"
            . "- Tokens MundiCam revocados.\n"
            . "- Tokens FCM eliminados.\n"
            . "- Sesiones WordPress revocadas.\n\n"
            . "Acciones pendientes del equipo RGPD:\n"
            . "- Eliminar o anonimizar la cuenta en WordPress.\n"
            . "- Revisar los datos de WooCommerce y los pedidos.\n"
            . "- Conservar únicamente los datos exigidos legalmente.\n"
            . "- Revisar Firebase, Firestore y otros sistemas asociados.\n"
            . "- Confirmar al usuario la finalización del proceso.\n";

        return wp_mail('rgpd@mundicam.com', $subject, $body, ['Content-Type: text/plain; charset=UTF-8']);
    }

    /**
     * v1.9.27 Reintento del correo RGPD (hook: mundicam_account_deletion_email_retry).
     */
    public static function retry_account_deletion_email($user_id, $request_id) {
        $user_id = (int) $user_id;
        $data = get_user_meta($user_id, self::ACCOUNT_DELETION_REQUEST_META, true);
        if (!is_array($data)) { return; }
        if (($data['request_id'] ?? '') !== $request_id) { return; }
        if (($data['status'] ?? '') !== 'pending') { return; }
        if (!empty($data['rgpd_email_sent'])) { return; }

        $billing_company = sanitize_text_field((string) get_user_meta($user_id, 'billing_company', true));
        $sent = self::send_rgpd_deletion_email($user_id, $data, $billing_company);

        if ($sent) {
            $data['rgpd_email_sent'] = true;
            $data['rgpd_email_sent_at_utc'] = current_time('mysql', true);
        } else {
            $data['rgpd_email_retry_count'] = (int) ($data['rgpd_email_retry_count'] ?? 0) + 1;
            if ($data['rgpd_email_retry_count'] < 3) {
                wp_schedule_single_event(time() + 300, 'mundicam_account_deletion_email_retry', [$user_id, $request_id]);
            } else {
                error_log('[MundiCam] RGPD email failed after 3 retries for user ' . absint($user_id));
            }
        }
        update_user_meta($user_id, self::ACCOUNT_DELETION_REQUEST_META, $data);
    }

    public static function order_preview(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $line_items = $request->get_param('line_items');
        if (!is_array($line_items) || empty($line_items)) {
            $line_items = array_values(self::get_persistent_cart($user_id, self::CART_META_KEY));
        }

        if (empty($line_items)) {
            return new WP_Error('mundicam_empty_preview', 'No hay productos para previsualizar el pedido.', ['status' => 400]);
        }

        try {
            $customer = null;
            try {
                $customer = new WC_Customer($user_id);
            } catch (Throwable $e) {
                $customer = null;
            }

            $round_at_subtotal = ('yes' === get_option('woocommerce_tax_round_at_subtotal'));
            $price_decimals = function_exists('wc_get_price_decimals') ? wc_get_price_decimals() : 2;

            $preview_lines = [];
            $subtotal = 0.0;
            $tax_total = 0.0;

            foreach ($line_items as $raw_item) {
                if (!is_array($raw_item)) {
                    continue;
                }

                $product_id = isset($raw_item['product_id']) ? (int) $raw_item['product_id'] : (int) ($raw_item['id'] ?? 0);
                $variation_id = (int) ($raw_item['variation_id'] ?? 0);
                $quantity = max(1, (int) ($raw_item['quantity'] ?? 1));
                $product = wc_get_product($variation_id > 0 ? $variation_id : $product_id);

                if (!($product instanceof WC_Product)) {
                    continue;
                }

                // Mismo origen de precio que /order/create: precio efectivo por rol.
                $price_data = self::resolve_product_price_data($product);
                $display_price = (!empty($price_data['has_price']) && is_numeric($price_data['display_price'])) ? (float) $price_data['display_price'] : 0;
                $unit_price_for_order = self::resolve_order_unit_price_for_item($product, $price_data);

                if (!$product->is_purchasable() || !self::app_product_available_by_stock_status($product) || $display_price <= 0 || $unit_price_for_order <= 0) {
                    return new WP_Error(
                        'mundicam_preview_invalid_product',
                        'Uno de los productos no está disponible para compra directa.',
                        ['status' => 400, 'product_id' => (int) $product->get_id()]
                    );
                }

                // v1.9.7 STOCK WEB: no bloqueamos preview por stock_quantity/almacenes internos.
                // WooCommerce stock_status ya se ha validado arriba.

                $line_total = $unit_price_for_order * $quantity;

                // v1.9.6 IVA de línea vía helper unificado (mismo cálculo que create).
                list($line_tax, ) = self::resolve_line_tax($line_total, $product, $customer);

                if (!$round_at_subtotal) {
                    $line_tax = round($line_tax, $price_decimals);
                }

                $subtotal += $line_total;
                $tax_total += $line_tax;

                $preview_lines[] = [
                    'product_id' => (int) $product->get_id(),
                    'parent_product_id' => $product_id,
                    'variation_id' => $variation_id,
                    'name' => $product->get_name(),
                    'sku' => (string) $product->get_sku(),
                    'quantity' => $quantity,
                    'unit_price' => wc_format_decimal($unit_price_for_order, 6),
                    'display_price' => wc_format_decimal($display_price, 2),
                    'line_subtotal' => wc_format_decimal($line_total, 2),
                    'line_tax' => wc_format_decimal($line_tax, 2),
                    'line_total' => wc_format_decimal($line_total + $line_tax, 2),
                    'price_source' => (string) ($price_data['source'] ?? ''),
                    'price_context' => (string) ($price_data['price_context'] ?? ''),
                ];
            }

            if (empty($preview_lines)) {
                return new WP_Error('mundicam_empty_preview_after_validation', 'No hay productos válidos para previsualizar.', ['status' => 400]);
            }

            // v1.9.8 Envío: si la app manda shipping_method_id, se calcula el coste
            // real y se suma al total. Se devuelven también todas las opciones.
            $shipping_address = $request->get_param('shipping_address');
            if (!is_array($shipping_address)) {
                $shipping_address = [];
            }
            $chosen_method_id = sanitize_text_field((string) $request->get_param('shipping_method_id'));

            $shipping_options = [];
            $shipping_cost = 0.0;
            $shipping_tax = 0.0;
            $shipping_label = '';
            $ship_destination = [];
            try {
                self::ensure_shipping_loaded();
                $ship_package = self::build_shipping_package($user_id, $line_items, $shipping_address);
                self::prime_shipping_context($ship_package['destination']);
                $ship_rates = self::filter_shipping_rates_for_mundicam(
                    self::resolve_shipping_rates($ship_package),
                    $ship_package
                );
                foreach ($ship_rates as $rate) {
                    if ($rate instanceof WC_Shipping_Rate) {
                        $shipping_options[] = self::shipping_rate_to_option($rate);
                    }
                }
                if ($chosen_method_id !== '' && isset($ship_rates[$chosen_method_id]) && $ship_rates[$chosen_method_id] instanceof WC_Shipping_Rate) {
                    $chosen_rate = $ship_rates[$chosen_method_id];
                    $shipping_cost = (float) $chosen_rate->get_cost();
                    $ship_taxes = $chosen_rate->get_taxes();
                    $shipping_tax = is_array($ship_taxes) ? (float) array_sum($ship_taxes) : 0.0;
                    $shipping_label = html_entity_decode(wp_strip_all_tags((string) $chosen_rate->get_label()), ENT_QUOTES, 'UTF-8');
                }
                $ship_destination = $ship_package['destination'];
            } catch (Throwable $e) {
                $ship_destination = [];
            }

            $subtotal = round($subtotal, 2);
            $shipping_cost = round($shipping_cost, 2);

            // v1.9.18 CUPÓN: si la app manda coupon_code, se valida contra estas
            // mismas líneas y se calcula el descuento. Si no es válido, se devuelve
            // el error real de WooCommerce (caducado, mínimo no alcanzado, no aplica
            // a estos productos...) para que la app lo muestre al cliente.
            $coupon_code_param = sanitize_text_field((string) $request->get_param('coupon_code'));
            $coupon_payload = null;
            $coupon_discount = 0.0;
            if ($coupon_code_param !== '') {
                $memory_order = self::build_memory_order_for_lines($user_id, $line_items);
                list($preview_coupon, $preview_per_item, $preview_discount, $coupon_error)
                    = self::resolve_coupon_discounts($memory_order, $coupon_code_param, $user_id);

                if ($coupon_error instanceof WP_Error) {
                    return $coupon_error;
                }
                if ($preview_coupon instanceof WC_Coupon) {
                    $coupon_discount = round((float) $preview_discount, 2);
                    $coupon_payload = [
                        'code' => $preview_coupon->get_code(),
                        'description' => (string) $preview_coupon->get_description(),
                        'discount_type' => (string) $preview_coupon->get_discount_type(),
                        'amount' => wc_format_decimal($preview_coupon->get_amount(), 2),
                        'discount' => wc_format_decimal($coupon_discount, 2),
                        'free_shipping' => (bool) $preview_coupon->get_free_shipping(),
                    ];
                }
            }

            // El cupón reduce la base imponible, así que el IVA de productos se
            // recalcula en proporción (mismo criterio que WooCommerce).
            $subtotal_after_discount = max(0, round($subtotal - $coupon_discount, 2));
            if ($coupon_discount > 0 && $subtotal > 0) {
                $tax_total = round($tax_total * ($subtotal_after_discount / $subtotal), 2);
            }

            $tax_total = round($tax_total + $shipping_tax, 2);
            $total = round($subtotal_after_discount + $shipping_cost + $tax_total, 2);

            return rest_ensure_response([
                'success' => true,
                'currency' => get_woocommerce_currency(),
                'line_items' => $preview_lines,
                'coupon' => $coupon_payload,
                'totals' => [
                    'subtotal' => wc_format_decimal($subtotal, 2),
                    'discount' => wc_format_decimal($coupon_discount, 2),
                    'shipping' => wc_format_decimal($shipping_cost, 2),
                    'tax_total' => wc_format_decimal($tax_total, 2),
                    'total' => wc_format_decimal($total, 2),
                ],
                'shipping' => [
                    'selected_method_id' => $chosen_method_id,
                    'label' => $shipping_label,
                    'cost' => wc_format_decimal($shipping_cost, 2),
                    'tax' => wc_format_decimal($shipping_tax, 2),
                    'cost_with_tax' => wc_format_decimal($shipping_cost + $shipping_tax, 2),
                ],
                'shipping_options' => $shipping_options,
                'destination' => $ship_destination,
                'destination_label' => is_array($ship_destination) ? self::format_destination_label($ship_destination) : '',
                'expected_total' => wc_format_decimal($total, 2),
                'cart_hash' => self::compute_cart_hash($line_items),
                'includes_shipping' => true,
            ]);
        } catch (Throwable $e) {
            return new WP_Error('mundicam_order_preview_error', 'No se pudo calcular la previsualización: ' . $e->getMessage(), ['status' => 500]);
        }
    }

    /**
     * v1.9.0 GET /order/status
     * Estado real de un pedido concreto tras el pago. La app consulta aquí y
     * NUNCA decide por su cuenta si un pedido está pagado o en proceso.
     * Acceso: propietario del pedido, admin/gestor, o quien presente el order_key.
     */
    /**
     * v1.9.26 GET /order/detail — detalle completo de pedido o presupuesto.
     * Pantalla tipo Amazon: productos con imagen, desglose de totales, direcciones,
     * pago, envío, notas y acciones disponibles según estado.
     */
    public static function order_detail(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $order_id = absint($request->get_param('order_id') ?: $request->get_param('id'));
        $order_key = sanitize_text_field((string) $request->get_param('order_key'));

        if ($order_id <= 0) {
            return new WP_Error('mundicam_order_detail_missing_id', 'Falta el identificador del pedido.', ['status' => 400]);
        }

        $order = wc_get_order($order_id);
        if (!($order instanceof WC_Order)) {
            return new WP_Error('mundicam_order_detail_not_found', 'Pedido no encontrado.', ['status' => 404]);
        }

        $key_matches = ($order_key !== '' && hash_equals((string) $order->get_order_key(), $order_key));
        if (!$key_matches && !self::user_can_access_order($order, $user_id)) {
            return new WP_Error('mundicam_order_detail_forbidden', 'No tienes permisos para ver este pedido.', ['status' => 403]);
        }

        return rest_ensure_response([
            'success' => true,
            'order' => self::order_detail_payload($order),
        ]);
    }

    public static function order_status(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $order_id = absint($request->get_param('order_id') ?: $request->get_param('id'));
        $order_key = sanitize_text_field((string) $request->get_param('order_key'));

        if ($order_id <= 0) {
            return new WP_Error('mundicam_order_status_missing_id', 'Falta el identificador del pedido.', ['status' => 400]);
        }

        $order = wc_get_order($order_id);
        if (!($order instanceof WC_Order)) {
            return new WP_Error('mundicam_order_status_not_found', 'Pedido no encontrado.', ['status' => 404]);
        }

        $key_matches = ($order_key !== '' && hash_equals((string) $order->get_order_key(), $order_key));
        if (!$key_matches && !self::user_can_access_order($order, $user_id)) {
            return new WP_Error('mundicam_order_status_forbidden', 'No tienes permisos para consultar este pedido.', ['status' => 403]);
        }

        $date_paid = $order->get_date_paid();
        $date_created = $order->get_date_created();

        return rest_ensure_response([
            'success' => true,
            'order_id' => $order->get_id(),
            'order_key' => $order->get_order_key(),
            'status' => $order->get_status(),
            'is_paid' => (bool) $order->is_paid(),
            'needs_payment' => (bool) $order->needs_payment(),
            'payment_method' => self::normalize_app_payment_method($order->get_payment_method()),
            'payment_method_title' => $order->get_payment_method_title(),
            'transaction_id' => (string) $order->get_transaction_id(),
            'currency' => $order->get_currency(),
            'subtotal' => wc_format_decimal($order->get_subtotal(), 2),
            'tax_total' => wc_format_decimal($order->get_total_tax(), 2),
            'shipping_total' => wc_format_decimal($order->get_shipping_total(), 2),
            'discount_total' => wc_format_decimal($order->get_total_discount(), 2),
            'total' => wc_format_decimal($order->get_total(), 2),
            'tax_lines' => self::order_tax_lines_payload($order),
            'date_created' => $date_created ? $date_created->date('c') : null,
            'date_paid' => $date_paid ? $date_paid->date('c') : null,
        ]);
    }

    // =============================================================
    // ENVÍO WOOCOMMERCE (v1.9.8) — zonas y métodos reales
    // Fallo #1: se normaliza la provincia (p.ej. "Murcia" -> "MU").
    // Fallo #2: se prepara el contexto de WooCommerce (WC()->customer)
    //           con el destino antes de calcular tarifas.
    // =============================================================

    /**
     * v1.9.18 CUPONES DE WOOCOMMERCE.
     *
     * Valida y calcula el descuento de un cupón sobre unas líneas YA valoradas al
     * precio de rol (con sus descuentos encadenados). Usa WC_Discounts, el motor
     * real de WooCommerce, por lo que respeta TODAS las reglas del cupón sin
     * reimplementarlas: caducidad, importe mínimo/máximo, límite de usos global y
     * por cliente, productos/categorías incluidos o excluidos, restricción por
     * email, exclusión de artículos en oferta, uso individual, etc.
     *
     * Importante: NO se usa $order->apply_coupon(), porque ese método recalcula los
     * totales del pedido y reintroduciría el PVP (el bug histórico). Aquí solo
     * calculamos el importe; la integración en los totales se hace a mano.
     *
     * @param WC_Order $order  Pedido (real o en memoria) con las líneas ya cargadas.
     * @param string   $code   Código introducido por el cliente.
     * @return array [WC_Coupon|null, array per_item_discounts, float total_discount, WP_Error|null]
     */
    private static function resolve_coupon_discounts(WC_Order $order, $code, $user_id) {
        $empty = [null, [], 0.0, null];

        $code = trim((string) $code);
        if ($code === '') {
            return $empty;
        }
        if (!class_exists('WC_Coupon') || !class_exists('WC_Discounts')) {
            return $empty;
        }

        $code = function_exists('wc_format_coupon_code') ? wc_format_coupon_code($code) : strtolower($code);

        try {
            $coupon = new WC_Coupon($code);

            if (!$coupon->get_id() && !$coupon->get_code()) {
                return [null, [], 0.0, new WP_Error(
                    'mundicam_coupon_not_found',
                    'El cupón no existe.',
                    ['status' => 400, 'coupon_code' => $code]
                )];
            }

            $discounts = new WC_Discounts($order);

            // Validación completa con las reglas reales del cupón.
            $valid = $discounts->is_coupon_valid($coupon);
            if (is_wp_error($valid)) {
                return [null, [], 0.0, new WP_Error(
                    'mundicam_coupon_invalid',
                    $valid->get_error_message(),
                    ['status' => 400, 'coupon_code' => $code]
                )];
            }

            // Límite de usos por cliente: WC_Discounts no lo comprueba sin sesión de
            // carrito, así que lo validamos aquí con el usuario autenticado real.
            $per_user_limit = (int) $coupon->get_usage_limit_per_user();
            if ($per_user_limit > 0) {
                $used_by = (array) $coupon->get_used_by();
                $user = get_user_by('id', (int) $user_id);
                $user_email = ($user instanceof WP_User) ? strtolower($user->user_email) : '';
                $times_used = 0;
                foreach ($used_by as $used) {
                    if ((string) $used === (string) $user_id) {
                        $times_used++;
                    } elseif ($user_email !== '' && strtolower((string) $used) === $user_email) {
                        $times_used++;
                    }
                }
                if ($times_used >= $per_user_limit) {
                    return [null, [], 0.0, new WP_Error(
                        'mundicam_coupon_usage_limit',
                        'Ya has utilizado este cupón el número máximo de veces permitido.',
                        ['status' => 400, 'coupon_code' => $code]
                    )];
                }
            }

            $discounts->apply_coupon($coupon);

            // Descuento por línea (claves = item_id del pedido) e importe total.
            $per_item = [];
            $raw_per_item = $discounts->get_discounts_by_coupon(true);
            $total_discount = 0.0;

            $all_item_discounts = $discounts->get_discounts(true);
            if (is_array($all_item_discounts) && isset($all_item_discounts[$coupon->get_code()])) {
                foreach ((array) $all_item_discounts[$coupon->get_code()] as $item_key => $amount) {
                    $amount = (float) $amount;
                    if ($amount > 0) {
                        $per_item[$item_key] = $amount;
                        $total_discount += $amount;
                    }
                }
            }

            if ($total_discount <= 0 && is_array($raw_per_item) && isset($raw_per_item[$coupon->get_code()])) {
                $total_discount = (float) $raw_per_item[$coupon->get_code()];
            }

            $total_discount = round($total_discount, wc_get_price_decimals());

            if ($total_discount <= 0) {
                return [null, [], 0.0, new WP_Error(
                    'mundicam_coupon_no_discount',
                    'El cupón no aplica ningún descuento a los productos de este pedido.',
                    ['status' => 400, 'coupon_code' => $code]
                )];
            }

            return [$coupon, $per_item, $total_discount, null];
        } catch (Throwable $e) {
            return [null, [], 0.0, new WP_Error(
                'mundicam_coupon_error',
                'No se pudo validar el cupón: ' . $e->getMessage(),
                ['status' => 500]
            )];
        }
    }

    /**
     * v1.9.18 Construye un WC_Order EN MEMORIA (nunca se guarda en base de datos)
     * con las líneas valoradas a precio de rol. Sirve para validar/calcular cupones
     * en /order/preview y /cart/coupon/validate sin crear ningún pedido.
     */
    private static function build_memory_order_for_lines($user_id, array $line_items) {
        $order = new WC_Order();
        $order->set_customer_id((int) $user_id);

        try {
            $customer = new WC_Customer((int) $user_id);
            $order->set_billing_email((string) $customer->get_billing_email());
        } catch (Throwable $e) {
            // Sin email: las restricciones por email del cupón no aplicarán.
        }

        foreach ($line_items as $raw_item) {
            if (!is_array($raw_item)) {
                continue;
            }
            $product_id = isset($raw_item['product_id']) ? (int) $raw_item['product_id'] : (int) ($raw_item['id'] ?? 0);
            $variation_id = (int) ($raw_item['variation_id'] ?? 0);
            $quantity = max(1, (int) ($raw_item['quantity'] ?? 1));
            $product = wc_get_product($variation_id > 0 ? $variation_id : $product_id);
            if (!($product instanceof WC_Product)) {
                continue;
            }

            $price_data = self::resolve_product_price_data($product);
            $unit_price = self::resolve_order_unit_price_for_item($product, $price_data);
            if ($unit_price <= 0) {
                continue;
            }
            $line_total = $unit_price * $quantity;

            $item = new WC_Order_Item_Product();
            $item->set_product($product);
            $item->set_name($product->get_name());
            $item->set_quantity($quantity);
            $item->set_subtotal($line_total);
            $item->set_total($line_total);
            $order->add_item($item);
        }

        return $order;
    }

    /**
     * v1.9.18 POST /cart/coupon/validate
     * Valida un cupón contra el carrito actual y devuelve el descuento que aplicaría,
     * SIN crear pedido. La app lo usa para dar feedback inmediato al cliente cuando
     * escribe el código en el checkout.
     */
    public static function coupon_validate(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $code = sanitize_text_field((string) ($request->get_param('coupon_code') ?: $request->get_param('code')));

        if ($code === '') {
            return new WP_Error('mundicam_coupon_missing', 'Introduce un código de cupón.', ['status' => 400]);
        }

        $line_items = $request->get_param('line_items');
        if (!is_array($line_items) || empty($line_items)) {
            $line_items = array_values(self::get_persistent_cart($user_id, self::CART_META_KEY));
        }
        if (empty($line_items)) {
            return new WP_Error('mundicam_coupon_empty_cart', 'No hay productos en el carrito para aplicar el cupón.', ['status' => 400]);
        }

        try {
            $memory_order = self::build_memory_order_for_lines($user_id, $line_items);
            if (count($memory_order->get_items()) <= 0) {
                return new WP_Error('mundicam_coupon_empty_cart', 'No hay productos válidos para aplicar el cupón.', ['status' => 400]);
            }

            list($coupon, $per_item, $discount, $error) = self::resolve_coupon_discounts($memory_order, $code, $user_id);
            if ($error instanceof WP_Error) {
                return $error;
            }
            if (!($coupon instanceof WC_Coupon)) {
                return new WP_Error('mundicam_coupon_invalid', 'El cupón no es válido.', ['status' => 400]);
            }

            return rest_ensure_response([
                'success' => true,
                'valid' => true,
                'coupon' => [
                    'code' => $coupon->get_code(),
                    'description' => (string) $coupon->get_description(),
                    'discount_type' => (string) $coupon->get_discount_type(),
                    'amount' => wc_format_decimal($coupon->get_amount(), 2),
                    'free_shipping' => (bool) $coupon->get_free_shipping(),
                ],
                'discount' => wc_format_decimal($discount, 2),
                'currency' => get_woocommerce_currency(),
            ]);
        } catch (Throwable $e) {
            return new WP_Error('mundicam_coupon_error', 'No se pudo validar el cupón: ' . $e->getMessage(), ['status' => 500]);
        }
    }


    public static function shipping_methods(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $line_items = $request->get_param('line_items');
        if (!is_array($line_items) || empty($line_items)) {
            $line_items = array_values(self::get_persistent_cart($user_id, self::CART_META_KEY));
        }

        if (empty($line_items)) {
            return new WP_Error('mundicam_shipping_empty', 'No hay productos para calcular el envío.', ['status' => 400]);
        }

        $shipping_address = $request->get_param('shipping_address');
        if (!is_array($shipping_address)) {
            $shipping_address = [];
        }

        try {
            self::ensure_shipping_loaded();
            $package = self::build_shipping_package($user_id, $line_items, $shipping_address);
            self::prime_shipping_context($package['destination']);
            $rates = self::filter_shipping_rates_for_mundicam(
                self::resolve_shipping_rates($package),
                $package
            );

            $options = [];
            foreach ($rates as $rate) {
                if ($rate instanceof WC_Shipping_Rate) {
                    $options[] = self::shipping_rate_to_option($rate);
                }
            }

            $destination = $package['destination'];
            $response = [
                'success' => true,
                'version' => self::VERSION,
                'shipping_options' => $options,
                'shipping_subtotal' => wc_format_decimal((float) ($package['contents_cost'] ?? 0), 2),
                'free_shipping_min_amount' => wc_format_decimal(self::FREE_SHIPPING_MIN_AMOUNT, 2),
                'destination' => $destination,
                'destination_label' => self::format_destination_label($destination),
            ];

            if (empty($options)) {
                $response['message'] = 'No hay métodos de envío disponibles para esta dirección. Revisa la dirección o contacta con MundiCam.';
            }

            return rest_ensure_response($response);
        } catch (Throwable $e) {
            return new WP_Error('mundicam_shipping_error', 'No se pudieron calcular los métodos de envío: ' . $e->getMessage(), ['status' => 500]);
        }
    }

    /**
     * v1.9.8 Carga el subsistema de envío/países de WooCommerce en contexto REST.
     */
    private static function ensure_shipping_loaded() {
        if (!function_exists('WC') || !WC()) {
            return;
        }
        if (WC()->countries === null && class_exists('WC_Countries')) {
            WC()->countries = new WC_Countries();
        }
        if (method_exists(WC(), 'shipping')) {
            WC()->shipping();
        }
    }

    /**
     * v1.9.8 FALLO #1: normaliza el código de provincia al formato que espera
     * WooCommerce. Si llega "Murcia" y WooCommerce usa "MU", el emparejamiento de
     * zona fallaría y solo saldría un método (o una zona genérica). Convierte el
     * nombre de provincia a su código oficial. Si ya llega el código, lo respeta.
     */
    private static function normalize_state_code($country, $state) {
        $country = strtoupper(trim((string) $country));
        $state = trim((string) $state);
        if ($state === '' || $country === '') {
            return $state;
        }
        if (!function_exists('WC') || !WC() || !WC()->countries) {
            return $state;
        }

        $states = WC()->countries->get_states($country);
        if (empty($states) || !is_array($states)) {
            return $state;
        }

        // Ya es un código válido (p.ej. "MU").
        if (isset($states[$state])) {
            return $state;
        }
        if (isset($states[strtoupper($state)])) {
            return strtoupper($state);
        }

        // Búsqueda inversa por nombre, sin acentos ni mayúsculas (Murcia -> MU).
        $target = self::normalize_role($state);
        foreach ($states as $code => $name) {
            if (self::normalize_role($name) === $target) {
                return (string) $code;
            }
        }

        return $state;
    }

    /**
     * v1.9.8 FALLO #2: fija la ubicación del cliente de WooCommerce con el destino
     * calculado, para que métodos/plugins que dependen de WC()->customer resuelvan
     * bien la disponibilidad (algunos no usan solo el package).
     */
    private static function prime_shipping_context($destination) {
        if (!function_exists('WC') || !WC() || !WC()->customer) {
            return;
        }
        try {
            $country = (string) ($destination['country'] ?? '');
            $state = (string) ($destination['state'] ?? '');
            $postcode = (string) ($destination['postcode'] ?? '');
            $city = (string) ($destination['city'] ?? '');

            WC()->customer->set_shipping_country($country);
            WC()->customer->set_shipping_state($state);
            WC()->customer->set_shipping_postcode($postcode);
            WC()->customer->set_shipping_city($city);
            WC()->customer->set_billing_country($country);
            WC()->customer->set_billing_state($state);
            WC()->customer->set_billing_postcode($postcode);
            WC()->customer->set_billing_city($city);
        } catch (Throwable $e) {
            // No bloqueamos el cálculo por fallo al fijar la ubicación.
        }
    }

    /**
     * v1.9.8 Construye el "package" de envío con precios de rol ya resueltos
     * (contents_cost correcto para umbrales de envío gratis) y destino del cliente.
     */
    private static function build_shipping_package($user_id, array $line_items, array $shipping_address = []) {
        $contents = [];
        $contents_cost = 0.0;

        foreach ($line_items as $raw_item) {
            if (!is_array($raw_item)) {
                continue;
            }
            $product_id = isset($raw_item['product_id']) ? (int) $raw_item['product_id'] : (int) ($raw_item['id'] ?? 0);
            $variation_id = (int) ($raw_item['variation_id'] ?? 0);
            $quantity = max(1, (int) ($raw_item['quantity'] ?? 1));
            $product = wc_get_product($variation_id > 0 ? $variation_id : $product_id);
            if (!($product instanceof WC_Product)) {
                continue;
            }

            $price_data = self::resolve_product_price_data($product);
            $unit_price = self::resolve_order_unit_price_for_item($product, $price_data);
            $line_total = $unit_price * $quantity;
            $contents_cost += $line_total;

            $key = self::cart_item_key($product_id, $variation_id);
            $contents[$key] = [
                'key' => $key,
                'product_id' => $product_id,
                'variation_id' => $variation_id,
                'variation' => [],
                'quantity' => $quantity,
                'data' => $product,
                'data_hash' => function_exists('wc_get_cart_item_data_hash') ? wc_get_cart_item_data_hash($product) : '',
                'line_tax_data' => ['subtotal' => [], 'total' => []],
                'line_subtotal' => $line_total,
                'line_subtotal_tax' => 0,
                'line_total' => $line_total,
                'line_tax' => 0,
            ];
        }

        $destination = self::resolve_shipping_destination($user_id, $shipping_address);

        return [
            'ID' => 0,
            'contents' => $contents,
            'contents_cost' => $contents_cost,
            'applied_coupons' => [],
            'user' => ['ID' => (int) $user_id],
            'destination' => $destination,
            'cart_subtotal' => $contents_cost,
        ];
    }

    /**
     * v1.9.8 Resuelve el destino: primero lo que envía la app; si falta, la
     * dirección de envío guardada del cliente y luego la de facturación. Aplica
     * normalización de provincia (FALLO #1). País por defecto: base de la tienda.
     */
    private static function resolve_shipping_destination($user_id, array $shipping_address = []) {
        $country = sanitize_text_field((string) ($shipping_address['country'] ?? ''));
        $state = sanitize_text_field((string) ($shipping_address['state'] ?? ''));
        $postcode = sanitize_text_field((string) ($shipping_address['postcode'] ?? ''));
        $city = sanitize_text_field((string) ($shipping_address['city'] ?? ''));
        $address_1 = sanitize_text_field((string) ($shipping_address['address_1'] ?? ''));
        $address_2 = sanitize_text_field((string) ($shipping_address['address_2'] ?? ''));

        if ($country === '' || $postcode === '' || $state === '') {
            try {
                $customer = new WC_Customer((int) $user_id);
                if ($country === '') {
                    $country = $customer->get_shipping_country() ?: $customer->get_billing_country();
                }
                if ($state === '') {
                    $state = $customer->get_shipping_state() ?: $customer->get_billing_state();
                }
                if ($postcode === '') {
                    $postcode = $customer->get_shipping_postcode() ?: $customer->get_billing_postcode();
                }
                if ($city === '') {
                    $city = $customer->get_shipping_city() ?: $customer->get_billing_city();
                }
                if ($address_1 === '') {
                    $address_1 = $customer->get_shipping_address_1() ?: $customer->get_billing_address_1();
                }
                if ($address_2 === '') {
                    $address_2 = $customer->get_shipping_address_2() ?: $customer->get_billing_address_2();
                }
            } catch (Throwable $e) {
                // Sin dirección del cliente: se usará el país base más abajo.
            }
        }

        if ($country === '' && function_exists('WC') && WC() && WC()->countries) {
            $country = (string) WC()->countries->get_base_country();
        }

        // FALLO #1: normalizar provincia al código de WooCommerce.
        $state = self::normalize_state_code($country, $state);

        return [
            'country' => $country,
            'state' => $state,
            'postcode' => $postcode,
            'city' => $city,
            'address' => $address_1,
            'address_1' => $address_1,
            'address_2' => $address_2,
        ];
    }

    /**
     * v1.9.8 Tarifas reales de la zona que corresponde al package, con el motor
     * de WooCommerce. Devuelve [rate_id => WC_Shipping_Rate].
     */
    private static function resolve_shipping_rates(array $package) {
        $rates = [];
        if (!class_exists('WC_Shipping_Zones')) {
            return $rates;
        }

        $zone = WC_Shipping_Zones::get_zone_matching_package($package);
        if (!$zone) {
            return $rates;
        }

        $methods = $zone->get_shipping_methods(true);
        foreach ($methods as $method) {
            if (!is_object($method) || !method_exists($method, 'get_rates_for_package')) {
                continue;
            }
            $method_rates = $method->get_rates_for_package($package);
            if (is_array($method_rates)) {
                foreach ($method_rates as $rate_id => $rate) {
                    if ($rate instanceof WC_Shipping_Rate) {
                        $rates[$rate_id] = $rate;
                    }
                }
            }
        }

        return $rates;
    }

    /**
     * Regla comercial MundiCam: entrega gratuita solo desde 350 € de subtotal.
     * Las recogidas en tienda/almacén y “mi transportista” siguen siendo 0 €
     * porque no son un envío gratuito asumido por MundiCam.
     */
    private static function filter_shipping_rates_for_mundicam(array $rates, array $package) {
        $subtotal = (float) ($package['contents_cost'] ?? 0);

        if ($subtotal + 0.0001 >= self::FREE_SHIPPING_MIN_AMOUNT) {
            return $rates;
        }

        $filtered = [];
        foreach ($rates as $rate_id => $rate) {
            if (!($rate instanceof WC_Shipping_Rate)) {
                continue;
            }

            $cost = (float) $rate->get_cost();
            $method_id = strtolower((string) $rate->get_method_id());
            $label = self::normalize_role(
                html_entity_decode(wp_strip_all_tags((string) $rate->get_label()), ENT_QUOTES, 'UTF-8')
            );

            $zero_cost_allowed = $method_id === 'local_pickup'
                || strpos($label, 'recoger') !== false
                || strpos($label, 'recogida') !== false
                || strpos($label, 'mitransportista') !== false
                || strpos($label, 'transportistapropio') !== false;

            if ($cost <= 0.0001 && !$zero_cost_allowed) {
                continue;
            }

            $filtered[$rate_id] = $rate;
        }

        return $filtered;
    }

    /**
     * v1.9.8 Convierte una WC_Shipping_Rate al JSON que consume Flutter.
     */
    private static function shipping_rate_to_option(WC_Shipping_Rate $rate) {
        $method_id = (string) $rate->get_method_id();
        $instance_id = (string) $rate->get_instance_id();
        $cost = (float) $rate->get_cost();
        $taxes = $rate->get_taxes();
        $tax = is_array($taxes) ? (float) array_sum($taxes) : 0.0;

        $is_pickup = ($method_id === 'local_pickup');
        $label = html_entity_decode(wp_strip_all_tags((string) $rate->get_label()), ENT_QUOTES, 'UTF-8');

        if (stripos($label, 'consultar') !== false) {
            $display_total = 'Consultar';
        } elseif ($cost > 0) {
            $display_total = wc_format_decimal($cost, 2) . ' €';
        } elseif (strpos($method_id, 'free_shipping') !== false) {
            $display_total = 'Gratis';
        } else {
            $display_total = '0,00 €';
        }

        return [
            'id' => (string) $rate->get_id(),
            'type' => $is_pickup ? 'pickup' : 'delivery',
            'title' => $label,
            'description' => '',
            'requires_address' => !$is_pickup,
            'method_id' => $method_id,
            'instance_id' => $instance_id,
            'total' => wc_format_decimal($cost, 2),
            'tax' => wc_format_decimal($tax, 2),
            'total_with_tax' => wc_format_decimal($cost + $tax, 2),
            'display_total' => $display_total,
        ];
    }

    /**
     * v1.9.8 Etiqueta legible del destino para mostrar bajo los métodos.
     */
    private static function format_destination_label(array $destination) {
        $parts = [];
        if (!empty($destination['address_1'])) {
            $parts[] = $destination['address_1'];
        }
        if (!empty($destination['address_2'])) {
            $parts[] = $destination['address_2'];
        }
        $tail = trim((string) ($destination['postcode'] ?? '') . ' ' . (string) ($destination['state'] ?? ''));
        if ($tail !== '') {
            $parts[] = $tail;
        }
        if (!empty($destination['city'])) {
            $parts[] = $destination['city'];
        }
        if (empty($parts)) {
            return '';
        }
        return 'Envío a ' . implode(', ', $parts) . '.';
    }

    /**
     * v1.9.8 Dirección de envío del PEDIDO (FALLO #3): usa la dirección elegida
     * por la app; si falta un campo, cae a la guardada del cliente. Normaliza la
     * provincia. Es la que se guarda en el pedido para almacén/etiqueta/email.
     */
    private static function resolve_order_shipping_address($user_id, array $shipping_address = []) {
        $customer = null;
        try {
            $customer = new WC_Customer((int) $user_id);
        } catch (Throwable $e) {
            $customer = null;
        }

        $pick = function($key, $ship_getter, $bill_getter) use ($shipping_address, $customer) {
            $v = trim((string) ($shipping_address[$key] ?? ''));
            if ($v !== '') {
                return sanitize_text_field($v);
            }
            if ($customer instanceof WC_Customer) {
                $sv = (string) $customer->{$ship_getter}();
                if ($sv !== '') {
                    return $sv;
                }
                return (string) $customer->{$bill_getter}();
            }
            return '';
        };

        $country = $pick('country', 'get_shipping_country', 'get_billing_country');
        if ($country === '' && function_exists('WC') && WC() && WC()->countries) {
            $country = (string) WC()->countries->get_base_country();
        }
        $state = self::normalize_state_code($country, $pick('state', 'get_shipping_state', 'get_billing_state'));

        return [
            'first_name' => $pick('first_name', 'get_shipping_first_name', 'get_billing_first_name'),
            'last_name' => $pick('last_name', 'get_shipping_last_name', 'get_billing_last_name'),
            'company' => $pick('company', 'get_shipping_company', 'get_billing_company'),
            'address_1' => $pick('address_1', 'get_shipping_address_1', 'get_billing_address_1'),
            'address_2' => $pick('address_2', 'get_shipping_address_2', 'get_billing_address_2'),
            'city' => $pick('city', 'get_shipping_city', 'get_billing_city'),
            'state' => $state,
            'postcode' => $pick('postcode', 'get_shipping_postcode', 'get_billing_postcode'),
            'country' => $country,
        ];
    }

    /**
     * v1.9.8 Resuelve la tarifa elegida por su id (p.ej. "apg_free_shipping:54").
     * Devuelve [cost, tax, taxes_array, WC_Shipping_Rate|null].
     */
    private static function resolve_chosen_shipping_rate($user_id, array $line_items, array $shipping_address, $chosen_method_id) {
        $chosen_method_id = trim((string) $chosen_method_id);
        if ($chosen_method_id === '') {
            return [0.0, 0.0, [], null];
        }

        self::ensure_shipping_loaded();
        $package = self::build_shipping_package($user_id, $line_items, $shipping_address);
        self::prime_shipping_context($package['destination']);
        $rates = self::filter_shipping_rates_for_mundicam(
            self::resolve_shipping_rates($package),
            $package
        );

        if (!isset($rates[$chosen_method_id]) || !($rates[$chosen_method_id] instanceof WC_Shipping_Rate)) {
            return [0.0, 0.0, [], null];
        }

        $rate = $rates[$chosen_method_id];
        $cost = (float) $rate->get_cost();
        $taxes = $rate->get_taxes();
        $taxes = is_array($taxes) ? $taxes : [];
        $tax = (float) array_sum($taxes);

        return [$cost, $tax, $taxes, $rate];
    }


    public static function order_payment_url(WP_REST_Request $request) {
        $woo = self::ensure_woocommerce();
        if (is_wp_error($woo)) {
            return $woo;
        }

        $user_id = (int) $request->get_param('_mundicam_user_id');
        $order_id = absint($request->get_param('order_id') ?: $request->get_param('id'));
        $order_key = sanitize_text_field((string) $request->get_param('order_key'));

        if ($order_id <= 0 || $order_key === '') {
            return new WP_Error('mundicam_payment_url_missing_data', 'Pedido o clave de pago no válidos.', ['status' => 400]);
        }

        $order = wc_get_order($order_id);
        if (!($order instanceof WC_Order)) {
            return new WP_Error('mundicam_payment_url_order_not_found', 'Pedido no encontrado.', ['status' => 404]);
        }

        $payload = self::secure_order_payment_payload($order, $user_id, $order_key, true);
        if (is_wp_error($payload)) {
            return $payload;
        }

        return rest_ensure_response(array_merge([
            'success' => true,
            'order' => self::order_payload($order),
        ], $payload));
    }

    private static function secure_order_payment_payload(WC_Order $order, $user_id, $order_key, $strict = true) {
        $user_id = (int) $user_id;
        $order_key = sanitize_text_field((string) $order_key);

        if ($order_key === '' || !hash_equals((string) $order->get_order_key(), $order_key)) {
            return $strict
                ? new WP_Error('mundicam_payment_url_bad_key', 'La clave de pago no coincide con el pedido.', ['status' => 403])
                : [];
        }

        if (!self::user_can_access_order($order, $user_id)) {
            return $strict
                ? new WP_Error('mundicam_payment_url_forbidden', 'No tienes permisos para pagar este pedido.', ['status' => 403])
                : [];
        }

        if ((float) $order->get_total() <= 0) {
            return $strict
                ? new WP_Error('mundicam_payment_url_empty_total', 'El pedido no tiene importe válido para pago con tarjeta.', ['status' => 400])
                : [];
        }

        $payment_method = self::normalize_app_payment_method($order->get_payment_method());
        if (!self::is_card_payment_method($payment_method)) {
            return $strict
                ? new WP_Error('mundicam_payment_url_wrong_gateway', 'Este pedido no está configurado para pago con tarjeta.', ['status' => 400])
                : [];
        }

        $status = $order->get_status();
        if (!in_array($status, ['pending', 'on-hold', 'failed'], true)) {
            return $strict
                ? new WP_Error('mundicam_payment_url_bad_status', 'El pedido no está pendiente de pago.', ['status' => 400])
                : [];
        }

        // La sesión REST de la app no comparte cookies con la WebView. En vez de
        // devolver directamente /checkout/order-pay (que puede pedir login web),
        // devolvemos un puente temporal y firmado que autentica esa WebView y la
        // redirige inmediatamente al pago de WooCommerce/Redsys.
        $url = self::create_app_payment_bridge_url($order, $user_id);

        return [
            'payment_url' => esc_url_raw($url),
            'checkout_payment_url' => esc_url_raw($url),
            'redirect_url' => esc_url_raw($url),
            'payment_method' => $payment_method,
            'payment_method_title' => $order->get_payment_method_title(),
            'payment_status' => $status,
            'payment_secure' => true,
        ];
    }

    private static function create_app_payment_bridge_url(WC_Order $order, $user_id) {
        $user_id = (int) $user_id;
        if ($user_id <= 0 || !self::user_can_access_order($order, $user_id)) {
            return '';
        }

        try {
            $plain_token = bin2hex(random_bytes(32));
        } catch (Throwable $e) {
            $plain_token = wp_generate_password(64, false, false) . wp_generate_uuid4();
        }

        $token_hash = hash('sha256', $plain_token);
        set_transient(
            self::APP_PAYMENT_BRIDGE_TRANSIENT_PREFIX . $token_hash,
            [
                'order_id' => (int) $order->get_id(),
                'user_id' => $user_id,
                'order_key' => (string) $order->get_order_key(),
                'created_at' => time(),
            ],
            self::APP_PAYMENT_BRIDGE_TTL
        );

        return esc_url_raw(set_url_scheme(add_query_arg(
            'mundicam_app_payment_token',
            $plain_token,
            home_url('/')
        ), 'https'));
    }

    /**
     * Abre la pasarela desde la app sin pedir un segundo login en la web.
     * El token es aleatorio, temporal, está ligado a usuario+pedido+order_key y
     * solo se emite tras autenticar el app_token en el endpoint REST.
     */
    public static function handle_app_payment_bridge() {
        if (empty($_GET['mundicam_app_payment_token'])) {
            return;
        }

        nocache_headers();

        $plain_token = sanitize_text_field(wp_unslash((string) $_GET['mundicam_app_payment_token']));
        if ($plain_token === '' || strlen($plain_token) < 40) {
            wp_die('El enlace de pago no es válido.', 'MundiCam', ['response' => 403]);
        }

        $token_hash = hash('sha256', $plain_token);
        $data = get_transient(self::APP_PAYMENT_BRIDGE_TRANSIENT_PREFIX . $token_hash);
        if (!is_array($data)) {
            wp_die('El enlace de pago ha caducado. Vuelve a abrir el pago desde la app.', 'MundiCam', ['response' => 410]);
        }

        $order_id = (int) ($data['order_id'] ?? 0);
        $user_id = (int) ($data['user_id'] ?? 0);
        $order_key = (string) ($data['order_key'] ?? '');
        $created_at = (int) ($data['created_at'] ?? 0);

        if ($order_id <= 0 || $user_id <= 0 || $order_key === '' ||
            $created_at <= 0 || (time() - $created_at) > self::APP_PAYMENT_BRIDGE_TTL) {
            delete_transient(self::APP_PAYMENT_BRIDGE_TRANSIENT_PREFIX . $token_hash);
            wp_die('El enlace de pago ha caducado. Vuelve a abrir el pago desde la app.', 'MundiCam', ['response' => 410]);
        }

        $order = wc_get_order($order_id);
        $user = get_user_by('id', $user_id);

        if (!($order instanceof WC_Order) || !($user instanceof WP_User) ||
            !hash_equals((string) $order->get_order_key(), $order_key) ||
            !self::user_can_access_order($order, $user_id) ||
            !$order->needs_payment()) {
            delete_transient(self::APP_PAYMENT_BRIDGE_TRANSIENT_PREFIX . $token_hash);
            wp_die('El pedido no está disponible para pago.', 'MundiCam', ['response' => 403]);
        }

        // Sesión web exclusiva de esta WebView. No se guarda ninguna contraseña.
        wp_set_current_user($user_id);
        wp_set_auth_cookie($user_id, false, is_ssl());

        try {
            self::bootstrap_user_context($user_id);
            if (function_exists('WC') && WC() && WC()->session) {
                WC()->session->set_customer_session_cookie(true);
            }
        } catch (Throwable $e) {
            // La cookie WordPress ya permite continuar; WooCommerce terminará de
            // inicializar su sesión al cargar /order-pay.
        }

        $target = $order->get_checkout_payment_url(false);
        if (empty($target)) {
            $target = wc_get_endpoint_url('order-pay', $order->get_id(), wc_get_checkout_url());
            $target = add_query_arg([
                'pay_for_order' => 'true',
                'key' => $order->get_order_key(),
            ], $target);
        }

        $target = add_query_arg('mundicam_app_autopay', '1', $target);

        wp_safe_redirect(set_url_scheme($target, 'https'), 302);
        exit;
    }

    /**
     * En la pantalla order-pay, pulsa automáticamente el botón de Redsys una
     * sola vez. La app ya ha confirmado pedido, importe y pago con tarjeta.
     */
    public static function render_app_autopay_script() {
        if (empty($_GET['mundicam_app_autopay']) ||
            !function_exists('is_wc_endpoint_url') ||
            !is_wc_endpoint_url('order-pay')) {
            return;
        }
        ?>
        <script>
        (function () {
            var key = 'mundicam_autopay_' + window.location.pathname;
            if (window.sessionStorage && sessionStorage.getItem(key) === '1') {
                return;
            }

            function startMundicamPayment() {
                var button = document.querySelector(
                    '#place_order, button[name="woocommerce_pay"], button[type="submit"].button.alt'
                );
                if (!button || button.disabled) {
                    window.setTimeout(startMundicamPayment, 250);
                    return;
                }

                if (window.sessionStorage) {
                    sessionStorage.setItem(key, '1');
                }
                button.click();
            }

            window.setTimeout(startMundicamPayment, 350);
        })();
        </script>
        <?php
    }

    private static function user_can_access_order(WC_Order $order, $user_id) {
        $user_id = (int) $user_id;
        if ($user_id <= 0) {
            return false;
        }

        if ((int) $order->get_customer_id() === $user_id) {
            return true;
        }

        $user = get_user_by('id', $user_id);
        if ($user instanceof WP_User && (user_can($user, 'manage_woocommerce') || user_can($user, 'manage_options'))) {
            return true;
        }

        return false;
    }

    private static function normalize_app_payment_method($payment_method) {
        $payment_method = sanitize_key((string) $payment_method);
        if (in_array($payment_method, ['redsys', 'redsys_sermepa', 'redsys_tpv', 'sermepa', 'tpv'], true) ||
            strpos($payment_method, 'redsys') !== false ||
            strpos($payment_method, 'sermepa') !== false) {
            return 'redsys';
        }
        if (in_array($payment_method, ['cheque', 'cod', 'giro', 'aplazado'], true)) {
            return 'cheque';
        }
        if ($payment_method === '') {
            return 'bacs';
        }
        return $payment_method;
    }

    private static function is_card_payment_method($payment_method) {
        return self::normalize_app_payment_method($payment_method) === 'redsys';
    }

    private static function resolve_card_gateway() {
        if (!function_exists('WC') || !WC() || !WC()->payment_gateways()) {
            return null;
        }

        try {
            $gateways = WC()->payment_gateways()->payment_gateways();
            foreach ((array) $gateways as $gateway) {
                if (!is_object($gateway)) {
                    continue;
                }
                $gateway_id = method_exists($gateway, 'get_id')
                    ? (string) $gateway->get_id()
                    : (string) ($gateway->id ?? '');
                if (self::is_card_payment_method($gateway_id)) {
                    return $gateway;
                }
            }
        } catch (Throwable $e) {
            return null;
        }

        return null;
    }

    private static function ensure_order_card_gateway(WC_Order $order) {
        $gateway = self::resolve_card_gateway();

        if (is_object($gateway)) {
            $order->set_payment_method($gateway);
            $title = method_exists($gateway, 'get_title')
                ? wp_strip_all_tags((string) $gateway->get_title())
                : '';
            $order->set_payment_method_title(
                $title !== '' ? $title : self::payment_method_default_title('redsys')
            );
            return;
        }

        // Fallback compatible con la instalación MundiCam actual.
        $order->set_payment_method('redsys');
        $order->set_payment_method_title(self::payment_method_default_title('redsys'));
    }

    private static function payment_method_default_title($payment_method) {
        $payment_method = self::normalize_app_payment_method($payment_method);
        if ($payment_method === 'redsys') {
            return 'Pago seguro con tarjeta';
        }
        if ($payment_method === 'cheque') {
            return 'Giro / pago aplazado';
        }
        if ($payment_method === 'bacs') {
            return 'Transferencia bancaria';
        }
        return $payment_method;
    }

    private static function customer_billing_address(WC_Customer $customer) {
        $billing_email = sanitize_email((string) $customer->get_billing_email());
        if ($billing_email === '' || !is_email($billing_email)) {
            $user = get_user_by('id', (int) $customer->get_id());
            if ($user instanceof WP_User && is_email($user->user_email)) {
                $billing_email = sanitize_email((string) $user->user_email);
            }
        }

        return [
            'first_name' => $customer->get_billing_first_name(),
            'last_name' => $customer->get_billing_last_name(),
            'company' => $customer->get_billing_company(),
            'address_1' => $customer->get_billing_address_1(),
            'address_2' => $customer->get_billing_address_2(),
            'city' => $customer->get_billing_city(),
            'state' => $customer->get_billing_state(),
            'postcode' => $customer->get_billing_postcode(),
            'country' => $customer->get_billing_country(),
            'email' => $billing_email,
            'phone' => $customer->get_billing_phone(),
        ];
    }

    private static function customer_shipping_address(WC_Customer $customer) {
        return [
            'first_name' => $customer->get_shipping_first_name(),
            'last_name' => $customer->get_shipping_last_name(),
            'company' => $customer->get_shipping_company(),
            'address_1' => $customer->get_shipping_address_1(),
            'address_2' => $customer->get_shipping_address_2(),
            'city' => $customer->get_shipping_city(),
            'state' => $customer->get_shipping_state(),
            'postcode' => $customer->get_shipping_postcode(),
            'country' => $customer->get_shipping_country(),
        ];
    }

    /**
     * v1.9.7 EMAIL CLIENTE: fuerza de forma controlada el email de pedido al cliente
     * cuando el pedido se crea desde la API. Se marca con meta para evitar reenvíos
     * por idempotencia o reintentos. No expone errores al cliente; los registra.
     */
    /**
     * v1.9.9 Orquestador de emails al crear pedido. Se llama SIEMPRE tras crear el
     * pedido, en cualquier estado (pending, on-hold, processing...). No depende de
     * que Redsys haya confirmado el pago.
     *  - Email INTERNO de aviso al equipo: siempre, con todos los datos del pedido.
     *  - Email al CLIENTE: siempre, con la plantilla de WooCommerce adecuada al
     *    estado real (on-hold -> aviso en espera; pending/tarjeta -> factura/pago;
     *    processing/completed -> su email correspondiente). Así se avisa al cliente
     *    sin afirmar falsamente que un pago con tarjeta ya está confirmado.
     */
    private static function send_order_emails(WC_Order $order) {
        if (!($order instanceof WC_Order) || (int) $order->get_id() <= 0) {
            return;
        }
        self::ensure_order_billing_email($order);
        self::send_internal_order_notification($order);
        self::send_customer_order_email($order);
    }

    /**
     * v1.9.22 Wrapper público: permite que los hooks globales de WooCommerce
     * disparen los emails del pedido sin exponer la lógica interna.
     */
    public static function app_send_order_emails(WC_Order $order) {
        self::send_order_emails($order);
    }

    /**
     * v1.9.22 Garantiza que el pedido tenga un billing_email válido ANTES de
     * enviar nada. Si falta, lo resuelve desde el cliente (user_email o meta
     * billing_email) y lo guarda en el pedido.
     */
    private static function ensure_order_billing_email(WC_Order $order) {
        $email = sanitize_email((string) $order->get_billing_email());
        if ($email !== '' && is_email($email)) {
            return $email;
        }

        $customer_id = (int) $order->get_customer_id();
        $resolved = '';

        if ($customer_id > 0) {
            $user = get_user_by('id', $customer_id);
            if ($user instanceof WP_User && is_email($user->user_email)) {
                $resolved = sanitize_email((string) $user->user_email);
            }
            if ($resolved === '') {
                $meta_email = sanitize_email((string) get_user_meta($customer_id, 'billing_email', true));
                if (is_email($meta_email)) {
                    $resolved = $meta_email;
                }
            }
        }

        if ($resolved !== '') {
            try {
                $order->set_billing_email($resolved);
                $order->save();
            } catch (Throwable $e) {
                error_log('[MundiCam Email] No se pudo guardar billing_email en el pedido ' . $order->get_id() . ': ' . $e->getMessage());
            }
        } else {
            error_log('[MundiCam Email] order_id=' . $order->get_id() . ' sin billing_email resoluble (customer_id=' . $customer_id . ')');
        }

        return $resolved;
    }

    /**
     * v1.9.22 EMAILS POR CAMBIO DE ESTADO.
     *
     * Se controla con una meta POR ESTADO (no una global), de modo que un pedido
     * puede avisar en on-hold y más tarde en processing sin que la primera meta
     * bloquee las siguientes.
     *
     * Importante: WooCommerce NO tiene plantilla de email al CLIENTE para
     * 'cancelled' ni para 'failed' (solo avisa al administrador). Por eso, para
     * esos dos estados el aviso al cliente se envía con wp_mail propio; si no,
     * el cliente nunca recibiría nada al cancelarse su pedido.
     */
    public static function app_send_status_change_emails(WC_Order $order, $old_status, $new_status) {
        if (!($order instanceof WC_Order) || (int) $order->get_id() <= 0) {
            return;
        }

        $new_status = str_replace('wc-', '', (string) $new_status);
        $old_status = str_replace('wc-', '', (string) $old_status);

        $allowed = ['pending', 'on-hold', 'processing', 'completed', 'cancelled', 'refunded', 'failed'];
        if (!in_array($new_status, $allowed, true)) {
            return;
        }

        // v1.9.23 Metas SEPARADAS: si el interno llega pero el del cliente falla
        // (o viceversa), solo se marca el que tuvo éxito. Así un reintento (manual
        // o por otro hook) puede reintentar el que falló sin repetir el que ya llegó.
        $meta_key_customer = '_mundicam_app_status_email_customer_' . str_replace('-', '_', $new_status) . '_v1';
        $meta_key_internal = '_mundicam_app_status_email_internal_' . str_replace('-', '_', $new_status) . '_v1';

        $skip_customer = ((string) $order->get_meta($meta_key_customer) === '1');
        $skip_internal = ((string) $order->get_meta($meta_key_internal) === '1');

        if ($skip_customer && $skip_internal) {
            error_log('[MundiCam Email] skipped=both_already_sent order_id=' . $order->get_id() . ' status=' . $new_status);
            return;
        }

        $billing_email = self::ensure_order_billing_email($order);
        $order_number = (string) $order->get_order_number();

        // --- Email al CLIENTE ---
        $sent_customer = false;
        if (!$skip_customer) {
            $wc_template = [
            'pending'    => 'WC_Email_Customer_Invoice',
            'on-hold'    => 'WC_Email_Customer_On_Hold_Order',
            'processing' => 'WC_Email_Customer_Processing_Order',
            'completed'  => 'WC_Email_Customer_Completed_Order',
            'refunded'   => 'WC_Email_Customer_Refunded_Order',
        ];

        if ($billing_email !== '' && is_email($billing_email)) {
            if (isset($wc_template[$new_status])) {
                $sent_customer = self::trigger_wc_customer_email($order, $wc_template[$new_status]);
            }

            // cancelled / failed (o si la plantilla de WooCommerce no existe o
            // está deshabilitada): aviso propio por wp_mail.
            if (!$sent_customer) {
                $texts = [
                    'pending'    => ['Pago pendiente',        'Tu pedido #%s está pendiente de pago.'],
                    'on-hold'    => ['Pedido en espera',      'Tu pedido #%s está pendiente de revisión o pago.'],
                    'processing' => ['Pedido en preparación', 'Tu pedido #%s se está preparando.'],
                    'completed'  => ['Pedido completado',     'Tu pedido #%s ha sido completado.'],
                    'cancelled'  => ['Pedido cancelado',      'Tu pedido #%s ha sido cancelado.'],
                    'refunded'   => ['Pedido reembolsado',    'Tu pedido #%s ha sido reembolsado.'],
                    'failed'     => ['Pago fallido',          'No se ha podido completar el pago del pedido #%s.'],
                ];
                $title = $texts[$new_status][0];
                $body_text = sprintf($texts[$new_status][1], $order_number);

                $html = '<div style="font-family:Arial,Helvetica,sans-serif;color:#222;max-width:680px;">'
                    . '<h2 style="color:#8B0000;">' . esc_html($title) . '</h2>'
                    . '<p>' . esc_html($body_text) . '</p>'
                    . self::build_internal_order_email_html($order)
                    . '</div>';

                $sent_customer = wp_mail(
                    $billing_email,
                    sprintf('%s - Pedido #%s', $title, $order_number),
                    $html,
                    ['Content-Type: text/html; charset=UTF-8']
                );

                if (!$sent_customer) {
                    error_log('[MundiCam Email] wp_mail=false cliente order_id=' . $order->get_id() . ' status=' . $new_status . ' to=' . $billing_email);
                }
            }
        }
        } // cierre de if (!$skip_customer)

        // --- Email INTERNO al equipo ---
        $sent_internal = false;
        if (!$skip_internal) {
            $to_internal = sanitize_email((string) apply_filters('mundicam_app_internal_order_email', get_option('admin_email'), $order));
            if ($to_internal !== '' && is_email($to_internal)) {
                $sent_internal = wp_mail(
                    $to_internal,
                    sprintf('[App MundiCam] Pedido #%s -> %s', $order_number, wc_get_order_status_name($new_status)),
                    '<p><strong>Cambio de estado:</strong> ' . esc_html($old_status) . ' &rarr; ' . esc_html($new_status) . '</p>'
                        . self::build_internal_order_email_html($order),
                    ['Content-Type: text/html; charset=UTF-8']
                );
                if (!$sent_internal) {
                    error_log('[MundiCam Email] wp_mail=false interno order_id=' . $order->get_id() . ' status=' . $new_status);
                }
            }
        }

        error_log(sprintf(
            '[MundiCam Email] order_id=%d old=%s new=%s customer_email=%s sent_customer=%s sent_internal=%s',
            $order->get_id(), $old_status, $new_status,
            ($billing_email !== '' ? 'ok' : 'missing'),
            $sent_customer ? '1' : '0',
            $sent_internal ? '1' : '0'
        ));

        // v1.9.23 Metas separadas: cada canal se marca independientemente.
        $changed = false;
        if ($sent_customer) {
            $order->update_meta_data($meta_key_customer, '1');
            $changed = true;
        }
        if ($sent_internal) {
            $order->update_meta_data($meta_key_internal, '1');
            $changed = true;
        }
        if ($changed) {
            $order->save_meta_data();
        }
    }

    /**
     * v1.9.22 Dispara una plantilla de email de cliente de WooCommerce, forzando
     * su habilitación temporal si estuviera desactivada en Ajustes -> Emails.
     */
    private static function trigger_wc_customer_email(WC_Order $order, $email_class) {
        try {
            if (!function_exists('WC') || !WC() || !method_exists(WC(), 'mailer')) {
                return false;
            }
            $mailer = WC()->mailer();
            $emails = is_object($mailer) && method_exists($mailer, 'get_emails') ? $mailer->get_emails() : [];
            if (!isset($emails[$email_class]) || !method_exists($emails[$email_class], 'trigger')) {
                return false;
            }

            $obj = $emails[$email_class];
            $was_enabled = method_exists($obj, 'is_enabled') ? $obj->is_enabled() : true;
            if (!$was_enabled && isset($obj->enabled)) {
                $obj->enabled = 'yes';
            }
            $obj->trigger($order->get_id(), $order);
            if (!$was_enabled && isset($obj->enabled)) {
                $obj->enabled = 'no';
            }
            return true;
        } catch (Throwable $e) {
            error_log('[MundiCam Email] Error disparando ' . $email_class . ' en pedido ' . $order->get_id() . ': ' . $e->getMessage());
            return false;
        }
    }

    /**
     * v1.9.22 Diagnóstico de envío de correo. Aísla si el problema está en PHP
     * (que no llama a wp_mail) o en el servidor/SMTP (que no entrega).
     */
    public static function email_test(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        $user = get_user_by('id', $user_id);

        $to = sanitize_email((string) $request->get_param('to'));
        if ($to === '' || !is_email($to)) {
            $to = ($user instanceof WP_User) ? sanitize_email($user->user_email) : sanitize_email(get_option('admin_email'));
        }
        if ($to === '' || !is_email($to)) {
            return new WP_Error('mundicam_email_test_no_recipient', 'No hay destinatario válido.', ['status' => 400]);
        }

        $mail_errors = [];
        $capture = function ($wp_error) use (&$mail_errors) {
            if ($wp_error instanceof WP_Error) {
                $mail_errors[] = $wp_error->get_error_message();
            }
        };
        add_action('wp_mail_failed', $capture);

        $sent = wp_mail(
            $to,
            '[MundiCam] Prueba de envío de correo',
            '<p>Si recibes este mensaje, wp_mail funciona correctamente en el servidor.</p>',
            ['Content-Type: text/html; charset=UTF-8']
        );

        remove_action('wp_mail_failed', $capture);

        return rest_ensure_response([
            'success' => (bool) $sent,
            'sent' => (bool) $sent,
            'to' => $to,
            'errors' => $mail_errors,
            'wp_mail_exists' => function_exists('wp_mail'),
            'woocommerce_mailer' => (function_exists('WC') && WC() && method_exists(WC(), 'mailer')),
            'hint' => $sent
                ? 'wp_mail ha aceptado el envío. Si no llega, revisa SMTP/spam del servidor.'
                : 'wp_mail ha fallado: el problema es del servidor de correo, no del plugin.',
        ]);
    }

    /**
     * v1.9.9 Email INTERNO de aviso al equipo. Siempre, en cualquier estado.
     * Usa wp_mail directamente (no depende de que WooCommerce dispare nada).
     */
    private static function send_internal_order_notification(WC_Order $order) {
        if ((string) $order->get_meta('_mundicam_app_internal_email_sent_v1') === '1') {
            return;
        }

        // Destinatario interno: filtrable; por defecto, email de administración.
        $to = apply_filters('mundicam_app_internal_order_email', get_option('admin_email'), $order);
        $to = sanitize_email((string) $to);
        if ($to === '' || !is_email($to)) {
            if (function_exists('error_log')) {
                error_log('[MundiCam App API] Email interno omitido: destinatario no válido (pedido ' . $order->get_id() . ').');
            }
            return;
        }

        try {
            $subject = sprintf('[App MundiCam] Nuevo pedido #%s (%s)', $order->get_order_number(), $order->get_status());
            $body = self::build_internal_order_email_html($order);

            $headers = [
                'Content-Type: text/html; charset=UTF-8',
            ];
            $reply_email = sanitize_email((string) $order->get_billing_email());
            if ($reply_email !== '' && is_email($reply_email)) {
                $headers[] = 'Reply-To: ' . $reply_email;
            }

            $sent = wp_mail($to, $subject, $body, $headers);

            if ($sent) {
                $order->update_meta_data('_mundicam_app_internal_email_sent_v1', '1');
                $order->save_meta_data();
            } elseif (function_exists('error_log')) {
                error_log('[MundiCam App API] wp_mail devolvió false para email interno del pedido ' . $order->get_id() . '.');
            }
        } catch (Throwable $e) {
            if (function_exists('error_log')) {
                error_log('[MundiCam App API] Error enviando email interno pedido ' . $order->get_id() . ': ' . $e->getMessage());
            }
        }
    }

    /**
     * v1.9.9 Construye el cuerpo HTML del email interno con todos los datos que
     * pidió el equipo (cliente, contacto, pago, envío, líneas, IVA, total, notas...).
     */
    private static function build_internal_order_email_html(WC_Order $order) {
        $money = function($amount) use ($order) {
            return function_exists('wc_price')
                ? wc_price($amount, ['currency' => $order->get_currency()])
                : number_format((float) $amount, 2, ',', '.') . ' €';
        };
        $esc = function($v) { return esc_html((string) $v); };

        // Comercial asociado (si el cliente tiene uno registrado en meta).
        $comercial = (string) get_user_meta((int) $order->get_customer_id(), 'comercial_asignado', true);
        if ($comercial === '') {
            $comercial = (string) $order->get_meta('_mundicam_app_comercial');
        }

        $rows_items = '';
        foreach ($order->get_items() as $item) {
            if (!($item instanceof WC_Order_Item_Product)) { continue; }
            $product = $item->get_product();
            $sku = $product instanceof WC_Product ? $product->get_sku() : '';
            $qty = (int) $item->get_quantity();
            $line_subtotal = (float) $item->get_subtotal();
            $unit = $qty > 0 ? $line_subtotal / $qty : $line_subtotal;
            $rows_items .= '<tr>'
                . '<td style="padding:6px;border:1px solid #ddd;">' . $esc($item->get_name()) . '</td>'
                . '<td style="padding:6px;border:1px solid #ddd;">' . $esc($sku) . '</td>'
                . '<td style="padding:6px;border:1px solid #ddd;text-align:center;">' . $qty . '</td>'
                . '<td style="padding:6px;border:1px solid #ddd;text-align:right;">' . $money($unit) . '</td>'
                . '<td style="padding:6px;border:1px solid #ddd;text-align:right;">' . $money($line_subtotal) . '</td>'
                . '</tr>';
        }

        $shipping_method = '';
        foreach ($order->get_items('shipping') as $ship) {
            if ($ship instanceof WC_Order_Item_Shipping) {
                $shipping_method = $ship->get_method_title();
                break;
            }
        }

        $billing = $order->get_formatted_billing_address() ?: '—';
        $shipping = $order->get_formatted_shipping_address() ?: '—';
        $date = $order->get_date_created() ? $order->get_date_created()->date('d/m/Y H:i') : '';

        $h = '<div style="font-family:Arial,Helvetica,sans-serif;color:#222;max-width:680px;">';
        $h .= '<h2 style="color:#8B0000;">Nuevo pedido desde App MundiCam</h2>';
        $h .= '<p><strong>Pedido:</strong> #' . $esc($order->get_order_number()) . ' &nbsp; '
            . '<strong>Fecha:</strong> ' . $esc($date) . ' &nbsp; '
            . '<strong>Estado inicial:</strong> ' . $esc(wc_get_order_status_name($order->get_status())) . '</p>';

        $h .= '<h3 style="color:#8B0000;">Cliente</h3><p>'
            . '<strong>Nombre:</strong> ' . $esc(trim($order->get_billing_first_name() . ' ' . $order->get_billing_last_name())) . '<br>'
            . '<strong>Empresa:</strong> ' . $esc($order->get_billing_company() ?: '—') . '<br>'
            . '<strong>Email:</strong> ' . $esc($order->get_billing_email()) . '<br>'
            . '<strong>Teléfono:</strong> ' . $esc($order->get_billing_phone() ?: '—') . '<br>'
            . '<strong>Comercial asociado:</strong> ' . $esc($comercial !== '' ? $comercial : '—') . '</p>';

        $h .= '<h3 style="color:#8B0000;">Pago y envío</h3><p>'
            . '<strong>Método de pago:</strong> ' . $esc($order->get_payment_method_title() ?: $order->get_payment_method()) . '<br>'
            . '<strong>Método de envío:</strong> ' . $esc($shipping_method ?: '—') . '<br>'
            . '<strong>Coste de envío:</strong> ' . $money($order->get_shipping_total()) . '</p>';

        $h .= '<h3 style="color:#8B0000;">Direcciones</h3>'
            . '<table style="width:100%;"><tr>'
            . '<td style="vertical-align:top;width:50%;"><strong>Facturación</strong><br>' . wp_kses_post($billing) . '</td>'
            . '<td style="vertical-align:top;width:50%;"><strong>Envío</strong><br>' . wp_kses_post($shipping) . '</td>'
            . '</tr></table>';

        $h .= '<h3 style="color:#8B0000;">Productos</h3>'
            . '<table style="border-collapse:collapse;width:100%;">'
            . '<thead><tr style="background:#f3f3f3;">'
            . '<th style="padding:6px;border:1px solid #ddd;text-align:left;">Producto</th>'
            . '<th style="padding:6px;border:1px solid #ddd;text-align:left;">SKU</th>'
            . '<th style="padding:6px;border:1px solid #ddd;">Cant.</th>'
            . '<th style="padding:6px;border:1px solid #ddd;text-align:right;">P. unit.</th>'
            . '<th style="padding:6px;border:1px solid #ddd;text-align:right;">Subtotal</th>'
            . '</tr></thead><tbody>' . $rows_items . '</tbody></table>';

        $h .= '<h3 style="color:#8B0000;">Totales</h3><p>'
            . '<strong>Subtotal:</strong> ' . $money($order->get_subtotal()) . '<br>'
            . '<strong>Envío:</strong> ' . $money($order->get_shipping_total()) . '<br>'
            . '<strong>IVA:</strong> ' . $money($order->get_total_tax()) . '<br>'
            . '<strong>Total:</strong> ' . $money($order->get_total()) . '</p>';

        $notes = $order->get_customer_note();
        if ($notes !== '') {
            $h .= '<h3 style="color:#8B0000;">Notas del cliente</h3><p>' . $esc($notes) . '</p>';
        }

        $h .= '<p style="margin-top:16px;color:#888;font-size:12px;">Origen: App MundiCam</p>';
        $h .= '</div>';

        return $h;
    }

    /**
     * v1.9.9 Email al CLIENTE, siempre, con la plantilla de WooCommerce adecuada
     * al estado real del pedido. No afirma "pagado" en pedidos de tarjeta pendientes.
     */
    private static function send_customer_order_email(WC_Order $order) {
        if ((string) $order->get_meta('_mundicam_app_customer_email_sent_v1') === '1') {
            return;
        }

        $billing_email = sanitize_email((string) $order->get_billing_email());
        if ($billing_email === '' || !is_email($billing_email)) {
            if (function_exists('error_log')) {
                error_log('[MundiCam App API] Email cliente omitido: pedido ' . $order->get_id() . ' sin billing_email válido.');
            }
            return;
        }

        try {
            if (!function_exists('WC') || !WC() || !method_exists(WC(), 'mailer')) {
                return;
            }

            $mailer = WC()->mailer();
            $emails = is_object($mailer) && method_exists($mailer, 'get_emails') ? $mailer->get_emails() : [];
            $status = (string) $order->get_status();

            // Plantilla adecuada al estado:
            //  - on-hold                -> "pedido en espera" (transferencia/manual)
            //  - processing             -> "pedido en proceso" (pago confirmado)
            //  - completed              -> "pedido completado"
            //  - pending/tarjeta/otros  -> "factura / pago del pedido" (incluye enlace de pago)
            switch ($status) {
                case 'on-hold':
                    $email_id = 'WC_Email_Customer_On_Hold_Order';
                    break;
                case 'processing':
                    $email_id = 'WC_Email_Customer_Processing_Order';
                    break;
                case 'completed':
                    $email_id = 'WC_Email_Customer_Completed_Order';
                    break;
                default:
                    $email_id = 'WC_Email_Customer_Invoice';
                    break;
            }

            $sent = false;
            if (isset($emails[$email_id]) && is_object($emails[$email_id]) && method_exists($emails[$email_id], 'trigger')) {
                // v1.9.10 Forzar habilitación temporal: si la plantilla de cliente
                // está desactivada en Ajustes -> Emails, trigger() no envía. La
                // habilitamos solo durante este disparo y restauramos después.
                $email_obj = $emails[$email_id];
                $was_enabled = method_exists($email_obj, 'is_enabled') ? $email_obj->is_enabled() : true;
                if (!$was_enabled && isset($email_obj->enabled)) {
                    $email_obj->enabled = 'yes';
                }
                try {
                    $email_obj->trigger($order->get_id(), $order);
                    $sent = true;
                } catch (Throwable $e) {
                    $sent = false;
                }
                if (!$was_enabled && isset($email_obj->enabled)) {
                    $email_obj->enabled = 'no';
                }
            }

            // Fallback: si no existe/no dispara esa plantilla, intentamos la factura.
            if (!$sent && isset($emails['WC_Email_Customer_Invoice']) && method_exists($emails['WC_Email_Customer_Invoice'], 'trigger')) {
                try {
                    $emails['WC_Email_Customer_Invoice']->trigger($order->get_id(), $order);
                    $sent = true;
                } catch (Throwable $e) {
                    $sent = false;
                }
            }

            // Fallback final: email propio con wp_mail si WooCommerce no envió nada.
            if (!$sent) {
                $subject = sprintf('Tu pedido en MundiCam #%s', $order->get_order_number());
                $body = self::build_internal_order_email_html($order);
                $headers = ['Content-Type: text/html; charset=UTF-8'];
                $sent = wp_mail($billing_email, $subject, $body, $headers);
                if ($sent && function_exists('error_log')) {
                    error_log('[MundiCam App API] Email cliente enviado por fallback wp_mail (pedido ' . $order->get_id() . ').');
                }
            }

            if ($sent) {
                $order->update_meta_data('_mundicam_app_customer_email_sent_v1', '1');
                $order->save_meta_data();
            } elseif (function_exists('error_log')) {
                error_log('[MundiCam App API] No se pudo enviar email al cliente del pedido ' . $order->get_id() . '.');
            }
        } catch (Throwable $e) {
            if (function_exists('error_log')) {
                error_log('[MundiCam App API] Error enviando email cliente pedido ' . $order->get_id() . ': ' . $e->getMessage());
            }
        }
    }

    private static function order_tax_lines_payload(WC_Order $order) {
        $tax_lines = [];
        foreach ($order->get_items('tax') as $tax_item) {
            if (!($tax_item instanceof WC_Order_Item_Tax)) {
                continue;
            }

            $rate_percent = '';
            $rate_id = (int) $tax_item->get_rate_id();
            if ($rate_id > 0 && method_exists('WC_Tax', 'get_rate_percent')) {
                $rate_percent = (string) WC_Tax::get_rate_percent($rate_id);
            }

            $tax_lines[] = [
                'id' => $tax_item->get_id(),
                'rate_id' => $rate_id,
                'label' => $tax_item->get_label(),
                'rate_code' => $tax_item->get_rate_code(),
                'rate_percent' => $rate_percent,
                'tax_total' => wc_format_decimal($tax_item->get_tax_total(), 2),
                'shipping_tax_total' => wc_format_decimal($tax_item->get_shipping_tax_total(), 2),
            ];
        }
        return $tax_lines;
    }

    /**
     * v1.9.26 Payload DETALLADO de pedido/presupuesto para la pantalla tipo Amazon.
     * Incluye: datos generales, estado con etiqueta, desglose de totales (subtotal,
     * IVA, envío, descuento, tasas, total), productos con imagen/SKU/precio por
     * línea, direcciones, pago, envío, notas y acciones disponibles.
     */
    private static function order_detail_payload(WC_Order $order) {
        $date_created = $order->get_date_created();
        $date_paid = $order->get_date_paid();
        $date_completed = $order->get_date_completed();

        // --- Productos ---
        $items = [];
        foreach ($order->get_items() as $item) {
            if (!($item instanceof WC_Order_Item_Product)) {
                continue;
            }
            $product = $item->get_product();
            $image = '';
            $permalink = '';
            $sku = '';
            if ($product instanceof WC_Product) {
                $img_id = $product->get_image_id();
                $image = $img_id ? (string) wp_get_attachment_url($img_id) : '';
                $permalink = (string) get_permalink($product->get_id());
                $sku = (string) $product->get_sku();
            }

            $qty = (int) $item->get_quantity();
            $line_subtotal = (float) $item->get_subtotal();
            $line_total = (float) $item->get_total();
            $line_tax = (float) $item->get_total_tax();
            $unit_price = $qty > 0 ? $line_subtotal / $qty : $line_subtotal;

            $items[] = [
                'product_id' => (int) $item->get_product_id(),
                'variation_id' => (int) $item->get_variation_id(),
                'sku' => $sku,
                'name' => (string) $item->get_name(),
                'quantity' => $qty,
                'price' => wc_format_decimal($unit_price, 2),
                'subtotal' => wc_format_decimal($line_subtotal, 2),
                'total' => wc_format_decimal($line_total, 2),
                'tax_total' => wc_format_decimal($line_tax, 2),
                'image' => $image,
                'permalink' => $permalink,
            ];
        }

        // --- Método de envío ---
        $shipping_method_title = '';
        foreach ($order->get_items('shipping') as $ship) {
            if ($ship instanceof WC_Order_Item_Shipping) {
                $shipping_method_title = $ship->get_method_title();
                break;
            }
        }

        // --- Tasas / cargos adicionales ---
        $fees_total = 0.0;
        foreach ($order->get_items('fee') as $fee) {
            if ($fee instanceof WC_Order_Item_Fee) {
                $fees_total += (float) $fee->get_total();
            }
        }

        // --- Estado legible ---
        $status = $order->get_status();
        $status_label = function_exists('wc_get_order_status_name')
            ? wc_get_order_status_name($status)
            : $status;
        // YITH puede no registrar sus etiquetas en wc_get_order_status_name.
        $yith_labels = [
            'ywraq-new' => 'Presupuesto nuevo',
            'ywraq-pending' => 'Presupuesto pendiente',
            'ywraq-accepted' => 'Presupuesto aceptado',
            'ywraq-rejected' => 'Presupuesto rechazado',
        ];
        if (isset($yith_labels[$status])) {
            $status_label = $yith_labels[$status];
        }

        // --- Acciones disponibles ---
        $is_quote = ((string) $order->get_meta('_mundicam_app_quote') === '1')
            || ((string) $order->get_meta('_ywraq_order_quote') !== '');
        $order_age_days = $date_created
            ? (int) ((time() - $date_created->getTimestamp()) / 86400)
            : 9999;

        $actions = [
            'can_pay' => $order->needs_payment(),
            'can_cancel' => in_array($status, ['pending', 'on-hold'], true),
            'can_repeat' => !$is_quote && in_array($status, ['processing', 'completed', 'cancelled', 'refunded'], true),
            'can_request_quote' => !$is_quote,
            'can_request_rma' => !$is_quote && $order_age_days <= 730 && in_array($status, ['processing', 'completed'], true),
        ];

        // --- Direcciones ---
        $addr = function($type) use ($order) {
            $get = 'get_' . $type . '_';
            return [
                'first_name' => (string) $order->{$get . 'first_name'}(),
                'last_name' => (string) $order->{$get . 'last_name'}(),
                'company' => (string) $order->{$get . 'company'}(),
                'address_1' => (string) $order->{$get . 'address_1'}(),
                'address_2' => (string) $order->{$get . 'address_2'}(),
                'postcode' => (string) $order->{$get . 'postcode'}(),
                'city' => (string) $order->{$get . 'city'}(),
                'state' => (string) $order->{$get . 'state'}(),
                'country' => (string) $order->{$get . 'country'}(),
            ];
        };

        $billing = $addr('billing');
        $billing['phone'] = (string) $order->get_billing_phone();
        $billing['email'] = (string) $order->get_billing_email();

        // v1.9.27 Para presupuestos: URL de pago del pedido técnico vinculado (si
        // existe) y si ya está pagado. Así Flutter puede reabrir el pago con
        // "Aceptar y pagar" sin volver a preguntar al usuario.
        $pending_order_id = null;
        $payment_url = null;
        $is_paid = false;
        if ($is_quote) {
            $is_paid = ((string) $order->get_meta('_mundicam_quote_paid') === '1');
            $linked_order_id = (int) $order->get_meta('_mundicam_quote_pending_order_id');
            if ($linked_order_id > 0) {
                $pending_order_id = $linked_order_id;
                $linked_order = wc_get_order($linked_order_id);
                if ($linked_order instanceof WC_Order && $linked_order->needs_payment()) {
                    self::ensure_order_card_gateway($linked_order);
                    $linked_order->save();
                    $payment_url = self::create_app_payment_bridge_url(
                        $linked_order,
                        (int) $linked_order->get_customer_id()
                    );
                }
            }
            $actions['can_pay'] = !$is_paid;
        }

        return [
            'id' => $order->get_id(),
            'number' => (string) $order->get_order_number(),
            'order_key' => (string) $order->get_order_key(),
            'status' => $status,
            'status_label' => $status_label,
            'date_created' => $date_created ? $date_created->date('c') : null,
            'date_paid' => $date_paid ? $date_paid->date('c') : null,
            'date_completed' => $date_completed ? $date_completed->date('c') : null,
            'is_quote' => $is_quote,
            'is_paid' => $is_paid,
            'pending_order_id' => $pending_order_id,
            'payment_url' => $payment_url,
            'subtotal' => wc_format_decimal($order->get_subtotal(), 2),
            'tax_total' => wc_format_decimal($order->get_total_tax(), 2),
            'shipping_total' => wc_format_decimal($order->get_shipping_total(), 2),
            'discount_total' => wc_format_decimal($order->get_total_discount(), 2),
            'fees_total' => wc_format_decimal($fees_total, 2),
            'total' => wc_format_decimal($order->get_total(), 2),
            'currency' => $order->get_currency(),
            'payment_method' => (string) $order->get_payment_method(),
            'payment_method_title' => (string) $order->get_payment_method_title(),
            'shipping_method_title' => $shipping_method_title,
            'customer_note' => (string) $order->get_customer_note(),
            'billing' => $billing,
            'shipping' => $addr('shipping'),
            'items' => $items,
            'actions' => $actions,
        ];
    }

    private static function order_payload(WC_Order $order) {
        $items = [];
        foreach ($order->get_items() as $item) {
            if (!($item instanceof WC_Order_Item_Product)) {
                continue;
            }
            $product = $item->get_product();
            $line_subtotal = (float) $item->get_subtotal();
            $line_tax = (float) $item->get_total_tax();
            $line_total = (float) $item->get_total();
            $items[] = [
                'id' => $item->get_id(),
                'product_id' => $item->get_product_id(),
                'variation_id' => $item->get_variation_id(),
                'name' => $item->get_name(),
                'quantity' => $item->get_quantity(),
                'subtotal' => wc_format_decimal($line_subtotal, 2),
                'tax' => wc_format_decimal($line_tax, 2),
                'total' => wc_format_decimal($line_total, 2),
                'line_subtotal' => wc_format_decimal($line_subtotal, 2),
                'line_tax' => wc_format_decimal($line_tax, 2),
                'line_total' => wc_format_decimal($line_total + $line_tax, 2),
                'sku' => $product instanceof WC_Product ? $product->get_sku() : '',
            ];
        }

        return [
            'id' => $order->get_id(),
            'number' => $order->get_order_number(),
            'order_key' => $order->get_order_key(),
            'status' => $order->get_status(),
            'date_created' => $order->get_date_created() ? $order->get_date_created()->date('c') : '',
            'subtotal' => wc_format_decimal($order->get_subtotal(), 2),
            'tax_total' => wc_format_decimal($order->get_total_tax(), 2),
            'shipping_total' => wc_format_decimal($order->get_shipping_total(), 2),
            'discount_total' => wc_format_decimal($order->get_total_discount(), 2),
            'total' => wc_format_decimal($order->get_total(), 2),
            'currency' => $order->get_currency(),
            'payment_method' => $order->get_payment_method(),
            'payment_method_title' => $order->get_payment_method_title(),
            'tax_lines' => self::order_tax_lines_payload($order),
            'line_items' => $items,
            'items' => $items,
            'payment_url' => self::is_card_payment_method($order->get_payment_method()) && in_array($order->get_status(), ['pending', 'on-hold', 'failed'], true)
                ? self::create_app_payment_bridge_url($order, (int) $order->get_customer_id())
                : '',
        ];
    }

    // =============================================================
    // CUSTOMER CREATION
    // =============================================================

    public static function customer_create(WP_REST_Request $request) {
        $user_id = (int) $request->get_param('_mundicam_user_id');
        $current_user = get_user_by('id', $user_id);

        if (!self::can_create_customers($current_user)) {
            return new WP_Error('mundicam_customer_create_forbidden', 'No tienes permisos para crear clientes.', ['status' => 403]);
        }

        $email = sanitize_email((string) $request->get_param('email'));
        if (empty($email) || !is_email($email)) {
            return new WP_Error('mundicam_customer_email_invalid', 'Email de cliente no válido.', ['status' => 400]);
        }

        // v1.9.22 NO CREAR USUARIOS DUPLICADOS. Se comprueban las dos vías por las
        // que WordPress podría acabar con dos cuentas para el mismo correo: el email
        // y el user_login (que aquí se genera a partir del email). Una misma cuenta
        // de empresa puede usarse desde varios móviles: no se duplica el usuario, se
        // añaden dispositivos (ver módulo FCM).
        $existing_user_id = (int) email_exists($email);
        if ($existing_user_id <= 0) {
            $existing_by_login = username_exists($email);
            $existing_user_id = $existing_by_login ? (int) $existing_by_login : 0;
        }

        if ($existing_user_id > 0) {
            // Si el llamante lo pide, se actualizan los datos del cliente EXISTENTE
            // en vez de crear otro usuario.
            if ((int) $request->get_param('update_if_exists') === 1 && class_exists('WC_Customer')) {
                try {
                    $existing_customer = new WC_Customer($existing_user_id);
                    $billing = $request->get_param('billing');
                    if (is_array($billing)) {
                        self::apply_customer_billing($existing_customer, $billing);
                    }
                    $shipping = $request->get_param('shipping');
                    if (is_array($shipping)) {
                        self::apply_customer_shipping($existing_customer, $shipping);
                    }
                    $existing_customer->save();
                } catch (Throwable $e) {
                    // Si falla la actualización, seguimos devolviendo el usuario existente.
                }

                return rest_ensure_response([
                    'success' => true,
                    'updated' => true,
                    'created' => false,
                    'user' => self::user_payload(get_user_by('id', $existing_user_id)),
                    'wordpress_id' => $existing_user_id,
                    'woocommerce_id' => $existing_user_id,
                    'message' => 'Este correo ya estaba registrado. Se han actualizado sus datos.',
                ]);
            }

            return new WP_Error(
                'mundicam_customer_exists',
                'Este correo ya está registrado. Inicia sesión o recupera tu contraseña.',
                ['status' => 409, 'wordpress_id' => $existing_user_id]
            );
        }

        $role = sanitize_key((string) ($request->get_param('role') ?: 'cliente'));
        $normalized_role = self::normalize_role($role);
        if (strpos($normalized_role, 'cliente') !== 0 && $role !== 'customer') {
            return new WP_Error('mundicam_customer_role_invalid', 'Solo se pueden crear roles de cliente desde la app.', ['status' => 400]);
        }

        $first_name = sanitize_text_field((string) $request->get_param('first_name'));
        $last_name = sanitize_text_field((string) $request->get_param('last_name'));
        $company = sanitize_text_field((string) $request->get_param('company'));
        $phone = sanitize_text_field((string) $request->get_param('phone'));
        $password = wp_generate_password(20, true, true);

        $new_user_id = wp_insert_user([
            'user_login' => $email,
            'user_email' => $email,
            'user_pass' => $password,
            'first_name' => $first_name,
            'last_name' => $last_name,
            'display_name' => trim($first_name . ' ' . $last_name) ?: $email,
            'role' => $role,
        ]);

        if (is_wp_error($new_user_id)) {
            return $new_user_id;
        }

        if (class_exists('WC_Customer')) {
            try {
                $customer = new WC_Customer($new_user_id);
                $customer->set_billing_email($email);
                $customer->set_billing_first_name($first_name);
                $customer->set_billing_last_name($last_name);
                $customer->set_billing_company($company);
                $customer->set_billing_phone($phone);

                $billing = $request->get_param('billing');
                if (is_array($billing)) {
                    self::apply_customer_billing($customer, $billing);
                }

                $shipping = $request->get_param('shipping');
                if (is_array($shipping)) {
                    self::apply_customer_shipping($customer, $shipping);
                }

                $customer->save();
            } catch (Throwable $e) {
                // Usuario creado igualmente; WooCommerce se puede completar después.
            }
        }

        if ((int) $request->get_param('send_reset_email') === 1) {
            self::send_new_customer_reset_email($new_user_id);
        }

        $created_user = get_user_by('id', $new_user_id);

        return rest_ensure_response([
            'success' => true,
            'user' => self::user_payload($created_user),
            'wordpress_id' => (int) $new_user_id,
            'woocommerce_id' => (int) $new_user_id,
        ]);
    }

    private static function apply_customer_billing(WC_Customer $customer, array $billing) {
        $map = [
            'first_name' => 'set_billing_first_name',
            'last_name' => 'set_billing_last_name',
            'company' => 'set_billing_company',
            'address_1' => 'set_billing_address_1',
            'address_2' => 'set_billing_address_2',
            'city' => 'set_billing_city',
            'state' => 'set_billing_state',
            'postcode' => 'set_billing_postcode',
            'country' => 'set_billing_country',
            'email' => 'set_billing_email',
            'phone' => 'set_billing_phone',
        ];

        foreach ($map as $key => $method) {
            if (isset($billing[$key]) && method_exists($customer, $method)) {
                $customer->{$method}(sanitize_text_field((string) $billing[$key]));
            }
        }

        foreach (self::customer_tax_meta_keys() as $tax_key) {
            if (!isset($billing[$tax_key])) {
                continue;
            }

            $tax_value = self::clean_tax_value($billing[$tax_key]);
            if ($tax_value === '') {
                continue;
            }

            $user_id = (int) $customer->get_id();
            if ($user_id > 0) {
                update_user_meta($user_id, 'billing_nif', $tax_value);
                update_user_meta($user_id, 'cif_nif', $tax_value);
                update_user_meta($user_id, $tax_key, $tax_value);
            }

            break;
        }
    }

    private static function apply_customer_shipping(WC_Customer $customer, array $shipping) {
        $map = [
            'first_name' => 'set_shipping_first_name',
            'last_name' => 'set_shipping_last_name',
            'company' => 'set_shipping_company',
            'address_1' => 'set_shipping_address_1',
            'address_2' => 'set_shipping_address_2',
            'city' => 'set_shipping_city',
            'state' => 'set_shipping_state',
            'postcode' => 'set_shipping_postcode',
            'country' => 'set_shipping_country',
        ];

        foreach ($map as $key => $method) {
            if (isset($shipping[$key]) && method_exists($customer, $method)) {
                $customer->{$method}(sanitize_text_field((string) $shipping[$key]));
            }
        }
    }

    private static function send_new_customer_reset_email($user_id) {
        $user = get_user_by('id', $user_id);
        if (!($user instanceof WP_User)) {
            return;
        }

        $key = get_password_reset_key($user);
        if (is_wp_error($key)) {
            return;
        }

        $url = network_site_url(
            'wp-login.php?action=rp&key=' . rawurlencode($key) . '&login=' . rawurlencode($user->user_login),
            'login'
        );

        wp_mail(
            $user->user_email,
            'Activa tu acceso profesional MundiCam',
            "Hola,\n\nSe ha creado tu acceso profesional a MundiCam. Puedes establecer tu contraseña aquí:\n\n" . $url . "\n\nGracias."
        );
    }

    /**
     * Firebase es opcional en esta fase. La versión fusionada anterior llamaba a
     * create_firebase_custom_token_for_user(), pero no incluía el método dentro
     * del mismo archivo. Para evitar errores silenciosos en /login, dejamos un
     * stub seguro: si en producción se instala una integración Firebase real,
     * se puede sustituir esta función por la generación de custom token.
     */
    private static function create_firebase_custom_token_for_user($user) {
        return '';
    }

}


/**
 * =============================================================================
 * NOTIFICACIONES PUSH (FCM HTTP v1) — v1.9.21
 * =============================================================================
 * Avisa al propietario de un pedido cuando: se crea, cambia de estado o se
 * reembolsa (parcial o total). Solo al cliente propietario, nunca a otros.
 *
 * CONFIGURACIÓN (una sola vez, en wp-config.php):
 *   define('MUNDICAM_FCM_SERVICE_ACCOUNT', '/ruta-privada/firebase-service-account.json');
 * El JSON debe estar FUERA de public_html y ser legible por PHP.
 *
 * Se usa FCM HTTP v1 (la API legacy con "server key" fue desactivada por Google).
 * Si la credencial falta o es inválida, se registra un error claro en el log;
 * nunca se abandona el envío en silencio.
 * =============================================================================
 */

if (!defined('MUNDICAM_FCM_TOKENS_META')) {
    define('MUNDICAM_FCM_TOKENS_META', '_mundicam_fcm_tokens_v1');
}
if (!defined('MUNDICAM_FCM_TOKEN_INDEX')) {
    define('MUNDICAM_FCM_TOKEN_INDEX', 'mundicam_fcm_token_index_v1');
}
if (!defined('MUNDICAM_FCM_AS_GROUP')) {
    define('MUNDICAM_FCM_AS_GROUP', 'mundicam-fcm');
}

/* -----------------------------------------------------------------------------
 * LOGS
 * -------------------------------------------------------------------------- */

/**
 * v1.9.21 Log estructurado. NUNCA registra el token completo, la private_key,
 * el JSON de la cuenta de servicio ni el access token OAuth.
 */
function mundicam_fcm_log(array $parts) {
    if (!function_exists('error_log')) {
        return;
    }
    $out = array();
    foreach ($parts as $k => $v) {
        if ($v === null || $v === '') {
            continue;
        }
        $out[] = $k . '=' . (is_scalar($v) ? (string) $v : wp_json_encode($v));
    }
    error_log('[FCM] ' . implode(' ', $out));
}

/**
 * v1.9.21 Hash corto del token, seguro para logs.
 */
function mundicam_fcm_token_hash($token) {
    return substr(hash('sha256', (string) $token), 0, 16);
}

/* -----------------------------------------------------------------------------
 * ESTADOS Y TEXTOS
 * -------------------------------------------------------------------------- */

/**
 * v1.9.21 Estados que generan notificación de cambio de estado.
 */
function mundicam_fcm_notifiable_statuses() {
    return apply_filters('mundicam_app_fcm_notifiable_statuses', array(
        'pending',
        'on-hold',
        'processing',
        'completed',
        'cancelled',
        'refunded',
        'failed',
    ));
}

/**
 * v1.9.21 Estados que NUNCA se notifican (borradores, papelera).
 */
function mundicam_fcm_excluded_statuses() {
    return array('checkout-draft', 'wc-checkout-draft', 'auto-draft', 'draft', 'trash');
}

/**
 * v1.9.21 Título y cuerpo por estado.
 */
function mundicam_fcm_status_message($status, $order_number) {
    $map = array(
        'pending'    => array('Pago pendiente',        'Tu pedido #%s está pendiente de pago.'),
        'on-hold'    => array('Pedido en espera',      'Tu pedido #%s está en espera de confirmación.'),
        'processing' => array('Pedido en preparación', 'Estamos preparando tu pedido #%s.'),
        'completed'  => array('Pedido completado',     'Tu pedido #%s ha sido completado.'),
        'cancelled'  => array('Pedido cancelado',      'Tu pedido #%s ha sido cancelado.'),
        'failed'     => array('Pago fallido',          'No se ha podido completar el pago del pedido #%s.'),
        'refunded'   => array('Pedido reembolsado',    'Tu pedido #%s ha sido reembolsado.'),
    );
    if (!isset($map[$status])) {
        return array('Pedido actualizado', sprintf('Tu pedido #%s ha cambiado de estado.', $order_number));
    }
    return array($map[$status][0], sprintf($map[$status][1], $order_number));
}

/* -----------------------------------------------------------------------------
 * EXCLUSIONES
 * -------------------------------------------------------------------------- */

/**
 * v1.9.21 ¿Es un presupuesto? Los presupuestos se guardan como pedidos y NO deben
 * generar notificaciones de pedido.
 */
function mundicam_fcm_is_quote(WC_Order $order) {
    return ((string) $order->get_meta('_mundicam_app_quote') === '1')
        || ((string) $order->get_meta('_ywraq_order_quote') !== '')
        || ((string) $order->get_meta('ywraq_raq') !== '');
}

/* -----------------------------------------------------------------------------
 * ÍNDICE GLOBAL DE TOKENS (hash -> user_id)
 * -------------------------------------------------------------------------- */

function mundicam_fcm_index_get() {
    $index = get_option(MUNDICAM_FCM_TOKEN_INDEX, array());
    return is_array($index) ? $index : array();
}

function mundicam_fcm_index_owner($token) {
    $index = mundicam_fcm_index_get();
    $hash = mundicam_fcm_token_hash($token);
    return isset($index[$hash]) ? (int) $index[$hash] : 0;
}

function mundicam_fcm_index_set($token, $user_id) {
    $index = mundicam_fcm_index_get();
    $index[mundicam_fcm_token_hash($token)] = (int) $user_id;
    if (count($index) > 20000) {
        $index = array_slice($index, -10000, null, true);
    }
    update_option(MUNDICAM_FCM_TOKEN_INDEX, $index, false);
}

function mundicam_fcm_index_remove($token) {
    $index = mundicam_fcm_index_get();
    $hash = mundicam_fcm_token_hash($token);
    if (isset($index[$hash])) {
        unset($index[$hash]);
        update_option(MUNDICAM_FCM_TOKEN_INDEX, $index, false);
    }
}

/**
 * v1.9.21 Retira un token de un usuario concreto (meta + índice).
 */
function mundicam_fcm_detach_token($token, $user_id) {
    $user_id = (int) $user_id;
    if ($user_id <= 0) {
        return;
    }
    $tokens = get_user_meta($user_id, MUNDICAM_FCM_TOKENS_META, true);
    if (is_array($tokens) && isset($tokens[$token])) {
        unset($tokens[$token]);
        update_user_meta($user_id, MUNDICAM_FCM_TOKENS_META, $tokens);
    }
}

/* -----------------------------------------------------------------------------
 * ENDPOINTS
 * -------------------------------------------------------------------------- */

add_action('rest_api_init', function () {
    $perm = array('Mundicam_App_API', 'permission_app_user');

    $register = array(
        'methods' => 'POST',
        'callback' => 'mundicam_fcm_register_device',
        'permission_callback' => $perm,
    );
    register_rest_route('mundicam-app/v1', '/fcm/register', $register);
    register_rest_route('mundicam-app/v1', '/notifications/register-device', $register);

    $unregister = array(
        'methods' => 'POST',
        'callback' => 'mundicam_fcm_unregister_device',
        'permission_callback' => $perm,
    );
    register_rest_route('mundicam-app/v1', '/fcm/unregister', $unregister);
    register_rest_route('mundicam-app/v1', '/notifications/unregister-device', $unregister);

    register_rest_route('mundicam-app/v1', '/fcm/test', array(
        'methods' => 'POST',
        'callback' => 'mundicam_fcm_test_notification',
        'permission_callback' => $perm,
    ));
});

/**
 * v1.9.21 Registra el token del dispositivo para el usuario AUTENTICADO.
 * El token se asocia siempre al usuario de la sesión, nunca al wordpress_id que
 * mande la app (manipulable). Si el token pertenecía a otra cuenta, se retira de
 * aquella mediante el índice global.
 */
function mundicam_fcm_register_device(WP_REST_Request $request) {
    $user_id = (int) $request->get_param('_mundicam_user_id');
    if ($user_id <= 0) {
        return new WP_Error('mundicam_fcm_no_user', 'Usuario no válido.', array('status' => 401));
    }

    $token = sanitize_text_field((string) ($request->get_param('fcm_token') ?: $request->get_param('token')));
    if ($token === '' || strlen($token) < 20) {
        return new WP_Error('mundicam_fcm_invalid_token', 'Token FCM no válido.', array('status' => 400));
    }

    $platform = sanitize_text_field((string) $request->get_param('platform'));
    if (!in_array($platform, array('android', 'ios', 'web'), true)) {
        $platform = 'unknown';
    }
    $device = sanitize_text_field((string) ($request->get_param('device') ?: $request->get_param('device_name')));

    // Propiedad única: si el token estaba en otra cuenta, se retira de ella.
    $previous_owner = mundicam_fcm_index_owner($token);
    if ($previous_owner > 0 && $previous_owner !== $user_id) {
        mundicam_fcm_detach_token($token, $previous_owner);
        mundicam_fcm_log(array('event' => 'token_reassigned', 'token_hash' => mundicam_fcm_token_hash($token), 'from_user' => $previous_owner, 'to_user' => $user_id));
    }

    $tokens = get_user_meta($user_id, MUNDICAM_FCM_TOKENS_META, true);
    if (!is_array($tokens)) {
        $tokens = array();
    }

    // v1.9.22 VARIOS DISPOSITIVOS POR LA MISMA CUENTA. Registrar un token nuevo
    // NUNCA elimina los anteriores del mismo usuario: se acumulan (móvil 1 + móvil
    // 2 + ...) y todos reciben las notificaciones del pedido.
    $now = current_time('mysql');
    $existing = isset($tokens[$token]) && is_array($tokens[$token]) ? $tokens[$token] : array();

    $tokens[$token] = array(
        'user_id' => $user_id,
        'platform' => $platform,
        'device' => $device,
        'created_at' => isset($existing['created_at']) ? $existing['created_at'] : $now,
        'updated_at' => $now,
        'last_seen_at' => $now,
        'enabled' => true,
    );

    if (count($tokens) > 20) {
        $tokens = array_slice($tokens, -20, null, true);
    }
    update_user_meta($user_id, MUNDICAM_FCM_TOKENS_META, $tokens);
    mundicam_fcm_index_set($token, $user_id);

    mundicam_fcm_log(array('event' => 'device_registered', 'user_id' => $user_id, 'token_hash' => mundicam_fcm_token_hash($token), 'platform' => $platform));

    return rest_ensure_response(array(
        'success' => true,
        'registered' => true,
        'platform' => $platform,
        'devices' => count($tokens),
    ));
}

/**
 * v1.9.21 Baja del token (logout / desinstalación).
 */
function mundicam_fcm_unregister_device(WP_REST_Request $request) {
    $user_id = (int) $request->get_param('_mundicam_user_id');
    $token = sanitize_text_field((string) ($request->get_param('fcm_token') ?: $request->get_param('token')));

    if ($user_id <= 0 || $token === '') {
        return new WP_Error('mundicam_fcm_invalid', 'Petición no válida.', array('status' => 400));
    }

    mundicam_fcm_detach_token($token, $user_id);
    mundicam_fcm_index_remove($token);
    mundicam_fcm_log(array('event' => 'device_unregistered', 'user_id' => $user_id, 'token_hash' => mundicam_fcm_token_hash($token)));

    return rest_ensure_response(array('success' => true, 'unregistered' => true));
}

/**
 * v1.9.21 POST /fcm/test — envía una notificación de prueba a los dispositivos
 * del usuario autenticado, usando EXACTAMENTE la misma función de envío que los
 * pedidos. No crea ni modifica ningún pedido.
 */
function mundicam_fcm_test_notification(WP_REST_Request $request) {
    $user_id = (int) $request->get_param('_mundicam_user_id');
    if ($user_id <= 0) {
        return new WP_Error('mundicam_fcm_no_user', 'Usuario no válido.', array('status' => 401));
    }

    $sa_error = '';
    $sa = mundicam_fcm_service_account($sa_error);
    if ($sa === null) {
        return new WP_Error('mundicam_fcm_service_account', 'Credencial de Firebase no disponible: ' . $sa_error, array('status' => 500));
    }

    $tokens = get_user_meta($user_id, MUNDICAM_FCM_TOKENS_META, true);
    $tokens = is_array($tokens) ? $tokens : array();

    $results = array();
    $sent = 0;
    $failed = 0;

    $data = array(
        'type' => 'order',
        'event' => 'test',
        'event_id' => 'test:' . $user_id . ':' . time(),
        'screen' => 'orders',
        'title' => 'Notificación de prueba',
        'body' => 'Si ves esto, las notificaciones de MundiCam funcionan correctamente.',
    );

    foreach (array_keys($tokens) as $token) {
        $r = mundicam_fcm_send_to_token($token, array(
            'title' => 'Notificación de prueba',
            'body' => 'Si ves esto, las notificaciones de MundiCam funcionan correctamente.',
        ), $data);

        if (!empty($r['success'])) {
            $sent++;
        } else {
            $failed++;
            if (!empty($r['invalid_token'])) {
                mundicam_fcm_detach_token($token, $user_id);
                mundicam_fcm_index_remove($token);
            }
        }
        $results[] = array(
            'token_hash' => mundicam_fcm_token_hash($token),
            'http_code' => $r['http_code'],
            'message_name' => $r['message_name'],
            'error_status' => $r['error_status'],
            'invalid_token' => (bool) $r['invalid_token'],
            'retryable' => (bool) $r['retryable'],
        );
    }

    return rest_ensure_response(array(
        'success' => ($failed === 0),
        'project_id' => $sa['project_id'],
        'tokens_found' => count($tokens),
        'sent' => $sent,
        'failed' => $failed,
        'results' => $results,
    ));
}

/* -----------------------------------------------------------------------------
 * CREDENCIALES Y ENVÍO
 * -------------------------------------------------------------------------- */

/**
 * v1.9.21 Cuenta de servicio de Firebase. Devuelve el array del JSON o null,
 * dejando en $error el motivo exacto (nunca vuelca el contenido del fichero).
 */
function mundicam_fcm_service_account(&$error = '') {
    $error = '';
    $raw = '';

    if (defined('MUNDICAM_FCM_SERVICE_ACCOUNT')) {
        $raw = MUNDICAM_FCM_SERVICE_ACCOUNT;
    }
    if ($raw === '') {
        $raw = (string) get_option('mundicam_fcm_service_account', '');
    }
    $raw = apply_filters('mundicam_app_fcm_service_account', $raw);

    if (!is_string($raw) || trim($raw) === '') {
        $error = 'falta la constante MUNDICAM_FCM_SERVICE_ACCOUNT en wp-config.php';
        return null;
    }
    $raw = trim($raw);

    if (strpos($raw, '{') !== 0) {
        if (!file_exists($raw)) {
            $error = 'la ruta del JSON no existe';
            return null;
        }
        if (!is_readable($raw)) {
            $error = 'el JSON existe pero PHP no puede leerlo (permisos)';
            return null;
        }
        $raw = (string) file_get_contents($raw);
    }

    $data = json_decode($raw, true);
    if (!is_array($data)) {
        $error = 'el contenido no es un JSON válido';
        return null;
    }
    foreach (array('project_id', 'client_email', 'private_key') as $key) {
        if (empty($data[$key])) {
            $error = 'al JSON le falta el campo ' . $key;
            return null;
        }
    }

    return $data;
}

/**
 * v1.9.21 Access token OAuth2 para FCM HTTP v1 (cacheado ~1h).
 * $force_refresh fuerza uno nuevo (usado tras un 401 UNAUTHENTICATED).
 */
function mundicam_fcm_access_token($force_refresh = false) {
    if (!$force_refresh) {
        $cached = get_transient('mundicam_fcm_access_token');
        if (is_string($cached) && $cached !== '') {
            return $cached;
        }
    } else {
        delete_transient('mundicam_fcm_access_token');
    }

    $sa_error = '';
    $sa = mundicam_fcm_service_account($sa_error);
    if ($sa === null) {
        mundicam_fcm_log(array('skipped' => 'service_account_missing', 'reason' => $sa_error));
        return '';
    }
    if (!function_exists('openssl_sign')) {
        mundicam_fcm_log(array('error' => 'openssl_unavailable'));
        return '';
    }

    $now = time();
    $b64 = function ($data) {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    };
    $signing_input = $b64(wp_json_encode(array('alg' => 'RS256', 'typ' => 'JWT'))) . '.' . $b64(wp_json_encode(array(
        'iss' => $sa['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'iat' => $now,
        'exp' => $now + 3600,
    )));

    $signature = '';
    if (!openssl_sign($signing_input, $signature, $sa['private_key'], 'sha256WithRSAEncryption')) {
        mundicam_fcm_log(array('error' => 'jwt_sign_failed', 'reason' => 'private_key inválida'));
        return '';
    }

    $response = wp_remote_post('https://oauth2.googleapis.com/token', array(
        'timeout' => 15,
        'body' => array(
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $signing_input . '.' . $b64($signature),
        ),
    ));

    if (is_wp_error($response)) {
        mundicam_fcm_log(array('error' => 'oauth_request_failed', 'reason' => $response->get_error_message()));
        return '';
    }

    $body = json_decode((string) wp_remote_retrieve_body($response), true);
    if (!is_array($body) || empty($body['access_token'])) {
        mundicam_fcm_log(array('error' => 'oauth_no_access_token', 'http' => wp_remote_retrieve_response_code($response)));
        return '';
    }

    $token = (string) $body['access_token'];
    $expires = isset($body['expires_in']) ? (int) $body['expires_in'] : 3600;
    set_transient('mundicam_fcm_access_token', $token, max(60, $expires - 120));

    return $token;
}

/**
 * v1.9.21 Envía a un token y devuelve un resultado ESTRUCTURADO para que el
 * llamador decida: registrar éxito, reintentar o eliminar el token.
 *
 * @return array success, retryable, invalid_token, http_code, error_status,
 *               error_code, message_name, retry_after
 */
function mundicam_fcm_send_to_token($token, array $notification, array $data, $is_retry_after_401 = false) {
    $result = array(
        'success' => false,
        'retryable' => false,
        'invalid_token' => false,
        'http_code' => 0,
        'error_status' => '',
        'error_code' => '',
        'message_name' => '',
        'retry_after' => 0,
    );

    $sa_error = '';
    $sa = mundicam_fcm_service_account($sa_error);
    if ($sa === null) {
        $result['error_status'] = 'SERVICE_ACCOUNT_MISSING';
        mundicam_fcm_log(array('skipped' => 'service_account_missing', 'reason' => $sa_error));
        return $result;
    }

    $access = mundicam_fcm_access_token($is_retry_after_401);
    if ($access === '') {
        $result['error_status'] = 'OAUTH_FAILED';
        $result['retryable'] = true;
        return $result;
    }

    // FCM exige que todos los valores de data sean cadenas.
    $string_data = array();
    foreach ($data as $k => $v) {
        $string_data[(string) $k] = is_scalar($v) ? (string) $v : wp_json_encode($v);
    }

    // notification + data juntos: necesario para que Android/iOS muestren el aviso
    // con la app minimizada o cerrada, y para que Flutter sepa qué pedido abrir.
    $message = array(
        'message' => array(
            'token' => $token,
            'notification' => array(
                'title' => (string) $notification['title'],
                'body' => (string) $notification['body'],
            ),
            'data' => $string_data,
            'android' => array(
                'priority' => 'high',
                'notification' => array(
                    'channel_id' => 'mundicam_orders',
                    'icon' => 'mundicam_notification_logo',
                    'color' => '#000000',
                    'sound' => 'default',
                ),
            ),
            'apns' => array(
                'headers' => array(
                    'apns-priority' => '10',
                    'apns-push-type' => 'alert',
                ),
                'payload' => array('aps' => array('sound' => 'default')),
            ),
        ),
    );

    $url = 'https://fcm.googleapis.com/v1/projects/' . rawurlencode($sa['project_id']) . '/messages:send';

    $response = wp_remote_post($url, array(
        'timeout' => 20,
        'headers' => array(
            'Authorization' => 'Bearer ' . $access,
            'Content-Type' => 'application/json; charset=utf-8',
        ),
        'body' => wp_json_encode($message),
    ));

    if (is_wp_error($response)) {
        // Error de red/timeout: temporal, se reintenta.
        $result['retryable'] = true;
        $result['error_status'] = 'NETWORK_ERROR';
        $result['error_code'] = $response->get_error_code();
        return $result;
    }

    $code = (int) wp_remote_retrieve_response_code($response);
    $body_raw = (string) wp_remote_retrieve_body($response);
    $body = json_decode($body_raw, true);
    $result['http_code'] = $code;

    $retry_after = wp_remote_retrieve_header($response, 'retry-after');
    if (is_numeric($retry_after)) {
        $result['retry_after'] = (int) $retry_after;
    }

    if ($code >= 200 && $code < 300) {
        $result['success'] = true;
        $result['message_name'] = is_array($body) && !empty($body['name']) ? (string) $body['name'] : '';
        return $result;
    }

    $error_status = '';
    $error_code = '';
    $details = array();
    if (is_array($body) && isset($body['error'])) {
        $error_status = isset($body['error']['status']) ? (string) $body['error']['status'] : '';
        $error_code = isset($body['error']['code']) ? (string) $body['error']['code'] : '';
        $details = isset($body['error']['details']) && is_array($body['error']['details']) ? $body['error']['details'] : array();
    }
    $result['error_status'] = $error_status;
    $result['error_code'] = $error_code;

    // ---- Token realmente inválido: SOLO con UNREGISTERED, o cuando los details
    // confirmen explícitamente que el registration token no vale. Un INVALID_ARGUMENT
    // genérico puede significar payload mal formado: en ese caso NO se borra el token.
    $details_blob = wp_json_encode($details);
    $is_unregistered = ($error_status === 'UNREGISTERED' || $error_status === 'NOT_FOUND');
    $details_say_bad_token = (
        strpos((string) $details_blob, 'UNREGISTERED') !== false
        || (strpos((string) $details_blob, 'INVALID_ARGUMENT') !== false
            && stripos((string) $details_blob, 'registration token') !== false)
    );
    $details_say_bad_payload = (strpos((string) $details_blob, 'google.rpc.BadRequest') !== false);

    if ($is_unregistered || ($details_say_bad_token && !$details_say_bad_payload)) {
        $result['invalid_token'] = true;
        return $result;
    }

    // ---- Errores temporales: se reintentan.
    if (in_array($code, array(429, 500, 502, 503, 504), true) || $error_status === 'UNAVAILABLE' || $error_status === 'INTERNAL') {
        $result['retryable'] = true;
        return $result;
    }

    // ---- 401: access token caducado. Se refresca y se reintenta UNA sola vez.
    if ($code === 401 || $error_status === 'UNAUTHENTICATED') {
        if (!$is_retry_after_401) {
            mundicam_fcm_log(array('event' => 'oauth_refresh_retry', 'http' => 401));
            return mundicam_fcm_send_to_token($token, $notification, $data, true);
        }
        $result['retryable'] = false; // Credenciales mal: no insistir.
        return $result;
    }

    // ---- Resto (payload inválido, SENDER_ID_MISMATCH, THIRD_PARTY_AUTH_ERROR,
    // proyecto incorrecto): error permanente, no se reintenta ni se borra token.
    mundicam_fcm_log(array(
        'error' => 'send_failed',
        'http' => $code,
        'error_status' => $error_status,
        'error_code' => $error_code,
        'token_hash' => mundicam_fcm_token_hash($token),
    ));

    return $result;
}

/* -----------------------------------------------------------------------------
 * DEDUPLICACIÓN POR EVENTO
 * -------------------------------------------------------------------------- */

/**
 * v1.9.21 Deduplicación por EVENTO concreto (con caducidad), no permanente por
 * estado. Así una transición legítima repetida más tarde (processing -> on-hold
 * -> processing) SÍ vuelve a notificar, pero el mismo evento disparado dos veces
 * seguidos no duplica el aviso.
 */
function mundicam_fcm_event_seen($event_id, $ttl = 600) {
    $key = 'mcfcm_' . md5((string) $event_id);
    if (get_transient($key) !== false) {
        return true;
    }
    set_transient($key, 1, (int) $ttl);
    return false;
}

/* -----------------------------------------------------------------------------
 * DESPACHO DE EVENTOS
 * -------------------------------------------------------------------------- */

/**
 * v1.9.21 Encola un evento. Action Scheduler si está disponible (persistente y
 * con reintentos); si no, shutdown como respaldo.
 */
function mundicam_fcm_enqueue_event(array $args, $delay = 0) {
    $args = wp_parse_args($args, array(
        'order_id' => 0,
        'event' => '',
        'event_id' => '',
        'old_status' => '',
        'new_status' => '',
        'refund_id' => 0,
        'refund_amount' => '',
        'refund_type' => '',
        'token' => '',
        'attempt' => 0,
    ));

    if (function_exists('as_schedule_single_action') && $delay > 0) {
        as_schedule_single_action(time() + (int) $delay, 'mundicam_fcm_dispatch_event', array($args), MUNDICAM_FCM_AS_GROUP);
        return;
    }
    if (function_exists('as_enqueue_async_action')) {
        as_enqueue_async_action('mundicam_fcm_dispatch_event', array($args), MUNDICAM_FCM_AS_GROUP);
        return;
    }
    add_action('shutdown', function () use ($args) {
        mundicam_fcm_dispatch_event($args);
    });
}

add_action('mundicam_fcm_dispatch_event', 'mundicam_fcm_dispatch_event', 10, 1);

/**
 * v1.9.21 Procesa un evento: resuelve destinatario y tokens, envía y gestiona
 * éxito / reintento / token inválido de forma independiente por dispositivo.
 */
function mundicam_fcm_dispatch_event($args) {
    try {
        if (!is_array($args)) {
            return;
        }
        $order_id = (int) (isset($args['order_id']) ? $args['order_id'] : 0);
        $event = (string) (isset($args['event']) ? $args['event'] : '');
        $event_id = (string) (isset($args['event_id']) ? $args['event_id'] : '');
        $old_status = (string) (isset($args['old_status']) ? $args['old_status'] : '');
        $new_status = (string) (isset($args['new_status']) ? $args['new_status'] : '');
        $refund_id = (int) (isset($args['refund_id']) ? $args['refund_id'] : 0);
        $refund_amount = (string) (isset($args['refund_amount']) ? $args['refund_amount'] : '');
        $refund_type = (string) (isset($args['refund_type']) ? $args['refund_type'] : '');
        $only_token = (string) (isset($args['token']) ? $args['token'] : '');
        $attempt = (int) (isset($args['attempt']) ? $args['attempt'] : 0);

        if ($order_id <= 0 || !function_exists('wc_get_order')) {
            mundicam_fcm_log(array('skipped' => 'invalid_order', 'order_id' => $order_id));
            return;
        }

        $order = wc_get_order($order_id);
        if (!($order instanceof WC_Order)) {
            mundicam_fcm_log(array('skipped' => 'invalid_order', 'order_id' => $order_id));
            return;
        }

        $status = $new_status !== '' ? $new_status : $order->get_status();
        $status = str_replace('wc-', '', $status);

        if (in_array($status, mundicam_fcm_excluded_statuses(), true)) {
            mundicam_fcm_log(array('skipped' => 'draft_or_trash', 'order_id' => $order_id, 'status' => $status));
            return;
        }
        if (mundicam_fcm_is_quote($order)) {
            mundicam_fcm_log(array('skipped' => 'quote', 'order_id' => $order_id));
            return;
        }

        // v1.9.22 Destinatario: TODOS los dispositivos de la CUENTA propietaria
        // (customer_id, o el usuario que corresponda al billing_email del pedido).
        $recipient = mundicam_fcm_get_order_recipient_tokens($order);
        $customer_id = (int) $recipient['user_id'];
        $all_tokens = $recipient['tokens'];

        if ($customer_id <= 0) {
            mundicam_fcm_log(array('skipped' => 'no_customer', 'order_id' => $order_id));
            return;
        }
        if (empty($all_tokens)) {
            mundicam_fcm_log(array('skipped' => 'no_tokens', 'order_id' => $order_id, 'customer_id' => $customer_id));
            return;
        }

        $tokens = ($only_token !== '') ? array($only_token => true) : $all_tokens;

        $order_number = (string) $order->get_order_number();

        // Título y cuerpo según el evento.
        if ($event === 'order_created') {
            $title = 'Pedido recibido';
            $body = sprintf('Hemos recibido tu pedido #%s.', $order_number);
        } elseif ($event === 'order_partially_refunded') {
            $amount_label = ($refund_amount !== '' && function_exists('wc_price'))
                ? wp_strip_all_tags(wc_price($refund_amount, array('currency' => $order->get_currency())))
                : $refund_amount . ' €';
            $title = 'Reembolso parcial';
            $body = sprintf('Se han reembolsado %s del pedido #%s.', $amount_label, $order_number);
        } elseif ($event === 'order_refunded') {
            $title = 'Pedido reembolsado';
            $body = sprintf('Tu pedido #%s ha sido reembolsado.', $order_number);
        } else {
            list($title, $body) = mundicam_fcm_status_message($status, $order_number);
        }

        $data = array(
            'type' => 'order',
            'event' => $event,
            'event_id' => $event_id,
            'order_id' => (string) $order->get_id(),
            'order_number' => $order_number,
            'old_status' => $old_status,
            'status' => $status,
            'screen' => 'orders',
            'route' => 'order_detail',
            'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
            'refund_id' => (string) $refund_id,
            'refund_amount' => $refund_amount,
            'refund_type' => $refund_type,
            'title' => $title,
            'body' => $body,
        );

        mundicam_fcm_log(array(
            'event' => $event,
            'event_id' => $event_id,
            'order_id' => $order_id,
            'old_status' => $old_status,
            'status' => $status,
            'customer_id' => $customer_id,
            'tokens' => count($tokens),
            'attempt' => $attempt,
        ));

        // Reintentos escalonados: 1 min, 5 min, 15 min. Máximo 3.
        $backoff = array(60, 300, 900);

        foreach (array_keys($tokens) as $token) {
            $meta = isset($all_tokens[$token]) && is_array($all_tokens[$token]) ? $all_tokens[$token] : array();
            $platform = isset($meta['platform']) ? $meta['platform'] : '';

            $r = mundicam_fcm_send_to_token($token, array('title' => $title, 'body' => $body), $data);

            mundicam_fcm_log(array(
                'event_id' => $event_id,
                'token_hash' => mundicam_fcm_token_hash($token),
                'platform' => $platform,
                'attempt' => $attempt,
                'http' => $r['http_code'],
                'message' => $r['message_name'],
                'error_status' => $r['error_status'],
                'retryable' => $r['retryable'] ? 1 : 0,
                'invalid_token' => $r['invalid_token'] ? 1 : 0,
            ));

            if (!empty($r['success'])) {
                continue; // Éxito real (HTTP 2xx + message name).
            }

            if (!empty($r['invalid_token'])) {
                // Solo tokens realmente inválidos: no afecta a los demás dispositivos.
                mundicam_fcm_detach_token($token, $customer_id);
                mundicam_fcm_index_remove($token);
                continue;
            }

            if (!empty($r['retryable']) && $attempt < count($backoff)) {
                $delay = !empty($r['retry_after']) ? max((int) $r['retry_after'], $backoff[$attempt]) : $backoff[$attempt];
                $retry_args = $args;
                $retry_args['token'] = $token;   // Reintento solo de este dispositivo.
                $retry_args['attempt'] = $attempt + 1;
                mundicam_fcm_enqueue_event($retry_args, $delay);
                mundicam_fcm_log(array('event' => 'retry_scheduled', 'event_id' => $event_id, 'token_hash' => mundicam_fcm_token_hash($token), 'in_seconds' => $delay, 'next_attempt' => $attempt + 1));
            }
        }
    } catch (Throwable $e) {
        mundicam_fcm_log(array('error' => 'dispatch_exception', 'reason' => $e->getMessage()));
    }
}

/* -----------------------------------------------------------------------------
 * HOOKS DE WOOCOMMERCE
 * -------------------------------------------------------------------------- */

/**
 * v1.9.22 Resuelve TODOS los tokens FCM de la CUENTA propietaria del pedido.
 *
 * No se trata de notificar a usuarios distintos: una misma cuenta de empresa
 * puede estar iniciada en varios móviles (estilo Amazon) y todos esos
 * dispositivos deben recibir el aviso del pedido.
 *
 * Orden de resolución:
 *   1. customer_id del pedido
 *   2. usuario cuyo user_email coincide con el billing_email del pedido
 *   3. usuario cuyo meta billing_email coincide con el billing_email del pedido
 *
 * @return array [ 'user_id' => int, 'tokens' => array token => meta ]
 */
function mundicam_fcm_get_order_recipient_tokens($order) {
    $result = array('user_id' => 0, 'tokens' => array());
    if (!($order instanceof WC_Order)) {
        return $result;
    }

    $user_id = (int) $order->get_customer_id();

    if ($user_id <= 0) {
        $billing_email = sanitize_email((string) $order->get_billing_email());
        if ($billing_email !== '' && is_email($billing_email)) {
            $user = get_user_by('email', $billing_email);
            if ($user instanceof WP_User) {
                $user_id = (int) $user->ID;
            } else {
                $found = get_users(array(
                    'meta_key' => 'billing_email',
                    'meta_value' => $billing_email,
                    'fields' => 'ID',
                    'number' => 1,
                ));
                if (!empty($found[0])) {
                    $user_id = (int) $found[0];
                }
            }
        }
    }

    if ($user_id <= 0) {
        return $result;
    }

    $tokens = get_user_meta($user_id, MUNDICAM_FCM_TOKENS_META, true);
    $tokens = is_array($tokens) ? $tokens : array();

    // Solo dispositivos activos, sin duplicados (las claves ya son únicas).
    $active = array();
    foreach ($tokens as $token => $meta) {
        if (is_array($meta) && isset($meta['enabled']) && $meta['enabled'] === false) {
            continue;
        }
        $active[$token] = is_array($meta) ? $meta : array();
    }

    $result['user_id'] = $user_id;
    $result['tokens'] = $active;

    return $result;
}

/* -----------------------------------------------------------------------------
 * EMAILS POR CAMBIO DE ESTADO
 * -------------------------------------------------------------------------- */

/**
 * v1.9.22 Dispara los emails (cliente + interno) en cada cambio de estado.
 * Va en un hook propio, separado del push, para que un fallo de FCM no impida
 * el email y viceversa.
 */
add_action('woocommerce_order_status_changed', function ($order_id, $old_status, $new_status) {
    try {
        if (!class_exists('Mundicam_App_API') || !method_exists('Mundicam_App_API', 'app_send_status_change_emails')) {
            return;
        }
        $order = wc_get_order($order_id);
        if (!($order instanceof WC_Order)) {
            return;
        }
        // Los presupuestos no generan emails de pedido.
        if (function_exists('mundicam_fcm_is_quote') && mundicam_fcm_is_quote($order)) {
            error_log('[MundiCam Email] skipped=quote order_id=' . $order_id);
            return;
        }
        Mundicam_App_API::app_send_status_change_emails($order, $old_status, $new_status);
    } catch (Throwable $e) {
        error_log('[MundiCam Email] Error en hook de cambio de estado (pedido ' . $order_id . '): ' . $e->getMessage());
    }
}, 20, 3);

/**
 * v1.9.21 PEDIDO NUEVO -> event=order_created, sea cual sea el estado inicial
 * (los pedidos de la app nacen en pending u on-hold y deben avisar igual).
 * Se difiere unos segundos para que el pedido esté completamente guardado.
 */
add_action('woocommerce_new_order', function ($order_id) {
    $order_id = (int) $order_id;
    if ($order_id <= 0) {
        return;
    }
    // v1.9.23 Ventana que suprime SOLO el cambio de estado automático que hace
    // WooCommerce inmediatamente al crear el pedido (pending->pending o similar).
    // Se guarda el estado inicial para no confundirlo con una confirmación real
    // de Redsys (pending->processing), que debe notificarse siempre.
    $order_obj = wc_get_order($order_id);
    $initial_status = ($order_obj instanceof WC_Order) ? $order_obj->get_status() : '';
    set_transient('mcfcm_new_' . $order_id, $initial_status, 30);

    $event_id = 'created:' . $order_id;
    if (mundicam_fcm_event_seen($event_id, 3600)) {
        mundicam_fcm_log(array('skipped' => 'duplicate', 'event_id' => $event_id));
        return;
    }

    mundicam_fcm_enqueue_event(array(
        'order_id' => $order_id,
        'event' => 'order_created',
        'event_id' => $event_id,
    ), 15);
}, 10, 1);

/**
 * v1.9.27 Cuando el PEDIDO TÉCNICO creado desde "Aceptar y pagar" confirma su
 * pago (pasa a processing/completed), el PRESUPUESTO original se marca como
 * pagado: deja de aparecer en /quotes y a partir de ahora se ve en /orders.
 *
 * No se elimina el presupuesto ni se duplica nada: solo se actualiza su meta y,
 * si procede, su estado. El pedido técnico es el que de verdad representa la
 * venta a partir de este punto.
 */
add_action('woocommerce_order_status_changed', function ($order_id, $old_status, $new_status) {
    try {
        $new_status = str_replace('wc-', '', (string) $new_status);
        if (!in_array($new_status, array('processing', 'completed'), true)) {
            return;
        }

        $order = wc_get_order($order_id);
        if (!($order instanceof WC_Order)) {
            return;
        }

        $quote_id = (int) $order->get_meta('_mundicam_app_from_quote');
        if ($quote_id <= 0) {
            return; // No es un pedido técnico vinculado a un presupuesto.
        }

        $quote = wc_get_order($quote_id);
        if (!($quote instanceof WC_Order)) {
            return;
        }

        // Idempotente: si ya se marcó como pagado, no repetir.
        if ((string) $quote->get_meta('_mundicam_quote_paid') === '1') {
            return;
        }

        $quote->update_meta_data('_mundicam_quote_paid', '1');
        $quote->update_meta_data('_mundicam_quote_paid_order_id', (int) $order->get_id());
        $quote->add_order_note('Presupuesto pagado a través del pedido #' . $order->get_id() . '. Ya no aparece como presupuesto pendiente.');
        $quote->save();

        error_log('[MundiCam Quote] quote_id=' . $quote_id . ' paid via order_id=' . $order->get_id() . ' status=' . $new_status);
    } catch (Throwable $e) {
        error_log('[MundiCam Quote] Error marcando presupuesto pagado (pedido ' . $order_id . '): ' . $e->getMessage());
    }
}, 15, 3);

/**
 * v1.9.21 CAMBIO DE ESTADO -> event=order_status_changed.
 * Se ignora el cambio producido dentro de la propia creación (fusionado con
 * order_created) y los estados no notificables.
 */
add_action('woocommerce_order_status_changed', function ($order_id, $old_status, $new_status) {
    $order_id = (int) $order_id;
    $old_status = str_replace('wc-', '', (string) $old_status);
    $new_status = str_replace('wc-', '', (string) $new_status);

    if (!in_array($new_status, mundicam_fcm_notifiable_statuses(), true)) {
        return;
    }
    if (in_array($new_status, mundicam_fcm_excluded_statuses(), true)) {
        return;
    }

    // v1.9.23 Solo suprimir si el cambio es hacia el MISMO estado con el que se
    // creó (p.ej. pending->pending). Si el nuevo estado es DISTINTO (pending->
    // processing por confirmación de Redsys), es una transición real y debe avisar.
    $initial_status = get_transient('mcfcm_new_' . $order_id);
    if ($initial_status !== false && $initial_status === $new_status) {
        mundicam_fcm_log(array('skipped' => 'initial_status_same', 'order_id' => $order_id, 'status' => $new_status));
        return;
    }

    $order = wc_get_order($order_id);
    $modified = ($order instanceof WC_Order && $order->get_date_modified()) ? $order->get_date_modified()->getTimestamp() : time();

    $event_id = 'status:' . $order_id . ':' . $old_status . ':' . $new_status . ':' . $modified;
    if (mundicam_fcm_event_seen($event_id, 600)) {
        mundicam_fcm_log(array('skipped' => 'duplicate', 'event_id' => $event_id));
        return;
    }

    mundicam_fcm_enqueue_event(array(
        'order_id' => $order_id,
        'event' => 'order_status_changed',
        'event_id' => $event_id,
        'old_status' => $old_status,
        'new_status' => $new_status,
    ));
}, 10, 3);

/**
 * v1.9.21 REEMBOLSOS -> order_partially_refunded / order_refunded.
 * La clave de deduplicación se basa en refund_id. Un reembolso total marca
 * además el evento de estado 'refunded' como visto, para no avisar dos veces.
 */
add_action('woocommerce_order_refunded', function ($order_id, $refund_id) {
    try {
        $order_id = (int) $order_id;
        $refund_id = (int) $refund_id;

        $order = wc_get_order($order_id);
        if (!($order instanceof WC_Order)) {
            return;
        }

        $refund = wc_get_order($refund_id);
        $refund_amount = ($refund instanceof WC_Order_Refund) ? (string) $refund->get_amount() : '';

        $total = (float) $order->get_total();
        $refunded_total = (float) $order->get_total_refunded();
        $is_full = ($total > 0 && $refunded_total + 0.005 >= $total);

        $event = $is_full ? 'order_refunded' : 'order_partially_refunded';
        $refund_type = $is_full ? 'full' : 'partial';
        $event_id = 'refund:' . $order_id . ':' . $refund_id;

        if (mundicam_fcm_event_seen($event_id, 3600)) {
            mundicam_fcm_log(array('skipped' => 'duplicate', 'event_id' => $event_id));
            return;
        }

        // v1.9.23 Un reembolso total también dispara order_status_changed a
        // 'refunded'. Lo marcamos como visto desde CUALQUIER estado previo posible
        // (no solo processing/completed) para que no llegue un segundo aviso.
        if ($is_full) {
            $modified = $order->get_date_modified() ? $order->get_date_modified()->getTimestamp() : time();
            $possible_origins = array('pending', 'on-hold', 'processing', 'completed', 'cancelled', 'failed');
            foreach ($possible_origins as $origin) {
                mundicam_fcm_event_seen('status:' . $order_id . ':' . $origin . ':refunded:' . $modified, 600);
            }
        }

        mundicam_fcm_enqueue_event(array(
            'order_id' => $order_id,
            'event' => $event,
            'event_id' => $event_id,
            'new_status' => $order->get_status(),
            'refund_id' => $refund_id,
            'refund_amount' => $refund_amount,
            'refund_type' => $refund_type,
        ));
    } catch (Throwable $e) {
        mundicam_fcm_log(array('error' => 'refund_hook_exception', 'reason' => $e->getMessage()));
    }
}, 10, 2);

/**
 * v1.7.1: alias de compatibilidad para evitar 404 si alguna pantalla de Flutter
 * sigue llamando a rutas antiguas o variantes de marca/categoría.
 *
 * No cambia la lógica de negocio: todos los alias terminan entrando en los mismos
 * métodos centrales de Mundicam_App_API, por lo que mantienen token, permisos,
 * precios por rol, stock interno y payload único.
 */
add_action('rest_api_init', function () {
    $permission = ['Mundicam_App_API', 'permission_app_user'];

    foreach (['mundicam-app/v1', 'mundicam/v1'] as $namespace) {
        // Alias básicos en namespace legacy.
        if ($namespace === 'mundicam/v1') {
            register_rest_route($namespace, '/categories', [
                'methods' => 'GET',
                'callback' => ['Mundicam_App_API', 'categories'],
                'permission_callback' => $permission,
            ]);
            register_rest_route($namespace, '/products', [
                'methods' => 'GET',
                'callback' => ['Mundicam_App_API', 'products'],
                'permission_callback' => $permission,
            ]);

            register_rest_route($namespace, '/products/(?P<id>\d+)', [
                'methods' => 'GET',
                'callback' => ['Mundicam_App_API', 'product_detail'],
                'permission_callback' => $permission,
            ]);
        }

        // Alias en español útiles si el código de Flutter antiguo usó nombres localizados.
        register_rest_route($namespace, '/categorias', [
            'methods' => 'GET',
            'callback' => ['Mundicam_App_API', 'categories'],
            'permission_callback' => $permission,
        ]);

        register_rest_route($namespace, '/marcas', [
            'methods' => 'GET',
            'callback' => ['Mundicam_App_API', 'brands'],
            'permission_callback' => $permission,
        ]);

        register_rest_route($namespace, '/productos', [
            'methods' => 'GET',
            'callback' => ['Mundicam_App_API', 'products'],
            'permission_callback' => $permission,
        ]);

        register_rest_route($namespace, '/producto/(?P<id>\d+)', [
            'methods' => 'GET',
            'callback' => ['Mundicam_App_API', 'product_detail'],
            'permission_callback' => $permission,
        ]);

        // Alias de productos por marca. El parámetro de ruta se llama "brand"
        // porque products() ya lo entiende como slug, ID o nombre normalizado.
        foreach ([
            '/brand/(?P<brand>[^/]+)/products',
            '/brands/(?P<brand>[^/]+)/products',
            '/products/brand/(?P<brand>[^/]+)',
            '/products/brands/(?P<brand>[^/]+)',
            '/products-by-brand/(?P<brand>[^/]+)',
            '/marca/(?P<brand>[^/]+)/productos',
            '/marcas/(?P<brand>[^/]+)/productos',
            '/productos/marca/(?P<brand>[^/]+)',
            '/productos-por-marca/(?P<brand>[^/]+)',
        ] as $route) {
            register_rest_route($namespace, $route, [
                'methods' => 'GET',
                'callback' => ['Mundicam_App_API', 'products'],
                'permission_callback' => $permission,
            ]);
        }

        // Alias de productos por categoría. El parámetro de ruta se llama "category"
        // porque products() ya acepta ID, slug o nombre.
        foreach ([
            '/category/(?P<category>[^/]+)/products',
            '/categories/(?P<category>[^/]+)/products',
            '/products/category/(?P<category>[^/]+)',
            '/products-by-category/(?P<category>[^/]+)',
            '/categoria/(?P<category>[^/]+)/productos',
            '/categorias/(?P<category>[^/]+)/productos',
            '/productos/categoria/(?P<category>[^/]+)',
            '/productos-por-categoria/(?P<category>[^/]+)',
        ] as $route) {
            register_rest_route($namespace, $route, [
                'methods' => 'GET',
                'callback' => ['Mundicam_App_API', 'products'],
                'permission_callback' => $permission,
            ]);
        }
    }
}, 25);

Mundicam_App_API::init();

register_activation_hook(__FILE__, static function() {
    if (false === get_option(Mundicam_App_API::TOKEN_INDEX_OPTION, false)) {
        add_option(Mundicam_App_API::TOKEN_INDEX_OPTION, [], '', false);
    }
});

// =============================================================
// FILTROS DE CATÁLOGO MUNDICAM - INTEGRADO
// =============================================================
/**
 * Endpoint personalizado para filtros de catálogo - Versión Mejorada
 * URL: https://www.mundicam.com/wp-json/mundicam/v1/catalog-filters?category_id=44
 * 
 * Características:
 * - Caché de resultados (5 minutos)
 * - Soporte para múltiples categorías
 * - Filtros con metadatos adicionales
 * - Ordenación alfabética de opciones
 * - Logs de depuración
 * - Más atributos de filtro
 * 
 * Instalación:
 * 1. Crear archivo en wp-content/themes/tu-tema/custom-endpoint-filters.php
 * 2. Agregar require_once get_template_directory() . '/custom-endpoint-filters.php'; en functions.php
 */

// ================================================================
// CONSTANTES DE CONFIGURACIÓN
// ================================================================

if (!defined('MUNDICAM_FILTERS_CACHE_TIME')) { define('MUNDICAM_FILTERS_CACHE_TIME', 300); } // 5 minutos en segundos
if (!defined('MUNDICAM_FILTERS_DEBUG')) { define('MUNDICAM_FILTERS_DEBUG', false); } // Activar logs de depuración


function mundicam_filters_permission_app_user(WP_REST_Request $request) {
    if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'permission_app_user')) {
        return Mundicam_App_API::permission_app_user($request);
    }

    return new WP_Error('mundicam_app_unauthorized', 'Sesión de app no válida. Vuelve a iniciar sesión.', ['status' => 401]);
}

// ================================================================
// 1. REGISTRAR EL ENDPOINT
// ================================================================

add_action('rest_api_init', function () {
    register_rest_route('mundicam/v1', '/catalog-filters', [
        'methods' => 'GET',
        'callback' => 'mundicam_get_catalog_filters',
        'permission_callback' => 'mundicam_filters_permission_app_user',
        'args' => [
            'category_id' => [
                'required' => true,
                'validate_callback' => function($param) {
                    return is_numeric($param) && $param > 0;
                }
            ],
            'search' => [
                'required' => false,
                'validate_callback' => function($param) {
                    return is_string($param);
                }
            ],
            'include_subcategories' => [
                'required' => false,
                'default' => false,
                'validate_callback' => function($param) {
                    return in_array((string) $param, ['1', '0', 'true', 'false', 'yes', 'no', ''], true) || is_bool($param) || is_numeric($param);
                }
            ],
            'brand_id' => [
                'required' => false,
                'validate_callback' => function($param) {
                    return $param === null || $param === '' || (is_numeric($param) && $param >= 0);
                }
            ],
            'min_price' => [
                'required' => false,
                'validate_callback' => function($param) {
                    return is_numeric($param) && $param >= 0;
                }
            ],
            'max_price' => [
                'required' => false,
                'validate_callback' => function($param) {
                    return is_numeric($param) && $param >= 0;
                }
            ]
        ]
    ]);
});

// ================================================================
// 2. FUNCIÓN PRINCIPAL DEL ENDPOINT
// ================================================================

function mundicam_get_catalog_filters($request) {
    // v1.6.0: aunque el endpoint sea compatible públicamente, si la app manda token
    // se inicializa el usuario real para que rangos de precio/filtros no mezclen roles.
    if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'permission_app_user')) {
        $has_token = trim((string) $request->get_header('authorization')) !== ''
            || trim((string) $request->get_header('x-mundicam-app-token')) !== ''
            || trim((string) $request->get_param('app_token')) !== '';
        if ($has_token) {
            try {
                Mundicam_App_API::permission_app_user($request);
            } catch (Throwable $e) {
                // No rompemos compatibilidad pública de filtros.
            }
        }
    }

    $category_id = intval($request->get_param('category_id'));
    $search = sanitize_text_field($request->get_param('search') ?? '');
    $include_subcategories = filter_var($request->get_param('include_subcategories') ?? false, FILTER_VALIDATE_BOOLEAN);
    $brand_id = intval($request->get_param('brand_id') ?? 0);
    if ($brand_id <= 0) {
        $brand_id = intval($request->get_param('brandId') ?? 0);
    }
    $min_price = floatval($request->get_param('min_price') ?? 0);
    $max_price = floatval($request->get_param('max_price') ?? 0);
    
    // Validar categoría
    if ($category_id <= 0) {
        return new WP_REST_Response([
            'success' => false,
            'error' => 'Categoría inválida',
            'code' => 'invalid_category'
        ], 400);
    }
    
    try {
        // Generar clave de caché
        $cache_key = mundicam_generate_cache_key($category_id, $search, $include_subcategories, $brand_id, $min_price, $max_price);
        if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'app_catalog_cache_identity')) {
            $cache_key .= '_role_' . md5(Mundicam_App_API::app_catalog_cache_identity());
        }
        
        // Intentar obtener de caché
        $cached_data = get_transient($cache_key);
        
        if ($cached_data !== false) {
            if (MUNDICAM_FILTERS_DEBUG) {
                error_log('🔵 [Mundicam Filters] Datos servidos desde caché para categoría ' . $category_id);
            }
            
            return new WP_REST_Response([
                'success' => true,
                'data' => $cached_data,
                'category_id' => $category_id,
                'from_cache' => true,
                'timestamp' => time(),
            ], 200);
        }
        
        // Construir filtros
        $filters = mundicam_build_category_filters(
            $category_id, 
            $search, 
            $include_subcategories, 
            $brand_id, 
            $min_price, 
            $max_price
        );
        
        // Guardar en caché
        set_transient($cache_key, $filters, MUNDICAM_FILTERS_CACHE_TIME);
        
        if (MUNDICAM_FILTERS_DEBUG) {
            error_log('🟢 [Mundicam Filters] Filtros generados y guardados en caché para categoría ' . $category_id . ' - ' . count($filters) . ' grupos');
        }
        
        return new WP_REST_Response([
            'success' => true,
            'data' => $filters,
            'category_id' => $category_id,
            'from_cache' => false,
            'timestamp' => time(),
        ], 200);
        
    } catch (Exception $e) {
        if (MUNDICAM_FILTERS_DEBUG) {
            error_log('🔴 [Mundicam Filters] Error: ' . $e->getMessage());
        }
        
        return new WP_REST_Response([
            'success' => false,
            'error' => $e->getMessage(),
            'code' => 'server_error'
        ], 500);
    }
}

// ================================================================
// 3. GENERAR CLAVE DE CACHÉ
// ================================================================

function mundicam_generate_cache_key($category_id, $search, $include_subcategories, $brand_id, $min_price, $max_price) {
    $parts = [
        'mundicam_filters',
        'cat_' . $category_id,
        'search_' . md5($search),
        'subcats_' . ($include_subcategories ? '1' : '0'),
        'brand_' . $brand_id,
        'minprice_' . round($min_price * 100),
        'maxprice_' . round($max_price * 100),
    ];
    
    return implode('_', $parts);
}

// ================================================================
// 3.1 HELPERS DE TAXONOMÍA PARA FILTROS APP
// ================================================================

function mundicam_filters_brand_taxonomies() {
    if (function_exists('mundicam_ctx_brand_taxonomies')) {
        return mundicam_ctx_brand_taxonomies();
    }
    return array('pa_marcas', 'product_brand', 'pa_marca', 'pa_fabricante', 'marca', 'brand');
}

function mundicam_filters_detect_brand_taxonomy() {
    foreach (mundicam_filters_brand_taxonomies() as $taxonomy) {
        if (!taxonomy_exists($taxonomy)) {
            continue;
        }

        $terms = get_terms(array(
            'taxonomy' => $taxonomy,
            'hide_empty' => true,
            'number' => 1,
        ));

        if (!is_wp_error($terms) && !empty($terms)) {
            return $taxonomy;
        }
    }

    foreach (mundicam_filters_brand_taxonomies() as $taxonomy) {
        if (taxonomy_exists($taxonomy)) {
            return $taxonomy;
        }
    }

    return 'pa_marcas';
}

function mundicam_filters_build_brand_tax_query($brand_id) {
    $brand_id = absint($brand_id);
    if ($brand_id <= 0) {
        return array();
    }

    foreach (mundicam_filters_brand_taxonomies() as $taxonomy) {
        if (!taxonomy_exists($taxonomy)) {
            continue;
        }

        $term = get_term($brand_id, $taxonomy);
        if ($term && !is_wp_error($term)) {
            return array(
                'taxonomy' => $taxonomy,
                'field' => 'term_id',
                'terms' => array($brand_id),
                'operator' => 'IN',
            );
        }
    }

    return array();
}

// ================================================================
// 4. CONSTRUIR FILTROS DE CATEGORÍA
// ================================================================

function mundicam_build_category_filters($category_id, $search = '', $include_subcategories = false, $brand_id = 0, $min_price = 0, $max_price = 0) {
    
    // ============================================================
    // 4.1 DEFINIR ATRIBUTOS DE FILTRO
    // ============================================================
    
    $brand_taxonomy = mundicam_filters_detect_brand_taxonomy();

    $attribute_definitions = [
        [
            'key' => 'fabricante',
            'title' => 'Fabricante',
            'taxonomy' => $brand_taxonomy,
            'icon' => 'brand',
            'type' => 'checkbox'
        ],
        [
            'key' => 'resolucion',
            'title' => 'Resolución',
            'taxonomy' => 'pa_resolucion',
            'icon' => 'resolution',
            'type' => 'checkbox'
        ],
        [
            'key' => 'lente',
            'title' => 'Lente',
            'taxonomy' => 'pa_lente',
            'icon' => 'lens',
            'type' => 'checkbox'
        ],
        [
            'key' => 'proteccion',
            'title' => 'Protección',
            'taxonomy' => 'pa_proteccion',
            'icon' => 'shield',
            'type' => 'checkbox'
        ],
        [
            'key' => 'microfono',
            'title' => 'Micrófono Integrado',
            'taxonomy' => 'pa_microfono-integrado',
            'icon' => 'microphone',
            'type' => 'checkbox'
        ],
        [
            'key' => 'wifi',
            'title' => 'WIFI',
            'taxonomy' => 'pa_wifi',
            'icon' => 'wifi',
            'type' => 'checkbox'
        ],
        [
            'key' => 'ancho_banda',
            'title' => 'Ancho de Banda',
            'taxonomy' => 'pa_ancho-de-banda',
            'icon' => 'speed',
            'type' => 'checkbox'
        ],
        [
            'key' => 'grabacion_main_stream',
            'title' => 'Grabación Main Stream',
            'taxonomy' => 'pa_grabacion-main-stream',
            'icon' => 'recording',
            'type' => 'checkbox'
        ],
        [
            'key' => 'protocolo',
            'title' => 'Protocolo',
            'taxonomy' => 'pa_protocolo',
            'icon' => 'protocol',
            'type' => 'checkbox'
        ],
        [
            'key' => 'smd',
            'title' => 'SMD+',
            'taxonomy' => 'pa_smd',
            'icon' => 'smd',
            'type' => 'checkbox'
        ],
        [
            'key' => 'tamano',
            'title' => 'Tamaño',
            'taxonomy' => 'pa_tamano',
            'icon' => 'size',
            'type' => 'checkbox'
        ],
        [
            'key' => 'color',
            'title' => 'Color',
            'taxonomy' => 'pa_color',
            'icon' => 'color',
            'type' => 'checkbox'
        ],
        [
            'key' => 'instalacion',
            'title' => 'Tipo de Instalación',
            'taxonomy' => 'pa_instalacion',
            'icon' => 'installation',
            'type' => 'checkbox'
        ],
        [
            'key' => 'vision_nocturna',
            'title' => 'Visión Nocturna',
            'taxonomy' => 'pa_vision-nocturna',
            'icon' => 'night',
            'type' => 'checkbox'
        ],
        [
            'key' => 'audio',
            'title' => 'Audio',
            'taxonomy' => 'pa_audio',
            'icon' => 'audio',
            'type' => 'checkbox'
        ],
        [
            'key' => 'poe',
            'title' => 'PoE',
            'taxonomy' => 'pa_poe',
            'icon' => 'poe',
            'type' => 'checkbox'
        ]
    ];
    
    // ============================================================
    // 4.2 OBTENER IDs DE PRODUCTOS DE LA CATEGORÍA
    // ============================================================
    
    $tax_query = [
        [
            'taxonomy' => 'product_cat',
            'field' => 'term_id',
            'terms' => [$category_id],
            'operator' => 'IN',
            'include_children' => (bool) $include_subcategories,
        ]
    ];
    
    $args = [
        'post_type' => 'product',
        'posts_per_page' => -1,
        'fields' => 'ids',
        'tax_query' => $tax_query,
        'post_status' => 'publish'
    ];
    
    // Búsqueda
    if (!empty($search)) {
        $args['s'] = $search;
    }
    
    // Filtro por marca usando la misma taxonomía real que WooCommerce/Perfect Brands/atributos.
    if ($brand_id > 0) {
        $brand_filter = mundicam_filters_build_brand_tax_query($brand_id);
        if (!empty($brand_filter)) {
            $args['tax_query'][] = $brand_filter;
        }
    }
    
    // Filtro por precio
    if ($min_price > 0 || $max_price > 0) {
        $meta_query = [];
        
        if ($min_price > 0) {
            $meta_query[] = [
                'key' => '_price',
                'value' => $min_price,
                'type' => 'NUMERIC',
                'compare' => '>='
            ];
        }
        
        if ($max_price > 0) {
            $meta_query[] = [
                'key' => '_price',
                'value' => $max_price,
                'type' => 'NUMERIC',
                'compare' => '<='
            ];
        }
        
        if (!empty($meta_query)) {
            $args['meta_query'] = $meta_query;
        }
    }
    
    $product_ids = get_posts($args);
    
    // Si no hay productos, retornar array vacío con metadatos
    if (empty($product_ids)) {
        if (MUNDICAM_FILTERS_DEBUG) {
            error_log('⚠️ [Mundicam Filters] No se encontraron productos para la categoría ' . $category_id);
        }
        
        return [
            'total_products' => 0,
            'filters' => [],
            'applied_filters' => [
                'category' => $category_id,
                'search' => $search,
                'brand' => $brand_id,
                'min_price' => $min_price,
                'max_price' => $max_price
            ]
        ];
    }
    
    // ============================================================
    // 4.3 OBTENER INFORMACIÓN DE LA CATEGORÍA
    // ============================================================
    
    $category = get_term($category_id, 'product_cat');
    $category_name = !is_wp_error($category) ? $category->name : '';
    $category_slug = !is_wp_error($category) ? $category->slug : '';
    
    // ============================================================
    // 4.4 CONSTRUIR FILTROS POR ATRIBUTO
    // ============================================================
    
    $filters = [];
    $total_products = count($product_ids);
    
    foreach ($attribute_definitions as $attr_def) {
        
        // Obtener todos los términos de este atributo
        $terms = get_terms([
            'taxonomy' => $attr_def['taxonomy'],
            'hide_empty' => false,
            'orderby' => 'name',
            'order' => 'ASC'
        ]);
        
        if (is_wp_error($terms) || empty($terms)) {
            continue;
        }
        
        $options = [];
        $total_options = 0;
        
        foreach ($terms as $term) {
            // Obtener productos que tienen este término
            $products_with_term = get_objects_in_term($term->term_id, $attr_def['taxonomy']);
            
            if (empty($products_with_term)) {
                continue;
            }
            
            // Contar cuántos productos de esta categoría tienen este término
            $count = count(array_intersect($product_ids, $products_with_term));
            
            if ($count > 0) {
                $options[] = [
                    'id' => $term->term_id,
                    'name' => $term->name,
                    'slug' => $term->slug,
                    'count' => $count,
                    'percentage' => round(($count / $total_products) * 100, 1),
                    'description' => $term->description ?? '',
                    'parent' => $term->parent ?? 0
                ];
                $total_options++;
            }
        }
        
        // Si hay opciones, agregar el grupo de filtros
        if (!empty($options)) {
            $filters[] = [
                'key' => $attr_def['key'],
                'title' => $attr_def['title'],
                'taxonomy' => $attr_def['taxonomy'],
                'icon' => $attr_def['icon'] ?? 'default',
                'type' => $attr_def['type'] ?? 'checkbox',
                'total_options' => $total_options,
                'options' => $options,
            ];
        }
    }
    
    // ============================================================
    // 4.5 FILTROS ADICIONALES (Rango de precios)
    // ============================================================
    
    // Obtener rango de precios de los productos
    $price_range = mundicam_get_price_range($product_ids);
    
    // ============================================================
    // 4.6 FILTRO DE STOCK
    // ============================================================
    
    $stock_filter = mundicam_get_stock_filter($product_ids);
    
    // ============================================================
    // 4.7 CONSTRUIR RESPUESTA COMPLETA
    // ============================================================
    
    $response = [
        'total_products' => $total_products,
        'category_info' => [
            'id' => $category_id,
            'name' => $category_name,
            'slug' => $category_slug,
        ],
        'applied_filters' => [
            'category' => $category_id,
            'search' => $search,
            'include_subcategories' => $include_subcategories,
            'brand_id' => $brand_id,
            'min_price' => $min_price,
            'max_price' => $max_price
        ],
        'price_range' => $price_range,
        'stock_filter' => $stock_filter,
        'filters' => $filters,
        'meta' => [
            'total_filter_groups' => count($filters),
            'total_filter_options' => array_sum(array_column($filters, 'total_options')),
            'timestamp' => time(),
            'cache_time' => MUNDICAM_FILTERS_CACHE_TIME
        ]
    ];
    
    if (MUNDICAM_FILTERS_DEBUG) {
        error_log('📊 [Mundicam Filters] Categoría ' . $category_id . 
                  ' - ' . $total_products . ' productos, ' . 
                  count($filters) . ' grupos de filtros');
    }
    
    return $response;
}

// ================================================================
// 5. FUNCIÓN AUXILIAR: OBTENER RANGO DE PRECIOS
// ================================================================

function mundicam_get_price_range($product_ids) {
    if (empty($product_ids)) {
        return [
            'min' => 0,
            'max' => 0,
            'avg' => 0,
            'currency' => 'EUR'
        ];
    }
    
    $prices = [];
    
    foreach ($product_ids as $product_id) {
        $product = wc_get_product($product_id);
        if (!$product) continue;
        
        $price = null;
        if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'app_product_price_number')) {
            $price = Mundicam_App_API::app_product_price_number($product);
        }
        if ($price === null || !is_numeric($price)) {
            $price = floatval($product->get_price());
        }
        if ($price > 0) {
            $prices[] = (float) $price;
        }
    }
    
    if (empty($prices)) {
        return [
            'min' => 0,
            'max' => 0,
            'avg' => 0,
            'currency' => 'EUR'
        ];
    }
    
    sort($prices);
    
    return [
        'min' => round($prices[0], 2),
        'max' => round(end($prices), 2),
        'avg' => round(array_sum($prices) / count($prices), 2),
        'currency' => get_woocommerce_currency(),
        'count' => count($prices)
    ];
}

// ================================================================
// 6. FUNCIÓN AUXILIAR: FILTRO DE STOCK
// ================================================================

function mundicam_get_stock_filter($product_ids) {
    if (empty($product_ids)) {
        return [
            'in_stock' => 0,
            'out_of_stock' => 0,
            'on_backorder' => 0
        ];
    }
    
    $in_stock = 0;
    $out_of_stock = 0;
    $on_backorder = 0;
    
    foreach ($product_ids as $product_id) {
        $product = wc_get_product($product_id);
        if (!$product) continue;
        
        $stock_status = (string) $product->get_stock_status();
        if ($stock_status === 'instock') {
            $in_stock++;
        } elseif ($stock_status === 'onbackorder') {
            $on_backorder++;
        } else {
            $out_of_stock++;
        }
    }
    
    return [
        'in_stock' => $in_stock,
        'out_of_stock' => $out_of_stock,
        'on_backorder' => $on_backorder,
        'total' => $in_stock + $out_of_stock + $on_backorder,
        'in_stock_percentage' => $in_stock > 0 ? round(($in_stock / ($in_stock + $out_of_stock + $on_backorder)) * 100, 1) : 0
    ];
}

// ================================================================
// 7. ENDPOINT PARA LIMPIAR CACHÉ (ADMIN)
// ================================================================

add_action('rest_api_init', function () {
    register_rest_route('mundicam/v1', '/clear-filters-cache', [
        'methods' => 'POST',
        'callback' => 'mundicam_clear_filters_cache',
        'permission_callback' => function() {
            return current_user_can('manage_options');
        }
    ]);
});

function mundicam_clear_filters_cache() {
    global $wpdb;
    
    // Eliminar todos los transients de filtros
    $count = $wpdb->query("
        DELETE FROM {$wpdb->options} 
        WHERE option_name LIKE '_transient_mundicam_filters_%' 
        OR option_name LIKE '_transient_timeout_mundicam_filters_%'
    ");
    
    return new WP_REST_Response([
        'success' => true,
        'message' => 'Caché de filtros limpiado',
        'deleted_count' => $count
    ], 200);
}

// ================================================================
// 8. ENDPOINT PARA OBTENER CATEGORÍAS CON FILTROS (BULK)
// ================================================================

add_action('rest_api_init', function () {
    register_rest_route('mundicam/v1', '/categories-filters', [
        'methods' => 'GET',
        'callback' => 'mundicam_get_categories_filters',
        'permission_callback' => 'mundicam_filters_permission_app_user',
        'args' => [
            'category_ids' => [
                'required' => true,
                'validate_callback' => function($param) {
                    $ids = explode(',', $param);
                    foreach ($ids as $id) {
                        if (!is_numeric($id) || $id <= 0) {
                            return false;
                        }
                    }
                    return true;
                }
            ]
        ]
    ]);
});

function mundicam_get_categories_filters($request) {
    $category_ids = array_map('intval', explode(',', $request->get_param('category_ids')));
    $results = [];
    
    foreach ($category_ids as $cat_id) {
        try {
            $filters = mundicam_build_category_filters($cat_id, '', false, 0, 0, 0);
            $results[] = [
                'category_id' => $cat_id,
                'success' => true,
                'data' => $filters
            ];
        } catch (Exception $e) {
            $results[] = [
                'category_id' => $cat_id,
                'success' => false,
                'error' => $e->getMessage()
            ];
        }
    }
    
    return new WP_REST_Response([
        'success' => true,
        'results' => $results
    ], 200);
}

// ================================================================
// 9. FIN DEL ARCHIVO
// ================================================================

// =============================================================
// BÚSQUEDA CONTEXTUAL / SKU MUNDICAM - INTEGRADO
// =============================================================
/**
 * Plugin Name: MundiCam Context Search Endpoint
 * Description: Endpoint independiente para búsqueda contextual de productos MundiCam: SKU exacto, variantes de referencia, términos técnicos, categorías y atributos relacionados. Unificado con el payload de precios por rol efectivo del plugin principal en v1.6.0.
 * Version: 1.0.4
 * Author: MundiCam
 */

if (!defined('ABSPATH')) {
    exit;
}

function mundicam_ctx_permission_app_user(WP_REST_Request $request) {
    if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'permission_app_user')) {
        return Mundicam_App_API::permission_app_user($request);
    }

    return new WP_Error('mundicam_app_unauthorized', 'Sesión de app no válida. Vuelve a iniciar sesión.', ['status' => 401]);
}

add_action('rest_api_init', function () {
    $args = array(
        'methods'             => WP_REST_Server::READABLE,
        'callback'            => 'mundicam_ctx_search_handle_request',
        'permission_callback' => 'mundicam_ctx_permission_app_user',
        'args'                => array(
            'search' => array(
                'required'          => false,
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'sku' => array(
                'required'          => false,
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'category_id' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
            ),
            'category' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
            ),
            'brand_id' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
            ),
            'brand' => array(
                'required'          => false,
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'orderby' => array(
                'required'          => false,
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'order' => array(
                'required'          => false,
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'attribute_terms' => array(
                'required'          => false,
            ),
            'page' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
                'default'           => 1,
            ),
            'per_page' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
                'default'           => 30,
            ),
            'debug' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
                'default'           => 0,
            ),
        ),
    );

    // Endpoint principal independiente. No pisa /products ni /catalog-filters.
    register_rest_route('mundicam/v1', '/context-search', $args);

    // Alias para Flutter si se prefiere mantener namespace de la app.
    register_rest_route('mundicam-app/v1', '/context-search', $args);

    // Endpoint específico para SKU; reutiliza la misma lógica.
    register_rest_route('mundicam/v1', '/sku-search', array(
        'methods'             => WP_REST_Server::READABLE,
        'callback'            => 'mundicam_ctx_search_handle_sku_request',
        'permission_callback' => 'mundicam_ctx_permission_app_user',
        'args'                => array(
            'sku' => array(
                'required'          => true,
                'sanitize_callback' => 'sanitize_text_field',
            ),
            'page' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
                'default'           => 1,
            ),
            'per_page' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
                'default'           => 30,
            ),
            'debug' => array(
                'required'          => false,
                'sanitize_callback' => 'absint',
                'default'           => 0,
            ),
        ),
    ));
});

function mundicam_ctx_search_handle_sku_request(WP_REST_Request $request) {
    $request->set_param('search', $request->get_param('sku'));
    return mundicam_ctx_search_handle_request($request);
}

function mundicam_ctx_search_handle_request(WP_REST_Request $request) {
    if (!function_exists('wc_get_product')) {
        return new WP_REST_Response(array(
            'success' => false,
            'message' => 'WooCommerce no está disponible.',
            'products' => array(),
            'data' => array(),
            'items' => array(),
        ), 500);
    }

    $raw_search = trim((string) ($request->get_param('search') ?: $request->get_param('sku') ?: ''));
    $page       = max(1, absint($request->get_param('page') ?: 1));
    $per_page   = min(100, max(1, absint($request->get_param('per_page') ?: 30)));
    $category_id = absint($request->get_param('category_id') ?: $request->get_param('category') ?: 0);

    // Si la búsqueda parece una referencia/SKU, buscamos globalmente.
    // Un SKU puede existir fuera de la familia desde la que se escribió.
    if (mundicam_ctx_looks_like_sku($raw_search)) {
        $category_id = 0;
    }

    $brand_id    = absint($request->get_param('brand_id') ?: 0);
    $brand_name  = sanitize_text_field((string) ($request->get_param('brand') ?: ''));
    $orderby     = sanitize_key((string) ($request->get_param('orderby') ?: ''));
    $order       = strtoupper(sanitize_text_field((string) ($request->get_param('order') ?: '')));
    $attribute_terms = mundicam_ctx_decode_attribute_terms($request->get_param('attribute_terms'));
    $debug      = absint($request->get_param('debug') ?: 0) === 1;

    if ($raw_search === '') {
        return new WP_REST_Response(array(
            'success' => true,
            'products' => array(),
            'data' => array(),
            'items' => array(),
            'page' => $page,
            'per_page' => $per_page,
            'total' => 0,
            'total_pages' => 1,
            'context' => array(
                'query' => '',
                'mode' => 'empty_query',
            ),
        ), 200);
    }

    $normalized_query = mundicam_ctx_normalize_text($raw_search);
    $tokens           = mundicam_ctx_query_tokens($raw_search);
    $sku_variants     = mundicam_ctx_sku_variants($raw_search);
    $expanded_terms   = mundicam_ctx_expand_context_terms($raw_search, $tokens);
    $search_terms     = mundicam_ctx_build_search_terms($raw_search, $tokens, $expanded_terms, $sku_variants);

    $scores  = array();
    $reasons = array();
    $matched_categories = array();
    $matched_terms = array();

    // 1) SKU exacto y variantes.
    foreach ($sku_variants as $variant) {
        mundicam_ctx_add_sku_matches($scores, $reasons, $variant, $category_id);
    }

    // 2) Búsqueda por frase/términos en productos.
    foreach ($search_terms as $index => $term) {
        $weight = ($index === 0) ? 950 : 520;
        mundicam_ctx_add_product_search_matches($scores, $reasons, $term, $weight, $category_id);
    }

    // 3) Categorías y taxonomías/atributos relacionados.
    $tax_terms = array_unique(array_merge($search_terms, $expanded_terms, $tokens));
    foreach ($tax_terms as $term) {
        mundicam_ctx_add_taxonomy_context_matches(
            $scores,
            $reasons,
            $matched_categories,
            $matched_terms,
            $term,
            $category_id
        );
    }

    // 4) Si hay pocos candidatos, ampliar con tokens fuertes.
    if (count($scores) < 12) {
        foreach ($tokens as $token) {
            if (mundicam_ctx_is_generic_token($token, count($tokens))) {
                continue;
            }
            mundicam_ctx_add_product_search_matches($scores, $reasons, $token, 260, $category_id);
        }
    }

    $products_scored = array();

    foreach ($scores as $product_id => $base_score) {
        $product = wc_get_product($product_id);
        if (!$product) {
            continue;
        }

        $parent_id = 0;
        if ($product->is_type('variation')) {
            $parent_id = $product->get_parent_id();
            if ($parent_id > 0) {
                $parent = wc_get_product($parent_id);
                if ($parent) {
                    $product = $parent;
                    $product_id = $parent_id;
                }
            }
        }

        if (isset($products_scored[$product_id])) {
            continue;
        }

        if (!mundicam_ctx_product_is_visible($product)) {
            continue;
        }

        if ($category_id > 0 && !mundicam_ctx_product_in_category($product->get_id(), $category_id)) {
            continue;
        }

        if (!mundicam_ctx_product_matches_brand($product, $brand_id, $brand_name)) {
            continue;
        }

        if (!mundicam_ctx_product_matches_attribute_terms($product, $attribute_terms)) {
            continue;
        }

        $semantic_score = mundicam_ctx_score_product($product, $raw_search, $normalized_query, $tokens, $expanded_terms, $sku_variants);
        $final_score = (int) $base_score + (int) $semantic_score;

        if ($final_score <= 0) {
            continue;
        }

        $products_scored[$product_id] = array(
            'product' => $product,
            'score'   => $final_score,
            'reasons' => isset($reasons[$product_id]) ? array_values(array_unique($reasons[$product_id])) : array(),
        );
    }

    mundicam_ctx_sort_scored_products($products_scored, $orderby, $order);

    $total = count($products_scored);
    $total_pages = max(1, (int) ceil($total / $per_page));
    $offset = ($page - 1) * $per_page;
    $slice = array_slice($products_scored, $offset, $per_page, true);

    $items = array();
    foreach ($slice as $entry) {
        $items[] = mundicam_ctx_product_to_app_array(
            $entry['product'],
            $debug ? $entry['score'] : null,
            $debug ? $entry['reasons'] : null
        );
    }

    $response = array(
        'success' => true,
        'products' => $items,
        'data' => $items,
        'items' => $items,
        'page' => $page,
        'per_page' => $per_page,
        'total' => $total,
        'total_pages' => $total_pages,
        'context' => array(
            'query' => $raw_search,
            'normalized_query' => $normalized_query,
            'tokens' => array_values($tokens),
            'sku_variants' => array_values($sku_variants),
            'expanded_terms' => array_values($expanded_terms),
            'search_terms' => array_values($search_terms),
            'matched_categories' => array_values($matched_categories),
            'matched_attribute_terms' => array_values($matched_terms),
            'category_id' => $category_id,
            'brand_id' => $brand_id,
            'brand' => $brand_name,
            'orderby' => $orderby,
            'order' => $order,
            'attribute_terms' => $attribute_terms,
            'mode' => 'contextual_sku_web_like_v103',
        ),
    );

    return new WP_REST_Response($response, 200);
}

function mundicam_ctx_decode_attribute_terms($raw) {
    if (empty($raw)) {
        return array();
    }

    if (is_array($raw)) {
        $data = $raw;
    } else {
        $decoded = json_decode(wp_unslash((string) $raw), true);
        $data = is_array($decoded) ? $decoded : array();
    }

    $result = array();
    foreach ($data as $taxonomy => $term_ids) {
        $taxonomy = sanitize_key((string) $taxonomy);
        if ($taxonomy === '' || !taxonomy_exists($taxonomy)) {
            continue;
        }
        if (!is_array($term_ids)) {
            $term_ids = array($term_ids);
        }
        $term_ids = array_values(array_unique(array_filter(array_map('absint', $term_ids))));
        if (!empty($term_ids)) {
            $result[$taxonomy] = $term_ids;
        }
    }

    return $result;
}

function mundicam_ctx_brand_taxonomies() {
    return array('pa_marcas', 'product_brand', 'pa_marca', 'pa_fabricante', 'marca', 'brand');
}

function mundicam_ctx_normalize_cmp($value) {
    $value = remove_accents(strtolower(trim((string) $value)));
    $value = preg_replace('/[^a-z0-9]+/', '', $value);
    return $value ?: '';
}

function mundicam_ctx_product_matches_brand($product, $brand_id = 0, $brand_name = '') {
    $brand_id = absint($brand_id);
    $brand_name = trim((string) $brand_name);

    if ($brand_id <= 0 && $brand_name === '') {
        return true;
    }

    $product_id = $product instanceof WC_Product ? $product->get_id() : absint($product);
    if ($product_id <= 0) {
        return false;
    }

    foreach (mundicam_ctx_brand_taxonomies() as $taxonomy) {
        if (!taxonomy_exists($taxonomy)) {
            continue;
        }

        if ($brand_id > 0 && has_term($brand_id, $taxonomy, $product_id)) {
            return true;
        }

        if ($brand_name !== '') {
            $terms = wp_get_post_terms($product_id, $taxonomy);
            if (is_wp_error($terms) || empty($terms)) {
                continue;
            }
            foreach ($terms as $term) {
                if (mundicam_ctx_normalize_cmp($term->name) === mundicam_ctx_normalize_cmp($brand_name) ||
                    mundicam_ctx_normalize_cmp($term->slug) === mundicam_ctx_normalize_cmp($brand_name)) {
                    return true;
                }
            }
        }
    }

    return false;
}

function mundicam_ctx_product_matches_attribute_terms($product, $attribute_terms) {
    if (empty($attribute_terms) || !is_array($attribute_terms)) {
        return true;
    }

    $product_id = $product instanceof WC_Product ? $product->get_id() : absint($product);
    if ($product_id <= 0) {
        return false;
    }

    foreach ($attribute_terms as $taxonomy => $term_ids) {
        $taxonomy = sanitize_key((string) $taxonomy);
        if ($taxonomy === '' || !taxonomy_exists($taxonomy)) {
            continue;
        }
        if (!is_array($term_ids)) {
            $term_ids = array($term_ids);
        }
        $term_ids = array_values(array_unique(array_filter(array_map('absint', $term_ids))));
        if (empty($term_ids)) {
            continue;
        }
        if (!has_term($term_ids, $taxonomy, $product_id)) {
            return false;
        }
    }

    return true;
}

function mundicam_ctx_product_price_number($product) {
    if (!($product instanceof WC_Product)) {
        return null;
    }
    if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'app_product_price_number')) {
        return Mundicam_App_API::app_product_price_number($product);
    }
    $price = $product->get_price();
    if ($price === '' || $price === null || !is_numeric($price)) {
        return null;
    }
    return (float) $price;
}

function mundicam_ctx_sort_scored_products(&$products_scored, $orderby = '', $order = '') {
    $orderby = sanitize_key((string) $orderby);
    $order = strtoupper(sanitize_text_field((string) $order));

    uasort($products_scored, function ($a, $b) use ($orderby, $order) {
        $pa = isset($a['product']) ? $a['product'] : null;
        $pb = isset($b['product']) ? $b['product'] : null;

        if ($orderby === 'price_asc' || ($orderby === 'price' && $order === 'ASC')) {
            $price_a = mundicam_ctx_product_price_number($pa);
            $price_b = mundicam_ctx_product_price_number($pb);
            $has_a = $price_a !== null && $price_a > 0;
            $has_b = $price_b !== null && $price_b > 0;
            if ($has_a !== $has_b) return $has_a ? -1 : 1;
            if ($has_a && $has_b) {
                $cmp = $price_a <=> $price_b;
                if ($cmp !== 0) return $cmp;
            }
            return ($pb instanceof WC_Product ? $pb->get_id() : 0) <=> ($pa instanceof WC_Product ? $pa->get_id() : 0);
        }

        if ($orderby === 'price_desc' || ($orderby === 'price' && $order === 'DESC')) {
            $price_a = mundicam_ctx_product_price_number($pa);
            $price_b = mundicam_ctx_product_price_number($pb);
            $has_a = $price_a !== null && $price_a > 0;
            $has_b = $price_b !== null && $price_b > 0;
            if ($has_a !== $has_b) return $has_a ? -1 : 1;
            if ($has_a && $has_b) {
                $cmp = $price_b <=> $price_a;
                if ($cmp !== 0) return $cmp;
            }
            return ($pb instanceof WC_Product ? $pb->get_id() : 0) <=> ($pa instanceof WC_Product ? $pa->get_id() : 0);
        }

        if ($orderby === 'date' || $orderby === 'recent' || $orderby === 'newest') {
            $da = $pa instanceof WC_Product && $pa->get_date_created() ? $pa->get_date_created()->getTimestamp() : 0;
            $db = $pb instanceof WC_Product && $pb->get_date_created() ? $pb->get_date_created()->getTimestamp() : 0;
            if ($da !== $db) return $db <=> $da;
        }

        if ($a['score'] === $b['score']) {
            $a_name = $pa instanceof WC_Product ? $pa->get_name() : '';
            $b_name = $pb instanceof WC_Product ? $pb->get_name() : '';
            return strcasecmp($a_name, $b_name);
        }
        return $b['score'] <=> $a['score'];
    });
}

function mundicam_ctx_add_score(&$scores, &$reasons, $product_id, $score, $reason) {
    $product_id = absint($product_id);
    if ($product_id <= 0) {
        return;
    }

    if (!isset($scores[$product_id])) {
        $scores[$product_id] = 0;
        $reasons[$product_id] = array();
    }

    $scores[$product_id] += (int) $score;
    if ($reason) {
        $reasons[$product_id][] = $reason;
    }
}

function mundicam_ctx_add_sku_matches(&$scores, &$reasons, $sku, $category_id = 0) {
    $sku = trim((string) $sku);
    if ($sku === '') {
        return;
    }

    $exact_id = wc_get_product_id_by_sku($sku);
    if ($exact_id) {
        if ($category_id <= 0 || mundicam_ctx_product_in_category($exact_id, $category_id)) {
            mundicam_ctx_add_score($scores, $reasons, $exact_id, 12000, 'sku_exact:' . $sku);
        }
    }

    $meta_query = new WP_Query(array(
        'post_type'      => array('product', 'product_variation'),
        'post_status'    => array('publish'),
        'posts_per_page' => 50,
        'fields'         => 'ids',
        'no_found_rows'  => true,
        'meta_query'     => array(
            array(
                'key'     => '_sku',
                'value'   => $sku,
                'compare' => 'LIKE',
            ),
        ),
    ));

    if (!empty($meta_query->posts)) {
        foreach ($meta_query->posts as $id) {
            $product = wc_get_product($id);
            if (!$product) {
                continue;
            }
            $target_id = $product->is_type('variation') && $product->get_parent_id() ? $product->get_parent_id() : $id;
            if ($category_id > 0 && !mundicam_ctx_product_in_category($target_id, $category_id)) {
                continue;
            }
            mundicam_ctx_add_score($scores, $reasons, $target_id, 8500, 'sku_like:' . $sku);
        }
    }

    wp_reset_postdata();
}

function mundicam_ctx_add_product_search_matches(&$scores, &$reasons, $term, $weight, $category_id = 0) {
    $term = trim((string) $term);
    if ($term === '' || mb_strlen($term) < 2) {
        return;
    }

    $args = array(
        'post_type'      => 'product',
        'post_status'    => 'publish',
        'posts_per_page' => 120,
        'fields'         => 'ids',
        'no_found_rows'  => true,
        's'              => $term,
    );

    if ($category_id > 0) {
        $args['tax_query'] = array(
            array(
                'taxonomy'         => 'product_cat',
                'field'            => 'term_id',
                'terms'            => array($category_id),
                'include_children' => true,
            ),
        );
    }

    $query = new WP_Query($args);

    if (!empty($query->posts)) {
        foreach ($query->posts as $id) {
            mundicam_ctx_add_score($scores, $reasons, $id, $weight, 'text_search:' . $term);
        }
    }

    wp_reset_postdata();
}

function mundicam_ctx_add_taxonomy_context_matches(&$scores, &$reasons, &$matched_categories, &$matched_terms, $term, $category_id = 0) {
    $term = trim((string) $term);
    if ($term === '' || mb_strlen($term) < 3) {
        return;
    }

    $taxonomies = mundicam_ctx_searchable_taxonomies();

    foreach ($taxonomies as $taxonomy) {
        if (!taxonomy_exists($taxonomy)) {
            continue;
        }

        $found_terms = get_terms(array(
            'taxonomy'   => $taxonomy,
            'hide_empty' => true,
            'search'     => $term,
            'number'     => 20,
        ));

        if (is_wp_error($found_terms) || empty($found_terms)) {
            continue;
        }

        foreach ($found_terms as $found_term) {
            $term_label = $taxonomy . ':' . $found_term->name;
            if ($taxonomy === 'product_cat') {
                $matched_categories[] = array(
                    'id' => (int) $found_term->term_id,
                    'name' => $found_term->name,
                    'slug' => $found_term->slug,
                );
            } else {
                $matched_terms[] = array(
                    'taxonomy' => $taxonomy,
                    'id' => (int) $found_term->term_id,
                    'name' => $found_term->name,
                    'slug' => $found_term->slug,
                );
            }

            $tax_query = array(
                array(
                    'taxonomy'         => $taxonomy,
                    'field'            => 'term_id',
                    'terms'            => array((int) $found_term->term_id),
                    'include_children' => $taxonomy === 'product_cat',
                ),
            );

            if ($category_id > 0 && $taxonomy !== 'product_cat') {
                $tax_query[] = array(
                    'taxonomy'         => 'product_cat',
                    'field'            => 'term_id',
                    'terms'            => array($category_id),
                    'include_children' => true,
                );
            }

            $query = new WP_Query(array(
                'post_type'      => 'product',
                'post_status'    => 'publish',
                'posts_per_page' => 100,
                'fields'         => 'ids',
                'no_found_rows'  => true,
                'tax_query'      => $tax_query,
            ));

            if (!empty($query->posts)) {
                $weight = $taxonomy === 'product_cat' ? 1100 : 720;
                foreach ($query->posts as $id) {
                    mundicam_ctx_add_score($scores, $reasons, $id, $weight, 'taxonomy:' . $term_label);
                }
            }

            wp_reset_postdata();
        }
    }
}

function mundicam_ctx_searchable_taxonomies() {
    $taxonomies = array('product_cat', 'product_tag');

    foreach (array('product_brand', 'pwb-brand', 'yith_product_brand') as $brand_taxonomy) {
        if (taxonomy_exists($brand_taxonomy)) {
            $taxonomies[] = $brand_taxonomy;
        }
    }

    if (function_exists('wc_get_attribute_taxonomies')) {
        $attributes = wc_get_attribute_taxonomies();
        if (!empty($attributes)) {
            foreach ($attributes as $attribute) {
                if (!empty($attribute->attribute_name)) {
                    $taxonomies[] = wc_attribute_taxonomy_name($attribute->attribute_name);
                }
            }
        }
    }

    return array_values(array_unique(array_filter($taxonomies)));
}

function mundicam_ctx_product_is_visible($product) {
    if (!$product || !is_a($product, 'WC_Product')) {
        return false;
    }

    $status = get_post_status($product->get_id());
    if ($status !== 'publish') {
        return false;
    }

    $visibility = $product->get_catalog_visibility();
    return $visibility !== 'hidden';
}

function mundicam_ctx_product_in_category($product_id, $category_id) {
    $product_id = absint($product_id);
    $category_id = absint($category_id);

    if ($product_id <= 0 || $category_id <= 0) {
        return true;
    }

    $terms = get_the_terms($product_id, 'product_cat');
    if (is_wp_error($terms) || empty($terms)) {
        return false;
    }

    foreach ($terms as $term) {
        if ((int) $term->term_id === $category_id) {
            return true;
        }

        $ancestors = get_ancestors((int) $term->term_id, 'product_cat');
        if (in_array($category_id, array_map('intval', $ancestors), true)) {
            return true;
        }
    }

    return false;
}

function mundicam_ctx_score_product($product, $raw_query, $normalized_query, $tokens, $expanded_terms, $sku_variants) {
    $name = mundicam_ctx_normalize_text($product->get_name());
    $sku  = mundicam_ctx_normalize_text($product->get_sku());
    $text = mundicam_ctx_product_search_text($product);

    $score = 0;

    foreach ($sku_variants as $variant) {
        $norm_variant = mundicam_ctx_normalize_text($variant);
        if ($norm_variant !== '' && $sku !== '') {
            if ($sku === $norm_variant) {
                $score += 15000;
            } elseif (strpos($sku, $norm_variant) !== false || strpos($norm_variant, $sku) !== false) {
                $score += 9000;
            }
        }
    }

    if ($normalized_query !== '') {
        if ($name === $normalized_query) {
            $score += 2800;
        } elseif (strpos($name, $normalized_query) === 0) {
            $score += 2300;
        } elseif (strpos($name, $normalized_query) !== false) {
            $score += 1800;
        }

        if ($sku === $normalized_query) {
            $score += 12000;
        } elseif ($sku !== '' && strpos($sku, $normalized_query) !== false) {
            $score += 6500;
        }
    }

    foreach ($tokens as $token) {
        $token = mundicam_ctx_normalize_text($token);
        if ($token === '' || mb_strlen($token) < 2) {
            continue;
        }

        if (strpos($sku, $token) !== false) {
            $score += 900;
        }
        if (strpos($name, $token) !== false) {
            $score += 520;
        }
        if (strpos($text, $token) !== false) {
            $score += 180;
        }
    }

    foreach ($expanded_terms as $term) {
        $term = mundicam_ctx_normalize_text($term);
        if ($term === '' || mb_strlen($term) < 3) {
            continue;
        }
        if (strpos($name, $term) !== false) {
            $score += 310;
        } elseif (strpos($text, $term) !== false) {
            $score += 120;
        }
    }

    $stock_status_for_score = (string) $product->get_stock_status();
    if (in_array($stock_status_for_score, array('instock', 'onbackorder'), true)) {
        $score += 15;
    }

    return $score;
}

function mundicam_ctx_product_search_text($product) {
    $parts = array(
        $product->get_name(),
        $product->get_sku(),
        wp_strip_all_tags($product->get_short_description()),
        wp_strip_all_tags($product->get_description()),
    );

    $cats = get_the_terms($product->get_id(), 'product_cat');
    if (!is_wp_error($cats) && !empty($cats)) {
        foreach ($cats as $cat) {
            $parts[] = $cat->name;
            $parts[] = $cat->slug;
        }
    }

    foreach ($product->get_attributes() as $attribute) {
        if (is_a($attribute, 'WC_Product_Attribute')) {
            $parts[] = $attribute->get_name();
            if ($attribute->is_taxonomy()) {
                $terms = wc_get_product_terms($product->get_id(), $attribute->get_name(), array('fields' => 'names'));
                if (!is_wp_error($terms)) {
                    $parts = array_merge($parts, $terms);
                }
            } else {
                $parts = array_merge($parts, $attribute->get_options());
            }
        }
    }

    return mundicam_ctx_normalize_text(implode(' ', array_filter($parts)));
}

function mundicam_ctx_product_to_app_array($product, $score = null, $reasons = null) {
    if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'app_product_payload')) {
        $can_view_stock = method_exists('Mundicam_App_API', 'app_current_user_can_view_internal_stock')
            ? Mundicam_App_API::app_current_user_can_view_internal_stock()
            : false;
        $data = Mundicam_App_API::app_product_payload($product, $can_view_stock);
        if ($score !== null) {
            $data['search_score'] = $score;
        }
        if ($reasons !== null) {
            $data['search_reasons'] = $reasons;
        }
        $data['query_engine'] = 'context_search_role_price_160';
        return $data;
    }

    $product_id = $product->get_id();

    $regular_price = $product->get_regular_price();
    $price = $product->get_price();

    if (($price === '' || $price === null || !is_numeric($price)) && $product->is_type('variable')) {
        $variation_price = $product->get_variation_price('min', true);
        if ($variation_price !== '' && $variation_price !== null && is_numeric($variation_price)) {
            $price = $variation_price;
        }
    }

    if (($price === '' || $price === null || !is_numeric($price))) {
        foreach (array('_price', '_sale_price', '_regular_price') as $meta_key) {
            $meta_price = get_post_meta($product_id, $meta_key, true);
            if ($meta_price !== '' && $meta_price !== null && is_numeric($meta_price)) {
                $price = $meta_price;
                break;
            }
        }
    }

    if (($regular_price === '' || $regular_price === null || !is_numeric($regular_price))) {
        $regular_price = $price;
    }

    $display_price = '';
    $display_regular = '';

    if ($price !== '' && $price !== null && is_numeric($price)) {
        $display_price = wc_get_price_to_display($product, array('price' => (float) $price));
    }

    if ($regular_price !== '' && $regular_price !== null && is_numeric($regular_price)) {
        $display_regular = wc_get_price_to_display($product, array('price' => (float) $regular_price));
    }

    $image_url = '';
    $image_full_url = '';
    $image_id = $product->get_image_id();
    if ($image_id) {
        $thumb = wp_get_attachment_image_src($image_id, 'woocommerce_thumbnail');
        $full = wp_get_attachment_image_src($image_id, 'full');
        if (is_array($thumb) && !empty($thumb[0])) {
            $image_url = $thumb[0];
        }
        if (is_array($full) && !empty($full[0])) {
            $image_full_url = $full[0];
        }
    }

    if ($image_url === '') {
        $gallery_ids = $product->get_gallery_image_ids();
        if (!empty($gallery_ids[0])) {
            $thumb = wp_get_attachment_image_src($gallery_ids[0], 'woocommerce_thumbnail');
            $full = wp_get_attachment_image_src($gallery_ids[0], 'full');
            if (is_array($thumb) && !empty($thumb[0])) {
                $image_url = $thumb[0];
            }
            if (is_array($full) && !empty($full[0])) {
                $image_full_url = $full[0];
            }
        }
    }

    if ($image_url === '') {
        $image_url = wc_placeholder_img_src('woocommerce_thumbnail');
    }
    if ($image_full_url === '') {
        $image_full_url = $image_url;
    }

    $categories = array();
    $cats = get_the_terms($product_id, 'product_cat');
    if (!is_wp_error($cats) && !empty($cats)) {
        foreach ($cats as $cat) {
            $categories[] = array(
                'id' => (int) $cat->term_id,
                'name' => html_entity_decode($cat->name, ENT_QUOTES, 'UTF-8'),
                'slug' => $cat->slug,
            );
        }
    }

    $attributes = array();
    foreach ($product->get_attributes() as $attribute) {
        if (!is_a($attribute, 'WC_Product_Attribute')) {
            continue;
        }

        $options = array();
        $attr_name = $attribute->get_name();
        $attr_label = wc_attribute_label($attr_name);

        if ($attribute->is_taxonomy()) {
            $term_names = wc_get_product_terms($product_id, $attr_name, array('fields' => 'names'));
            if (!is_wp_error($term_names)) {
                $options = array_values($term_names);
            }
        } else {
            $options = array_values(array_map('strval', $attribute->get_options()));
        }

        if (!empty($options)) {
            $attributes[] = array(
                'id' => $attribute->get_id(),
                'name' => $attr_label ?: $attr_name,
                'slug' => $attr_name,
                'options' => $options,
                'visible' => $attribute->get_visible(),
                'variation' => $attribute->get_variation(),
            );
        }
    }

    $brand_name = '';
    foreach (mundicam_ctx_brand_taxonomies() as $taxonomy) {
        if (!taxonomy_exists($taxonomy)) {
            continue;
        }
        $terms = wp_get_post_terms($product_id, $taxonomy);
        if (!is_wp_error($terms) && !empty($terms[0]) && $terms[0] instanceof WP_Term) {
            $brand_name = html_entity_decode($terms[0]->name, ENT_QUOTES, 'UTF-8');
            break;
        }
    }

    if ($brand_name === '') {
        foreach ($attributes as $attribute) {
            $name = isset($attribute['name']) ? mundicam_ctx_normalize_cmp($attribute['name']) : '';
            $slug = isset($attribute['slug']) ? mundicam_ctx_normalize_cmp($attribute['slug']) : '';
            if (strpos($name, 'marca') !== false || strpos($name, 'fabricante') !== false || strpos($name, 'brand') !== false || in_array($slug, array('pamarca', 'pamarcas', 'pafabricante'), true)) {
                if (!empty($attribute['options'][0])) {
                    $brand_name = (string) $attribute['options'][0];
                    break;
                }
            }
        }
    }

    $has_price = $display_price !== '' && is_numeric($display_price) && (float) $display_price > 0;
    $stock_status = (string) $product->get_stock_status();
    if (!in_array($stock_status, array('instock', 'outofstock', 'onbackorder'), true)) {
        $stock_status = 'outofstock';
    }
    $is_in_stock = in_array($stock_status, array('instock', 'onbackorder'), true);
    $can_add_to_cart = $product->is_purchasable() && $has_price && $is_in_stock;
    $formatted_price = $has_price ? wc_format_decimal($display_price, 2) : '0.00';
    $formatted_regular = $display_regular !== '' && is_numeric($display_regular) ? wc_format_decimal($display_regular, 2) : $formatted_price;

    $data = array(
        'id' => $product_id,
        'name' => html_entity_decode($product->get_name(), ENT_QUOTES, 'UTF-8'),
        'slug' => $product->get_slug(),
        'type' => $product->get_type(),
        'status' => get_post_status($product_id),
        'sku' => $product->get_sku(),
        'price' => $formatted_price,
        'regular_price' => $formatted_regular,
        'display_price' => $formatted_price,
        'display_regular_price' => $formatted_regular,
        'role_price' => $formatted_price,
        'raw_price' => $price === '' || $price === null ? '' : (string) $price,
        'sale_price' => (string) $product->get_sale_price(),
        'price_html' => $product->get_price_html(),
        'has_price' => $has_price,
        'stock_status' => $stock_status,
        'stock_quantity' => 0,
        'is_in_stock' => $is_in_stock,
        'is_purchasable' => $can_add_to_cart,
        'purchasable' => $can_add_to_cart,
        'can_add_to_cart' => $can_add_to_cart,
        'can_request_quote' => true,
        'on_sale' => $product->is_on_sale(),
        'short_description' => wp_strip_all_tags($product->get_short_description()),
        'description' => wp_kses_post($product->get_description()),
        'images' => array(array('src' => $image_url, 'full_src' => $image_full_url)),
        'image' => $image_url,
        'categories' => $categories,
        'attributes' => $attributes,
        'brand_name' => $brand_name,
        'brand' => $brand_name,
        'permalink' => get_permalink($product_id),
    );

    if ($score !== null) {
        $data['search_score'] = $score;
    }

    if ($reasons !== null) {
        $data['search_reasons'] = $reasons;
    }

    return $data;
}

function mundicam_ctx_build_search_terms($raw_search, $tokens, $expanded_terms, $sku_variants) {
    $terms = array();
    $clean = trim(preg_replace('/\s+/', ' ', (string) $raw_search));

    if ($clean !== '') {
        $terms[] = $clean;
    }

    $without_stop = mundicam_ctx_remove_stopwords($clean);
    if ($without_stop !== '' && mundicam_ctx_normalize_text($without_stop) !== mundicam_ctx_normalize_text($clean)) {
        $terms[] = $without_stop;
    }

    foreach ($sku_variants as $sku) {
        if (mb_strlen($sku) >= 4) {
            $terms[] = $sku;
        }
    }

    foreach ($tokens as $token) {
        if (!mundicam_ctx_is_generic_token($token, count($tokens))) {
            $terms[] = $token;
        }
    }

    foreach ($expanded_terms as $term) {
        if (!mundicam_ctx_is_generic_token($term, count($tokens))) {
            $terms[] = $term;
        }
    }

    $unique = array();
    foreach ($terms as $term) {
        $term = trim((string) $term);
        if ($term === '' || mb_strlen($term) < 2) {
            continue;
        }
        $key = mundicam_ctx_normalize_text($term);
        if ($key === '' || isset($unique[$key])) {
            continue;
        }
        $unique[$key] = $term;
    }

    return array_slice(array_values($unique), 0, 28);
}

function mundicam_ctx_looks_like_sku($value) {
    $raw = trim((string) $value);
    if ($raw === '') {
        return false;
    }
    $compact = preg_replace('/[^A-Z0-9]/', '', strtoupper($raw));
    if (strlen($compact) < 5 || !preg_match('/\d/', $compact)) {
        return false;
    }
    return strpos($raw, '-') !== false || strpos($raw, '_') !== false || preg_match('/[A-Z]{2,}\d|\d[A-Z]{2,}/i', $raw);
}

function mundicam_ctx_sku_variants($raw_search) {
    $raw = trim((string) $raw_search);
    if ($raw === '') {
        return array();
    }

    $variants = array($raw);
    $variants[] = strtoupper($raw);
    $variants[] = strtolower($raw);
    $variants[] = str_replace(' ', '', $raw);
    $variants[] = str_replace('-', '', $raw);
    $variants[] = str_replace(array('-', '_'), ' ', $raw);
    $variants[] = str_replace(array(' ', '_'), '-', $raw);

    $compact = preg_replace('/[^A-Za-z0-9]/', '', $raw);
    if ($compact && strlen($compact) >= 4) {
        $variants[] = $compact;
        $variants[] = strtoupper($compact);
    }

    $parts = preg_split('/[\s\-_\/]+/', $raw);
    if (is_array($parts)) {
        foreach ($parts as $part) {
            $part = trim($part);
            if (strlen($part) >= 4 && preg_match('/\d/', $part)) {
                $variants[] = $part;
                $variants[] = strtoupper($part);
            }
        }
    }

    $unique = array();
    foreach ($variants as $variant) {
        $variant = trim((string) $variant);
        if ($variant === '' || strlen($variant) < 3) {
            continue;
        }
        $key = strtolower($variant);
        $unique[$key] = $variant;
    }

    return array_values($unique);
}

function mundicam_ctx_query_tokens($value) {
    $clean = mundicam_ctx_normalize_text($value);
    $parts = preg_split('/\s+/', $clean);
    $tokens = array();

    foreach ($parts as $part) {
        $part = trim($part);
        if ($part === '' || mb_strlen($part) < 2) {
            continue;
        }
        if (mundicam_ctx_is_stopword($part)) {
            continue;
        }
        $tokens[] = $part;
    }

    return array_values(array_unique($tokens));
}

function mundicam_ctx_remove_stopwords($value) {
    $parts = preg_split('/\s+/', trim((string) $value));
    $out = array();

    foreach ($parts as $part) {
        $norm = mundicam_ctx_normalize_text($part);
        if ($norm === '' || mundicam_ctx_is_stopword($norm)) {
            continue;
        }
        $out[] = $part;
    }

    return trim(implode(' ', $out));
}

function mundicam_ctx_is_stopword($word) {
    static $stopwords = null;
    if ($stopwords === null) {
        $stopwords = array_flip(array(
            'de', 'del', 'la', 'el', 'los', 'las', 'para', 'por', 'con', 'sin', 'en', 'un', 'una', 'unos', 'unas', 'y', 'o', 'a', 'al', 'the', 'of', 'to', 'for', 'and'
        ));
    }
    return isset($stopwords[$word]);
}

function mundicam_ctx_is_generic_token($token, $token_count = 1) {
    $token = mundicam_ctx_normalize_text($token);
    if ($token_count <= 1) {
        return false;
    }

    return in_array($token, array(
        'seguridad', 'sistema', 'sistemas', 'producto', 'productos', 'profesional', 'profesionales', 'electronica', 'electronico', 'instalacion', 'instalaciones'
    ), true);
}

function mundicam_ctx_expand_context_terms($raw_search, $tokens) {
    $normalized = mundicam_ctx_normalize_text($raw_search);
    $terms = array();

    $add = function ($items) use (&$terms) {
        foreach ((array) $items as $item) {
            $item = trim((string) $item);
            if ($item !== '') {
                $terms[] = $item;
            }
        }
    };

    if (mundicam_ctx_contains_any($normalized, array('caja', 'cajas', 'gabinete', 'armario', 'envolvente', 'cofre', 'box'))) {
        $add(array(
            'caja', 'cajas', 'caja seguridad', 'cajas seguridad', 'gabinete', 'armario', 'envolvente', 'cofre', 'box', 'proteccion', 'protección', 'montaje', 'exterior', 'metalica', 'metálica', 'detector sismico', 'detector sísmico', 'sismico', 'sísmico', 'MCI', 'PowerSafe', 'Power Safe'
        ));
    }

    if (mundicam_ctx_contains_any($normalized, array('camara', 'camaras', 'camera', 'cctv', 'video', 'domo', 'dome', 'turret', 'bullet', 'tubular', 'ptz', 'ip'))) {
        $add(array('camara', 'cámara', 'camaras', 'cámaras', 'cctv', 'video ip', 'domo', 'dome', 'turret', 'bullet', 'tubular', 'ptz', 'wizsense', 'colorvu', 'wdr', 'smart dual light', 'poe'));
    }

    if (mundicam_ctx_contains_any($normalized, array('grabador', 'grabadores', 'nvr', 'xvr', 'dvr', 'recorder'))) {
        $add(array('grabador', 'grabadores', 'nvr', 'xvr', 'dvr', 'canales', 'h265', 'h.265', 'poe', 'ip'));
    }

    if (mundicam_ctx_contains_any($normalized, array('alarma', 'alarmas', 'intrusion', 'intrusión', 'detector', 'sensor', 'sirena', 'teclado', 'hub'))) {
        $add(array('alarma', 'intrusion', 'intrusión', 'hub', 'detector', 'sensor', 'sirena', 'teclado', 'contacto', 'mando', 'ajax', 'ksenia', 'lares', 'grado 2', 'grado 3'));
    }

    if (mundicam_ctx_contains_any($normalized, array('incendio', 'fuego', 'en54', 'humo', 'termico', 'térmico'))) {
        $add(array('incendio', 'en54', 'detector humo', 'detector térmico', 'detector termico', 'sirena incendio', 'pulsador', 'central incendio', 'teletek', 'ajax fire'));
    }

    if (mundicam_ctx_contains_any($normalized, array('switch', 'router', 'poe', 'wifi', 'wi fi', 'networking', 'red', 'redes', 'omada', 'vigi', 'tplink', 'tp link'))) {
        $add(array('switch', 'router', 'poe', 'wifi', 'wi-fi', 'networking', 'redes', 'omada', 'vigi', 'tp-link', 'tplink', 'access point', 'punto acceso'));
    }

    if (mundicam_ctx_contains_any($normalized, array('rj45', 'cable', 'latiguillo', 'conector', 'utp', 'ftp', 'cat6', 'cat 6', 'bnc', 'coaxial'))) {
        $add(array('rj45', 'cable', 'latiguillo', 'conector', 'utp', 'ftp', 'cat6', 'cat 6', 'bnc', 'coaxial', 'bobina'));
    }

    if (mundicam_ctx_contains_any($normalized, array('fuente', 'alimentacion', 'alimentación', 'bateria', 'batería', 'pila', 'transformador'))) {
        $add(array('fuente', 'fuente alimentación', 'alimentador', 'alimentacion', 'alimentación', 'bateria', 'batería', 'pila', 'transformador', '12v', '24v'));
    }

    if (mundicam_ctx_contains_any($normalized, array('4g', 'lte', 'sim', 'm2m', 'iot', 'wisim'))) {
        $add(array('4g', 'lte', 'sim', 'm2m', 'iot', 'router 4g', 'multioperador', 'wisim', 'wiSIM'));
    }

    if (mundicam_ctx_contains_any($normalized, array('solar', 'autonomo', 'autónomo', 'energia', 'energía', 'farola'))) {
        $add(array('solar', 'autonomo', 'autónomo', 'energia', 'energía', 'bateria', 'batería', 'panel solar', 'farola', 'evolve', 'powersafe'));
    }

    // Marcas habituales para que una búsqueda por contexto también encuentre familias vinculadas.
    $brands = array('dahua', 'hikvision', 'ajax', 'ksenia', 'teletek', 'tp-link', 'tplink', 'vigi', 'omada', 'mobotix', 'secury360', 'evolve', 'wisim', 'mci', 'powersafe', 'power safe');
    foreach ($brands as $brand) {
        if (strpos($normalized, mundicam_ctx_normalize_text($brand)) !== false) {
            $add(array($brand));
        }
    }

    $unique = array();
    foreach ($terms as $term) {
        $key = mundicam_ctx_normalize_text($term);
        if ($key !== '') {
            $unique[$key] = $term;
        }
    }

    return array_values($unique);
}

function mundicam_ctx_contains_any($source, $values) {
    foreach ($values as $value) {
        $value = mundicam_ctx_normalize_text($value);
        if ($value !== '' && strpos($source, $value) !== false) {
            return true;
        }
    }
    return false;
}

function mundicam_ctx_normalize_text($value) {
    $value = wp_strip_all_tags((string) $value);
    $value = html_entity_decode($value, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    $value = mb_strtolower($value, 'UTF-8');

    $replace = array(
        'á' => 'a', 'à' => 'a', 'ä' => 'a', 'â' => 'a', 'ã' => 'a',
        'é' => 'e', 'è' => 'e', 'ë' => 'e', 'ê' => 'e',
        'í' => 'i', 'ì' => 'i', 'ï' => 'i', 'î' => 'i',
        'ó' => 'o', 'ò' => 'o', 'ö' => 'o', 'ô' => 'o', 'õ' => 'o',
        'ú' => 'u', 'ù' => 'u', 'ü' => 'u', 'û' => 'u',
        'ñ' => 'n', 'ç' => 'c',
    );
    $value = strtr($value, $replace);
    $value = preg_replace('/[^a-z0-9]+/u', ' ', $value);
    $value = preg_replace('/\s+/', ' ', $value);

    return trim($value);
}

// =============================================================
// RMA MUNDICAM - INTEGRADO (v1.0.0)
// =============================================================
// Endpoints incluidos:
// - POST /wp-json/mundicam/v1/rma
// - GET  /wp-json/mundicam/v1/rma?email=cliente@dominio.com
// - POST /wp-json/mundicam-app/v1/rma
// - GET  /wp-json/mundicam-app/v1/rma?email=cliente@dominio.com
// - GET  /wp-json/wc/v3/rma?email=cliente@dominio.com  (compatibilidad app actual)

if (!defined('MUNDICAM_RMA_POST_TYPE')) {
    define('MUNDICAM_RMA_POST_TYPE', 'mundicam_rma');
}

add_action('init', 'mundicam_rma_register_post_type');
function mundicam_rma_register_post_type() {
    register_post_type(MUNDICAM_RMA_POST_TYPE, array(
        'labels' => array(
            'name' => 'RMA MundiCam',
            'singular_name' => 'RMA MundiCam',
            'menu_name' => 'RMA MundiCam',
            'add_new_item' => 'Añadir RMA',
            'edit_item' => 'Editar RMA',
            'view_item' => 'Ver RMA',
            'search_items' => 'Buscar RMA',
        ),
        'public' => false,
        'show_ui' => true,
        'show_in_menu' => 'woocommerce',
        'show_in_rest' => false,
        'supports' => array('title', 'editor'),
        'capability_type' => 'shop_order',
        'map_meta_cap' => true,
    ));
}

add_action('rest_api_init', 'mundicam_rma_register_routes');
function mundicam_rma_register_routes() {
    $rma_args = array(
        'methods' => WP_REST_Server::READABLE,
        'callback' => 'mundicam_rma_list_request',
        'permission_callback' => 'mundicam_rma_permission_read',
        'args' => array(
            'email' => array(
                'required' => false,
                'sanitize_callback' => 'sanitize_email',
            ),
            'customer_email' => array(
                'required' => false,
                'sanitize_callback' => 'sanitize_email',
            ),
            'page' => array(
                'required' => false,
                'sanitize_callback' => 'absint',
                'default' => 1,
            ),
            'per_page' => array(
                'required' => false,
                'sanitize_callback' => 'absint',
                'default' => 30,
            ),
        ),
    );

    $rma_create_args = array(
        'methods' => WP_REST_Server::CREATABLE,
        'callback' => 'mundicam_rma_create_request',
        'permission_callback' => 'mundicam_rma_permission_create',
    );

    register_rest_route('mundicam/v1', '/rma', $rma_args);
    register_rest_route('mundicam/v1', '/rma', $rma_create_args);

    register_rest_route('mundicam-app/v1', '/rma', $rma_args);
    register_rest_route('mundicam-app/v1', '/rma', $rma_create_args);

    // Compatibilidad con llamadas antiguas de la app que consultaban /wp-json/wc/v3/rma.
    register_rest_route('wc/v3', '/rma', $rma_args);
}

function mundicam_rma_permission_create(WP_REST_Request $request) {
    if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'permission_app_user')) {
        $allowed = Mundicam_App_API::permission_app_user($request);
        if (is_wp_error($allowed)) {
            return $allowed;
        }
        return true;
    }

    return new WP_Error('mundicam_app_unauthorized', 'Sesión de app no válida. Vuelve a iniciar sesión.', array('status' => 401));
}

function mundicam_rma_permission_read(WP_REST_Request $request) {
    if (class_exists('Mundicam_App_API') && method_exists('Mundicam_App_API', 'permission_app_user')) {
        $allowed = Mundicam_App_API::permission_app_user($request);
        if (is_wp_error($allowed)) {
            return $allowed;
        }
        return true;
    }

    return new WP_Error('mundicam_app_unauthorized', 'Sesión de app no válida. Vuelve a iniciar sesión.', array('status' => 401));
}

function mundicam_rma_clean_text($value) {
    if (is_array($value) || is_object($value)) {
        return '';
    }
    return sanitize_text_field(wp_strip_all_tags((string) $value));
}

function mundicam_rma_clean_textarea($value) {
    if (is_array($value) || is_object($value)) {
        return '';
    }
    return sanitize_textarea_field(wp_strip_all_tags((string) $value));
}

function mundicam_rma_request_email(WP_REST_Request $request) {
    $email = sanitize_email((string) ($request->get_param('email') ?: $request->get_param('customer_email') ?: $request->get_param('billing_email') ?: ''));
    return is_email($email) ? $email : '';
}

function mundicam_rma_current_user_can_manage() {
    return current_user_can('manage_woocommerce') || current_user_can('manage_options');
}

function mundicam_rma_order_belongs_to_email($order, $email) {
    if (!($order instanceof WC_Order) || !is_email($email)) {
        return false;
    }

    $order_email = sanitize_email((string) $order->get_billing_email());
    if ($order_email !== '' && strtolower($order_email) === strtolower($email)) {
        return true;
    }

    $customer_id = (int) $order->get_customer_id();
    if ($customer_id > 0) {
        $user = get_user_by('id', $customer_id);
        if ($user instanceof WP_User && strtolower((string) $user->user_email) === strtolower($email)) {
            return true;
        }
    }

    return false;
}

function mundicam_rma_order_contains_product($order, $product_id) {
    if (!($order instanceof WC_Order)) {
        return false;
    }

    $product_id = absint($product_id);
    if ($product_id <= 0) {
        return false;
    }

    foreach ($order->get_items() as $item) {
        if (!($item instanceof WC_Order_Item_Product)) {
            continue;
        }
        if ((int) $item->get_product_id() === $product_id || (int) $item->get_variation_id() === $product_id) {
            return true;
        }
    }

    return false;
}

/**
 * v1.9.16 Envía aviso por email a soporte/admin cuando se crea un RMA desde la app.
 * Destinatario filtrable con 'mundicam_app_rma_support_email' (por defecto,
 * el email de administración de WordPress). Nunca bloquea la creación del RMA.
 */
function mundicam_rma_notify_support($post_id, $order, $product_name, $product_sku, $reason, $description, $customer_email) {
    try {
        $to = apply_filters('mundicam_app_rma_support_email', get_option('admin_email'), $post_id, $order);
        $to = sanitize_email((string) $to);
        if ($to === '' || !is_email($to)) {
            return;
        }

        $order_number = ($order instanceof WC_Order) ? $order->get_order_number() : '';
        $subject = sprintf('[App MundiCam] Nueva solicitud RMA #%d (pedido %s)', (int) $post_id, $order_number);

        $esc = 'esc_html';
        $body  = '<div style="font-family:Arial,Helvetica,sans-serif;color:#222;max-width:680px;">';
        $body .= '<h2 style="color:#8B0000;">Nueva solicitud RMA desde la App</h2>';
        $body .= '<p><strong>RMA:</strong> #' . (int) $post_id . '<br>';
        $body .= '<strong>Pedido:</strong> ' . $esc($order_number) . '<br>';
        $body .= '<strong>Fecha:</strong> ' . $esc(current_time('d/m/Y H:i')) . '</p>';
        $body .= '<h3 style="color:#8B0000;">Cliente</h3><p>';
        $body .= '<strong>Email:</strong> ' . $esc($customer_email) . '</p>';
        $body .= '<h3 style="color:#8B0000;">Producto</h3><p>';
        $body .= '<strong>Nombre:</strong> ' . $esc($product_name) . '<br>';
        $body .= '<strong>SKU:</strong> ' . $esc($product_sku !== '' ? $product_sku : '—') . '</p>';
        $body .= '<h3 style="color:#8B0000;">Motivo</h3><p>' . $esc($reason) . '</p>';
        if ((string) $description !== '') {
            $body .= '<h3 style="color:#8B0000;">Descripción</h3><p>' . nl2br($esc($description)) . '</p>';
        }
        $body .= '<p style="margin-top:16px;color:#888;font-size:12px;">Origen: App MundiCam</p>';
        $body .= '</div>';

        $headers = array('Content-Type: text/html; charset=UTF-8');
        $reply = sanitize_email((string) $customer_email);
        if ($reply !== '' && is_email($reply)) {
            $headers[] = 'Reply-To: ' . $reply;
        }

        $sent = wp_mail($to, $subject, $body, $headers);
        if (!$sent && function_exists('error_log')) {
            error_log('[MundiCam App API] wp_mail devolvió false para aviso RMA #' . (int) $post_id . '.');
        }
    } catch (Throwable $e) {
        if (function_exists('error_log')) {
            error_log('[MundiCam App API] Error enviando aviso RMA: ' . $e->getMessage());
        }
    }
}

function mundicam_rma_create_request(WP_REST_Request $request) {
    if (!function_exists('wc_get_order') || !function_exists('wc_get_product')) {
        return new WP_Error('mundicam_rma_woocommerce_missing', 'WooCommerce no está disponible.', array('status' => 500));
    }

    $email = mundicam_rma_request_email($request);
    $order_id = absint($request->get_param('order_id') ?: $request->get_param('orderId') ?: 0);
    $product_id = absint($request->get_param('product_id') ?: $request->get_param('productId') ?: 0);
    $reason = mundicam_rma_clean_text($request->get_param('reason') ?: $request->get_param('motivo') ?: '');
    $description = mundicam_rma_clean_textarea($request->get_param('description') ?: $request->get_param('descripcion') ?: $request->get_param('message') ?: '');

    if ($email === '') {
        return new WP_Error('mundicam_rma_invalid_email', 'Email de cliente no válido.', array('status' => 400));
    }

    if ($order_id <= 0) {
        return new WP_Error('mundicam_rma_invalid_order', 'Pedido no válido.', array('status' => 400));
    }

    if ($product_id <= 0) {
        return new WP_Error('mundicam_rma_invalid_product', 'Producto no válido.', array('status' => 400));
    }

    if ($reason === '') {
        $reason = 'Solicitud RMA';
    }

    $order = wc_get_order($order_id);
    if (!($order instanceof WC_Order)) {
        return new WP_Error('mundicam_rma_order_not_found', 'Pedido no encontrado.', array('status' => 404));
    }

    // v1.9.24 Bloqueo de RMA en pedidos antiguos: no se permite solicitar RMA
    // en pedidos de más de 2 años. Protección en servidor (la app también oculta
    // el botón, pero este bloqueo impide peticiones manuales/externas).
    $order_date = $order->get_date_created();
    if ($order_date instanceof WC_DateTime) {
        $age_days = (int) ((time() - $order_date->getTimestamp()) / 86400);
        if ($age_days > 730) { // 2 años = 730 días
            return new WP_Error(
                'mundicam_rma_order_too_old',
                'No se puede solicitar RMA en pedidos de más de 2 años.',
                array('status' => 400, 'order_age_days' => $age_days)
            );
        }
    }

    if (!mundicam_rma_current_user_can_manage() && !mundicam_rma_order_belongs_to_email($order, $email)) {
        return new WP_Error('mundicam_rma_order_email_mismatch', 'El pedido no corresponde al email indicado.', array('status' => 403));
    }

    if (!mundicam_rma_order_contains_product($order, $product_id)) {
        return new WP_Error('mundicam_rma_product_not_in_order', 'El producto no pertenece al pedido indicado.', array('status' => 400));
    }

    $product = wc_get_product($product_id);
    $product_name = $product instanceof WC_Product ? $product->get_name() : ('Producto #' . $product_id);
    $product_sku = $product instanceof WC_Product ? $product->get_sku() : '';

    $title = sprintf('RMA #%s - Pedido #%s - %s', date_i18n('Ymd-His'), $order->get_order_number(), $email);
    $post_id = wp_insert_post(array(
        'post_type' => MUNDICAM_RMA_POST_TYPE,
        'post_status' => 'publish',
        'post_title' => $title,
        'post_content' => $description,
        'post_author' => (int) get_current_user_id(),
    ), true);

    if (is_wp_error($post_id)) {
        return new WP_Error('mundicam_rma_create_error', 'No se pudo crear la solicitud RMA.', array('status' => 500));
    }

    $meta = array(
        '_mundicam_rma_email' => $email,
        '_mundicam_rma_order_id' => $order_id,
        '_mundicam_rma_order_number' => $order->get_order_number(),
        '_mundicam_rma_product_id' => $product_id,
        '_mundicam_rma_product_name' => $product_name,
        '_mundicam_rma_product_sku' => $product_sku,
        '_mundicam_rma_reason' => $reason,
        '_mundicam_rma_description' => $description,
        '_mundicam_rma_status' => 'pending',
        '_mundicam_rma_created_at' => current_time('mysql'),
    );

    foreach ($meta as $key => $value) {
        update_post_meta($post_id, $key, $value);
    }

    $order->add_order_note(sprintf(
        'Solicitud RMA creada desde la app. RMA #%d. Producto: %s%s. Motivo: %s',
        (int) $post_id,
        $product_name,
        $product_sku !== '' ? ' (' . $product_sku . ')' : '',
        $reason
    ));

    do_action('mundicam_app_rma_created', $post_id, $order_id, $product_id, $email, $request);

    // v1.9.16 Aviso por email a soporte/admin. Antes el RMA se creaba pero NO se
    // avisaba a nadie: quedaba solo en el CPT. No bloquea la respuesta si falla.
    mundicam_rma_notify_support($post_id, $order, $product_name, $product_sku, $reason, $description, $email);

    $payload = mundicam_rma_payload($post_id);

    return new WP_REST_Response(array(
        'success' => true,
        'message' => 'Solicitud RMA creada correctamente.',
        'rma_id' => (int) $post_id,
        'id' => (int) $post_id,
        'rma' => $payload,
        'data' => $payload,
    ), 201);
}

function mundicam_rma_list_request(WP_REST_Request $request) {
    $email = mundicam_rma_request_email($request);
    $page = max(1, absint($request->get_param('page') ?: 1));
    $per_page = min(100, max(1, absint($request->get_param('per_page') ?: 30)));

    $meta_query = array();

    if ($email !== '' && !mundicam_rma_current_user_can_manage()) {
        $meta_query[] = array(
            'key' => '_mundicam_rma_email',
            'value' => $email,
            'compare' => '=',
        );
    } elseif ($email !== '') {
        $meta_query[] = array(
            'key' => '_mundicam_rma_email',
            'value' => $email,
            'compare' => '=',
        );
    }

    // Si no hay email y no es administrador/gestor, no devolvemos datos.
    if ($email === '' && !mundicam_rma_current_user_can_manage()) {
        return new WP_REST_Response(array(
            'success' => true,
            'rma' => array(),
            'requests' => array(),
            'data' => array(),
            'items' => array(),
            'total' => 0,
            'total_pages' => 1,
        ), 200);
    }

    $query_args = array(
        'post_type' => MUNDICAM_RMA_POST_TYPE,
        'post_status' => 'publish',
        'posts_per_page' => $per_page,
        'paged' => $page,
        'orderby' => 'date',
        'order' => 'DESC',
        'fields' => 'ids',
    );

    if (!empty($meta_query)) {
        $query_args['meta_query'] = $meta_query;
    }

    $query = new WP_Query($query_args);
    $items = array();

    foreach ((array) $query->posts as $post_id) {
        $items[] = mundicam_rma_payload((int) $post_id);
    }

    return new WP_REST_Response(array(
        'success' => true,
        'rma' => $items,
        'requests' => $items,
        'data' => $items,
        'items' => $items,
        'page' => $page,
        'per_page' => $per_page,
        'total' => (int) $query->found_posts,
        'total_pages' => max(1, (int) $query->max_num_pages),
    ), 200);
}

function mundicam_rma_payload($post_id) {
    $post_id = absint($post_id);
    $post = get_post($post_id);
    if (!$post || $post->post_type !== MUNDICAM_RMA_POST_TYPE) {
        return array();
    }

    $order_id = absint(get_post_meta($post_id, '_mundicam_rma_order_id', true));
    $product_id = absint(get_post_meta($post_id, '_mundicam_rma_product_id', true));

    return array(
        'id' => $post_id,
        'rma_id' => $post_id,
        'number' => 'RMA-' . $post_id,
        'status' => (string) get_post_meta($post_id, '_mundicam_rma_status', true),
        'email' => (string) get_post_meta($post_id, '_mundicam_rma_email', true),
        'customer_email' => (string) get_post_meta($post_id, '_mundicam_rma_email', true),
        'order_id' => $order_id,
        'order_number' => (string) get_post_meta($post_id, '_mundicam_rma_order_number', true),
        'product_id' => $product_id,
        'product_name' => (string) get_post_meta($post_id, '_mundicam_rma_product_name', true),
        'product_sku' => (string) get_post_meta($post_id, '_mundicam_rma_product_sku', true),
        'sku' => (string) get_post_meta($post_id, '_mundicam_rma_product_sku', true),
        'reason' => (string) get_post_meta($post_id, '_mundicam_rma_reason', true),
        'description' => (string) get_post_meta($post_id, '_mundicam_rma_description', true),
        'date_created' => get_the_date('c', $post_id),
        'created_at' => (string) get_post_meta($post_id, '_mundicam_rma_created_at', true),
        'permalink' => get_edit_post_link($post_id, ''),
    );
}