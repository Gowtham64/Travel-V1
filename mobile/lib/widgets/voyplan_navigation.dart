import 'package:flutter/material.dart';

const _navigationCyan = Color(0xFF38BDF8);

/// The single source of truth for VoyPlan's authenticated navigation labels
/// and order. Every post-login surface uses this vocabulary and route order.
enum VoyPlanNavigationItem {
  home,
  planTrip,
  aiCopilot,
  myTrips,
  savedPlaces,
  vehicles,
  destinations,
  tripInspiration,
  features,
}

extension VoyPlanNavigationItemDetails on VoyPlanNavigationItem {
  String get label => switch (this) {
        VoyPlanNavigationItem.home => 'Home',
        VoyPlanNavigationItem.planTrip => 'Plan Trip',
        VoyPlanNavigationItem.aiCopilot => 'AI Co-Pilot',
        VoyPlanNavigationItem.myTrips => 'My Trips',
        VoyPlanNavigationItem.savedPlaces => 'Saved Places',
        VoyPlanNavigationItem.vehicles => 'Vehicles',
        VoyPlanNavigationItem.destinations => 'Destinations',
        VoyPlanNavigationItem.tripInspiration => 'Trip Inspiration',
        VoyPlanNavigationItem.features => 'Features',
      };

  IconData get icon => switch (this) {
        VoyPlanNavigationItem.home => Icons.home_rounded,
        VoyPlanNavigationItem.planTrip => Icons.add_road_rounded,
        VoyPlanNavigationItem.aiCopilot => Icons.auto_awesome_rounded,
        VoyPlanNavigationItem.myTrips => Icons.bookmark_rounded,
        VoyPlanNavigationItem.savedPlaces => Icons.favorite_rounded,
        VoyPlanNavigationItem.vehicles => Icons.directions_car_rounded,
        VoyPlanNavigationItem.destinations => Icons.explore_rounded,
        VoyPlanNavigationItem.tripInspiration => Icons.lightbulb_rounded,
        VoyPlanNavigationItem.features => Icons.featured_play_list_rounded,
      };
}

const voyPlanPrimaryNavigation = <VoyPlanNavigationItem>[
  VoyPlanNavigationItem.home,
  VoyPlanNavigationItem.planTrip,
  VoyPlanNavigationItem.destinations,
  VoyPlanNavigationItem.tripInspiration,
  VoyPlanNavigationItem.myTrips,
  VoyPlanNavigationItem.savedPlaces,
  VoyPlanNavigationItem.features,
  VoyPlanNavigationItem.aiCopilot,
];

/// The post-login route order. Kept separate so the public landing remains
/// untouched while the authenticated product has its full account navigation.
const voyPlanAuthenticatedPrimaryNavigation = <VoyPlanNavigationItem>[
  VoyPlanNavigationItem.home,
  VoyPlanNavigationItem.planTrip,
  VoyPlanNavigationItem.aiCopilot,
  VoyPlanNavigationItem.myTrips,
  VoyPlanNavigationItem.savedPlaces,
  VoyPlanNavigationItem.vehicles,
  VoyPlanNavigationItem.destinations,
  VoyPlanNavigationItem.tripInspiration,
  VoyPlanNavigationItem.features,
];

