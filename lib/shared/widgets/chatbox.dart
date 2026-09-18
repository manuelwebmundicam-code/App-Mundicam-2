import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/support/presentation/pages/chat_search_page.dart';

final chatBoxProvider = StateProvider<bool>((ref) => true);

class ChatBox extends ConsumerWidget {
  final double bottomOffset;

  const ChatBox({
    super.key,
    this.bottomOffset = 16,
  });

  static const Color _brandRed = Color(0xFFA60909);
  static const Color _dark = Color(0xFF111827);
  static const Color _onlineGreen = Color(0xFF34D399);

  void _openChat(BuildContext context, WidgetRef ref) {
    FocusScope.of(context).unfocus();
    ref.read(chatSearchControllerProvider.notifier).reset();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ChatSearchPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool visible = ref.watch(chatBoxProvider);

    if (!visible) {
      return const SizedBox.shrink();
    }

    // Diseño estable: el chat mantiene siempre el mismo tamaño visual
    // en móvil, tablet y escritorio. El layout del footer reserva su espacio,
    // así que no necesita crecer ni encogerse según el dispositivo.
    const double chatWidth = 164;
    const double chatHeight = 60;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      right: 12,
      bottom: bottomOffset,
      child: SafeArea(
        top: false,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openChat(context, ref),
              child: Container(
                width: chatWidth,
                height: chatHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _dark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                    width: 1.2,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.20),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.09),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Image.asset(
                        'assets/images/mundicamlogochatbox.png',
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                        errorBuilder: (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) {
                          return const Icon(
                            Icons.support_agent_rounded,
                            color: _brandRed,
                            size: 28,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            '¿Dudas?',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Oswald',
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Yo te ayudo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.05,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _onlineGreen,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: _onlineGreen.withOpacity(0.55),
                            blurRadius: 7,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
