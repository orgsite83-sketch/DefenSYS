import 'package:flutter/material.dart';
import 'dart:typed_data';

import '../../../theme/defensys_tokens.dart';

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

final _emailPattern = RegExp(r'^[^@]+@[^@]+\.[^@]+$');

class ProfileEditScreen extends StatefulWidget {
  final StudentProfile profile;
  const ProfileEditScreen({super.key, required this.profile});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _idCtrl;
  Uint8List? _avatarBytes;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.name);
    _emailCtrl = TextEditingController(text: widget.profile.email);
    _idCtrl = TextEditingController(text: widget.profile.studentId);
    _avatarBytes = widget.profile.avatarBytes;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // Image picking not supported in this build
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    widget.profile
      ..name = _nameCtrl.text.trim()
      ..email = _emailCtrl.text.trim()
      ..studentId = _idCtrl.text.trim()
      ..avatarBytes = _avatarBytes;
    Navigator.pop(context, widget.profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: DefensysTokens.maroon,
        foregroundColor: Colors.white,
        title: const Text('Edit Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Avatar
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.15),
                    backgroundImage: _avatarBytes != null
                        ? MemoryImage(_avatarBytes!)
                        : null,
                    child: _avatarBytes == null
                        ? Text(
                            _nameCtrl.text.isNotEmpty
                                ? _nameCtrl.text[0].toUpperCase()
                                : 'S',
                            style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.maroon),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroon,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.upload_rounded,
                    size: 14, color: DefensysTokens.maroon),
                label: const Text('Upload Photo',
                    style:
                        TextStyle(fontSize: 13, color: DefensysTokens.maroon)),
              ),
            ),
            if (_avatarBytes != null)
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _avatarBytes = null),
                  icon: const Icon(Icons.delete_outline,
                      size: 14, color: Colors.red),
                  label: const Text('Remove Photo',
                      style: TextStyle(fontSize: 13, color: Colors.red)),
                ),
              ),
            const SizedBox(height: 20),
            _field(
              'Full Name',
              _nameCtrl,
              Icons.person_outline,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name cannot be empty' : null,
            ),
            const SizedBox(height: 14),
            _field(
              'Email Address',
              _emailCtrl,
              Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Email is required';
                }
                if (!_emailPattern.hasMatch(v.trim())) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _field(
              'Student ID',
              _idCtrl,
              Icons.badge_outlined,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Student ID is required'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: widget.profile.team,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Team',
                prefixIcon: const Icon(Icons.group_outlined, size: 20),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Save Changes',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.white,
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
}
