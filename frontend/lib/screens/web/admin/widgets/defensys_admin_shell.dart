import 'package:flutter/material.dart';

enum DefensysAdminSection {
  overview,
  academicPeriods,
  userManagement,
  studentTeams,
  studentAcademicRecords,
  gradeCenter,
  rubricEngine,
  repositoryAudit,
  curriculumAnalytics,
  scheduling,
  defenseBoard,
  defenseStages,
}

class DefensysUi {
  static const sidebarWidth = 260.0;
  static const minDesktopWidth = 1180.0;
  static const topNavHeight = 70.0;
  static const contentPadding = EdgeInsets.fromLTRB(40, 20, 40, 36);

  static const fontFamily = 'Poppins';
  static const primaryMaroon = Color(0xFF7A110A);
  static const primaryDark = Color(0xFF5E0D08);
  static const accentGold = Color(0xFFFFC107);
  static const techBlue = Color(0xFF3B82F6);
  static const steelGrey = Color(0xFF6B7280);
  static const bgLight = Color(0xFFF3F4F6);
  static const textDark = Color(0xFF1F2937);
  static const white = Colors.white;

  static const successBg = Color(0xFFD1FAE5);
  static const successText = Color(0xFF065F46);
  static const successBorder = Color(0xFFA7F3D0);
  static const warningBg = Color(0xFFFEF3C7);
  static const warningText = Color(0xFF92400E);
  static const warningBorder = Color(0xFFFDE68A);
  static const infoBg = Color(0xFFDBEAFE);
  static const infoText = Color(0xFF1E40AF);
  static const infoBorder = Color(0xFFBFDBFE);
  static const neutralBg = Color(0xFFF3F4F6);
  static const neutralText = Color(0xFF374151);
  static const neutralBorder = Color(0xFFE5E7EB);

  static TextStyle get pageTitle => const TextStyle(
    fontFamily: fontFamily,
    color: primaryMaroon,
    fontSize: 21,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
  );

  static TextStyle get sectionTitle => const TextStyle(
    fontFamily: fontFamily,
    color: textDark,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  static TextStyle get subtitle => const TextStyle(
    fontFamily: fontFamily,
    color: steelGrey,
    fontSize: 13,
    height: 1.45,
  );

  static TextStyle get tableHeader => const TextStyle(
    fontFamily: fontFamily,
    color: steelGrey,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.45,
  );

  static TextStyle get tableCell => const TextStyle(
    fontFamily: fontFamily,
    color: neutralText,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  static BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  /// Minimal flat pill switch: inactive track `#D1D5DB`, white thumb, no outline or overlay.
  static const switchInactiveTrack = Color(0xFFD1D5DB);

  static Widget flatSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
    Color activeTrackColor = primaryMaroon,
    double scale = 1.0,
  }) {
    final w = Switch(
      value: value,
      onChanged: onChanged,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashRadius: 0,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      trackOutlineColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      trackOutlineWidth: const WidgetStatePropertyAll<double>(0),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return activeTrackColor;
        }
        return switchInactiveTrack;
      }),
      thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
    );
    if (scale == 1.0) {
      return w;
    }
    return Transform.scale(
      scale: scale,
      alignment: Alignment.centerLeft,
      child: w,
    );
  }
}

class DefensysAdminShell extends StatelessWidget {
  final DefensysAdminSection activeSection;
  final String activeSemesterLabel;
  final Widget child;
  final ValueChanged<DefensysAdminSection> onNavigate;
  final VoidCallback onLogout;
  final bool scrollContent;

