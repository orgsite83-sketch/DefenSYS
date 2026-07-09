import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';


import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../services/authenticated_client.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/feedback_toast.dart';

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
/// - Displays user info as read-only (name, ID, email, role, team).
/// - Provides a Change Password form (current + new + confirm).
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

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetchHistory());
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
        showErrorToast(context, 'Unsupported format. Please select JPEG, PNG, or WEBP.');
        return;
      }

      if (file.size > 10 * 1024 * 1024) {
        showErrorToast(context, 'Image size must not exceed 10MB.');
        return;
      }

      final bytes = file.bytes;
      if (bytes == null) {
        showErrorToast(context, 'Failed to read image data.');
        return;
      }

      setState(() => _isSaving = true);

      final client = ref.read(authenticatedHttpClientProvider);
      final request = http.MultipartRequest(
        'PATCH',
        Uri.parse('${ApiConfig.baseUrl}/me/'),
      );

      request.files.add(http.MultipartFile.fromBytes(
        'avatar',
        bytes,
        filename: file.name,
      ));

      final streamedResponse = await client.sendAuthenticated(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (response.statusCode == 200) {
        final updatedUser = jsonDecode(response.body);
        ref.read(authProvider.notifier).updateCurrentUser(updatedUser);
        showSuccessToast(context, 'Profile picture updated successfully!');
      } else {
        final data = jsonDecode(response.body);
        showErrorToast(context, data['detail'] ?? 'Failed to upload profile picture.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
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

    setState(() => _isSaving = true);
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final response = await client.patch(
        Uri.parse('${ApiConfig.baseUrl}/me/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'remove_avatar': 'true'}),
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (response.statusCode == 200) {
        final updatedUser = jsonDecode(response.body);
        ref.read(authProvider.notifier).updateCurrentUser(updatedUser);
        showSuccessToast(context, 'Profile picture removed.');
      } else {
        final data = jsonDecode(response.body);
        showErrorToast(context, data['detail'] ?? 'Failed to remove profile picture.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showErrorToast(context, 'Connection error: $e');
      }
    }
  }

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
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
        showSuccessToast(context, 'Password changed successfully!');
      } else {
        final data = jsonDecode(response.body);
        final errorMsg = _extractError(data);
        showErrorToast(context, errorMsg);
      }
    } catch (e) {
      if (mounted) showErrorToast(context, 'Connection error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _extractError(dynamic data) {
    if (data is Map) {
      // DRF validation errors come in various shapes.
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
    final isWide = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: kIsWeb
          ? null
          : AppBar(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
              title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
              elevation: 0,
            ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: _buildProfileCard(displayName, username, email, roleLabel, user),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 6,
                          child: Column(
                            children: [
                              _buildChangePasswordCard(),
                              const SizedBox(height: 24),
                              _buildHistoryCard(),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildProfileCard(displayName, username, email, roleLabel, user),
                        const SizedBox(height: 24),
                        _buildChangePasswordCard(),
                        const SizedBox(height: 24),
                        _buildHistoryCard(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildProfileCard(
    String displayName,
    String username,
    String email,
    String roleLabel,
    Map<String, dynamic> user,
  ) {
    final avatarUrl = user['avatar'] != null
        ? ApiConfig.publicMediaUrl(user['avatar'] as String)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with avatar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  DefensysTokens.maroon,
                  DefensysTokens.maroon.withValues(alpha: 0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl == null
                          ? Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: _pickAndUploadAvatar,
                          borderRadius: BorderRadius.circular(20),
                          child: const Icon(
                            Icons.camera_alt_outlined,
                            size: 20,
                            color: DefensysTokens.maroon,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    roleLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _pickAndUploadAvatar,
                      icon: const Icon(Icons.upload_outlined, size: 14, color: Colors.white),
                      label: const Text(
                        'Upload Photo',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                    if (avatarUrl != null) ...[
                      const SizedBox(width: 10),
                      TextButton.icon(
                        onPressed: _deleteAvatar,
                        icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.white),
                        label: const Text(
                          'Remove',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Info rows
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _infoRow(Icons.badge_outlined, 'ID', username),
                const Divider(height: 28),
                _infoRow(Icons.email_outlined, 'Email', email.isNotEmpty ? email : 'Not set'),
                if (user['team_id'] != null) ...[
                  const Divider(height: 28),
                  _infoRow(Icons.group_outlined, 'Team', 'Team ${user['team_id']}'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: DefensysTokens.maroon.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: DefensysTokens.maroon),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1a1a2e),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChangePasswordCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                  child: const Icon(Icons.lock_outline, size: 20, color: DefensysTokens.maroon),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Change Password',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a1a2e),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _passwordField(
              controller: _currentPassCtrl,
              label: 'Current Password',
              obscure: _obscureCurrent,
              onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
              validator: (v) => v == null || v.isEmpty ? 'Enter current password' : null,
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _newPassCtrl,
              label: 'New Password',
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter new password';
                if (v.length < 8) return 'Password must be at least 8 characters';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _passwordField(
              controller: _confirmPassCtrl,
              label: 'Confirm New Password',
              obscure: _obscureConfirm,
              onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Confirm your new password';
                if (v != _newPassCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysTokens.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
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
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DefensysTokens.maroon),
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                    child: const Icon(Icons.history, size: 20, color: DefensysTokens.maroon),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Activity History',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1a1a2e),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20, color: DefensysTokens.maroon),
                onPressed: _isLoadingHistory ? null : _fetchHistory,
                tooltip: 'Refresh History',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isLoadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: DefensysTokens.maroon),
              ),
            )
          else if (_historyError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 36, color: Colors.red),
                    const SizedBox(height: 8),
                    Text(
                      _historyError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DefensysTokens.maroon,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _fetchHistory,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_history.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off, size: 40, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'No recent actions recorded.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _history.length,
                  separatorBuilder: (context, index) => const Divider(height: 16),
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

                    // Pick appropriate icon based on category
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
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(iconData, size: 18, color: Colors.grey.shade700),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: DefensysTokens.maroon.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
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
                                const SizedBox(height: 6),
                                Text(
                                  action,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1a1a2e),
                                  ),
                                ),
                                if (reason.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Reason: $reason',
                                    style: TextStyle(
                                      fontSize: 12,
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
    // 1. Exact custom mappings for common actions
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

    // 2. Generic fallback formatting: e.g. "rubric.create" -> "Created Rubric"
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
              formattedVerb = verb[0].toUpperCase() + verb.substring(1).replaceAll('_', ' ');
            }
        }

        final formattedSubject = subject.isNotEmpty
            ? subject[0].toUpperCase() + subject.substring(1).replaceAll('_', ' ')
            : '';
        return '$formattedVerb $formattedSubject'.trim();
      }
    }

    // If no dots, just capitalize words and remove underscores
    return rawAction.split(RegExp(r'[\._]'))
        .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
        .join(' ');
  }
}
