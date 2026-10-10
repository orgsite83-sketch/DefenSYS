import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

// ==========================================
// INTERACTIVE SIGNATURE DRAWING PAD DIALOG
// ==========================================

class SignatureDrawDialog extends StatefulWidget {
  const SignatureDrawDialog({super.key});

  @override
  State<SignatureDrawDialog> createState() => _SignatureDrawDialogState();
}

class _SignatureDrawDialogState extends State<SignatureDrawDialog> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  bool _isSaving = false;

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
    });
  }

  Future<Uint8List?> _renderPngBytes() async {
    if (_strokes.isEmpty && _currentStroke.isEmpty) return null;

    const width = 600.0;
    const height = 240.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    final paint = Paint()
      ..color =
          const Color(0xFF0F172A) // Dark slate ink
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    final allStrokes = [..._strokes];
    if (_currentStroke.isNotEmpty) {
      allStrokes.add(_currentStroke);
    }

    for (final stroke in allStrokes) {
      if (stroke.length < 2) {
        if (stroke.isNotEmpty) {
          canvas.drawCircle(
            stroke.first,
            1.75,
            paint..style = PaintingStyle.fill,
          );
          paint.style = PaintingStyle.stroke;
        }
        continue;
      }
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    try {
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      img.dispose();
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasStrokes = _strokes.isNotEmpty || _currentStroke.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(
                      Icons.draw_rounded,
                      color: DefensysTokens.maroon,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Digital E-Signature Pad',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Use your mouse or touchscreen to draw your signature in the box below.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),

                // Canvas pad container
                Container(
                  width: double.infinity,
                  height: 240,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        // Dashed baseline
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 45,
                          child: Container(
                            height: 1,
                            color: const Color(0xFFCBD5E1),
                          ),
                        ),
                        Positioned(
                          right: 20,
                          bottom: 16,
                          child: Text(
                            'SIGNATURE LINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade400,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        // Interactive Drawing Area
                        GestureDetector(
                          onPanStart: (details) {
                            setState(() {
                              _currentStroke = [details.localPosition];
                            });
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              _currentStroke.add(details.localPosition);
                            });
                          },
                          onPanEnd: (details) {
                            setState(() {
                              if (_currentStroke.isNotEmpty) {
                                _strokes.add(List.from(_currentStroke));
                                _currentStroke = [];
                              }
                            });
                          },
                          child: CustomPaint(
                            key: const ValueKey('signature-drawing-pad'),
                            size: Size.infinite,
                            painter: _SignaturePainter(
                              strokes: _strokes,
                              currentStroke: _currentStroke,
                            ),
                          ),
                        ),
                        if (!hasStrokes)
                          IgnorePointer(
                            child: Center(
                              child: Text(
                                'Sign here',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: hasStrokes ? _clear : null,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Clear Pad'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, null),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton.icon(
                          onPressed: hasStrokes && !_isSaving
                              ? () async {
                                  setState(() => _isSaving = true);
                                  final bytes = await _renderPngBytes();
                                  if (context.mounted) {
                                    Navigator.pop(context, bytes);
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save & Apply'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DefensysTokens.maroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;

  _SignaturePainter({required this.strokes, required this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    final allStrokes = [...strokes];
    if (currentStroke.isNotEmpty) {
      allStrokes.add(currentStroke);
    }

    for (final stroke in allStrokes) {
      if (stroke.length < 2) {
        if (stroke.isNotEmpty) {
          canvas.drawCircle(
            stroke.first,
            1.75,
            paint..style = PaintingStyle.fill,
          );
          paint.style = PaintingStyle.stroke;
        }
        continue;
      }
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
