import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../export/defensys_pdf_viewer.dart';

class MinutesReviewDialog extends StatelessWidget {
  const MinutesReviewDialog({
    super.key,
    required this.pdfBytes,
    required this.panelists,
    required this.hasSignature,
  });
  final Uint8List pdfBytes;
  final Map<String, bool> panelists;
  final bool hasSignature;
  bool get ready =>
      panelists.isNotEmpty &&
      panelists.values.every((done) => done) &&
      hasSignature;

  @override
  Widget build(BuildContext context) {
    final checklist = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Before you sign',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final panelist in panelists.entries)
          _check(panelist.key, panelist.value),
        _check('E-signature uploaded', hasSignature),
        const SizedBox(height: 12),
        const Text(
          'Signing locks these minutes and sends them to the project adviser for review. The administrator signs last as chairman.',
        ),
      ],
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 1100,
        height: MediaQuery.sizeOf(context).height * .9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Review minutes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Back to editing',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pdf = DefensysPdfViewer(pdfBytes: pdfBytes);
                  return constraints.maxWidth >= 800
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 7, child: pdf),
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: checklist,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(
                              height: constraints.maxHeight * .38,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: checklist,
                              ),
                            ),
                            Expanded(child: pdf),
                          ],
                        );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Back to editing'),
                  ),
                  FilledButton(
                    onPressed: ready
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text('Sign and submit'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _check(String label, bool done) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(
          done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ],
    ),
  );
}
