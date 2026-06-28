import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../services/auth_provider.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/e_signature_provider.dart';
import '../../../widgets/confirm_dialog.dart';

class ESignatureUploadDialog extends ConsumerStatefulWidget {
  const ESignatureUploadDialog({super.key});

  @override
  ConsumerState<ESignatureUploadDialog> createState() => _ESignatureUploadDialogState();
}

class _ESignatureUploadDialogState extends ConsumerState<ESignatureUploadDialog> {
  bool _isLoading = false;
  bool _isFetchingSignature = false;
  Uint8List? _existingSignatureBytes;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _fetchExistingSignature();
  }

  Future<void> _fetchExistingSignature() async {
    final user = ref.read(authProvider).user;
    final signaturePath = user?['e_signature']?.toString();
    if (signaturePath == null || signaturePath.isEmpty) return;

    setState(() {
      _isFetchingSignature = true;
      _errorMessage = null;
    });

    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final bytes = await client.fetchAuthenticatedFile(signaturePath);
      if (mounted) {
        setState(() {
          _existingSignatureBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load existing signature image: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingSignature = false;
        });
      }
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        setState(() {
          _errorMessage = 'Could not read file data. Please try again.';
        });
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final success = await ref.read(eSignatureProvider).uploadSignature(
        file.bytes!,
        file.name,
      );

      if (success) {
        if (mounted) {
          setState(() {
            _successMessage = 'E-signature uploaded successfully.';
            _isLoading = false;
          });
        }
        await _fetchExistingSignature();
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Upload failed. Please ensure the file is a valid image (PNG/JPG).';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error picking/uploading file: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteSignature() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove E-Signature',
      message: 'Are you sure you want to remove your uploaded e-signature? You will not be able to sign minutes of defense until you upload a new one.',
      confirmLabel: 'Remove',
      cancelLabel: 'Cancel',
      destructive: true,
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final success = await ref.read(eSignatureProvider).deleteSignature();
      if (success) {
        if (mounted) {
          setState(() {
            _existingSignatureBytes = null;
            _successMessage = 'E-signature removed successfully.';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to remove e-signature.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error removing e-signature: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final hasSignature = user?['e_signature'] != null && user?['e_signature'] != '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 24,
      backgroundColor: Colors.white,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.draw_rounded, color: DefensysTokens.maroon, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'E-Signature Settings',
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          color: DefensysTokens.textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?['name']?.toString() ?? 'Faculty User',
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                ),
              ],
            ),
            const Divider(height: 32),
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          color: Color(0xFF991B1B),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_successMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF16A34A), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          color: Color(0xFF166534),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'Your e-signature will be automatically attached to capstone defense minutes of defense when you submit or review them.',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                color: Color(0xFF4B5563),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _isFetchingSignature
                    ? const Center(child: CircularProgressIndicator())
                    : hasSignature && _existingSignatureBytes != null
                        ? Stack(
                            children: [
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Image.memory(
                                    _existingSignatureBytes!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check, color: Colors.green.shade700, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Active',
                                        style: TextStyle(
                                          fontFamily: DefensysTokens.fontFamily,
                                          color: Colors.green.shade800,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.drive_file_rename_outline_rounded, color: Colors.grey.shade400, size: 40),
                                const SizedBox(height: 8),
                                Text(
                                  'No signature uploaded yet',
                                  style: TextStyle(
                                    fontFamily: DefensysTokens.fontFamily,
                                    color: Colors.grey.shade500,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (hasSignature) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      onPressed: _isLoading ? null : _deleteSignature,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: BorderSide(color: Colors.red.shade200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Icon(hasSignature ? Icons.sync_rounded : Icons.upload_file_rounded, size: 18),
                    label: Text(hasSignature ? 'Replace Image' : 'Upload Image'),
                    onPressed: _isLoading ? null : _pickAndUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: DefensysTokens.gold,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      disabledBackgroundColor: Colors.grey.shade200,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
