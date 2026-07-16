/// Configuración central del endpoint MundiCam App API.
///
/// No calcula precios. Solo define dónde está el endpoint PHP de WordPress.
///
/// En producción, si se usa clave `MUNDICAM_APP_API_KEY`, es preferible cargarla
/// desde Remote Config/backend seguro o variables de compilación, no dejarla fija
/// en el repositorio.
class MundicamEndpointConfig {
  const MundicamEndpointConfig._();

  static const String defaultBaseUrl = String.fromEnvironment(
    'MUNDICAM_BASE_URL',
    defaultValue: 'https://www.mundicam.com',
  );

  static const String defaultApiKey = String.fromEnvironment(
    'MUNDICAM_APP_API_KEY',
    defaultValue: '',
  );

  static const int defaultPerPage = 24;
}
