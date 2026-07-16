import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/support/presentation/pages/chat_search_page.dart';

final chatBoxProvider = StateProvider<bool>((ref) => true);

class ChatBox extends ConsumerWidget {
  const ChatBox({super.key});

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

    return Positioned(
      right: 14,
      bottom: 16,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _openChat(context, ref),
            child: Container(
              width: 184,
              constraints: const BoxConstraints(
                minHeight: 62,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: _dark,
                borderRadius: BorderRadius.circular(22),
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
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Image.asset(
                      'assets/images/mundicamlogochatbox.png',
                      width: 30,
                      height: 30,
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
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '¿Dudas?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Oswald',
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Yo te ayudo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
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
    );
  }
}
