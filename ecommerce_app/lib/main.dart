import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uts_gaming_console/core/constants/app_strings.dart';
import 'package:uts_gaming_console/core/routes/app_router.dart';
import 'package:uts_gaming_console/core/services/secure_storage.dart';
import 'package:uts_gaming_console/core/theme/app_theme.dart';
import 'package:uts_gaming_console/features/auth/presentation/providers/auth_provider.dart';
import 'package:uts_gaming_console/features/cart/presentation/providers/cart_provider.dart';
import 'package:uts_gaming_console/features/cart/presentation/providers/checkout_provider.dart';
import 'package:uts_gaming_console/features/dashboard/presentation/providers/product_provider.dart';
import 'package:uts_gaming_console/features/dashboard/presentation/pages/transaction_history_page.dart';
import 'firebase_options.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission();
  } catch (e) {
    debugPrint("Firebase/FCM initialization skipped (Mock/Error): $e");
  }

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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinking();
    _initFirebaseMessaging();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _initDeepLinking() {
    _appLinks = AppLinks();

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (!mounted) return;
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('Deep Link Error: $err');
    });

    _appLinks.getInitialLink().then((uri) {
      if (uri != null && mounted) {
        _handleDeepLink(uri);
      }
    });
  }

  void _initFirebaseMessaging() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got an FCM message in the foreground!');
        if (message.notification != null) {
          final context = MyApp.navigatorKey.currentContext;
          if (context != null) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                icon: const Icon(Icons.notifications_active, color: Colors.blue, size: 48),
                title: Text(message.notification!.title ?? 'Notifikasi Transaksi'),
                content: Text(message.notification!.body ?? ''),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      // Refresh transactions list if page is open
                      MyApp.navigatorKey.currentState?.pushNamed('/transaction-history');
                    },
                    child: const Text('Lihat Riwayat'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            );
          }
        }
      });
    } catch (e) {
      debugPrint("FCM listener setup skipped: $e");
    }
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Received Deep Link: $uri');
    bool isCallback = (uri.scheme == 'ecommerce' && uri.host == 'callback');
    if (kIsWeb && uri.queryParameters.containsKey('status') && uri.queryParameters.containsKey('trx_id')) {
      isCallback = true;
    }

    if (isCallback) {
      final status = uri.queryParameters['status'];
      final trxId = uri.queryParameters['trx_id'] ?? 'N/A';
      final amount = uri.queryParameters['amount'] ?? '0';
      final recipient = uri.queryParameters['recipient_email'] ?? 'recipient@example.com';

      final context = MyApp.navigatorKey.currentContext;
      if (context != null) {
        // Save to local secure storage
        final now = DateTime.now();
        final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        
        SecureStorage.saveTransaction({
          'trx_id': trxId,
          'amount': amount,
          'recipient_email': recipient,
          'status': status,
          'date': dateStr,
        });

        if (status == 'success') {
          context.read<CartProvider>().clearCart();
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.check_circle, color: Colors.green, size: 60),
              title: const Text('Pembayaran Berhasil'),
              content: Text(
                'Transaksi Anda dengan ID $trxId sebesar Rp $amount berhasil dibayar via E-Money.',
                textAlign: TextAlign.center,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    MyApp.navigatorKey.currentState?.pushNamedAndRemoveUntil(AppRouter.dashboard, (route) => false);
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          final error = uri.queryParameters['error'] ?? 'Cancelled';
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.error, color: Colors.red, size: 60),
              title: const Text('Pembayaran Gagal'),
              content: Text('Error: $error\nID Transaksi: $trxId'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: MyApp.navigatorKey,
      initialRoute: AppRouter.login,
      routes: {
        ...AppRouter.routes,
        '/transaction-history': (context) => const TransactionHistoryPage(),
      },
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