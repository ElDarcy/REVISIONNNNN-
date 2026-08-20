import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../services/pickup_service.dart';

/// Staff screen for verifying customer pickup via QR scan or PIN fallback.
///
/// Flow:
/// 1. Camera scans QR code containing pickup token
/// 2. If scan fails, staff can enter 6-digit PIN manually
/// 3. Calls PickupService.verifyPickup() to validate
/// 4. Shows success/failure result with "Transaction LT-XXXX" terminology
class PickupVerificationScreen extends StatefulWidget {
  const PickupVerificationScreen({super.key});

  @override
  State<PickupVerificationScreen> createState() =>
      _PickupVerificationScreenState();
}

class _PickupVerificationScreenState extends State<PickupVerificationScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _cameraController;
  bool _isProcessing = false;
  bool _showPinEntry = false;
  String? _errorMessage;
  Map<String, dynamic>? _result;

  // PIN entry controllers
  final List<TextEditingController> _pinControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(6, (_) => FocusNode());

  // Success animation
  late AnimationController _animController;
  late Animation<double> _animScale;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    for (final c in _pinControllers) {
      c.dispose();
    }
    for (final f in _pinFocusNodes) {
      f.dispose();
    }
    _animController.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final token = barcode.rawValue!;
    _verify(token: token);
  }

  Future<void> _verify({String? token, String? code}) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _result = null;
    });

    final staffId = context.read<AuthProvider>().user?.id ?? '';
    final orderProvider = context.read<OrderProvider>();
    final result = await PickupService.verifyPickup(
      token: token,
      code: code,
      staffId: staffId,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      // Collect any outstanding balance before handing over the laundry.
      final orderId = result['orderId'] as String?;
      if (orderId != null) {
        final order = await orderProvider.getOrderById(orderId);
        if (mounted && order != null && order.outstandingBalance > 0) {
          await _collectOutstandingBalance(order);
        }
      }

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _result = result;
      });
      _animController.forward(from: 0.0);
      _showSuccessDialog();
    } else {
      setState(() {
        _isProcessing = false;
        _errorMessage = result['message']?.toString() ?? 'Verification failed.';
      });
      // Clear PIN boxes on failure
      for (final c in _pinControllers) {
        c.clear();
      }
      if (_showPinEntry && _pinFocusNodes.isNotEmpty) {
        _pinFocusNodes[0].requestFocus();
      }
    }
  }

  Future<void> _collectOutstandingBalance(OrderModel order) async {
    var method = 'Cash';
    final amount = order.outstandingBalance;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.payments_outlined, color: AppColors.warning, size: 28),
                SizedBox(width: 8),
                Text('Collect Balance'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance Due: ₱${amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Collect this remaining balance from the customer before handing over the laundry.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Cash'),
                      selected: method == 'Cash',
                      onSelected: (_) => setDialogState(() => method = 'Cash'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('GCash'),
                      selected: method == 'GCash',
                      onSelected: (_) => setDialogState(() => method = 'GCash'),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: const Text('Confirm Collection', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final staffId = context.read<AuthProvider>().user?.id ?? '';
    final success = await context.read<OrderProvider>().collectBalance(
          orderId: order.id,
          staffId: staffId,
          amount: amount,
          method: method,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Balance collected.' : 'Failed to collect balance.',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  void _showSuccessDialog() {
    // Build the display ID from transactionNumber or fallback to orderId
    final txnNumber = _result?['transactionNumber'] as String?;
    final orderId = _result?['orderId'] as String?;
    final customerName = _result?['customerName'] as String?;

    // Use transactionNumber directly — it's the LT-YYYY-NNNN format
    final displayId = txnNumber ?? (orderId != null ? 'Transaction ${orderId.substring(0, 8).toUpperCase()}' : 'Transaction');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _animScale,
              builder: (context, child) {
                return Transform.scale(
                  scale: _animScale.value,
                  child: child,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 64,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Pickup Verified!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Transaction',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              displayId,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            if (customerName != null && customerName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Customer: $customerName',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Pickup verified successfully.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // close dialog
                Navigator.pop(context); // go back to staff home
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Done',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submitPin() {
    final code = _pinControllers.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() {
        _errorMessage = 'Please enter the complete 6-digit code.';
      });
      return;
    }
    _verify(code: code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Pickup'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _showPinEntry ? _buildPinEntry() : _buildQrScanner(),
    );
  }

  Widget _buildQrScanner() {
    return Column(
      children: [
        // Camera view
        Expanded(
          flex: 3,
          child: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(
                controller: _cameraController!,
                onDetect: _onBarcodeDetected,
              ),
              // Scanning overlay
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              if (_isProcessing)
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        // Controls
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Point camera at customer\'s pickup QR code',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Need help? Ask the customer for their pickup PIN.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _showPinEntry = true;
                      _errorMessage = null;
                    }),
                    icon: const Icon(Icons.dialpad),
                    label: const Text('Enter Code Manually'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPinEntry() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline, size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            'Enter Pickup Code',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the customer for their 6-digit pickup PIN.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 32),

          // OTP-style PIN input — 6 separate boxes, masked, centered
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              return Container(
                width: 48,
                height: 56,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _pinFocusNodes[index].hasFocus
                        ? AppColors.primary
                        : Colors.grey.shade300,
                    width: _pinFocusNodes[index].hasFocus ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: _pinControllers[index].text.isNotEmpty
                      ? AppColors.primary.withValues(alpha: 0.05)
                      : null,
                ),
                child: TextField(
                  controller: _pinControllers[index],
                  focusNode: _pinFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  maxLength: 1,
                  obscureText: true,
                  obscuringCharacter: '\u2022',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: (value) {
                    setState(() {}); // Rebuild to update box color
                    if (value.isNotEmpty && index < 5) {
                      _pinFocusNodes[index + 1].requestFocus();
                    } else if (value.isEmpty && index > 0) {
                      _pinFocusNodes[index - 1].requestFocus();
                    }
                    if (index == 5 && value.isNotEmpty) {
                      _submitPin();
                    }
                  },
                ),
              );
            }),
          ),

          const SizedBox(height: 24),

          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _submitPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Verify Pickup',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
            ),
          ),

          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() {
              _showPinEntry = false;
              _errorMessage = null;
              for (final c in _pinControllers) {
                c.clear();
              }
            }),
            child: const Text('Back to QR Scanner'),
          ),
        ],
      ),
    );
  }
}
