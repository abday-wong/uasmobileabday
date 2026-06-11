import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  runApp(const EMoneyWalletApp());
}

class EMoneyWalletApp extends StatelessWidget {
  const EMoneyWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Money Wallet',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFDE59),
          primary: const Color(0xFFFFDE59),
          secondary: const Color(0xFF38BDF8),
        ),
        fontFamily: 'Courier New',
        useMaterial3: true,
      ),
      home: const WalletMainScreen(),
    );
  }
}

// ==========================================
// NEUBRUTALISM CUSTOM WIDGETS
// ==========================================

class BrutalCard extends StatelessWidget {
  final Widget child;
  final Color backgroundColor;
  final double borderWidth;
  final double shadowOffset;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const BrutalCard({
    super.key,
    required this.child,
    this.backgroundColor = Colors.white,
    this.borderWidth = 3.0,
    this.shadowOffset = 4.0,
    this.borderRadius = 8.0,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.black, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black,
            offset: Offset(shadowOffset, shadowOffset),
            blurRadius: 0.0,
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

class BrutalButton extends StatefulWidget {
  final Widget child;
  final Color backgroundColor;
  final VoidCallback? onPressed;

  const BrutalButton({
    super.key,
    required this.child,
    this.backgroundColor = const Color(0xFF38BDF8),
    this.onPressed,
  });

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<BrutalButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: isEnabled ? (_) {
        setState(() => _isPressed = false);
        widget.onPressed!();
      } : null,
      onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        transform: Matrix4.translationValues(
          _isPressed ? 2.0 : 0.0,
          _isPressed ? 2.0 : 0.0,
          0.0,
        ),
        decoration: BoxDecoration(
          color: isEnabled ? widget.backgroundColor : Colors.grey[300],
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.black, width: 3.0),
          boxShadow: _isPressed
              ? []
              : const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(3.0, 3.0),
                    blurRadius: 0.0,
                  ),
                ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 24.0),
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

class BrutalTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final IconData? prefixIcon;
  final bool enabled;
  final TextInputType keyboardType;
  final Widget? suffix;

  const BrutalTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.prefixIcon,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.black, width: 3.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(3.0, 3.0),
            blurRadius: 0.0,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontFamily: 'Courier New'),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Courier New'),
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Colors.black) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

// ==========================================
// MAIN SCREEN CONTROLLER
// ==========================================

class WalletMainScreen extends StatefulWidget {
  const WalletMainScreen({super.key});

  @override
  State<WalletMainScreen> createState() => _WalletMainScreenState();
}

class _WalletMainScreenState extends State<WalletMainScreen> {
  // Config: Adjust this based on where your backend is running.
  // 10.0.2.2 is the alias to host loopback interface in Android Emulator.
  final String _backendUrl = 'http://10.0.2.2:8080/v1';

  String? _jwtToken;
  String? _userEmail;
  int _balance = 0;
  bool _totpEnabled = false;
  bool _isLoading = false;

  // Login Controllers
  final TextEditingController _loginEmailController = TextEditingController(text: 'test@example.com');
  final TextEditingController _otpConfirmController = TextEditingController();
  bool _otpSent = false;
  String? _debugOtp; // Store debug OTP returned by backend in test mode

  // Transaction Deep Link Data
  Map<String, String>? _pendingTrx;

