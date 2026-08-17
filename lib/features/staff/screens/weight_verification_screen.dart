import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../engines/order_load_engine.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/order_provider.dart';

class _ImageProcessingRequest {
  const _ImageProcessingRequest(this.bytes, this.transaction, this.weight, this.timestamp);

  final Uint8List bytes;
  final String transaction;
  final double weight;
  final String timestamp;
}

Uint8List? _processImage(_ImageProcessingRequest request) {
  return WeightVerificationScreen.generateWatermarkedProofBytes(
    request.bytes,
    request.transaction,
    request.weight,
    request.timestamp,
  );
}

class WeightVerificationScreen extends StatefulWidget {
  final String orderId;

  const WeightVerificationScreen({super.key, required this.orderId});

  static Uint8List? generateWatermarkedProofBytes(
    Uint8List bytes,
    String transaction,
    double weight,
    String timestamp,
  ) {
    try {
      final original = img.decodeImage(bytes);
      if (original == null) return null;

      // 1280px retains legibility for a scale display while avoiding a
      // multi-megabyte camera original being encoded and uploaded.
      const maxSide = 1280;
      final resized = original.width > maxSide || original.height > maxSide
          ? (original.width >= original.height
              ? img.copyResize(original, width: maxSide)
              : img.copyResize(original, height: maxSide))
          : original;

      // Four watermark lines need a little more room on landscape photos.
      final overlayHeight = (resized.height * 0.28).toInt();
      img.fillRect(
        resized,
        x1: 0,
        y1: resized.height - overlayHeight,
        x2: resized.width,
        y2: resized.height,
        color: img.ColorRgba8(0, 0, 0, 180),
      );

      final padding = (resized.width * 0.04).toInt();
      var yPos = resized.height - overlayHeight + (padding / 2).toInt();
      final useLargeFont = overlayHeight >= 260;
      final font = useLargeFont ? img.arial48 : img.arial24;
      final lineSpacing = useLargeFont ? 55 : 30;

      img.drawString(
        resized,
        'SCALE WEIGHT VERIFICATION',
        font: font,
        x: padding,
        y: yPos,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      yPos += lineSpacing;
      img.drawString(
        resized,
        'Transaction: $transaction',
        font: font,
        x: padding,
        y: yPos,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      yPos += lineSpacing;
      img.drawString(
        resized,
        'Weight: ${weight.toStringAsFixed(2)} kg',
        font: font,
        x: padding,
        y: yPos,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      yPos += lineSpacing;
      img.drawString(
        resized,
        'Captured: $timestamp',
        font: font,
        x: padding,
        y: yPos,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      return Uint8List.fromList(img.encodeJpg(resized, quality: 78));
    } catch (e) {
      debugPrint('Sync processing error: $e');
      return null;
    }
  }

  @override
  State<WeightVerificationScreen> createState() =>
      _WeightVerificationScreenState();
}

class _WeightVerificationScreenState extends State<WeightVerificationScreen> {
  final _weightController = TextEditingController();
  Uint8List? _evidenceBytes;
  bool _submitting = false;
  String? _submissionProgress;
  int? _originalImageBytes;
  int? _finalImageBytes;
  int? _processingMilliseconds;
  String? _proofId;
  String? _proofBase64;

  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _showCamera = false;

  @override
  void dispose() {
    _weightController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      debugPrint('Initializing camera...');
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras found. Please ensure your camera is connected and allowed.');
      }

      debugPrint('Found ${cameras.length} cameras.');

      // Prefer rear camera (environment)
      CameraDescription? selectedCamera;
      try {
        selectedCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
      } catch (_) {
        selectedCamera = cameras.first;
      }

      debugPrint('Selected camera: ${selectedCamera.name}');

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium, // Optimized: Medium (720p approx) is enough for scale reading and much faster
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraReady = true;
        });
      }
      debugPrint('Camera initialized successfully.');
    } catch (e) {
      debugPrint('CAMERA INITIALIZATION ERROR: $e');
      if (mounted) {
        setState(() {
          _showCamera = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CAMERA ERROR: $e'), 
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
          ),
        );
      }
    }
  }

  Future<void> _takePicture(OrderModel order) async {
    if (_cameraController == null || !_isCameraReady) return;

    final weight = double.tryParse(_weightController.text.trim());
    if (weight == null || !weight.isFinite || weight <= 0) {
      _message('Enter a valid actual weight before capturing the scale photo.');
      return;
    }

    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      await _cameraController?.dispose();

      if (!mounted) return;
      setState(() {
        _submitting = true;
        _submissionProgress = 'Processing photo...';
        _showCamera = false;
        _isCameraReady = false;
        _cameraController = null;
      });

      final processingWatch = Stopwatch()..start();
      final proof = await _prepareProof(bytes, order, weight);
      processingWatch.stop();
      if (proof == null) throw Exception('Image processing failed. Please retake the photo.');

      debugPrint(
        'Weight proof prepared: original=${bytes.lengthInBytes}B, '
        'final=${proof.lengthInBytes}B, processing=${processingWatch.elapsedMilliseconds}ms',
      );
      if (!mounted) return;
      setState(() {
        // The preview and upload both use this one final JPEG.
        _evidenceBytes = proof;
        _originalImageBytes = bytes.lengthInBytes;
        _finalImageBytes = proof.lengthInBytes;
        _processingMilliseconds = processingWatch.elapsedMilliseconds;
        _proofId = null;
        _proofBase64 = null;
        _submissionProgress = null;
        _submitting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submissionProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickEvidence() async {
    // One live-camera path on Android and Web; no picker or gallery fallback.
    setState(() {
      _showCamera = true;
    });
    await _initializeCamera();
  }

  Future<Uint8List?> _prepareProof(
    Uint8List capturedBytes,
    OrderModel order,
    double weight,
  ) async {
    final transaction = order.transactionNumber ?? order.id.toUpperCase().substring(0, 12);
    final now = DateTime.now();
    final timestamp = DateFormat('MMM dd, yyyy hh:mm a').format(now);
    return compute(
      _processImage,
      _ImageProcessingRequest(capturedBytes, transaction, weight, timestamp),
    );
  }

  Future<void> _submit(OrderModel order, String staffId) async {
    final weightText = _weightController.text.trim();
    final weight = double.tryParse(weightText);
    
    if (weight == null || !weight.isFinite || weight <= 0) {
      _message('Enter a valid actual weight.');
      return;
    }
    if (_evidenceBytes == null) {
      _message('A scale photo is required.');
      return;
    }
    
    setState(() {
      _submitting = true;
      _submissionProgress = 'Saving verification...';
    });
    final orderProvider = context.read<OrderProvider>();
    final totalWatch = Stopwatch()..start();

    try {
      _proofBase64 ??= base64Encode(_evidenceBytes!);
      _proofId ??= const Uuid().v4();

      // Base64 is about 4/3 the final JPEG size. Keep the proof document
      // comfortably below Firestore's 1 MiB document limit after metadata.
      const maxProofBase64Bytes = 700 * 1024;
      final base64Bytes = utf8.encode(_proofBase64!).length;
      debugPrint('WEIGHT PROOF ORIGINAL SIZE: ${_originalImageBytes ?? 0} bytes');
      debugPrint('WEIGHT PROOF FINAL JPEG SIZE: ${_evidenceBytes!.lengthInBytes} bytes');
      debugPrint('WEIGHT PROOF BASE64 SIZE: $base64Bytes bytes');
      if (base64Bytes > maxProofBase64Bytes) {
        throw Exception(
          'The processed scale proof is too large to save safely. Please retake the photo.',
        );
      }

      final firestoreWatch = Stopwatch()..start();
      debugPrint('WEIGHT FIRESTORE SAVE START order=${order.id}');
      final submitted = await orderProvider.submitWeightVerification(
            orderId: order.id,
            staffId: staffId,
            actualWeight: weight,
            proofId: _proofId!,
            proofBase64: _proofBase64!,
          );
      firestoreWatch.stop();
      debugPrint(
        'WEIGHT FIRESTORE SAVE COMPLETE order=${order.id} '
        'success=$submitted in ${firestoreWatch.elapsedMilliseconds}ms',
      );
      totalWatch.stop();
      debugPrint(
        'Weight proof submitted: original=${_originalImageBytes ?? 0}B, '
        'final=${_finalImageBytes ?? _evidenceBytes!.lengthInBytes}B, '
        'processing=${_processingMilliseconds ?? 0}ms, '
        'firestore=${firestoreWatch.elapsedMilliseconds}ms, '
        'total=${totalWatch.elapsedMilliseconds}ms',
      );
      if (!submitted) {
        // Reuse the same proof ID/Base64 if the staff retries a failed
        // transaction; a second proof document is never generated.
        debugPrint('WEIGHT PROOF RETAINED for Firestore retry order=${order.id}');
      }
      if (mounted) {
        _message(submitted
            ? 'Weight submitted successfully.'
            : 'Could not submit the weight verification.');
        if (submitted) {
          debugPrint('WEIGHT SUBMISSION COMPLETE order=${order.id}');
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        _message(errorMessage.startsWith('The processed scale proof')
            ? errorMessage
            : 'Weight submission failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submissionProgress = null;
        });
      }
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final staffId = context.watch<AuthProvider>().user?.id ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Weight Verification')),
      body: StreamBuilder<OrderModel?>(
        stream: context.read<OrderProvider>().streamOrderById(widget.orderId),
        builder: (context, snapshot) {
          final order = snapshot.data;
          if (order == null) return const Center(child: CircularProgressIndicator());
          if (order.assignedTo != staffId && order.staffId != staffId) {
            return const Center(child: Text('This transaction is not assigned to you.'));
          }
          final locked = order.weightStatus == 'submitted' || order.isWeightVerified;
          if (_weightController.text.isEmpty && order.actualWeight != null) {
            _weightController.text = order.actualWeight!.toString();
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Weight Verification V2 (Camera Only)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      _row('Declared Weight', '${order.weight.toStringAsFixed(2)} kg'),
                      _row('Estimated Weight', '${order.displayedEstimatedWeight.toStringAsFixed(2)} kg'),
                      _row(
                        'Actual Weight',
                        order.isWeightVerified && order.actualWeight != null
                            ? '${order.actualWeight!.toStringAsFixed(2)} kg'
                            : 'Not verified',
                      ),
                      _row(
                        'Required Loads',
                        order.isWeightVerified && order.actualWeight != null
                            ? '${OrderLoadEngine.computeNumberOfLoads(order.actualWeight!)} machine cycles'
                            : 'Pending verification',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _weightController,
                        enabled: !locked && !_submitting,
                        onChanged: (_) {
                          if (_evidenceBytes != null && !_submitting) {
                            setState(() {
                              // A proof is tied to its entered weight. Require
                              // a retake instead of submitting a mismatched
                              // watermark after the field is edited.
                              _evidenceBytes = null;
                              _originalImageBytes = null;
                              _finalImageBytes = null;
                              _processingMilliseconds = null;
                              _proofId = null;
                              _proofBase64 = null;
                            });
                          }
                        },
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Actual Weight (kg)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!locked && !_showCamera)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _submitting ? null : _pickEvidence,
                            icon: const Icon(Icons.videocam, size: 24),
                            label: Text(
                              _evidenceBytes == null ? 'OPEN AUTHENTIC CAMERA' : 'RETAKE PHOTO',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      if (_showCamera) ...[
                        const SizedBox(height: 12),
                        if (_isCameraReady && _cameraController != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: _cameraController!.value.aspectRatio,
                              child: CameraPreview(_cameraController!),
                            ),
                          )
                        else
                          const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.close),
                                label: const Text('CANCEL CAMERA'),
                                onPressed: () {
                                  _cameraController?.dispose();
                                  setState(() {
                                    _showCamera = false;
                                    _isCameraReady = false;
                                    _cameraController = null;
                                  });
                                },
                                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('CAPTURE SCALE PROOF'),
                                onPressed: _isCameraReady && !_submitting
                                    ? () => _takePicture(order)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_evidenceBytes != null && !_showCamera) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_evidenceBytes!, height: 180, width: double.infinity, fit: BoxFit.cover),
                        ),
                        if (_originalImageBytes != null && _finalImageBytes != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Optimized ${_formatBytes(_originalImageBytes!)} to ${_formatBytes(_finalImageBytes!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                      if (order.weightStatus == 'rejected') ...[
                        const SizedBox(height: 12),
                        Text('Rejected: ${order.weightVerificationNote ?? 'Please submit a corrected measurement.'}', style: const TextStyle(color: Colors.red)),
                      ],
                      if (locked) ...[
                        const SizedBox(height: 12),
                        Text(order.isWeightVerified ? 'Weight verified by admin.' : 'Awaiting admin verification.'),
                        if (order.weightSubmittedAt != null)
                          Text('Submitted ${DateHelper.formatDateTime(order.weightSubmittedAt!)}'),
                      ],
                      if (!locked) ...[
                        if (_submissionProgress != null) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Text(_submissionProgress!),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        const Divider(),
                        const Center(
                          child: Text(
                            'SYSTEM AUDIT: CAMERA-ONLY MODE ACTIVE',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                            onPressed: _submitting ? null : () => _submit(order, staffId),
                            icon: const Icon(Icons.verified_outlined),
                            label: Text(_submissionProgress ?? 'Submit Weight for Admin Verification'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
      );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}
