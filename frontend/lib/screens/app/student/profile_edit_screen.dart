import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';

import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../services/authenticated_client.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../toasts/feedback_toast.dart';

MediaType _inferMediaType(String filename) {
  final ext = filename.toLowerCase().split('.').last;
  if (ext == 'jpg' || ext == 'jpeg') return MediaType('image', 'jpeg');
  if (ext == 'webp') return MediaType('image', 'webp');
  return MediaType('image', 'png');
}

class StudentProfile {
  String name;
  String email;
  String studentId;
  String team;
  Uint8List? avatarBytes;

  StudentProfile({
    required this.name,
    required this.email,
    required this.studentId,
    required this.team,
    this.avatarBytes,
  });
}

/// Profile screen for all roles (student, faculty, admin).
///
/// - Displays user info in a dense, high-impact web layout.
/// - Provides E-Signature management (interactive canvas drawing & PNG file upload).
/// - Provides Change Password form with strength & validation rules.
/// - Shows real-time Activity Audit Trail.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _isLoadingHistory = false;
  List<dynamic> _history = [];
  String? _historyError;

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSavingPassword = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingSignature = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetchHistory());
  }

  @override
  void dispose() {
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final response = await client.get(
        Uri.parse('${ApiConfig.baseUrl}/me/history/'),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _history = data['history'] ?? [];
          _isLoadingHistory = false;
        });
      } else {
        setState(() {
          _historyError = 'Failed to load history (${response.statusCode})';
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _historyError = 'Connection error: $e';
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final name = file.name.toLowerCase();
      final isSupported = name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.webp');
      if (!isSupported) {
        if (!mounted) return;
        showErrorToast(context, 'Unsupported format. Select JPEG, PNG, or WEBP.');
        return;
      }

      if (file.size > 10 * 1024 * 1024) {
        if (!mounted) return;
        showErrorToast(context, 'Image size must not exceed 10MB.');
        return;
      }

      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        showErrorToast(context, 'Failed to read image data.');
        return;
      }

      setState(() => _isUploadingAvatar = true);

      final client = ref.read(authenticatedHttpClientProvider);
      final request = http.MultipartRequest(
        'PATCH',
        Uri.parse('${ApiConfig.baseUrl}/me/'),
      );

      request.files.add(http.MultipartFile.fromBytes(
        'avatar',
        bytes,
        filename: file.name,
        contentType: _inferMediaType(file.name),
      ));

      final streamedResponse = await client.sendAuthenticated(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);

      if (response.statusCode == 200) {
        final updatedUser = jsonDecode(response.body);
        ref.read(authProvider.notifier).updateCurrentUser(updatedUser);
        showSuccessToast(context, 'Profile picture updated successfully!');
      } else {
        final data = jsonDecode(response.body);
        showErrorToast(context, data['detail'] ?? 'Failed to upload picture.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        showErrorToast(context, 'Upload error: $e');
      }
    }
  }

  Future<void> _deleteAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove Photo'),
        content: const Text('Are you sure you want to remove your profile picture?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final response = await client.patch(
        Uri.parse('${ApiConfig.baseUrl}/me/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'remove_avatar': 'true'}),
      );

      if (!mounted) return;
      setState(() => _isUploadingAvatar = false);

      if (response.statusCode == 200) {
        final updatedUser = jsonDecode(response.body);
        ref.read(authProvider.notifier).updateCurrentUser(updatedUser);
        showSuccessToast(context, 'Profile picture removed.');
      } else {
        final data = jsonDecode(response.body);
        showErrorToast(context, data['detail'] ?? 'Failed to remove photo.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        showErrorToast(context, 'Connection error: $e');
      }
    }
  }

  // --- E-SIGNATURE LOGIC ---

  Future<void> _uploadSignatureBytes(Uint8List bytes, String filename) async {
    setState(() => _isUploadingSignature = true);
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final request = http.MultipartRequest(
        'PATCH',
        Uri.parse('${ApiConfig.baseUrl}/me/'),
      );

      request.files.add(http.MultipartFile.fromBytes(
        'e_signature',
        bytes,
        filename: filename,
        contentType: _inferMediaType(filename),
      ));

      final streamedResponse = await client.sendAuthenticated(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;
      setState(() => _isUploadingSignature = false);

      if (response.statusCode == 200) {
        final updatedUser = jsonDecode(response.body);
        ref.read(authProvider.notifier).updateCurrentUser(updatedUser);
        showSuccessToast(context, 'E-Signature updated successfully!');
      } else {
        final data = jsonDecode(response.body);
        showErrorToast(context, data['detail'] ?? 'Failed to upload e-signature.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingSignature = false);
        showErrorToast(context, 'Upload error: $e');
      }
    }
  }

  Future<void> _pickAndUploadSignatureImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final name = file.name.toLowerCase();
      final isSupported = name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.webp');
      if (!isSupported) {
        if (!mounted) return;
        showErrorToast(context, 'Unsupported format. Select PNG, JPEG, or WEBP.');
        return;
      }

      if (file.size > 10 * 1024 * 1024) {
        if (!mounted) return;
        showErrorToast(context, 'Signature image must not exceed 10MB.');
        return;
      }

      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        showErrorToast(context, 'Failed to read image file.');
        return;
      }

      await _uploadSignatureBytes(bytes, file.name);
    } catch (e) {
      if (mounted) showErrorToast(context, 'Error picking signature file: $e');
    }
  }

  Future<void> _openSignatureDrawDialog() async {
    final Uint8List? signatureBytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SignatureDrawDialog(),
    );

    if (signatureBytes != null && signatureBytes.isNotEmpty) {
      await _uploadSignatureBytes(signatureBytes, 'drawn_signature.png');
    }
  }

  Future<void> _deleteSignature() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove E-Signature'),
        content: const Text('Are you sure you want to remove your stored digital signature?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Remove Signature'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUploadingSignature = true);
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final response = await client.patch(
        Uri.parse('${ApiConfig.baseUrl}/me/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'remove_e_signature': 'true'}),
      );

      if (!mounted) return;
      setState(() => _isUploadingSignature = false);

      if (response.statusCode == 200) {
        final updatedUser = jsonDecode(response.body);
        ref.read(authProvider.notifier).updateCurrentUser(updatedUser);
        showSuccessToast(context, 'E-Signature removed.');
      } else {
        final data = jsonDecode(response.body);
        showErrorToast(context, data['detail'] ?? 'Failed to remove signature.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingSignature = false);
        showErrorToast(context, 'Connection error: $e');
      }
    }
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingPassword = true);
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final response = await client.post(
        Uri.parse('${ApiConfig.authUrl}/change-password/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'current_password': _currentPassCtrl.text,
          'new_password': _newPassCtrl.text,
          'confirm_password': _confirmPassCtrl.text,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        _currentPassCtrl.clear();
        _newPassCtrl.clear();
        _confirmPassCtrl.clear();
        setState(() {});
        showSuccessToast(context, 'Password changed successfully!');
      } else {
        dynamic data;
        try {
          data = jsonDecode(response.body);
        } catch (_) {
          data = null;
        }
        final errorMsg = data != null ? _extractError(data) : 'Server error (${response.statusCode}). Please try again later.';
        showErrorToast(context, errorMsg);
      }
    } catch (e) {
      if (mounted) showErrorToast(context, 'Connection error: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _isSavingPassword = false);
    }
  }

  String _extractError(dynamic data) {
    if (data is Map) {
      for (final key in ['detail', 'current_password', 'new_password', 'confirm_password', 'non_field_errors']) {
        final val = data[key];
        if (val is String && val.isNotEmpty) return val;
        if (val is List && val.isNotEmpty) return val.first.toString();
      }
      return data.values.firstWhere(
        (v) => v is String && v.isNotEmpty,
        orElse: () => 'Failed to change password.',
      ).toString();
    }
    return 'Failed to change password.';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    final displayName = name.isNotEmpty ? name : (user['username'] ?? 'User');
    final username = user['username'] ?? '';
    final email = user['email'] ?? '';
    final role = (user['role'] ?? 'student') as String;
    final roleLabel = role[0].toUpperCase() + role.substring(1);
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 100
      appBar: kIsWeb
          ? null
          : AppBar(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
              title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
              elevation: 0,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Hero Card Banner
            _buildHeroBanner(displayName, username, email, roleLabel, user, isWide),
                const SizedBox(height: 20),

                // Main Content Grid
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Identity & E-Signature
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            _buildIdentityCard(displayName, username, email, roleLabel, user),
                            const SizedBox(height: 20),
                            _buildESignatureCard(user),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Right Column: Security & Activity Feed
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: [
                            _buildChangePasswordCard(username, email),
                            const SizedBox(height: 20),
                            _buildHistoryCard(),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildIdentityCard(displayName, username, email, roleLabel, user),
                      const SizedBox(height: 20),
                      _buildESignatureCard(user),
                      const SizedBox(height: 20),
                      _buildChangePasswordCard(username, email),
                      const SizedBox(height: 20),
                      _buildHistoryCard(),
                    ],
                  ),
              ],
            ),
        ),
    );
  }

  // --- HERO BANNER ---

  Widget _buildHeroBanner(
    String displayName,
    String username,
    String email,
    String roleLabel,
    Map<String, dynamic> user,
    bool isWide,
  ) {
    final avatarUrl = user['avatar'] != null
        ? ApiConfig.publicMediaUrl(user['avatar'] as String)
        : null;

    final facultyRoles = user['facultyRoles'] as Map<String, dynamic>? ?? {};
    final isPanelist = facultyRoles['panelist'] == true || user['is_panelist'] == true;
    final isPitLead = facultyRoles['pitLead'] == true || user['is_pit_lead'] == true;
    final isAdviser = facultyRoles['adviser'] == true || user['is_adviser'] == true;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DefensysTokens.maroon,
            const Color(0xFF520B13),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: DefensysTokens.maroon.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
            child: Flex(
              direction: isWide ? Axis.horizontal : Axis.vertical,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment:
                  isWide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar stack with quick upload trigger
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white38, width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 42,
                            backgroundColor: Colors.white24,
                            backgroundImage:
                                avatarUrl != null ? NetworkImage(avatarUrl) : null,
                            child: avatarUrl == null
                                ? Text(
                                    displayName.isNotEmpty
                                        ? displayName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        if (_isUploadingAvatar)
                          Positioned.fill(
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: _pickAndUploadAvatar,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 16,
                                color: DefensysTokens.maroon,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  roleLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            email.isNotEmpty ? email : 'No email provided',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          // Additional Capability Tags
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _badgeTag('ID: $username', Icons.badge_outlined),
                              if (user['team_id'] != null)
                                _badgeTag(
                                  'Team #${user['team_id']}',
                                  Icons.groups_outlined,
                                ),
                              if (isPitLead)
                                _badgeTag('PIT Leader', Icons.stars_rounded),
                              if (isPanelist)
                                _badgeTag('Panelist', Icons.assignment_ind_outlined),
                              if (isAdviser)
                                _badgeTag('Adviser', Icons.school_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isWide) const SizedBox(height: 16),
                // Action Buttons for Avatar
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                      icon: const Icon(Icons.upload_file_rounded, size: 16),
                      label: const Text('Change Photo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    if (avatarUrl != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _isUploadingAvatar ? null : _deleteAvatar,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: Color(0xFFFCA5A5),
                        ),
                        label: const Text(
                          'Remove',
                          style: TextStyle(color: Color(0xFFFCA5A5)),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
    );
  }

  Widget _badgeTag(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  // --- IDENTITY CARD ---

  Widget _buildIdentityCard(
    String displayName,
    String username,
    String email,
    String roleLabel,
    Map<String, dynamic> user,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: DefensysTokens.maroon,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Identity & Account Details',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),
          _detailGridItem('Full Name', displayName, Icons.account_circle_outlined),
          const SizedBox(height: 14),
          _detailGridItem('Username / ID', username, Icons.badge_outlined),
          const SizedBox(height: 14),
          _detailGridItem(
            'Email Address',
            email.isNotEmpty ? email : 'Not set',
            Icons.email_outlined,
          ),
          const SizedBox(height: 14),
          _detailGridItem('System Role', roleLabel, Icons.admin_panel_settings_outlined),
          if (user['team_id'] != null) ...[
            const SizedBox(height: 14),
            _detailGridItem(
              'Team Assignment',
              'Team #${user['team_id']}',
              Icons.group_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailGridItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- E-SIGNATURE CARD ---

  Widget _buildESignatureCard(Map<String, dynamic> user) {
    final eSigPath = user['e_signature']?.toString();
    final eSigUrl = eSigPath != null && eSigPath.isNotEmpty
        ? ApiConfig.publicMediaUrl(eSigPath)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.draw_rounded,
                      size: 18,
                      color: DefensysTokens.maroon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Official E-Signature',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: eSigUrl != null
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      eSigUrl != null
                          ? Icons.check_circle_rounded
                          : Icons.pending_outlined,
                      size: 12,
                      color: eSigUrl != null
                          ? const Color(0xFF166534)
                          : const Color(0xFF92400E),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      eSigUrl != null ? 'Configured' : 'Not Set',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: eSigUrl != null
                            ? const Color(0xFF166534)
                            : const Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),

          // Signature Preview Box (styled like a document signing box)
          Container(
            width: double.infinity,
            height: 130,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFCBD5E1),
                style: BorderStyle.solid,
              ),
            ),
            child: Stack(
              children: [
                // Dashed baseline indicator for signature
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 30,
                  child: Container(
                    height: 1,
                    color: const Color(0xFFCBD5E1),
                  ),
                ),
                Positioned(
                  right: 30,
                  bottom: 12,
                  child: Text(
                    'SIGNATURE BASELINE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade400,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (_isUploadingSignature)
                  const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DefensysTokens.maroon,
                    ),
                  )
                else if (eSigUrl != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.network(
                        eSigUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined, color: Colors.red),
                            SizedBox(height: 4),
                            Text(
                              'Failed to load signature',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.gesture_rounded,
                          size: 32,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No e-signature on file',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Draw or upload a PNG image with transparent background',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUploadingSignature
                      ? null
                      : _openSignatureDrawDialog,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Draw Signature'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DefensysTokens.maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isUploadingSignature
                      ? null
                      : _pickAndUploadSignatureImage,
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Upload Image'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              if (eSigUrl != null) ...[
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _isUploadingSignature ? null : _deleteSignature,
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  tooltip: 'Remove signature',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE2E2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your signature will be embedded into defense evaluation reports and official panel minutes.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- CHANGE PASSWORD CARD ---

  Widget _buildChangePasswordCard(String username, String email) {
    final newPass = _newPassCtrl.text;
    final confirmPass = _confirmPassCtrl.text;

    final isMinLength = newPass.length >= 8;
    final hasLetters = RegExp(r'[A-Za-z]').hasMatch(newPass);
    final hasNumbersOrSymbols = RegExp(r'[0-9!@#$%^&*(),.?":{}|<>]').hasMatch(newPass);
    final hasMix = hasLetters && hasNumbersOrSymbols;
    
    final notSimilarToUser = username.isEmpty || !newPass.toLowerCase().contains(username.toLowerCase());
    final notSimilarToEmail = email.isEmpty || !newPass.toLowerCase().contains(email.split('@').first.toLowerCase());
    final isNotSimilar = notSimilarToUser && notSimilarToEmail;
    
    final isMatch = confirmPass.isNotEmpty && newPass == confirmPass;

    // Strength score calculation
    int strengthScore = 0;
    if (newPass.isNotEmpty) {
      if (isMinLength) strengthScore++;
      if (hasMix) strengthScore++;
      if (isNotSimilar && newPass.length >= 10) strengthScore++;
    }

    String strengthText = 'Too short';
    Color strengthColor = const Color(0xFFEF4444); // Red
    double strengthPercent = 0.2;

    if (newPass.isEmpty) {
      strengthText = 'Enter password';
      strengthColor = const Color(0xFF94A3B8);
      strengthPercent = 0.0;
    } else if (strengthScore == 1) {
      strengthText = 'Weak';
      strengthColor = const Color(0xFFEF4444);
      strengthPercent = 0.33;
    } else if (strengthScore == 2) {
      strengthText = 'Fair';
      strengthColor = const Color(0xFFF59E0B);
      strengthPercent = 0.66;
    } else if (strengthScore == 3) {
      strengthText = 'Strong';
      strengthColor = const Color(0xFF10B981);
      strengthPercent = 1.0;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: DefensysTokens.maroon,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Security & Password',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),

            _passwordField(
              controller: _currentPassCtrl,
              label: 'Current Password',
              obscure: _obscureCurrent,
              onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
              validator: (v) => v == null || v.isEmpty ? 'Enter current password' : null,
            ),
            const SizedBox(height: 12),
            _passwordField(
              controller: _newPassCtrl,
              label: 'New Password',
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter new password';
                if (v.length < 8) return 'Minimum 8 characters required';
                if (!isNotSimilar) return 'Password is too similar to your username or email';
                return null;
              },
            ),

            if (newPass.isNotEmpty) ...[
              const SizedBox(height: 10),
              // Password Policy Guidance Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 15, color: DefensysTokens.maroon),
                        SizedBox(width: 8),
                        Text(
                          'Password Guidelines & Accepted Characters',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Allowed: Letters (A-Z, a-z), Numbers (0-9), and Symbols (! @ # \$ % ^ & * _ + - =)\n'
                      '• Restrictions: Min 8 characters; cannot be too similar to your username or email; cannot be a common password.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Strength bar
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: strengthPercent,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    strengthText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: strengthColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Requirement Checklist
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  children: [
                    _reqCheckItem('At least 8 characters long', isMinLength),
                    const SizedBox(height: 4),
                    _reqCheckItem('Contains letters and numbers/symbols', hasMix),
                    const SizedBox(height: 4),
                    _reqCheckItem('Not similar to your username ($username) or email', isNotSimilar),
                    const SizedBox(height: 4),
                    _reqCheckItem('Matches confirmation password', isMatch),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            _passwordField(
              controller: _confirmPassCtrl,
              label: 'Confirm New Password',
              obscure: _obscureConfirm,
              onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Confirm new password';
                if (v != _newPassCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSavingPassword ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysTokens.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: _isSavingPassword
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Update Password',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reqCheckItem(String label, bool isSatisfied) {
    return Row(
      children: [
        Icon(
          isSatisfied ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: isSatisfied ? const Color(0xFF10B981) : Colors.grey.shade400,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSatisfied ? FontWeight.w600 : FontWeight.normal,
              color: isSatisfied ? const Color(0xFF0F172A) : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        prefixIcon: const Icon(Icons.key_outlined, size: 18),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
        ),
      ),
    );
  }

  // --- HISTORY CARD ---

  Widget _buildHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_toggle_off_rounded,
                      size: 18,
                      color: DefensysTokens.maroon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Activity History',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18, color: DefensysTokens.maroon),
                onPressed: _isLoadingHistory ? null : _fetchHistory,
                tooltip: 'Refresh Activity Log',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),

          if (_isLoadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: CircularProgressIndicator(color: DefensysTokens.maroon),
              ),
            )
          else if (_historyError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 32, color: Colors.red),
                    const SizedBox(height: 6),
                    Text(
                      _historyError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _fetchHistory,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_history.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  children: [
                    Icon(Icons.history_rounded, size: 36, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text(
                      'No recent actions recorded.',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 340),
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _history.length,
                  separatorBuilder: (context, index) => const Divider(
                    height: 16,
                    color: Color(0xFFF8FAFC),
                  ),
                  itemBuilder: (context, index) {
                    final log = _history[index];
                    final rawAction = log['action'] ?? 'Unknown Action';
                    final action = _formatActionText(rawAction);
                    final category = log['category'] ?? '';
                    final categoryLabel = log['category_label'] ?? category;
                    final reason = log['reason'] ?? '';
                    final createdAtStr = log['created_at'];

                    String formattedDate = '';
                    if (createdAtStr != null) {
                      try {
                        final dt = DateTime.parse(createdAtStr).toLocal();
                        formattedDate = DateFormat('MMM d, yyyy h:mm a').format(dt);
                      } catch (_) {
                        formattedDate = createdAtStr;
                      }
                    }

                    IconData iconData = Icons.info_outline;
                    switch (category) {
                      case 'academic_period':
                        iconData = Icons.calendar_month_outlined;
                        break;
                      case 'grade_center':
                        iconData = Icons.grade_outlined;
                        break;
                      case 'scheduling':
                        iconData = Icons.event_outlined;
                        break;
                      case 'student_teams':
                        iconData = Icons.group_outlined;
                        break;
                      case 'repository':
                        iconData = Icons.folder_shared_outlined;
                        break;
                      case 'guest_access':
                        iconData = Icons.vpn_key_outlined;
                        break;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(iconData, size: 16, color: const Color(0xFF475569)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: DefensysTokens.maroon.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        categoryLabel,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: DefensysTokens.maroon,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      formattedDate,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  action,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                if (reason.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Reason: $reason',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatActionText(String rawAction) {
    final customMappings = {
      'rubric.create': 'Created Rubric',
      'rubric.update': 'Updated Rubric',
      'rubric.delete': 'Deleted Rubric',
      'semester.active_switch': 'Switched Active Semester',
      'academic_period.create': 'Created Academic Period',
      'academic_period.update': 'Updated Academic Period',
      'academic_period.delete': 'Deleted Academic Period',
      'grade.publish': 'Published Grades',
      'grade.update': 'Updated Grades',
      'scheduling.create': 'Created Schedule',
      'scheduling.update': 'Updated Schedule',
      'scheduling.delete': 'Deleted Schedule',
      'student_teams.create': 'Created Student Team',
      'student_teams.update': 'Updated Student Team',
      'repository.upload': 'Uploaded Document',
      'repository.delete': 'Deleted Document',
      'guest_access.grant': 'Granted Guest Access',
      'guest_access.revoke': 'Revoked Guest Access',
    };

    if (customMappings.containsKey(rawAction)) {
      return customMappings[rawAction]!;
    }

    if (rawAction.contains('.')) {
      final parts = rawAction.split('.');
      if (parts.length == 2) {
        final subject = parts[0];
        final verb = parts[1];

        String formattedVerb = verb;
        switch (verb) {
          case 'create':
            formattedVerb = 'Created';
            break;
          case 'update':
            formattedVerb = 'Updated';
            break;
          case 'delete':
            formattedVerb = 'Deleted';
            break;
          case 'upload':
            formattedVerb = 'Uploaded';
            break;
          case 'publish':
            formattedVerb = 'Published';
            break;
          case 'grant':
            formattedVerb = 'Granted';
            break;
          case 'revoke':
            formattedVerb = 'Revoked';
            break;
          case 'switch':
            formattedVerb = 'Switched';
            break;
          case 'active_switch':
            formattedVerb = 'Switched Active';
            break;
          default:
            if (verb.isNotEmpty) {
              formattedVerb =
                  verb[0].toUpperCase() + verb.substring(1).replaceAll('_', ' ');
            }
        }

        final formattedSubject = subject.isNotEmpty
            ? subject[0].toUpperCase() + subject.substring(1).replaceAll('_', ' ')
            : '';
        return '$formattedVerb $formattedSubject'.trim();
      }
    }

    return rawAction
        .split(RegExp(r'[\._]'))
        .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
        .join(' ');
  }
}

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
      ..color = const Color(0xFF0F172A) // Dark slate ink
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
          canvas.drawCircle(stroke.first, 1.75, paint..style = PaintingStyle.fill);
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
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final hasStrokes = _strokes.isNotEmpty || _currentStroke.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.draw_rounded, color: DefensysTokens.maroon),
                      SizedBox(width: 10),
                      Text(
                        'Digital E-Signature Pad',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
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
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
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
                        child: Container(height: 1, color: const Color(0xFFCBD5E1)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
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
          canvas.drawCircle(stroke.first, 1.75, paint..style = PaintingStyle.fill);
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
