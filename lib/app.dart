import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';

class FietsRadarApp extends StatelessWidget {
  const FietsRadarApp({super.key});

  static const Color forest = Color(0xFF12372A);
  static const Color lime = Color(0xFFC5F36B);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: forest,
      brightness: Brightness.light,
      primary: forest,
      secondary: lime,
      surface: const Color(0xFFF7F9F5),
    );

    return MaterialApp(
      title: 'FietsRadar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F9F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F9F5),
          foregroundColor: forest,
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: forest.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: lime.withValues(alpha: 0.55),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? forest : Colors.black54,
            );
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F4EF),
          hintStyle: const TextStyle(color: Colors.black45),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: forest, width: 1.4),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
