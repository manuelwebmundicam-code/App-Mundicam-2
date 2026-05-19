import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

class EmpresaPage extends StatelessWidget {
  const EmpresaPage({super.key});

  // Función para llamar
  Future<void> _hacerLlamada() async {
    final Uri url = Uri.parse('tel:968629383');
    if (!await launchUrl(url)) {
      debugPrint('No se pudo realizar la llamada');
    }
  }

  Future<void> _enviarWhatsApp() async {
    final Uri url = Uri.parse(
      "https://wa.me/34619078632?text=Hola Mundicam, me gustaría realizar una consulta.",
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('No se pudo abrir WhatsApp');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("SOBRE MUNDICAM"),
        backgroundColor: AppColors.primary,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/banners/banner4.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    "MUNDICAM SEGURIDAD",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "MÁS DE 20 AÑOS DE EXPERIENCIA",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "¿Quiénes somos?",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Mundicam nace en el año 2004 como una empresa familiar dedicada a la distribución de sistemas de seguridad. Hoy, somos un referente nacional e internacional en el sector del CCTV e intrusión.",
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Nuestra filosofía se basa en tres pilares fundamentales: el mejor asesoramiento técnico, un stock permanente y una logística envidiable.",
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildMundicamValue(
                    Icons.verified_user,
                    "GARANTÍA",
                    "Productos certificados de primeras marcas.",
                  ),
                  _buildMundicamValue(
                    Icons.support_agent,
                    "SOPORTE TÉCNICO",
                    "Asesoramiento especializado personalizado.",
                  ),
                  _buildMundicamValue(
                    Icons.local_shipping,
                    "LOGÍSTICA",
                    "Envíos rápidos a toda la península y Europa.",
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 55,
                          child: ElevatedButton.icon(
                            onPressed: _hacerLlamada,
                            icon: const Icon(Icons.phone),
                            label: const Text("Llámanos"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Botón de WhatsApp
                      Expanded(
                        child: SizedBox(
                          height: 55,
                          child: ElevatedButton.icon(
                            onPressed: _enviarWhatsApp,
                            icon: const Icon(Icons.chat),
                            label: const Text("Whatsapp"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSedeHorizontal(
                          "España",
                          "C/ Mayor, 44, 1º Izq.\n30500 Molina de Segura\nMurcia\n(+34) 968 62 93 83",
                        ),
                        _buildSedeHorizontal(
                          "Portugal",
                          "Av. do Forte 3\nEd. Suécia IV, sala 1.08\n2790-072 Carnaxide\n(+351) 308 802 598",
                        ),
                        _buildSedeHorizontal(
                          "Italia",
                          "Via Faro, nº 21\n20876, Ornago MB\nItalia\n(+39) 039 930 04 08",
                        ),
                        _buildSedeHorizontal(
                          "Francia",
                          "355 Av. Henri Schneider\n69330, Meyzieu\nFrancia\n(+33) 01 82 88 09 26",
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMundicamValue(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSedeHorizontal(String pais, String info) {
    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pais.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            info,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