  late final AppLinks _appLinks;
  StreamSubscription? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinking();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _loginEmailController.dispose();
    _otpConfirmController.dispose();
    super.dispose();
  }

  void _initDeepLinking() {
    _appLinks = AppLinks();

    // Listen to incoming deep links (scheme: emoney://)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (!mounted) return;
      _handleIncomingDeepLink(uri);
    }, onError: (err) {
      debugPrint('Deep Link Error: $err');
    });

    // Check initial link on cold start
    _appLinks.getInitialLink().then((uri) {
      if (uri != null && mounted) {
        _handleIncomingDeepLink(uri);
      }
    });
  }

  void _handleIncomingDeepLink(Uri uri) {
    debugPrint('Received Deep Link: $uri');
    if (uri.scheme == 'emoney' && uri.host == 'pay') {
      final amount = uri.queryParameters['amount'];
      final recipient = uri.queryParameters['recipient'];
      final trxId = uri.queryParameters['trx_id'];
      final callback = uri.queryParameters['callback'];

      if (amount != null && recipient != null && trxId != null && callback != null) {
        setState(() {
          _pendingTrx = {
            'amount': amount,
            'recipient': recipient,
            'trx_id': trxId,
            'callback': callback,
          };
        });

        // Prompt payment confirmation UI if logged in, otherwise let user login first
        if (_jwtToken != null) {
          _openPaymentConfirmationDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to complete your payment request.', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  // API Call: Request Email OTP
  Future<void> _requestEmailOTP() async {
    final email = _loginEmailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/otp/send-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          _otpSent = true;
          _debugOtp = data['otp']; // For test environment convenience
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OTP sent to $email. (Debug OTP: ${_debugOtp ?? ''})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            backgroundColor: const Color(0xFF38BDF8),
          ),
        );
      } else {
        _showErrorSnackBar(data['error'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      _showErrorSnackBar('Network Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // API Call: Confirm OTP and retrieve JWT token
  Future<void> _confirmOTP() async {
    final email = _loginEmailController.text.trim();
    final otp = _otpConfirmController.text.trim();
    if (email.isEmpty || otp.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/otp/confirm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          _jwtToken = data['token'];
          _userEmail = data['user']['email'];
          _balance = data['user']['balance'];
          _totpEnabled = data['user']['totp_enabled'] ?? false;
          _otpConfirmController.clear();
          _otpSent = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully authenticated!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            backgroundColor: Color(0xFF38BDF8),
          ),
        );

        // Fetch latest profile
        _fetchUserProfile();

        // Check if there was a pending transaction deep link waiting
        if (_pendingTrx != null) {
          _openPaymentConfirmationDialog();
        }
      } else {
        _showErrorSnackBar(data['error'] ?? 'Incorrect OTP code');
      }
    } catch (e) {
      _showErrorSnackBar('Network Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // API Call: Get Profile details
  Future<void> _fetchUserProfile() async {
    if (_jwtToken == null) return;

    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _balance = data['balance'];
          _totpEnabled = data['totp_enabled'] ?? false;
        });
      }
    } catch (e) {
      debugPrint('Failed to refresh profile: $e');
    }
  }

  // Open QR Setup for TOTP Authenticator
  Future<void> _setupGoogleAuthenticator() async {
    if (_jwtToken == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/otp/totp/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final String secret = data['secret'];
        final String qrCodeUrl = data['qr_code_url'];
        _showTOTPRegistrationDialog(secret, qrCodeUrl);
      } else {
        _showErrorSnackBar(data['error'] ?? 'Failed to register TOTP');
      }
    } catch (e) {
      _showErrorSnackBar('Network Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Dialog: Show QR Code to user (Neubrutalism Styled)
  void _showTOTPRegistrationDialog(String secret, String qrUrl) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0),
            side: const BorderSide(color: Colors.black, width: 3),
          ),
          backgroundColor: Colors.white,
          title: const Text('2FA CONFIGURATION', style: TextStyle(fontWeight: FontWeight.extrabold, color: Colors.black)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '1. Scan QR code in Authenticator App:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: Border.all(color: Colors.black, width: 2),
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    data: qrUrl,
                    version: QrVersions.auto,
                    size: 160.0,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Secret Key:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(height: 4),
                Container(
                  color: const Color(0xFFFFDE59),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  border: Border.all(color: Colors.black, width: 2),
                  child: SelectableText(
                    secret,
                    style: const TextStyle(fontWeight: FontWeight.extrabold, fontSize: 14, color: Colors.black),
                  ),
                ),
                const Divider(height: 32, color: Colors.black, thickness: 2),
                const Text('2. Confirm 6-Digit Code:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(height: 12),
                BrutalTextField(
                  controller: textController,
                  labelText: 'ENTER AUTH CODE',
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = textController.text.trim();
                if (code.length != 6) return;

                final verifyRes = await http.post(
                  Uri.parse('$_backendUrl/otp/totp/verify'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $_jwtToken',
                  },
                  body: jsonEncode({'code': code}),
                );

                if (verifyRes.statusCode == 200) {
                  Navigator.of(context).pop();
                  _fetchUserProfile(); // Reload profile status
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('TOTP Security Enabled!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      backgroundColor: Color(0xFFFFDE59),
                    ),
                  );
                } else {
                  final data = jsonDecode(verifyRes.body);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(data['error'] ?? 'Incorrect verification code')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.black, width: 2)),
              ),
              child: const Text('ACTIVATE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Open payment confirmation screen (Neubrutalism Dialog)
  void _openPaymentConfirmationDialog() {
    if (_pendingTrx == null) return;

    final int amount = int.parse(_pendingTrx!['amount']!);
    final String recipient = _pendingTrx!['recipient']!;
    final String trxId = _pendingTrx!['trx_id']!;

    if (_balance < amount) {
      _cancelTransaction(errorMsg: 'Insufficient wallet balance (Rp ${currencyFormat(_balance)})');
      return;
    }

    final otpTextController = TextEditingController();
    bool localOtpRequested = false;
    String? localDebugOtp;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (ctx, dialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: Colors.black, width: 3),
          ),
          title: Container(
            color: const Color(0xFFFFDE59),
            padding: const EdgeInsets.all(8),
            border: const Border(bottom: BorderSide(color: Colors.black, width: 3)),
            child: const Text(
              'TRANSACTION_AUTHORIZATION',
              style: TextStyle(fontWeight: FontWeight.extrabold, color: Colors.black, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          titlePadding: EdgeInsets.zero,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('RECIPIENT:', style: TextStyle(fontWeight: FontWeight.extrabold, color: Colors.black, fontSize: 12)),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[200],
                border: Border.all(color: Colors.black, width: 2),
                child: Text(recipient, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
              ),
              const SizedBox(height: 12),
              const Text('TOTAL DEBIT:', style: TextStyle(fontWeight: FontWeight.extrabold, color: Colors.black, fontSize: 12)),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFFFDE59),
                border: Border.all(color: Colors.black, width: 2),
                child: Text(
                  'Rp ${currencyFormat(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.extrabold, fontSize: 22, color: Colors.black),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Current Balance:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12)),
                  Text('Rp ${currencyFormat(_balance)}', style: const TextStyle(fontWeight: FontWeight.extrabold, fontSize: 12, color: Colors.black)),
                ],
              ),
              const Divider(height: 24, color: Colors.black, thickness: 2),

              if (_totpEnabled) ...[
                const Text('Enter 6-Digit Authenticator Code (2FA):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                BrutalTextField(
                  controller: otpTextController,
                  labelText: '2FA CODE',
                  keyboardType: TextInputType.number,
                ),
              ] else ...[
                const Text('Enter 6-Digit Email OTP (2FA):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: BrutalTextField(
                        controller: otpTextController,
                        labelText: 'OTP CODE',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    BrutalButton(
                      backgroundColor: const Color(0xFFFFDE59),
                      onPressed: localOtpRequested
                          ? null
                          : () async {
                              final response = await http.post(
                                Uri.parse('$_backendUrl/otp/send-email'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({'email': _userEmail}),
                              );
                              if (response.statusCode == 200) {
                                final data = jsonDecode(response.body);
                                dialogState(() {
                                  localOtpRequested = true;
                                  localDebugOtp = data['otp'];
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('OTP sent to your email successfully.')),
                                );
                              }
                            },
                      child: Text(localOtpRequested ? 'SENT' : 'SEND', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12)),
                    ),
                  ],
                ),
                if (localDebugOtp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text('Debug OTP Code: $localDebugOtp', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _cancelTransaction(errorMsg: 'Payment declined by user.');
              },
              child: const Text('DECLINE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.extrabold)),
            ),
            ElevatedButton(
              onPressed: () async {
                final otpCode = otpTextController.text.trim();
                if (otpCode.isEmpty) return;

                final response = await http.post(
                  Uri.parse('$_backendUrl/payment/transfer'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $_jwtToken',
                  },
                  body: jsonEncode({
                    'recipient_email': recipient,
                    'amount': amount,
                    'otp': otpCode,
                    'otp_type': _totpEnabled ? 'totp' : 'email',
                  }),
                );

                final data = jsonDecode(response.body);
                if (response.statusCode == 200) {
                  Navigator.of(context).pop(); // Close dialog
                  _completePaymentSuccess(amount, recipient, trxId);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(data['error'] ?? 'Authentication failed', style: const TextStyle(fontWeight: FontWeight.bold)),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.black, width: 2)),
              ),
              child: const Text('AUTHORIZE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Complete Payment and redirect back to E-Commerce using callback URI
  void _completePaymentSuccess(int amount, String recipient, String trxId) async {
    final callback = _pendingTrx!['callback']!;

    final callbackUri = Uri.parse(
      '$callback?status=success'
      '&trx_id=$trxId'
      '&amount=$amount'
      '&recipient_email=${Uri.encodeComponent(recipient)}'
    );

    setState(() {
      _pendingTrx = null;
    });

    _fetchUserProfile();

    debugPrint('Launching Callback Link: $callbackUri');
    if (await canLaunchUrl(callbackUri)) {
      await launchUrl(callbackUri, mode: LaunchMode.externalApplication);
    } else {
      _showCallbackErrorDialog(callbackUri);
    }
  }

  // Decline or fail payment
  void _cancelTransaction({required String errorMsg}) async {
    if (_pendingTrx == null) return;

    final callback = _pendingTrx!['callback']!;
    final trxId = _pendingTrx!['trx_id']!;

    final callbackUri = Uri.parse(
      '$callback?status=failed'
      '&trx_id=$trxId'
      '&error=${Uri.encodeComponent(errorMsg)}'
    );

    setState(() {
      _pendingTrx = null;
    });

    debugPrint('Launching Failure Callback Link: $callbackUri');
    if (await canLaunchUrl(callbackUri)) {
      await launchUrl(callbackUri, mode: LaunchMode.externalApplication);
    } else {
      _showCallbackErrorDialog(callbackUri);
    }
  }

  void _showCallbackErrorDialog(Uri uri) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Colors.black, width: 3)),
        title: const Text('REDIRECT FAILURE', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Could not open callback redirection scheme automatically. Copy link below:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey[100],
              border: Border.all(color: Colors.black, width: 2),
              child: SelectableText(uri.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.red,
      ),
    );
  }

  String currencyFormat(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = _jwtToken != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WALLET_SYSTEM', style: TextStyle(color: Colors.black, fontWeight: FontWeight.extrabold, fontFamily: 'Courier New')),
        backgroundColor: const Color(0xFFFFDE59),
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Colors.black, width: 4)),
        actions: [
          if (isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: BrutalButton(
                backgroundColor: const Color(0xFF38BDF8),
                onPressed: () {
                  setState(() {
                    _jwtToken = null;
                    _userEmail = null;
                    _balance = 0;
                    _totpEnabled = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged out.')),
                  );
                },
                child: const Text('LOGOUT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12)),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: isLoggedIn ? _buildWalletDashboard() : _buildLoginScreen(),
            ),
    );
  }

  // Screen layout: Login Form (Neubrutalism Theme)
  Widget _buildLoginScreen() {
    return BrutalCard(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Icon(Icons.account_balance_wallet_outlined, size: 70, color: Colors.black),
          ),
          const SizedBox(height: 16),
          const Text(
            'SECURE_WALLET_ACCESS',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.extrabold, color: Colors.black),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Verify account identity using multi-factor credentials.',
            style: TextStyle(color: Colors.black55, fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          BrutalTextField(
            controller: _loginEmailController,
            labelText: 'EMAIL ADDRESS',
            prefixIcon: Icons.email,
            enabled: !_otpSent,
          ),
          const SizedBox(height: 20),
          if (_otpSent) ...[
            BrutalTextField(
              controller: _otpConfirmController,
              labelText: 'OTP VERIFICATION CODE',
              prefixIcon: Icons.lock_open,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
          ],
          BrutalButton(
            backgroundColor: const Color(0xFFFFDE59),
            onPressed: _otpSent ? _confirmOTP : _requestEmailOTP,
            child: Text(
              _otpSent ? 'CONFIRM AUTHENTICATION' : 'REQUEST OTP CODE',
              style: const TextStyle(fontWeight: FontWeight.extrabold, fontSize: 14, color: Colors.black),
            ),
          ),
          if (_otpSent) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _otpSent = false;
                  _otpConfirmController.clear();
                });
              },
              child: const Text('CHANGE EMAIL ADDRESS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
            ),
          ],
        ],
      ),
    );
  }

  // Screen layout: Wallet Dashboard (Neubrutalism Theme)
  Widget _buildWalletDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Balance Banner
        BrutalCard(
          backgroundColor: const Color(0xFFFFDE59),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('WALLET BALANCE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.extrabold, fontSize: 13)),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.black, size: 24),
                    onPressed: _fetchUserProfile,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Rp ${currencyFormat(_balance)}',
                style: const TextStyle(color: Colors.black, fontSize: 28, fontWeight: FontWeight.extrabold, letterSpacing: 1),
              ),
              const Divider(color: Colors.black, thickness: 1.5, height: 20),
              Text(
                'SESSION: $_userEmail',
                style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Deep Link payment reminder banner if active
        if (_pendingTrx != null) ...[
          BrutalCard(
            backgroundColor: const Color(0xFF38BDF8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.black),
                    SizedBox(width: 8),
                    Text(
                      'PENDING TRANSACTION!',
                      style: TextStyle(fontWeight: FontWeight.extrabold, color: Colors.black, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Merchant requests payment: Rp ${currencyFormat(int.parse(_pendingTrx!['amount']!))}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    BrutalButton(
                      backgroundColor: Colors.red[300]!,
                      onPressed: () => _cancelTransaction(errorMsg: 'Cancelled by user'),
                      child: const Text('DECLINE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 11)),
                    ),
                    const SizedBox(width: 12),
                    BrutalButton(
                      backgroundColor: const Color(0xFFFFDE59),
                      onPressed: _openPaymentConfirmationDialog,
                      child: const Text('REVIEW PAY', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // 2FA Security Configurations
        BrutalCard(
          backgroundColor: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock, color: Colors.black),
                  SizedBox(width: 8),
                  Text('SECURITY_SETUP', style: TextStyle(fontWeight: FontWeight.extrabold, fontSize: 14)),
                ],
              ),
              const Divider(color: Colors.black, thickness: 1.5, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('GOOGLE AUTHENTICATOR (2FA)', style: TextStyle(fontWeight: FontWeight.extrabold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          _totpEnabled ? 'STATUS: ENABLED' : 'STATUS: NOT ACTIVE (Email OTP Fallback)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _totpEnabled ? Colors.green[800] : Colors.orange[800]),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _totpEnabled ? Icons.verified_user : Icons.gpp_maybe,
                    color: _totpEnabled ? Colors.green[800] : Colors.orange[800],
                    size: 28,
                  )
                ],
              ),
              const SizedBox(height: 16),
              if (!_totpEnabled)
                BrutalButton(
                  backgroundColor: const Color(0xFFFFDE59),
                  onPressed: _setupGoogleAuthenticator,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner, color: Colors.black, size: 18),
                      SizedBox(width: 8),
                      Text('REGISTER AUTHENTICATOR', style: TextStyle(fontWeight: FontWeight.extrabold, color: Colors.black, fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// Verified with TOTP verification and local secure sessions.

