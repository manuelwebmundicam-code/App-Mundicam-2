import 'package:flutter/material.dart';

import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/chatbox.dart';
import 'package:mundicam/features/home/presentation/widgets/brands_banner.dart';
import 'package:mundicam/features/home/presentation/widgets/header.dart';
import 'package:mundicam/features/home/presentation/widgets/search_bar.dart';
import 'package:mundicam/features/home/presentation/widgets/menu_bar.dart';
import 'package:mundicam/features/home/presentation/widgets/category_grid.dart';
import 'package:mundicam/features/home/presentation/widgets/news_section.dart';
import 'package:mundicam/features/home/presentation/widgets/academy_banner.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showSecondaryContent = false;
  bool _showChatBox = false;

  @override
  void initState() {
    super.initState();

    // Primero se pinta la estructura principal.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _showSecondaryContent = true;
      });
    });

    // El chatbox se carga un poco después para no bloquear el primer render.
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _showChatBox = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: [
                    const Header(),
                    const SearchBarWidget(),
                    const MenuBarWidget(),
                    const SizedBox(height: 20),

                    _buildSectionTitle('CATEGORÍAS'),
                    const SizedBox(height: 10),
                    const CategoryGrid(),

                    const SizedBox(height: 5),

                    if (_showSecondaryContent) ...[
                      const BrandsBanner(),
                      const SizedBox(height: 15),
                      const AcademyBanner(),
                      const SizedBox(height: 15),
                      _buildSectionTitle('NOTICIAS'),
                      const NewsBanner(),
                    ] else ...[
                      _buildSkeletonBlock(height: 120),
                      const SizedBox(height: 15),
                      _buildSkeletonBlock(height: 95),
                      const SizedBox(height: 15),
                      _buildSectionTitle('NOTICIAS'),
                      _buildSkeletonBlock(height: 150),
                    ],

                    const SizedBox(height: 16),
                  ],
                ),
              ),

              if (_showChatBox) const ChatBox(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            letterSpacing: 1.2,
            fontFamily: 'Oswald',
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonBlock({required double height}) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
