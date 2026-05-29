import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/user_provider.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('user_token');
  runApp(
    ChangeNotifierProvider(
      create: (_) => UserProvider(),
      child: GoraCabsApp(isLoggedIn: token != null && token.isNotEmpty),
    ),
  );
}

class GoraCabsApp extends StatelessWidget {
  final bool isLoggedIn;
  const GoraCabsApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gora Cabs',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: isLoggedIn ? const HomeScreen() : const WelcomeScreen(),
    );
  }
}
