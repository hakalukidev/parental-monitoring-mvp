import 'services/app_config.dart';
import 'design/seftly_theme.dart';
import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  await ApiService.instance.loadPersistedToken();
  await NotificationService.instance.init(rootNavigatorKey);
  runApp(const ParentApp());
}

class ParentApp extends StatelessWidget {
  const ParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Seftly Parent',
      theme: SeftlyTheme.light(),
      darkTheme: SeftlyTheme.dark(),
      themeMode: ThemeMode.system,
      home: FutureBuilder<String?>(
        future: ApiService.instance.accessToken,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final hasToken = snapshot.data != null;
          return hasToken ? const DashboardScreen() : const LoginScreen();
        },
      ),
    );
  }
}
