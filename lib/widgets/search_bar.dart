import 'package:flutter/material.dart';

import '../pages/busqueda_resultados_page.dart';
import '../theme.dart';

class SearchBarWidget extends StatefulWidget {
  const SearchBarWidget({super.key});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _buscar(String value) {
    final String query = value.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BusquedaResultadosPage(query: query),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasText = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        onSubmitted: _buscar,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontFamily: 'Oswald',
        ),
        decoration: InputDecoration(
          hintText: 'Buscar por producto, marca, tecnología...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontFamily: 'Oswald',
          ),
          prefixIcon: IconButton(
            icon: const Icon(
              Icons.search_rounded,
              color: Colors.white,
              size: 24,
            ),
            onPressed: () => _buscar(_controller.text),
          ),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                  onPressed: () {
                    _controller.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.primary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 4,
          ),
        ),
      ),
    );
  }
}
