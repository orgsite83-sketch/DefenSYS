import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _sections = [
    _TermsSection(
      title: '1. Acceptance of Terms',
      content:
          'By accessing or using DefenSYS, you agree to be bound by these Terms and Conditions. '
          'If you do not agree to any part of these terms, you must not use the system. '
          'Continued use of DefenSYS constitutes full acceptance of these terms.',
    ),
    _TermsSection(
      title: '2. Eligibility',
      content:
          'DefenSYS is exclusively available to:\n\n'
          '• Enrolled students of the Department of Information Technology\n'
          '• Faculty members assigned as advisers or panelists\n'
          '• Authorized system administrators\n\n'
          'Access is granted by the institution and may be revoked at any time.',
    ),
    _TermsSection(
      title: '3. User Accounts',
      content:
          'You are responsible for:\n\n'
          '• Maintaining the confidentiality of your login credentials\n'
          '• All activities that occur under your account\n'
          '• Notifying the administrator immediately of any unauthorized access\n\n'
          'Sharing your account credentials with others is strictly prohibited and may result in '
          'account suspension.',
    ),
    _TermsSection(
      title: '4. Acceptable Use',
      content:
          'You agree to use DefenSYS only for its intended academic purposes. You must not:\n\n'
          '• Attempt to bypass security controls or access restrictions\n'
          '• Submit false, misleading, or fraudulent evaluation scores\n'
          '• Reproduce, distribute, or publish documents from the Digital Vault\n'
          '• Interfere with the system\'s operation or other users\' access\n'
          '• Use the system for any commercial or non-academic purpose',
    ),
    _TermsSection(
      title: '5. Evaluation Integrity',
      content:
          'All evaluation scores submitted through DefenSYS are subject to the Grade Lock Rule:\n\n'
          '• Scores become permanently locked once posted\n'
          '• Submitting a grade is a formal academic act and carries full responsibility\n'
          '• Attempts to manipulate, falsify, or coerce evaluation scores are violations of '
          'academic integrity and institutional policy\n\n'
          'Violations may result in disciplinary action.',
    ),
    _TermsSection(
      title: '6. Intellectual Property',
      content:
          'All project documents, manuscripts, source code, and presentations uploaded to the '
          'Digital Vault remain the intellectual property of the respective student teams and '
          'the institution.\n\n'
          'Unauthorized reproduction, distribution, or use of archived materials is strictly '
          'prohibited. The watermarking and read-only protections in place must not be circumvented.',
    ),
    _TermsSection(
      title: '7. Document Submissions',
      content:
          'By uploading documents to DefenSYS, you confirm that:\n\n'
          '• The content is your original work or properly attributed\n'
          '• You have the right to submit the document\n'
          '• The document does not violate any third-party rights\n'
          '• The content complies with institutional academic standards\n\n'
          'The institution reserves the right to remove any content that violates these conditions.',
    ),
    _TermsSection(
      title: '8. System Availability',
      content:
          'DefenSYS is provided on an "as available" basis. The institution does not guarantee '
          'uninterrupted access and is not liable for any loss resulting from system downtime, '
          'maintenance, or technical issues. Users are advised to complete submissions and '
          'evaluations well before deadlines.',
    ),
    _TermsSection(
      title: '9. Limitation of Liability',
      content:
          'The institution and DefenSYS developers shall not be liable for:\n\n'
          '• Loss of data due to technical failures\n'
          '• Incorrect grades resulting from user input errors\n'
          '• Unauthorized access resulting from user negligence\n'
          '• Any indirect or consequential damages arising from system use',
    ),
    _TermsSection(
      title: '10. Termination',
      content:
          'The institution reserves the right to suspend or terminate any user account that '
          'violates these Terms and Conditions, without prior notice. Upon termination, access '
          'to all system features will be immediately revoked.',
    ),
    _TermsSection(
      title: '11. Amendments',
      content:
          'These Terms and Conditions may be updated at any time to reflect changes in system '
          'functionality, institutional policy, or legal requirements. Users will be notified '
          'of material changes. Continued use of DefenSYS after amendments constitutes '
          'acceptance of the updated terms.',
    ),
    _TermsSection(
      title: '12. Governing Policy',
      content:
          'These Terms and Conditions are governed by the academic policies and regulations of '
          'the institution. Any disputes arising from the use of DefenSYS shall be resolved '
          'through the institution\'s established grievance and disciplinary procedures.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
        backgroundColor: AppColors.maroon,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.maroon,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.gavel_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text('Terms & Conditions',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
                const SizedBox(height: 8),
                Text('Last Updated: January 1, 2026',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 8),
                Text(
                  'Please read these terms carefully before using DefenSYS. '
                  'These terms govern your use of the system and your responsibilities as a user.',
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withValues(alpha: 0.85), height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ..._sections.map((s) => _sectionCard(s)),
          const SizedBox(height: 16),
          // Agreement banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline_rounded, color: AppColors.gold, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'By using DefenSYS, you acknowledge that you have read, understood, '
                    'and agree to be bound by these Terms and Conditions.',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('© 2026 DefenSYS. All rights reserved.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.6))),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sectionCard(_TermsSection s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.maroon)),
          const SizedBox(height: 8),
          Text(s.content,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
        ],
      ),
    );
  }
}

class _TermsSection {
  final String title;
  final String content;
  const _TermsSection({required this.title, required this.content});
}
