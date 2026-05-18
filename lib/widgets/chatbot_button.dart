import 'package:flutter/material.dart';

class ChatbotButton extends StatelessWidget {
  final VoidCallback onTap;

  const ChatbotButton({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          size: const Size(150, 72),
          painter: SpeechBubblePainter(),
          child: Container(
            width: 150,
            height: 72,
            padding: const EdgeInsets.only(
              left: 14,
              right: 16,
              top: 8,
              bottom: 18,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/mundicamlogo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '¿Dudas?\nTe ayudo',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
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

// ESTO ES LO QUE DIBUJA LA FORMA DE BOCADILLO
class SpeechBubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.fill;

    final path = Path();

    const double radius = 22.0;
    const double tailHeight = 12.0;

    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          0,
          size.width,
          size.height - tailHeight,
        ),
        const Radius.circular(radius),
      ),
    );

    path.moveTo(size.width * 0.68, size.height - tailHeight);
    path.lineTo(size.width * 0.84, size.height);
    path.lineTo(size.width * 0.90, size.height - tailHeight);
    path.close();

    canvas.drawShadow(path, Colors.black, 6.0, true);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}