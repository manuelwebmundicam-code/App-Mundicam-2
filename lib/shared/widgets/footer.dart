import 'package:flutter/material.dart';

class Footer extends StatelessWidget {
  const Footer({super.key});
  //USAR EN PERFIL NO EN EL MAINNNN
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text("+34 968 629 383", style: TextStyle(color: Colors.white)),
          SizedBox(height: 5),
          Text(
            "MundiCam Security Distribution",
            style: TextStyle(color: Colors.white),
          ),

          SizedBox(height: 10),
          Text(
            "Polígono Industrial Base 2000\nLorquí, Murcia (España)",
            style: TextStyle(color: Colors.white70),
          ),

          SizedBox(height: 10),
          Text("pedidos@mundicam.com", style: TextStyle(color: Colors.white)),

          SizedBox(height: 20),

          Text(
            "CATEGORÍAS",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          Text(
            "Video CCTV\nVideo IP\nIntrusión\nNetworking\nDrones PRO",
            style: TextStyle(color: Colors.white70),
          ),

          SizedBox(height: 20),

          Text(
            "EMPRESA",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          Text(
            "Quiénes somos\nContacto\nTrabaja con nosotros",
            style: TextStyle(color: Colors.white70),
          ),

          SizedBox(height: 20),

          Text("© MUNDICAM 2025-2026", style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
