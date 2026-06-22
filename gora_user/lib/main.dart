import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const GoraCabsApp(),
    ),
  );
}

class GoraCabsApp extends StatelessWidget {
  const GoraCabsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().mode;
    return MaterialApp(
      title: 'Gora Cabs',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      // Global back handler: any back press from an inner screen
      // pops the stack all the way to home. From home → exits app.
      builder: (context, child) {
        return Builder(builder: (ctx) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              final nav = Navigator.of(ctx);
              if (nav.canPop()) {
                nav.popUntil((route) => route.isFirst);
              } else {
                SystemNavigator.pop();
              }
            },
            child: child!,
          );
        });
      },
      home: const SplashScreen(),
    );
  }
}