  const DefensysAdminShell({
    super.key,
    required this.activeSection,
    required this.activeSemesterLabel,
    required this.child,
    required this.onNavigate,
    required this.onLogout,
    this.scrollContent = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DefensysUi.bgLight,
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: DefensysUi.fontFamily),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < DefensysUi.minDesktopWidth
                ? DefensysUi.minDesktopWidth
                : constraints.maxWidth;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: Row(
                  children: [
                    _Sidebar(
                      activeSection: activeSection,
                      onNavigate: onNavigate,
                      onLogout: onLogout,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _TopNav(activeSemesterLabel: activeSemesterLabel),
                          Expanded(
                            child: scrollContent
                                ? SingleChildScrollView(
                                    padding: DefensysUi.contentPadding,
                                    child: child,
                                  )
                                : child,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class DefensysPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? actions;

  const DefensysPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: DefensysUi.primaryMaroon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(title, style: DefensysUi.pageTitle),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: DefensysUi.subtitle),
            ],
          ),
        ),
        if (actions != null) ...[const SizedBox(width: 20), actions!],
      ],
    );
  }
}

class DefensysCard extends StatelessWidget {
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  const DefensysCard({
    super.key,
    required this.child,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: DefensysUi.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class DefensysStatusBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;
  final Color borderColor;
  final bool showDot;

  const DefensysStatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.textColor,
    required this.borderColor,
    this.showDot = false,
  });

  const DefensysStatusBadge.success({
    super.key,
    required this.label,
    this.showDot = true,
  }) : background = DefensysUi.successBg,
       textColor = DefensysUi.successText,
       borderColor = DefensysUi.successBorder;

