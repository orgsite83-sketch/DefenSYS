import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/l10n_ext.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/offline_banner.dart';
import '../../../../notifications/notifications_modal.dart';
import '../../../../notifications/notifications_provider.dart';
import '../../../../services/auth_provider.dart';
import '../../../../config/api_config.dart';
import '../../../../widgets/defensys_logo_mark.dart';
import '../../faculty/e_signature_upload_dialog.dart';
import '../../../../widgets/buttons/defensys_theme_toggle.dart';
import '../../../../services/theme_provider.dart';

export '../../../../widgets/status_badge.dart';

enum DefensysAdminSection {
  overview,
  academicPeriods,
  userManagement,
  studentTeams,
  studentAcademicRecords,
  gradeCenter,
  rubrics,
  repositoryAudit,
  curriculumAnalytics,
  auditCompliance,
  scheduling,
  defenseBoard,
  defenseStages,
}

class DefensysUi {
  static const sidebarWidth = DefensysTokens.sidebarWidth;
  static const minDesktopWidth = DefensysTokens.minDesktopWidth;
  static const topNavHeight = DefensysTokens.topNavHeight;
  static const contentPadding = DefensysTokens.contentPadding;

  static const fontFamily = DefensysTokens.fontFamily;
  static const primaryMaroon = DefensysTokens.maroon;
  static const primaryDark = DefensysTokens.maroonDark;
  static const accentGold = DefensysTokens.gold;
  static const techBlue = DefensysTokens.techBlue;
  static const steelGrey = DefensysTokens.steelGrey;
  static const bgLight = DefensysTokens.background;
  static const textDark = DefensysTokens.textDark;
  static const white = DefensysTokens.surface;

  static const successBg = DefensysTokens.successBg;
  static const successText = DefensysTokens.successText;
  static const successBorder = DefensysTokens.successBorder;
  static const warningBg = DefensysTokens.warningBg;
  static const warningText = DefensysTokens.warningText;
  static const warningBorder = DefensysTokens.warningBorder;
  static const infoBg = DefensysTokens.infoBg;
  static const infoText = DefensysTokens.infoText;
  static const infoBorder = DefensysTokens.infoBorder;
  static const neutralBg = DefensysTokens.neutralBg;
  static const neutralText = DefensysTokens.neutralText;
  static const neutralBorder = DefensysTokens.neutralBorder;

  static TextStyle get pageTitle => DefensysTokens.pageTitle;

  static TextStyle get sectionTitle => DefensysTokens.sectionTitle;

  static TextStyle get subtitle => DefensysTokens.subtitle;

  static TextStyle get tableHeader => DefensysTokens.tableHeader;

  static TextStyle get tableCell => DefensysTokens.tableCell;

  static BoxDecoration cardDecoration([BuildContext? context]) =>
      DefensysTokens.cardDecoration(context);

  static const switchInactiveTrack = DefensysTokens.switchInactiveTrack;

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

class DefensysAdminShell extends StatefulWidget {
  final DefensysAdminSection? activeSection;
  final bool isProfileActive;
  final String activeSemesterLabel;
  final Widget child;
  final ValueChanged<DefensysAdminSection> onNavigate;
  final VoidCallback onLogout;
  final bool scrollContent;

  const DefensysAdminShell({
    super.key,
    this.activeSection,
    this.isProfileActive = false,
    required this.activeSemesterLabel,
    required this.child,
    required this.onNavigate,
    required this.onLogout,
    this.scrollContent = true,
  });

  @override
  State<DefensysAdminShell> createState() => _DefensysAdminShellState();
}

class _DefensysAdminShellState extends State<DefensysAdminShell> {
  bool _isCollapsed = false;

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: DefensysUi.fontFamily),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= DefensysUi.minDesktopWidth;

          void handleNavigate(DefensysAdminSection section) {
            widget.onNavigate(section);
            if (!isWide) {
              Navigator.of(context).pop();
            }
          }

          void handleLogout() {
            if (!isWide) {
              Navigator.of(context).pop();
            }
            widget.onLogout();
          }

          final sidebar = _Sidebar(
            activeSection: widget.activeSection,
            isProfileActive: widget.isProfileActive,
            onNavigate: isWide ? widget.onNavigate : handleNavigate,
            onLogout: handleLogout,
            isCollapsed: isWide && _isCollapsed,
            onToggleCollapse: isWide ? _toggleCollapse : null,
          );

