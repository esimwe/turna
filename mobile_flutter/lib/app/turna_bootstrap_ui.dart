import 'package:flutter/material.dart';

import 'turna_theme.dart';

ThemeData buildTurnaAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: TurnaColors.backgroundSoft,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TurnaColors.primary,
      primary: TurnaColors.primary,
      surface: TurnaColors.surface,
      onSurface: TurnaColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: TurnaColors.background,
      foregroundColor: TurnaColors.text,
      centerTitle: false,
    ),
    dividerColor: TurnaColors.divider,
  );
}

class TurnaLaunchPage extends StatelessWidget {
  const TurnaLaunchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14305788),
                      blurRadius: 30,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'ios/Runner/Assets.xcassets/AppIcon.appiconset/180x180.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Turnalar selam goturur.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: TurnaColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
