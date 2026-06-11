import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Background messaging handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission();
  } catch (e) {
    debugPrint("Firebase initialization skipped (Mock Mode): $e");
  }
  runApp(const ECommerceApp());
}

class ECommerceApp extends StatelessWidget {
  const ECommerceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Global Merchant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ProductListScreen(),
    );
  }
}

class Product {
  final String id;
  final String name;
  final String description;
  final int price;
  final String imageUrl;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
  });
}

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final List<Product> _products = [
    Product(
      id: 'P001',
      name: 'Wireless Mechanical Keyboard',
      description: 'RGB Backlit mechanical keyboard with tactile brown switches.',
      price: 150000,
      imageUrl: '⌨️',
    ),
    Product(
      id: 'P002',
      name: 'Ergonomic Gaming Mouse',
      description: 'Ultra-lightweight mouse with high-precision 26k DPI sensor.',
      price: 50000,
      imageUrl: '🖱️',
    ),
    Product(
      id: 'P003',
      name: 'Noise Cancelling Headset',
      description: 'Over-ear headphones with active noise cancellation and clear mic.',
      price: 250000,
      imageUrl: '🎧',
    ),
    Product(
      id: 'P004',
      name: '4K Ultra-Wide Monitor',
      description: '34-inch curved monitor perfect for productivity and gaming.',
      price: 1000000,
      imageUrl: '🖥️',
    ),
  ];

  final Map<String, int> _cart = {};
  late final AppLinks _appLinks;
  StreamSubscription? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinking();
    _initFirebaseMessaging();
  }

  void _initFirebaseMessaging() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got an FCM message in the foreground!');
        if (message.notification != null) {
          _showPaymentResultDialog(
            title: message.notification!.title ?? 'Transaction Alert',
            message: message.notification!.body ?? '',
            isSuccess: true,
          );
        }
      });
    } catch (e) {
      debugPrint("FCM listener setup skipped: $e");
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _initDeepLinking() {
    _appLinks = AppLinks();
    
    // Listen to incoming deep links (scheme: ecommerce://)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (!mounted) return;
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('Deep Link Error: $err');
    });

    // Check initial link when app starts from cold boot
    _appLinks.getInitialLink().then((uri) {
      if (uri != null && mounted) {
        _handleDeepLink(uri);
      }
    });
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Received Deep Link: $uri');
    if (uri.scheme == 'ecommerce' && uri.host == 'callback') {
      final status = uri.queryParameters['status'];
      final trxId = uri.queryParameters['trx_id'] ?? 'N/A';
      final amount = uri.queryParameters['amount'] ?? '0';
      final recipient = uri.queryParameters['recipient_email'] ?? 'N/A';

      if (status == 'success') {
        _showPaymentResultDialog(
          title: 'Payment Successful',
          message: 'Your payment of Rp ${currencyFormat(int.parse(amount))} to $recipient was processed successfully.\n\nTransaction ID: $trxId',
          isSuccess: true,
        );
        setState(() {
          _cart.clear(); // Clear cart on success
        });
      } else {
        final errorMsg = uri.queryParameters['error'] ?? 'Transaction was cancelled by user.';
        _showPaymentResultDialog(
          title: 'Payment Failed',
          message: 'Error: $errorMsg\n\nTransaction ID: $trxId',
          isSuccess: false,
        );
      }
    }
  }

  void _showPaymentResultDialog({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          isSuccess ? Icons.check_circle : Icons.error,
          color: isSuccess ? Colors.green : Colors.red,
          size: 60,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String currencyFormat(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  int get _cartTotal {
    int total = 0;
    _cart.forEach((productId, quantity) {
      final prod = _products.firstWhere((p) => p.id == productId);
      total += prod.price * quantity;
    });
    return total;
  }

  void _addToCart(Product product) {
    setState(() {
      _cart[product.id] = (_cart[product.id] ?? 0) + 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to cart'),
        duration: const Duration(seconds: 1),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            setState(() {
              if (_cart[product.id]! > 1) {
                _cart[product.id] = _cart[product.id]! - 1;
              } else {
                _cart.remove(product.id);
              }
            });
          },
        ),
      ),
    );
  }

  void _openCheckoutSheet() {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your cart is empty!')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Checkout Summary',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ..._cart.entries.map((entry) {
              final prod = _products.firstWhere((p) => p.id == entry.key);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${prod.name} (x${entry.value})', style: const TextStyle(fontSize: 14)),
                    Text('Rp ${currencyFormat(prod.price * entry.value)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  'Rp ${currencyFormat(_cartTotal)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _triggerEMoneyPayment();
              },
              icon: const Icon(Icons.wallet, color: Colors.white),
              label: const Text('Pay with E-Money (Wallet)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _triggerEMoneyPayment() async {
    // 1. Generate unique transaction identifier
    final trxId = 'TX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    
    // 2. Define payment request parameters
    final amount = _cartTotal;
    const merchantEmail = 'recipient@example.com'; // recipient seeded email in GORM backend
    const callbackUrl = 'ecommerce://callback';
    
    // 3. Construct deep link scheme
    // Scheme format: emoney://pay?amount=XXX&recipient=XXX&trx_id=XXX&callback=XXX
    final deepLinkUri = Uri.parse(
      'emoney://pay?amount=$amount'
      '&recipient=$merchantEmail'
      '&trx_id=$trxId'
      '&callback=${Uri.encodeComponent(callbackUrl)}'
    );

    debugPrint('Launching E-Money Deep Link: $deepLinkUri');

    // 4. Launch the deep link to E-Money Wallet application
    if (await canLaunchUrl(deepLinkUri)) {
      await launchUrl(deepLinkUri, mode: LaunchMode.externalApplication);
    } else {
      // Wallet app not installed or scheme unsupported
      _showAppNotInstalledDialog(deepLinkUri);
    }
  }

  void _showAppNotInstalledDialog(Uri fallbackUri) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('E-Money App Not Found'),
        content: const Text(
          'The E-Money Wallet application is not installed on this device. '
          'Please install the wallet application to continue with the App-to-App payment integration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // In production, direct to play store. In testing, show link details
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Deep Link Telemetry'),
                  content: SelectableText('Deep Link Uri:\n$fallbackUri'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('OK'),
                    )
                  ],
                ),
              );
            },
            child: const Text('View Deep Link Uri'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Merchant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                onPressed: _openCheckoutSheet,
              ),
              if (_cart.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _cart.values.fold(0, (sum, val) => sum + val).toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final prod = _products[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Text(
                    prod.imageUrl,
                    style: const TextStyle(fontSize: 40),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prod.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          prod.description,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Rp ${currencyFormat(prod.price)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_shopping_cart, color: Colors.teal),
                    onPressed: () => _addToCart(prod),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: _cart.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openCheckoutSheet,
              backgroundColor: Colors.teal,
              icon: const Icon(Icons.shopping_bag, color: Colors.white),
              label: Text(
                'Checkout (Rp ${currencyFormat(_cartTotal)})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}

// Tested with local Android Emulator and localhost loopbacks.


// Tested with local Android Emulator and localhost loopbacks.


// Typo fixes.