          final contentColumn = Column(
            children: [
              _TopNav(
                activeSemesterLabel: widget.activeSemesterLabel,
                showMenuButton: !isWide,
              ),
              Expanded(
                child: OfflineBanner(
                  child: widget.scrollContent
                      ? SingleChildScrollView(
                          padding: DefensysUi.contentPadding,
                          child: widget.child,
                        )
                      : widget.child,
                ),
              ),
            ],
          );

          if (isWide) {
            return Scaffold(
              backgroundColor: DefensysTokens.backgroundOf(context),
              body: Row(
                children: [
                  RepaintBoundary(child: sidebar),
                  Expanded(
                    child: RepaintBoundary(child: contentColumn),
                  ),
                ],
              ),
            );
          }

          return Scaffold(
            backgroundColor: DefensysTokens.backgroundOf(context),
            drawer: Drawer(
              width: DefensysUi.sidebarWidth,
              backgroundColor: DefensysTokens.panelOf(context),
              surfaceTintColor: Colors.transparent,
              child: sidebar,
            ),
            body: contentColumn,
          );
        },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    Icon(
                      icon,
                      color: isDark ? DefensysTokens.mistMaroon : DefensysUi.primaryMaroon,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      style: DefensysUi.pageTitle.copyWith(
                        color: isDark ? const Color(0xFFF4F4F5) : DefensysTokens.maroon,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: DefensysUi.subtitle.copyWith(
                  color: isDark ? const Color(0xFFA1A1AA) : DefensysTokens.textSecondary,
                ),
              ),
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
      decoration: DefensysTokens.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _TopNav extends StatelessWidget {
  final String activeSemesterLabel;
  final bool showMenuButton;

  const _TopNav({
    required this.activeSemesterLabel,
    this.showMenuButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DefensysUi.topNavHeight,
      padding: EdgeInsets.only(
        left: showMenuButton ? 8 : 32,
        right: 40,
      ),
      decoration: BoxDecoration(
        color: DefensysTokens.panelOf(context),
        border: Border(
          bottom: BorderSide(
            color: DefensysTokens.borderOf(context),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Open menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          _SemesterPill(label: activeSemesterLabel),
          const SizedBox(width: 16),
          const _NotificationsBell(),
          const SizedBox(width: 10),
          const DefensysThemeToggle(),
        ],
      ),
    );
  }
}

class _NotificationsBell extends ConsumerStatefulWidget {
  const _NotificationsBell();

  @override
  ConsumerState<_NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends ConsumerState<_NotificationsBell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).fetchNotifications();
    });
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const NotificationsModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Badge(
      isLabelVisible: state.unreadCount > 0,
      label: Text(
        state.unreadCount.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: isDark ? DefensysTokens.mistMaroon : DefensysUi.primaryMaroon,
      child: IconButton(
        icon: Icon(
          Icons.notifications_outlined,
          color: isDark ? const Color(0xFFA1A1AA) : DefensysUi.steelGrey,
          size: 23,
        ),
        tooltip: 'Notifications',
        onPressed: () => _showNotifications(context),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final DefensysAdminSection? activeSection;
  final bool isProfileActive;
  final ValueChanged<DefensysAdminSection> onNavigate;
  final VoidCallback onLogout;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const _Sidebar({
    this.activeSection,
    this.isProfileActive = false,
    required this.onNavigate,
    required this.onLogout,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final groups = <_NavGroup>[
      _NavGroup(
        title: 'Dashboard',
        entries: [
          _NavEntry(
            section: DefensysAdminSection.overview,
            icon: Icons.show_chart_rounded,
            label: l10n.navOverview,
          ),
        ],
      ),
      _NavGroup(
        title: 'Setup & Configuration',
        entries: [
          _NavEntry(
            section: DefensysAdminSection.academicPeriods,
            icon: Icons.calendar_month_rounded,
            label: l10n.navAcademicPeriods,
          ),
          _NavEntry(
            section: DefensysAdminSection.rubrics,
            icon: Icons.checklist_rounded,
            label: l10n.navRubricEngine,
          ),
          _NavEntry(
            section: DefensysAdminSection.defenseStages,
            icon: Icons.layers_rounded,
            label: l10n.navDefenseStages,
          ),
        ],
      ),
      _NavGroup(
        title: 'People & Teams',
        entries: [
          _NavEntry(
            section: DefensysAdminSection.userManagement,
            icon: Icons.manage_accounts_rounded,
            label: l10n.navUserManagement,
          ),
          _NavEntry(
            section: DefensysAdminSection.studentTeams,
            icon: Icons.groups_rounded,
            label: l10n.navStudentTeams,
          ),
        ],
      ),
      _NavGroup(
        title: 'Defense Operations',
        entries: [
          _NavEntry(
            section: DefensysAdminSection.defenseBoard,
            icon: Icons.view_agenda_rounded,
            label: l10n.navDefenseBoard,
          ),
          _NavEntry(
            section: DefensysAdminSection.gradeCenter,
            icon: Icons.grade_rounded,
            label: l10n.navGradeCenter,
          ),
        ],
      ),
      _NavGroup(
        title: 'Analytics & Audit',
        entries: [
          _NavEntry(
            section: DefensysAdminSection.repositoryAudit,
            icon: Icons.folder_rounded,
            label: l10n.navRepositoryAudit,
          ),
          _NavEntry(
            section: DefensysAdminSection.curriculumAnalytics,
            icon: Icons.manage_search_rounded,
            label: l10n.navCurriculumAnalytics,
          ),
          _NavEntry(
            section: DefensysAdminSection.auditCompliance,
            icon: Icons.verified_user_outlined,
            label: 'Audit Trail',
          ),
        ],
      ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: isCollapsed ? 68.0 : DefensysUi.sidebarWidth,
      decoration: BoxDecoration(
        color: DefensysTokens.panelOf(context),
        border: Border(
          right: BorderSide(color: DefensysTokens.borderOf(context), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header / Brand area
          if (isCollapsed)
            SizedBox(
              height: 64,
              width: 68,
              child: Center(
                child: IconButton(
                  icon: const _SidebarPanelIcon(size: 20),
                  tooltip: 'Expand sidebar',
                  splashRadius: 18,
                  onPressed: onToggleCollapse,
                ),
              ),
            )
          else
            Container(
              height: 64,
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
              child: Row(
                children: [
                  const _BrandSeal(size: 30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'DefenSYS',
                                style: TextStyle(
                                  fontFamily: DefensysUi.fontFamily,
                                  color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                softWrap: false,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF28272D) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: DefensysTokens.borderOf(context),
                                ),
                              ),
                              child: Text(
                                'Admin',
                                style: TextStyle(
                                  fontFamily: DefensysUi.fontFamily,
                                  color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Academic Portal',
                          style: TextStyle(
                            fontFamily: DefensysUi.fontFamily,
                            color: isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ],
                    ),
                  ),
                  if (onToggleCollapse != null)
                    IconButton(
                      icon: const _SidebarPanelIcon(size: 18),
                      tooltip: 'Collapse sidebar',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      splashRadius: 16,
                      onPressed: onToggleCollapse,
                    ),
                ],
              ),
            ),

          // Hairline divider below header
          Divider(height: 1, thickness: 1, color: DefensysTokens.borderOf(context)),

          // Scrollable Navigation List (Clean direct groups)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              children: [
                for (int i = 0; i < groups.length; i++) ...[
                  if (i > 0)
                    SizedBox(height: isCollapsed ? 8 : 20),
                  _SectionHeader(
                    title: groups[i].title,
                    isCollapsed: isCollapsed,
                    isFirst: i == 0,
                  ),
                  const SizedBox(height: 4),
                  for (final e in groups[i].entries)
                    _NavItem(
                      section: e.section,
                      activeSection: activeSection,
                      icon: e.icon,
                      label: e.label,
                      onTap: onNavigate,
                      isCollapsed: isCollapsed,
                    ),
                ],
              ],
            ),
          ),

          // Hairline divider above profile
          Divider(height: 1, thickness: 1, color: DefensysTokens.borderOf(context)),

          // User Profile Card
          _UserProfileCard(
            onLogout: onLogout,
            isCollapsed: isCollapsed,
            isActive: isProfileActive,
          ),
        ],
      ),
    );
  }
}

class _NavGroup {
  final String title;
  final List<_NavEntry> entries;

  const _NavGroup({
    required this.title,
    required this.entries,
  });
}

class _NavEntry {
  final DefensysAdminSection section;
  final IconData icon;
  final String label;

  const _NavEntry({
    required this.section,
    required this.icon,
    required this.label,
  });
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isCollapsed;
  final bool isFirst;

  const _SectionHeader({
    required this.title,
    this.isCollapsed = false,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isCollapsed) {
      if (isFirst) {
        return const SizedBox(height: 4);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Divider(height: 1, thickness: 1, color: DefensysTokens.borderOf(context)),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 6 : 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: DefensysUi.fontFamily,
          color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _UserProfileCard extends ConsumerWidget {
  final VoidCallback onLogout;
  final bool isCollapsed;
  final bool isActive;

  const _UserProfileCard({
    required this.onLogout,
    this.isCollapsed = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authProvider).user;
    final displayName = user != null && user['name'] != null
        ? user['name'] as String
        : 'Administrator';

    final avatarUrl = user?['avatar'] != null
        ? ApiConfig.publicMediaUrl(user!['avatar'] as String)
        : null;

    final popupItems = <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: 'profile',
        height: 38,
        child: Row(
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 16,
              color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569),
            ),
            const SizedBox(width: 10),
            Text(
              'Profile',
              style: TextStyle(
                fontFamily: DefensysUi.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'signature',
        height: 38,
        child: Row(
          children: [
            Icon(
              Icons.draw_outlined,
              size: 16,
              color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569),
            ),
            const SizedBox(width: 10),
            Text(
              'E-Signature',
              style: TextStyle(
                fontFamily: DefensysUi.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'theme',
        height: 38,
        child: Row(
          children: [
            Icon(
              isDark ? Icons.light_mode_outlined : Icons.bedtime_outlined,
              size: 16,
              color: isDark ? DefensysTokens.mistGold : const Color(0xFF475569),
            ),
            const SizedBox(width: 10),
            Text(
              isDark ? 'Light Mode' : 'Mist Dark',
              style: TextStyle(
                fontFamily: DefensysUi.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: 'logout',
        height: 38,
        child: Row(
          children: const [
            Icon(Icons.logout_rounded, size: 16, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text(
              'Log Out',
              style: TextStyle(
                fontFamily: DefensysUi.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      ),
    ];

    void handleSelect(String value) {
      if (value == 'profile') {
        context.go('/admin/profile');
      } else if (value == 'signature') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (context) => const ESignatureUploadDialog(),
          );
        });
      } else if (value == 'theme') {
        ref.read(themeModeProvider.notifier).toggleTheme();
      } else if (value == 'logout') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onLogout();
        });
      }
    }

    final collapsedCard = Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      height: 54,
      alignment: Alignment.center,
      child: PopupMenuButton<String>(
        tooltip: '$displayName (Admin)',
        offset: const Offset(50, 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: DefensysTokens.borderOf(context), width: 1),
        ),
        color: DefensysTokens.panelOf(context),
        elevation: 4,
        onSelected: handleSelect,
        itemBuilder: (context) => popupItems,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive
                  ? (isDark ? DefensysTokens.mistMaroon : DefensysTokens.maroon)
                  : (isDark
                      ? DefensysTokens.mistMaroon.withValues(alpha: 0.4)
                      : DefensysTokens.maroon.withValues(alpha: 0.25)),
              width: isActive ? 2.0 : 1.5,
            ),
            color: isDark ? DefensysTokens.mistMaroon : DefensysTokens.maroon,
            image: avatarUrl != null
                ? DecorationImage(
                    image: NetworkImage(avatarUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: avatarUrl == null
              ? const Center(
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                )
              : null,
        ),
      ),
    );

    final expandedCard = Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? (isDark
                ? DefensysTokens.mistMaroon.withValues(alpha: 0.18)
                : DefensysTokens.maroon.withValues(alpha: 0.08))
            : (isDark ? const Color(0xFF28272D) : const Color(0xFFFAFAFA)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? (isDark
                  ? DefensysTokens.mistMaroon.withValues(alpha: 0.5)
                  : DefensysTokens.maroon.withValues(alpha: 0.35))
              : DefensysTokens.borderOf(context),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.go('/admin/profile'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (isDark
                                  ? DefensysTokens.mistMaroon
                                  : DefensysUi.primaryMaroon)
                              .withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                        color: isDark
                            ? DefensysTokens.mistMaroon
                            : DefensysUi.primaryMaroon,
                        image: avatarUrl != null
                            ? DecorationImage(
                                image: NetworkImage(avatarUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: avatarUrl == null
                          ? const Center(
                              child: Icon(
                                Icons.admin_panel_settings_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontFamily: DefensysUi.fontFamily,
                              color: isDark
                                  ? const Color(0xFFF4F4F5)
                                  : const Color(0xFF0F172A),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Academic Portal',
                            style: TextStyle(
                              fontFamily: DefensysUi.fontFamily,
                              color: isDark
                                  ? const Color(0xFFA1A1AA)
                                  : const Color(0xFF64748B),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account options',
            icon: Icon(
              Icons.more_horiz_rounded,
              color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B),
              size: 18,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 16,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: DefensysTokens.borderOf(context), width: 1),
            ),
            color: DefensysTokens.panelOf(context),
            elevation: 4,
            offset: const Offset(0, -180),
            onSelected: handleSelect,
            itemBuilder: (context) => popupItems,
          ),
        ],
      ),
    );

    if (isCollapsed) {
      return SizedBox(
        width: 68,
        height: 74,
        child: Center(
          child: collapsedCard,
        ),
      );
    }
    return expandedCard;
  }
}

class _NavItem extends StatefulWidget {
  final DefensysAdminSection section;
  final DefensysAdminSection? activeSection;
  final IconData icon;
  final String label;
  final IconData? trailing;
  final ValueChanged<DefensysAdminSection> onTap;
  final bool isCollapsed;

  const _NavItem({
    required this.section,
    this.activeSection,
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
    this.isCollapsed = false,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSection != oldWidget.activeSection) {
      if (_isPressed && widget.activeSection == widget.section) {
        _isPressed = false;
      }
    }
  }

  void _handleTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
  }

  void _handleTapCancel() {
    if (mounted) setState(() => _isPressed = false);
  }

  void _handleTapUp(TapUpDetails _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isPressed && widget.activeSection != widget.section) {
        setState(() => _isPressed = false);
      }
    });
  }

  void _handleTap() {
    widget.onTap(widget.section);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.section == widget.activeSection;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeBg = isDark ? DefensysTokens.mistMaroon : DefensysTokens.maroon;
    const activeColor = Colors.white;

    final isHighlighted = selected || _isPressed;
    final Color? bgColor;
    if (isHighlighted) {
      bgColor = activeBg;
    } else if (_isHovered) {
      bgColor = isDark ? const Color(0xFF28272D) : const Color(0xFFF4F4F5);
    } else {
      bgColor = null;
    }

    final textColor = isHighlighted
        ? activeColor
        : (isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B));
    final iconColor = isHighlighted
        ? activeColor
        : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B));

    if (widget.isCollapsed) {
      return Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              onTap: _handleTap,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: 18,
                    color: iconColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: _handleTap,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Center(
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: iconColor,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.label,
                            style: TextStyle(
                              fontFamily: DefensysUi.fontFamily,
                              color: textColor,
                              fontSize: 13,
                              fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.trailing != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            widget.trailing,
                            size: 16,
                            color: isHighlighted
                                ? Colors.white.withValues(alpha: 0.85)
                                : (isDark
                                    ? const Color(0xFF71717A)
                                    : const Color(0xFF94A3B8)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.45)
            : DefensysUi.successBg,
        border: isDark
            ? Border.all(
                color: const Color(0xFF059669).withValues(alpha: 0.4),
                width: 1)
            : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: DefensysUi.fontFamily,
          color: isDark ? const Color(0xFF6EE7B7) : DefensysUi.successText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BrandSeal extends StatelessWidget {
  const _BrandSeal({this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DefensysLogoMark(
      size: size,
      colorMode: DefensysLogoColorMode.brand,
    );
  }
}

class _SidebarPanelIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _SidebarPanelIcon({
    this.size = 18,
    this.color = const Color(0xFF64748B),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _SidebarPanelPainter(color: color),
      ),
    );
  }
}

class _SidebarPanelPainter extends CustomPainter {
  final Color color;

  _SidebarPanelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.088;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(size.width * 0.22),
    );

    // Outer rounded rectangle
    canvas.drawRRect(rect, paint);

    // Inner vertical divider (left pane separator)
    final lineX = size.width * 0.35;
    canvas.drawLine(
      Offset(lineX, strokeWidth / 2),
      Offset(lineX, size.height - strokeWidth / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SidebarPanelPainter oldDelegate) => oldDelegate.color != color;
}