/// A transparent version of the VoyPlan route mark for use on any surface.
///
/// The source artwork includes the safe-area padding required for adaptive app
/// icons. Scaling it within a clipped box removes that padding for headers
/// without adding a light or dark backing plate behind the mark.
class VoyPlanBrandMark extends StatelessWidget {
  const VoyPlanBrandMark({
    super.key,
    required this.size,
    this.semanticLabel = 'VoyPlan',
  });

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRect(
        child: Transform.scale(
          scale: 1.55,
          child: Image.asset(
            'assets/icon/voyplan_foreground.png',
            fit: BoxFit.contain,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}

/// The authenticated top bar and account drawer share this navigation system.
///
/// It follows the reference hierarchy: search and utility controls remain
/// calm in the top bar, while profile and every signed-in destination live in
/// one polished, direct-access drawer.
class VoyPlanAuthenticatedNavigation extends StatelessWidget {
  const VoyPlanAuthenticatedNavigation({
    super.key,
    required this.onHome,
    required this.onNotifications,
    required this.onThemeToggle,
    required this.onMenu,
    required this.displayName,
    this.avatarUrl,
    this.isDark = true,
  });

  final VoidCallback onHome;
  final VoidCallback onNotifications;
  final VoidCallback onThemeToggle;
  final VoidCallback onMenu;
  final String displayName;
  final String? avatarUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final palette = _NavigationPalette.forBrightness(
      isDark ? Brightness.dark : Brightness.light,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return SizedBox(
          height: compact ? 64 : 66,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
            child: Row(
              children: [
                _BrandLockup(
                  compact: compact,
                  palette: palette,
                  onTap: onHome,
                ),
                const Spacer(),
                _TopBarAction(
                  tooltip: 'Notifications',
                  icon: Icons.notifications_none_rounded,
                  palette: palette,
                  onTap: onNotifications,
                  showBadge: true,
                ),
                const SizedBox(width: 4),
                _TopBarAction(
                  tooltip:
                      isDark ? 'Use light navigation' : 'Use dark navigation',
                  icon: isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  palette: palette,
                  onTap: onThemeToggle,
                ),
                SizedBox(width: compact ? 5 : 12),
                Tooltip(
                  message: 'Open menu',
                  child: InkWell(
                    onTap: onMenu,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: _ProfileAvatar(
                        displayName: displayName,
                        avatarUrl: avatarUrl,
                        palette: palette,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Optional compact desktop navigation surface.
///
/// The dashboard now uses the same on-demand drawer at every size. This
/// widget remains available for a future explicit pinned-navigation setting,
/// but is not inserted into the default dashboard layout.
class VoyPlanDashboardSidebar extends StatelessWidget {
  const VoyPlanDashboardSidebar({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onProfile,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    this.isDark = true,
  });

  final VoyPlanNavigationItem activeItem;
  final ValueChanged<VoyPlanNavigationItem> onItemSelected;
  final VoidCallback onProfile;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final palette = _NavigationPalette.forBrightness(
      isDark ? Brightness.dark : Brightness.light,
    );

    return Container(
      width: 170,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF07111E).withValues(alpha: 0.9)
            : const Color(0xFFF7FBFF).withValues(alpha: 0.96),
        border: Border(right: BorderSide(color: palette.divider)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: isDark ? 0.36 : 0.08),
            blurRadius: 24,
            offset: const Offset(8, 0),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 0, 4, 13),
              child: _BrandLockup(
                compact: false,
                palette: palette,
                onTap: () => onItemSelected(VoyPlanNavigationItem.home),
              ),
            ),
            Divider(height: 1, color: palette.divider),
            const SizedBox(height: 7),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in voyPlanAuthenticatedPrimaryNavigation)
                    _DashboardSideNavItem(
                      item: item,
                      palette: palette,
                      active: activeItem == item,
                      onTap: () => onItemSelected(item),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DashboardProfileTile(
              palette: palette,
              displayName: displayName,
              email: email,
              avatarUrl: avatarUrl,
              onTap: onProfile,
            ),
          ],
        ),
      ),
    );
  }
}

/// The small utility cluster used above the desktop dashboard. Search remains
/// absent; the profile picture deliberately opens the on-demand navigation.
class VoyPlanDashboardTopTools extends StatelessWidget {
  const VoyPlanDashboardTopTools({
    super.key,
    required this.onNotifications,
    required this.onThemeToggle,
    required this.onProfile,
    required this.displayName,
    this.avatarUrl,
    this.isDark = true,
  });

  final VoidCallback onNotifications;
  final VoidCallback onThemeToggle;
  final VoidCallback onProfile;
  final String displayName;
  final String? avatarUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final palette = _NavigationPalette.forBrightness(
      isDark ? Brightness.dark : Brightness.light,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TopBarAction(
          tooltip: 'Notifications',
          icon: Icons.notifications_none_rounded,
          palette: palette,
          onTap: onNotifications,
          showBadge: true,
        ),
        const SizedBox(width: 4),
        _TopBarAction(
          tooltip: isDark ? 'Use light theme' : 'Use dark theme',
          icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          palette: palette,
          onTap: onThemeToggle,
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Open navigation',
          child: InkWell(
            onTap: onProfile,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: _ProfileAvatar(
                displayName: displayName,
                avatarUrl: avatarUrl,
                palette: palette,
                size: 34,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full post-login route menu, available only when requested from the profile
/// picture so it never occupies dashboard space when it is not needed.
class VoyPlanAuthenticatedDrawer extends StatelessWidget {
  const VoyPlanAuthenticatedDrawer({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onNotifications,
    required this.onThemeToggle,
    required this.onProfile,
    required this.onSettings,
    required this.onHelp,
    required this.onContact,
    required this.onSignOut,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    this.isDark = true,
  });

  final VoyPlanNavigationItem activeItem;
  final ValueChanged<VoyPlanNavigationItem> onItemSelected;
  final VoidCallback onNotifications;
  final VoidCallback onThemeToggle;
  final VoidCallback onProfile;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onContact;
  final VoidCallback onSignOut;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final palette = _NavigationPalette.forBrightness(
      isDark ? Brightness.dark : Brightness.light,
    );
    final width = MediaQuery.sizeOf(context).width;
    final drawerWidth = width < 430 ? width * 0.92 : 370.0;

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(22)),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 34,
                offset: const Offset(-10, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              _DrawerHeader(
                palette: palette,
                onClose: () => Navigator.of(context).pop(),
              ),
              Divider(height: 1, color: palette.divider),
              Expanded(
                child: _MobileDrawerBody(
                  palette: palette,
                  activeItem: activeItem,
                  onItemSelected: onItemSelected,
                  onNotifications: onNotifications,
                  onThemeToggle: onThemeToggle,
                  onProfile: onProfile,
                  onSettings: onSettings,
                  onHelp: onHelp,
                  onContact: onContact,
                  onSignOut: onSignOut,
                  displayName: displayName,
                  email: email,
                  avatarUrl: avatarUrl,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationPalette {
  const _NavigationPalette({
    required this.surface,
    required this.border,
    required this.divider,
    required this.shadow,
    required this.primaryText,
    required this.secondaryText,
    required this.toolBackground,
    required this.hoverBackground,
    required this.profileBackground,
  });

  final Color surface;
  final Color border;
  final Color divider;
  final Color shadow;
  final Color primaryText;
  final Color secondaryText;
  final Color toolBackground;
  final Color hoverBackground;
  final Color profileBackground;

  factory _NavigationPalette.forBrightness(Brightness brightness) {
    if (brightness == Brightness.light) {
      return const _NavigationPalette(
        surface: Color(0xFFF9FCFF),
        border: Color(0xFFC5DDEB),
        divider: Color(0xFFE2EBF2),
        shadow: Color(0x160F172A),
        primaryText: Color(0xFF0C2850),
        secondaryText: Color(0xFF50647B),
        toolBackground: Color(0xFFF0F7FC),
        hoverBackground: Color(0xFFE7F7FF),
        profileBackground: Color(0xFFEAF6FF),
      );
    }
    return const _NavigationPalette(
      surface: Color(0xFF0B1728),
      border: Color(0xFF227EA1),
      divider: Color(0xFF203B55),
      shadow: Color(0x77000000),
      primaryText: Color(0xFFF8FAFC),
      secondaryText: Color(0xFFB6C4D7),
      toolBackground: Color(0xFF13273C),
      hoverBackground: Color(0xFF113857),
      profileBackground: Color(0xFF132A44),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({
    required this.compact,
    required this.palette,
    required this.onTap,
  });

  final bool compact;
  final _NavigationPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'VoyPlan home',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VoyPlanBrandMark(size: compact ? 31 : 38),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VoyPlan',
                    style: TextStyle(
                      color: palette.primaryText,
                      fontFamily: 'Playfair Display',
                      fontSize: compact ? 17 : 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  if (!compact)
                    Text(
                      'DISCOVER. DESIGN. DRIVE.',
                      style: TextStyle(
                        color: _navigationCyan,
                        fontSize: 6.8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.95,
                      ),
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

class _TopBarAction extends StatelessWidget {
  const _TopBarAction({
    required this.tooltip,
    required this.icon,
    required this.palette,
    required this.onTap,
    this.showBadge = false,
  });

  final String tooltip;
  final IconData icon;
  final _NavigationPalette palette;
  final VoidCallback onTap;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 21, color: palette.primaryText),
              if (showBadge)
                const Positioned(
                  top: 8,
                  right: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFFF4B66),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(width: 7, height: 7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.palette, required this.onClose});

  final _NavigationPalette palette;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 14, 13),
      child: Row(
        children: [
          Expanded(
            child: _BrandLockup(
              compact: false,
              palette: palette,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          _TopBarAction(
            tooltip: 'Close menu',
            icon: Icons.close_rounded,
            palette: palette,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _WideDrawerBody extends StatelessWidget {
  const _WideDrawerBody({
    required this.palette,
    required this.activeItem,
    required this.onItemSelected,
    required this.onNotifications,
    required this.onThemeToggle,
    required this.onProfile,
    required this.onSettings,
    required this.onHelp,
    required this.onContact,
    required this.onSignOut,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.isDark,
  });

  final _NavigationPalette palette;
  final VoyPlanNavigationItem activeItem;
  final ValueChanged<VoyPlanNavigationItem> onItemSelected;
  final VoidCallback onNotifications;
  final VoidCallback onThemeToggle;
  final VoidCallback onProfile;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onContact;
  final VoidCallback onSignOut;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 282,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 18),
            children: [
              _DrawerProfileCard(
                palette: palette,
                displayName: displayName,
                email: email,
                avatarUrl: avatarUrl,
                onTap: onProfile,
              ),
              const SizedBox(height: 14),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.home,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.home,
                onTap: () => onItemSelected(VoyPlanNavigationItem.home),
              ),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.planTrip,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.planTrip,
                onTap: () => onItemSelected(VoyPlanNavigationItem.planTrip),
              ),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.aiCopilot,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.aiCopilot,
                onTap: () => onItemSelected(VoyPlanNavigationItem.aiCopilot),
              ),
              _DrawerSectionLabel(label: 'YOUR JOURNEY', palette: palette),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.myTrips,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.myTrips,
                onTap: () => onItemSelected(VoyPlanNavigationItem.myTrips),
              ),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.savedPlaces,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.savedPlaces,
                onTap: () => onItemSelected(VoyPlanNavigationItem.savedPlaces),
              ),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.vehicles,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.vehicles,
                onTap: () => onItemSelected(VoyPlanNavigationItem.vehicles),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: palette.divider),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 18, 18),
            children: [
              _DrawerSectionLabel(label: 'EXPLORE', palette: palette),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.destinations,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.destinations,
                onTap: () => onItemSelected(VoyPlanNavigationItem.destinations),
              ),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.tripInspiration,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.tripInspiration,
                onTap: () =>
                    onItemSelected(VoyPlanNavigationItem.tripInspiration),
              ),
              _DrawerNavItem(
                item: VoyPlanNavigationItem.features,
                palette: palette,
                active: activeItem == VoyPlanNavigationItem.features,
                onTap: () => onItemSelected(VoyPlanNavigationItem.features),
              ),
              _DrawerSectionLabel(label: 'ACCOUNT', palette: palette),
              _DrawerActionItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                palette: palette,
                onTap: onProfile,
              ),
              _DrawerActionItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                palette: palette,
                onTap: onSettings,
              ),
              _DrawerActionItem(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                palette: palette,
                onTap: onNotifications,
              ),
              Divider(height: 22, color: palette.divider),
              _DrawerActionItem(
                icon: Icons.help_outline_rounded,
                label: 'Help & Support',
                palette: palette,
                onTap: onHelp,
              ),
              _DrawerActionItem(
                icon: Icons.mail_outline_rounded,
                label: 'Contact Us',
                palette: palette,
                onTap: onContact,
              ),
              _DrawerActionItem(
                icon: isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: isDark ? 'Light Mode' : 'Dark Mode',
                palette: palette,
                onTap: onThemeToggle,
              ),
              _DrawerActionItem(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                palette: palette,
                onTap: onSignOut,
                danger: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileDrawerBody extends StatelessWidget {
  const _MobileDrawerBody({
    required this.palette,
    required this.activeItem,
    required this.onItemSelected,
    required this.onNotifications,
    required this.onThemeToggle,
    required this.onProfile,
    required this.onSettings,
    required this.onHelp,
    required this.onContact,
    required this.onSignOut,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.isDark,
  });

  final _NavigationPalette palette;
  final VoyPlanNavigationItem activeItem;
  final ValueChanged<VoyPlanNavigationItem> onItemSelected;
  final VoidCallback onNotifications;
  final VoidCallback onThemeToggle;
  final VoidCallback onProfile;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onContact;
  final VoidCallback onSignOut;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: [
        _DrawerProfileCard(
          palette: palette,
          displayName: displayName,
          email: email,
          avatarUrl: avatarUrl,
          onTap: onProfile,
        ),
        const SizedBox(height: 12),
        for (final item in voyPlanAuthenticatedPrimaryNavigation) ...[
          if (item == VoyPlanNavigationItem.myTrips ||
              item == VoyPlanNavigationItem.destinations)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Divider(height: 1, color: palette.divider),
            ),
          _DrawerNavItem(
            item: item,
            palette: palette,
            active: activeItem == item,
            onTap: () => onItemSelected(item),
          ),
        ],
        Divider(height: 24, color: palette.divider),
        _DrawerActionItem(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          palette: palette,
          onTap: onNotifications,
        ),
        _DrawerActionItem(
          icon: Icons.settings_outlined,
          label: 'Settings',
          palette: palette,
          onTap: onSettings,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _FooterAction(
                icon: isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                label: 'Theme',
                palette: palette,
                onTap: onThemeToggle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _FooterAction(
                icon: Icons.help_outline_rounded,
                label: 'Help',
                palette: palette,
                onTap: onHelp,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _FooterAction(
                icon: Icons.mail_outline_rounded,
                label: 'Contact',
                palette: palette,
                onTap: onContact,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _FooterAction(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                palette: palette,
                onTap: onSignOut,
                danger: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DrawerProfileCard extends StatelessWidget {
  const _DrawerProfileCard({
    required this.palette,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.onTap,
  });

  final _NavigationPalette palette;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.profileBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            _ProfileAvatar(
              displayName: displayName,
              avatarUrl: avatarUrl,
              palette: palette,
              size: 42,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.primaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.secondaryText,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.secondaryText,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label, required this.palette});

  final String label;
  final _NavigationPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
      child: Text(
        label,
        style: TextStyle(
          color: _navigationCyan,
          fontSize: 9,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.item,
    required this.palette,
    required this.active,
    required this.onTap,
  });

  final VoyPlanNavigationItem item;
  final _NavigationPalette palette;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DrawerItemShell(
      active: active,
      palette: palette,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            item.icon,
            size: 18,
            color: active ? _navigationCyan : palette.primaryText,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                color: active ? _navigationCyan : palette.primaryText,
                fontSize: 13,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardSideNavItem extends StatelessWidget {
  const _DashboardSideNavItem({
    required this.item,
    required this.palette,
    required this.active,
    required this.onTap,
  });

  final VoyPlanNavigationItem item;
  final _NavigationPalette palette;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DrawerItemShell(
      active: active,
      palette: palette,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            item.icon,
            size: 16,
            color: active ? _navigationCyan : palette.primaryText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? _navigationCyan : palette.primaryText,
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardProfileTile extends StatelessWidget {
  const _DashboardProfileTile({
    required this.palette,
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.onTap,
  });

  final _NavigationPalette palette;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.profileBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            _ProfileAvatar(
              displayName: displayName,
              avatarUrl: avatarUrl,
              palette: palette,
              size: 31,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.primaryText,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.secondaryText,
                      fontSize: 8,
                    ),
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

class _DrawerActionItem extends StatelessWidget {
  const _DrawerActionItem({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final _NavigationPalette palette;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF5A70) : palette.primaryText;
    return _DrawerItemShell(
      palette: palette,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerItemShell extends StatefulWidget {
  const _DrawerItemShell({
    required this.palette,
    required this.onTap,
    required this.child,
    this.active = false,
  });

  final _NavigationPalette palette;
  final VoidCallback onTap;
  final Widget child;
  final bool active;

  @override
  State<_DrawerItemShell> createState() => _DrawerItemShellState();
}

class _DrawerItemShellState extends State<_DrawerItemShell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.active || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: widget.active
                ? _navigationCyan.withValues(alpha: 0.18)
                : highlighted
                    ? widget.palette.hoverBackground
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.active
                ? Border(
                    left: BorderSide(color: _navigationCyan, width: 3),
                  )
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final _NavigationPalette palette;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF5A70) : palette.primaryText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: palette.toolBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.displayName,
    required this.avatarUrl,
    required this.palette,
    this.size = 38,
  });

  final String displayName;
  final String? avatarUrl;
  final _NavigationPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = displayName
        .trim()
        .split(RegExp(r'\\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0])
        .join()
        .toUpperCase();
    final image = avatarUrl == null || avatarUrl!.isEmpty
        ? null
        : NetworkImage(avatarUrl!);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _navigationCyan.withValues(alpha: 0.18),
        border: Border.all(
          color: _navigationCyan.withValues(alpha: 0.65),
          width: 1.4,
        ),
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: image == null
          ? Text(
              initials.isEmpty ? 'V' : initials,
              style: TextStyle(
                color: palette.primaryText,
                fontSize: size * 0.32,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}
