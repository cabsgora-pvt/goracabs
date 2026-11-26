import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'services/app_foreground.dart';
import 'services/route_observer.dart';
import 'services/session_guard.dart';
import 'services/update_gate.dart';
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

class GoraCabsApp extends StatefulWidget {
  const GoraCabsApp({super.key});

  @override
  State<GoraCabsApp> createState() => _GoraCabsAppState();
}

class _GoraCabsAppState extends State<GoraCabsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // At start: the update check, a due session refresh, and any payment
    // whose confirmation never reached Gora (see AppForeground).
    WidgetsBinding.instance.addPostFrameCallback((_) => AppForeground.run());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // And again every time the rider comes back to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppForeground.run();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().mode;
    return MaterialApp(
      // Lets a rejected token (401) sign the rider out from wherever they are.
      navigatorKey: SessionGuard.navigatorKey,
      // Polling screens pause while another screen covers them (RouteAware).
      navigatorObservers: [appRouteObserver],
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
            // A required update covers every screen; an optional one shows a
            // banner (UpdateGate).
            child: UpdateOverlay(child: child!),
          );
        });
      },
      home: const SplashScreen(),
    );
  }
}
