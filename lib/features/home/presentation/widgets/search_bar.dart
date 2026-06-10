import 'package:flutter/material.dart';

import 'package:mundicam/features/catalog/presentation/pages/busqueda_resultados_page.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.text,
          onSubmitted: _buscar,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: 'Oswald',
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Buscar por producto, marca, tecnología...',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontFamily: 'Oswald',
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: IconButton(
              icon: const Icon(
                Icons.search_rounded,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => _buscar(_controller.text),
            ),
            suffixIcon: hasText
                ? IconButton(
              icon: const Icon(
                Icons.clear_rounded,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: () {
                _controller.clear();
              },
            )
                : IconButton(
              icon: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => _buscar(_controller.text),
            ),
            filled: true,
            fillColor: Colors.transparent,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 4,
            ),
          ),
        ),
      ),
    );
  }
}