  const DefensysStatusBadge.inactive({
    super.key,
    required this.label,
    this.showDot = false,
  }) : background = DefensysUi.neutralBg,
       textColor = DefensysUi.steelGrey,
       borderColor = DefensysUi.neutralBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: DefensysUi.fontFamily,
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopNav extends StatelessWidget {
  final String activeSemesterLabel;

  const _TopNav({required this.activeSemesterLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DefensysUi.topNavHeight,
      padding: const EdgeInsets.only(left: 32, right: 40),
      decoration: BoxDecoration(
        color: DefensysUi.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Spacer(),
          const SizedBox(width: 16),
          _SemesterPill(label: activeSemesterLabel),
          const SizedBox(width: 16),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: DefensysUi.primaryMaroon,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Administrator',
            style: TextStyle(
              fontFamily: DefensysUi.fontFamily,
              color: DefensysUi.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final DefensysAdminSection activeSection;
  final ValueChanged<DefensysAdminSection> onNavigate;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.activeSection,
    required this.onNavigate,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DefensysUi.sidebarWidth,
      color: DefensysUi.primaryMaroon,
      child: Column(
        children: [
          Container(
            height: 92,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const _BrandSeal(size: 40),
                const SizedBox(width: 14),
                const Text(
                  'DefenSYS',
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    color: DefensysUi.accentGold,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 20),
              children: [
                _NavItem(
                  section: DefensysAdminSection.overview,
                  activeSection: activeSection,
                  icon: Icons.show_chart_rounded,
                  label: 'Overview',
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.academicPeriods,
                  activeSection: activeSection,
                  icon: Icons.calendar_month_rounded,
                  label: 'Academic Periods',
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.userManagement,
                  activeSection: activeSection,
                  icon: Icons.groups_2_rounded,
                  label: 'User Management',
                  trailing: Icons.keyboard_arrow_down_rounded,
                  onTap: onNavigate,
                ),
                if (_isUserManagementOpen) ...[
                  _SubNavItem(
                    section: DefensysAdminSection.userManagement,
                    activeSection: activeSection,
                    icon: Icons.person_rounded,
                    label: 'Users',
                    onTap: onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.studentTeams,
                    activeSection: activeSection,
                    icon: Icons.groups_rounded,
                    label: 'Student Teams',
                    onTap: onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.studentAcademicRecords,
                    activeSection: activeSection,
                    icon: Icons.badge_rounded,
                    label: 'Student Academic\nRecords',
                    onTap: onNavigate,
                  ),
                ],
                _NavItem(
                  section: DefensysAdminSection.gradeCenter,
                  activeSection: activeSection,
                  icon: Icons.grade_rounded,
                  label: 'Grade Center',
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.rubricEngine,
                  activeSection: activeSection,
                  icon: Icons.checklist_rounded,
                  label: 'Rubric Engine',
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.repositoryAudit,
                  activeSection: activeSection,
                  icon: Icons.camera_alt_rounded,
                  label: 'Repository Audit',
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.curriculumAnalytics,
                  activeSection: activeSection,
                  icon: Icons.manage_search_rounded,
                  label: 'Curriculum Analytics',
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.scheduling,
                  activeSection: activeSection,
                  icon: Icons.event_note_rounded,
                  label: 'Scheduling',
                  trailing: Icons.keyboard_arrow_down_rounded,
                  onTap: onNavigate,
                ),
                if (_isSchedulingOpen) ...[
                  _SubNavItem(
                    section: DefensysAdminSection.scheduling,
                    activeSection: activeSection,
                    icon: Icons.auto_awesome_rounded,
                    label: 'Defense Scheduler',
                    onTap: onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.defenseBoard,
                    activeSection: activeSection,
                    icon: Icons.view_column_rounded,
                    label: 'Defense Board',
                    onTap: onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.defenseStages,
                    activeSection: activeSection,
                    icon: Icons.layers_rounded,
                    label: 'Defense Stages',
                    onTap: onNavigate,
                  ),
                ],
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.09)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onLogout,
              hoverColor: Colors.white.withValues(alpha: 0.05),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFD1D5DB),
                      size: 18,
                    ),
                    SizedBox(width: 14),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        fontFamily: DefensysUi.fontFamily,
                        color: Color(0xFFD1D5DB),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  bool get _isUserManagementOpen =>
      activeSection == DefensysAdminSection.userManagement ||
      activeSection == DefensysAdminSection.studentTeams ||
      activeSection == DefensysAdminSection.studentAcademicRecords;

  bool get _isSchedulingOpen =>
      activeSection == DefensysAdminSection.scheduling ||
      activeSection == DefensysAdminSection.defenseBoard ||
      activeSection == DefensysAdminSection.defenseStages;
}

class _NavItem extends StatelessWidget {
  final DefensysAdminSection section;
  final DefensysAdminSection activeSection;
  final IconData icon;
  final String label;
  final IconData? trailing;
  final ValueChanged<DefensysAdminSection> onTap;

  const _NavItem({
    required this.section,
    required this.activeSection,
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected =
        section == activeSection ||
        (section == DefensysAdminSection.userManagement &&
            (activeSection == DefensysAdminSection.studentTeams ||
                activeSection ==
                    DefensysAdminSection.studentAcademicRecords)) ||
        (section == DefensysAdminSection.scheduling &&
            (activeSection == DefensysAdminSection.scheduling ||
                activeSection == DefensysAdminSection.defenseBoard ||
                activeSection == DefensysAdminSection.defenseStages));
    final color = selected ? DefensysUi.accentGold : const Color(0xFFD1D5DB);

    return Material(
      color: selected ? DefensysUi.primaryDark : Colors.transparent,
      child: InkWell(
        onTap: () => onTap(section),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    left: BorderSide(color: DefensysUi.accentGold, width: 4),
                  )
                : null,
          ),
          padding: EdgeInsets.only(left: selected ? 23 : 27, right: 24),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null)
                Icon(trailing, color: color.withValues(alpha: 0.86), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  final DefensysAdminSection section;
  final DefensysAdminSection activeSection;
  final IconData icon;
  final String label;
  final ValueChanged<DefensysAdminSection> onTap;

  const _SubNavItem({
    required this.section,
    required this.activeSection,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = section == activeSection;
    final color = selected ? DefensysUi.accentGold : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(section),
        hoverColor: Colors.white.withValues(alpha: 0.04),
        child: Container(
          constraints: const BoxConstraints(minHeight: 39),
          padding: const EdgeInsets.fromLTRB(56, 8, 22, 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    color: color,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SemesterPill extends StatelessWidget {
  final String label;

  const _SemesterPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: DefensysUi.successBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: DefensysUi.fontFamily,
          color: DefensysUi.successText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BrandSeal extends StatelessWidget {
  final double size;

  const _BrandSeal({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        color: Colors.white,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: DefensysUi.primaryMaroon,
            child: Icon(
              Icons.shield_rounded,
              color: DefensysUi.accentGold,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
