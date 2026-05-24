import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navigation/app_router.dart';
import '../services/terms_acceptance.dart';
import '../theme/app_theme.dart';

class TermsAgreementScreen extends StatefulWidget {
  final String role;
  final Map<String, dynamic>? userData;
  const TermsAgreementScreen({super.key, required this.role, this.userData});

  @override
  State<TermsAgreementScreen> createState() => _TermsAgreementScreenState();
}

class _TermsAgreementScreenState extends State<TermsAgreementScreen> {
  bool _agreed = false;

  static const _sections = [
    _Section(
      '1. Acceptance of Terms',
      'By accessing or using DefenSYS, you agree to be bound by these Terms and Conditions. '
          'If you do not agree to any part of these terms, you must not use the system. '
          'Continued use of DefenSYS constitutes full acceptance of these terms.',
    ),
    _Section(
      '2. Eligibility',
      'DefenSYS is exclusively available to enrolled students of the Department of Information Technology, '
          'faculty members assigned as advisers or panelists, and authorized system administrators. '
          'Access is granted by the institution and may be revoked at any time.',
    ),
    _Section(
      '3. User Accounts',
      'You are responsible for maintaining the confidentiality of your login credentials and all '
          'activities that occur under your account. Sharing your account credentials with others is '
          'strictly prohibited and may result in account suspension.',
    ),
    _Section(
      '4. Acceptable Use',
      'You agree to use DefenSYS only for its intended academic purposes. You must not attempt to '
          'bypass security controls, submit false evaluation scores, reproduce documents from the Digital '
          'Vault, or use the system for any commercial or non-academic purpose.',
    ),
    _Section(
      '5. Evaluation Integrity',
      'All evaluation scores submitted through DefenSYS are subject to the Grade Lock Rule. '
          'Scores become permanently locked once posted. Attempts to manipulate, falsify, or coerce '
          'evaluation scores are violations of academic integrity and may result in disciplinary action.',
    ),
    _Section(
      '6. Intellectual Property',
      'All project documents, manuscripts, source code, and presentations uploaded to the Digital '
          'Vault remain the intellectual property of the respective student teams and the institution. '
          'Unauthorized reproduction or distribution of archived materials is strictly prohibited.',
    ),
    _Section(
      '7. Document Submissions',
      'By uploading documents to DefenSYS, you confirm that the content is your original work, '
          'you have the right to submit it, and it complies with institutional academic standards.',
    ),
    _Section(
      '8. System Availability',
      'DefenSYS is provided on an "as available" basis. The institution does not guarantee '
          'uninterrupted access and is not liable for any loss resulting from system downtime or '
          'technical issues.',
    ),
    _Section(
      '9. Limitation of Liability',
      'The institution and DefenSYS developers shall not be liable for loss of data due to '
          'technical failures, incorrect grades resulting from user input errors, or any indirect '
          'damages arising from system use.',
    ),
    _Section(
      '10. Amendments',
      'These Terms and Conditions may be updated at any time. Users will be notified of material '
          'changes. Continued use of DefenSYS after amendments constitutes acceptance of the updated terms.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(color: AppColors.maroon),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'DefenSYS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Terms & Conditions',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Please read carefully before continuing.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: _sections.length,
                itemBuilder: (_, i) {
                  final s = _sections[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.maroon,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.content,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Bottom agreement bar ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Checkbox row
                  GestureDetector(
                    onTap: () => setState(() => _agreed = !_agreed),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _agreed,
                          activeColor: AppColors.maroon,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) =>
                              setState(() => _agreed = v ?? false),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'I have read and agree to the Terms & Conditions',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            // Disagree — show dialog and stay
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: const Text(
                                  'Access Denied',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                content: const Text(
                                  'You must agree to the Terms & Conditions to use DefenSYS.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text(
                                      'Go Back',
                                      style: TextStyle(color: AppColors.maroon),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Disagree',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _agreed
                              ? () async {
                                  await TermsAcceptance.recordAcceptance();
                                  if (!context.mounted) return;
                                  context.go(homeRouteForRoleLabel(widget.role));
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.maroon,
                            disabledBackgroundColor: Colors.grey.shade300,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Agree & Continue',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section {
  final String title;
  final String content;
  const _Section(this.title, this.content);
}
