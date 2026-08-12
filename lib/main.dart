import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'providers/recording_provider.dart';
import 'providers/activation_provider.dart';
import 'services/voice_assistant_service.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://jwldcxoijckdwjfuhijr.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp3bGRjeG9pamNrZHdqZnVoaWpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyMjA3MzYsImV4cCI6MjEwMTc5NjczNn0.ytYeWPKkths7sI1rrZ9xlZrwTAUctgThsXUJupjmmmo',
    // Admin authentication is deliberately kept in memory only. The app has
    // no OAuth/deep-link sign-in flow, so privileged refresh tokens must not
    // be persisted in SharedPreferences or device backups.
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      detectSessionInUri: false,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ActivationProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => RecordingProvider()),
        ChangeNotifierProvider(create: (_) => VoiceAssistantService()),
      ],
      child: MaterialApp(
        title: 'EliteRadIq',
        debugShowCheckedModeBanner: false,

        // Setup RTL Arabic as default locale
        locale: const Locale('ar', 'IQ'),
        supportedLocales: const [Locale('ar', 'IQ'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        // التطبيق يعمل دائماً بالوضع الداكن بغض النظر عن إعدادات الجهاز.
        themeMode: ThemeMode.dark,

        // --- Light Theme (Material 3 + Apple HIG) ---
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          fontFamily: 'Cairo',
          colorScheme: ColorScheme.fromSeed(
            brightness: Brightness.light,
            seedColor: const Color(0xFF087CFF),
            primary: const Color(0xFF087CFF),
            secondary: const Color(0xFF38BDF8),
          ),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            centerTitle: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.black.withOpacity(0.04),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.black.withOpacity(0.05), width: 1),
            ),
          ),
          pageTransitionsTheme: PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),

        // --- Dark Theme (Premium OLED + Material 3) ---
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'Cairo',
          colorScheme: ColorScheme.fromSeed(
            brightness: Brightness.dark,
            seedColor: const Color(0xFF087CFF),
            primary: const Color(0xFF087CFF),
            secondary: const Color(0xFFD9A441),
            surface: const Color(0xFF020814),
            surfaceContainer: const Color(0xFF08182A),
            surfaceContainerHigh: const Color(0xFF0A1D32),
            surfaceContainerHighest: const Color(0xFF0D2238),
            onSurface: const Color(0xFFF5F7FA),
            onSurfaceVariant: const Color(0xFFAAB7C8),
            tertiary: const Color(0xFF38BDF8),
          ),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            centerTitle: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: const Color(0xFF08182A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
            ),
          ),
          pageTransitionsTheme: PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),

        home: const SplashScreen(),
      ),
    );
  }
}
