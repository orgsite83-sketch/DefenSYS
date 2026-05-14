import 'package:flutter/material.dart';

class RepoProject {
  final String team, title, type, adviser;
  final List<String> members;
  final List<RepoDoc> docs;
  final IconData logoIcon;
  RepoProject({
    required this.team,
    required this.title,
    required this.type,
    required this.adviser,
    required this.members,
    required this.docs,
    this.logoIcon = Icons.school,
  });
}

class RepoDoc {
  final String title, filename, type, size, date, abstract;
  RepoDoc(this.title, this.filename, this.type, this.size, this.date, this.abstract);
}

final Map<String, Map<String, List<RepoProject>>> archiveData = {
  'SY 2025-2026': {
    '2nd Semester': [
      RepoProject(
        team: 'Team Alpha',
        title: 'AI-Based Attendance System',
        type: 'Capstone',
        members: ['Juan Dela Cruz', 'Maria Santos', 'Pedro Reyes'],
        adviser: 'Prof. Ricardo Santos',
        logoIcon: Icons.face_retouching_natural,
        docs: [
          RepoDoc('Capstone Proposal', 'proposal_team_alpha.pdf', 'Proposal', '2.4 MB',
              'Feb 10, 2026',
              'This proposal presents an AI-Based Attendance System designed to automate student attendance tracking using facial recognition technology. The system aims to reduce manual recording errors, improve efficiency, and provide real-time attendance analytics for faculty and administrators within the Department of Information Technology.'),
          RepoDoc('Final Manuscript', 'manuscript_team_alpha.pdf', 'Manuscript', '5.1 MB',
              'Mar 5, 2026',
              'This manuscript documents the complete development of the AI-Based Attendance System. It covers the system architecture, machine learning model training using a convolutional neural network, database design, and evaluation results. The system achieved a 96.4% recognition accuracy across a test dataset of 150 students under varied lighting conditions.'),
          RepoDoc('Presentation Slides', 'slides_team_alpha.pdf', 'Presentation', '3.8 MB',
              'Mar 12, 2026',
              'Defense presentation slides for the AI-Based Attendance System capstone project. Covers problem statement, objectives, methodology, system demo walkthrough, results and discussion, and recommendations for future development.'),
          RepoDoc('Source Code Docs', 'sourcecode_team_alpha.pdf', 'Source Code', '1.2 MB',
              'Mar 1, 2026',
              'Technical documentation of the source code for the AI-Based Attendance System. Includes module descriptions, API references, database schema, setup instructions, and code annotations.'),
        ],
      ),
      RepoProject(
        team: 'Team Beta',
        title: 'Smart Inventory Management',
        type: 'Capstone',
        members: ['Ana Lim', 'Carlo Mendoza', 'Rina Torres'],
        adviser: 'Prof. Elena Cruz',
        logoIcon: Icons.inventory_2,
        docs: [
          RepoDoc('Capstone Proposal', 'proposal_team_beta.pdf', 'Proposal', '1.9 MB',
              'Feb 12, 2026',
              'This proposal outlines a Smart Inventory Management System for small-to-medium enterprises, leveraging barcode scanning and predictive restocking algorithms to minimize stockouts and overstock situations.'),
          RepoDoc('Final Manuscript', 'manuscript_team_beta.pdf', 'Manuscript', '4.3 MB',
              'Mar 6, 2026',
              'Full documentation of the Smart Inventory Management System, covering system design, database architecture, REST API implementation, and user acceptance testing results with 92% satisfaction rate from pilot users.'),
        ],
      ),
    ],
    '1st Semester': [
      RepoProject(
        team: 'Team Gamma',
        title: 'Online Voting System for Student Council',
        type: 'Pre-Capstone',
        members: ['Leo Bautista', 'Cris Navarro', 'Mia Flores'],
        adviser: 'Prof. Dante Reyes',
        docs: [
          RepoDoc('Project Proposal', 'proposal_team_gamma.pdf', 'Proposal', '1.5 MB',
              'Sep 8, 2025',
              'A secure online voting platform for student council elections, featuring OTP-based voter authentication, real-time vote tallying, and audit trail generation to ensure election integrity.'),
          RepoDoc('Presentation Slides', 'slides_team_gamma.pdf', 'Presentation', '2.1 MB',
              'Oct 15, 2025',
              'Pre-capstone defense slides covering system overview, security mechanisms, database design, and live demo of the voting interface and admin dashboard.'),
        ],
      ),
    ],
  },
  'SY 2024-2025': {
    '2nd Semester': [
      RepoProject(
        team: 'Team Delta',
        title: 'Library Management System',
        type: 'Capstone',
        members: ['Ryan Ocampo', 'Liza Tan', 'Mark Villanueva'],
        adviser: 'Prof. Ricardo Santos',
        logoIcon: Icons.local_library,
        docs: [
          RepoDoc('Final Manuscript', 'manuscript_team_delta.pdf', 'Manuscript', '6.2 MB',
              'Mar 10, 2025',
              'Comprehensive documentation of a Library Management System with RFID-based book tracking, automated overdue notifications, and an analytics dashboard for librarians to monitor borrowing trends.'),
          RepoDoc('Source Code Docs', 'sourcecode_team_delta.pdf', 'Source Code', '0.9 MB',
              'Mar 8, 2025',
              'Source code documentation for the Library Management System built with Laravel (backend) and Vue.js (frontend), including ER diagrams, API documentation, and deployment guide.'),
        ],
      ),
    ],
    '1st Semester': [
      RepoProject(
        team: 'Team Echo',
        title: 'Campus Navigation App',
        type: 'Pre-Capstone',
        members: ['Nina Castillo', 'Gio Santos', 'Trish Aquino'],
        adviser: 'Prof. Elena Cruz',
        docs: [
          RepoDoc('Project Proposal', 'proposal_team_echo.pdf', 'Proposal', '1.1 MB',
              'Sep 5, 2024',
              'An indoor campus navigation mobile app using Bluetooth Low Energy beacons to guide students and visitors to classrooms, offices, and facilities within the university campus.'),
        ],
      ),
    ],
  },
};
