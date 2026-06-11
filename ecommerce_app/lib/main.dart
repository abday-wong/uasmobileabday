import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uts_gaming_console/core/constants/app_strings.dart';
import 'package:uts_gaming_console/core/routes/app_router.dart';
import 'package:uts_gaming_console/core/services/secure_storage.dart';
import 'package:uts_gaming_console/core/theme/app_theme.dart';
import 'package:uts_gaming_console/features/auth/presentation/providers/auth_provider.dart';
import 'package:uts_gaming_console/features/cart/presentation/providers/cart_provider.dart';
import 'package:uts_gaming_console/features/cart/presentation/providers/checkout_provider.dart';
import 'package:uts_gaming_console/features/dashboard/presentation/providers/product_provider.dart';
import 'firebase_options.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => CheckoutProvider()),
      ],
      child: const MyApp(),
    ),
  );
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                  AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme:                  AppTheme.light,
      initialRoute:           AppRouter.login,
      routes:                 AppRouter.routes,
    );
  }
}


class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2)); // Animasi splash
    if (!mounted) return;

    final token = await SecureStorage.getToken();
    final route = token != null ? AppRouter.dashboard : AppRouter.login;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );
}