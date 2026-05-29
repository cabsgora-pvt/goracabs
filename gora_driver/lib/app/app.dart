import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/splash/splash_page.dart';
import '../providers/driver_provider.dart';
import 'app_routes.dart';

class GoraDriverApp extends StatelessWidget {
  const GoraDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DriverProvider(),
      child: BlocProvider(
        create: (_) => AuthBloc(),
        child: MaterialApp(
          title: 'Gora Driver',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          initialRoute: SplashPage.route,
          routes: AppRoutes.routes,
          onGenerateRoute: (settings) {
            final builder = AppRoutes.routes[settings.name];
            if (builder != null) {
              return MaterialPageRoute(builder: builder, settings: settings);
            }
            return MaterialPageRoute(builder: (_) => const SplashPage());
          },
        ),
      ),
    );
  }
}
