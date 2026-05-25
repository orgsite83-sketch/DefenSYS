import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    _PolicySection(
      title: '1. Information We Collect',
      content:
          'DefenSYS collects the following information to operate the system:\n\n'
          '• Account credentials (email address, hashed password)\n'
          '• User role and institutional affiliation\n'
          '• Team and project information submitted through the platform\n'
          '• Evaluation scores and rubric responses\n'
          '• Document uploads and repository access logs\n'
          '• System activity timestamps and audit trails',
    ),
    _PolicySection(
      title: '2. How We Use Your Information',
      content:
          'Collected data is used exclusively for:\n\n'
          '• Authenticating users and enforcing role-based access\n'
          '• Processing and recording defense evaluations\n'
          '• Generating grade summaries and academic reports\n'
          '• Maintaining the digital vault and document archive\n'
          '• Supporting curriculum analytics and trend reporting\n'
          '• Auditing system activity for institutional compliance',
    ),
    _PolicySection(
      title: '3. Data Sharing',
      content:
          'DefenSYS does not sell, trade, or share your personal information with third parties. '
          'Data is accessible only to:\n\n'
          '• System administrators within the institution\n'
          '• Faculty members for their assigned teams\n'
          '• Students for their own team and evaluation records\n\n'
          'All access is governed by the role-based permission system.',
    ),
    _PolicySection(
      title: '4. Document Security',
      content:
          'All uploaded documents in the Digital Vault are protected by:\n\n'
          '• Dynamic watermarking on every viewed page\n'
          '• Read-only browser viewer enforcement\n'
          '• Disabled copy and download functionality for students\n'
          '• View count tracking and access logging\n'
          '• Secure viewing request workflows',
    ),
    _PolicySection(
      title: '5. Grade Data & Lock Policy',
      content:
          'Evaluation scores are subject to the Grade Lock Rule:\n\n'
          '• Scores in draft state may be edited freely by the grader\n'
          '• Once posted, scores are permanently locked and cannot be modified\n'
          '• Only system administrators may correct posted scores through a supervised audit process\n'
          '• All grade changes are logged with timestamps',
    ),
    _PolicySection(
      title: '6. Data Retention',
      content:
          'Academic records, evaluation data, and project archives are retained for the duration '
          'required by institutional policy. Users may request data review through the system '
          'administrator. Account data is removed upon formal request following institutional '
          'offboarding procedures.',
    ),
    _PolicySection(
      title: '7. Security Measures',
      content:
          'DefenSYS implements the following security practices:\n\n'
          '• Password hashing using industry-standard algorithms\n'
          '• Role-based access control on all endpoints\n'
          '• Session management and authentication tokens\n'
          '• Conflict-of-interest enforcement (advisers cannot panel their own teams)\n'
          '• Audit logs for all sensitive operations',
    ),
    _PolicySection(
      title: '8. Your Rights',
      content:
          'As a user of DefenSYS, you have the right to:\n\n'
          '• Access your own profile and evaluation records\n'
          '• Request correction of inaccurate personal information\n'
          '• Request account deactivation through your administrator\n\n'
          'For any data-related concerns, contact your Department IT Administrator.',
    ),
    _PolicySection(
      title: '9. Changes to This Policy',
      content:
          'This privacy policy may be updated to reflect changes in system functionality or '
          'institutional requirements. Users will be notified of significant changes through '
          'the system. Continued use of DefenSYS after updates constitutes acceptance of the '
          'revised policy.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: AppColors.maroon,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.maroon,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.privacy_tip_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Text('Privacy Policy',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
                const SizedBox(height: 8),
                Text('Effective Date: January 1, 2026',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 8),
                Text(
                  'DefenSYS is committed to protecting the privacy and security of all users within '
                  'the Department of Information Technology.',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85), height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ..._sections.map((s) => _sectionCard(s)),
          const SizedBox(height: 16),
          // Contact card
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
                Icon(Icons.contact_support_rounded, color: AppColors.gold, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Questions?',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                      SizedBox(height: 4),
                      Text(
                        'Contact your Department IT Administrator for any privacy-related concerns or data requests.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('© 2026 DefenSYS. All rights reserved.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.6))),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sectionCard(_PolicySection s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.maroon)),
          const SizedBox(height: 8),
          Text(s.content,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
        ],
      ),
    );
  }
}

class _PolicySection {
  final String title;
  final String content;
  const _PolicySection({required this.title, required this.content});
}
