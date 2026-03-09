part of '../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.session,
    required this.onSessionUpdated,
    required this.onLogout,
  });

  final AuthSession session;
  final void Function(AuthSession session) onSessionUpdated;
  final VoidCallback onLogout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<TurnaUserProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = ProfileApi.fetchMe(widget.session);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.userId != widget.session.userId ||
        oldWidget.session.token != widget.session.token) {
      _profileFuture = ProfileApi.fetchMe(widget.session);
    }
  }

  void _reloadProfile() {
    setState(() {
      _profileFuture = ProfileApi.fetchMe(widget.session);
    });
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    _reloadProfile();
  }

  Future<void> _openProfileEditor() async {
    await _openPage(
      ProfilePage(
        session: widget.session,
        onProfileUpdated: widget.onSessionUpdated,
      ),
    );
  }

  Widget _buildSectionPanel(List<_SettingsMenuAction> actions) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 0,
              ),
              leading: Icon(
                actions[index].icon,
                color: TurnaColors.textMuted,
                size: 21,
              ),
              title: Text(
                actions[index].label,
                style: TextStyle(
                  color: TurnaColors.text,
                  fontSize: 16.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: Colors.black.withValues(alpha: 0.34),
              ),
              onTap: actions[index].onTap,
            ),
            if (index != actions.length - 1)
              const Divider(height: 1, indent: 58, endIndent: 18),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      body: SafeArea(
        child: FutureBuilder<TurnaUserProfile>(
          future: _profileFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final about = profile?.about?.trim();
            final subtitle = (about != null && about.isNotEmpty)
                ? about
                : '@${widget.session.userId}';

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.search_rounded, size: 23),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ayarlar',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: TurnaColors.text,
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: _openProfileEditor,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _SessionAvatar(session: widget.session, radius: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.session.displayName,
                                  style: const TextStyle(
                                    fontSize: 17.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF131716),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TurnaColors.backgroundSoft,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.edit_note_rounded,
                                        size: 14,
                                        color: TurnaColors.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: TurnaColors.textMuted,
                                            fontSize: 13.2,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.black.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (snapshot.hasError) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      snapshot.error.toString(),
                      style: const TextStyle(
                        color: Color(0xFFC0392B),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _buildSectionPanel([
                  _SettingsMenuAction(
                    icon: Icons.campaign_outlined,
                    label: 'Reklam yayinlayin',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Reklam yayinlayin'),
                    ),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.storefront_outlined,
                    label: 'Isletme araclari',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Isletme araclari'),
                    ),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.verified_outlined,
                    label: 'Meta Verified',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Meta Verified'),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _buildSectionPanel([
                  _SettingsMenuAction(
                    icon: Icons.star_border_rounded,
                    label: 'Yildizli',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Yildizli')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.campaign_outlined,
                    label: 'Toplu mesaj listeleri',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Toplu mesaj listeleri'),
                    ),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.groups_outlined,
                    label: 'Topluluklar',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Topluluklar')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.devices_outlined,
                    label: 'Bagli cihazlar',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Bagli cihazlar'),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _buildSectionPanel([
                  _SettingsMenuAction(
                    icon: Icons.key_outlined,
                    label: 'Hesap',
                    onTap: () => _openPage(const AccountPage()),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.lock_outline_rounded,
                    label: 'Gizlilik',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Gizlilik')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Sohbetler',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Sohbetler')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.notifications_none_rounded,
                    label: 'Bildirimler',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Bildirimler')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.receipt_long_outlined,
                    label: 'Siparisler',
                    onTap: () =>
                        _openPage(const PlaceholderPage(title: 'Siparisler')),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.swap_vert_rounded,
                    label: 'Depolama ve veriler',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Depolama ve veriler'),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _buildSectionPanel([
                  _SettingsMenuAction(
                    icon: Icons.help_outline_rounded,
                    label: 'Yardim ve geri bildirim',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Yardim ve geri bildirim'),
                    ),
                  ),
                  _SettingsMenuAction(
                    icon: Icons.person_add_alt_1_outlined,
                    label: 'Kisileri davet edin',
                    onTap: () => _openPage(
                      const PlaceholderPage(title: 'Kisileri davet edin'),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cikis yap'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE25241),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SessionAvatar extends StatelessWidget {
  const _SessionAvatar({required this.session, this.radius = 25});

  final AuthSession session;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return _ProfileAvatar(
      label: session.displayName,
      avatarUrl: session.avatarUrl,
      authToken: session.token,
      radius: radius,
    );
  }
}

class _BottomProfileTabIcon extends StatelessWidget {
  const _BottomProfileTabIcon({required this.session, this.selected = false});

  final AuthSession session;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? TurnaColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: _SessionAvatar(session: session, radius: 11),
    );
  }
}

class _SettingsMenuAction {
  const _SettingsMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _TurnaBottomBar extends StatelessWidget {
  const _TurnaBottomBar({
    required this.selectedIndex,
    required this.unreadChats,
    required this.session,
    required this.onSelect,
  });

  final int selectedIndex;
  final int unreadChats;
  final AuthSession session;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Durum',
                selected: selectedIndex == 0,
                iconBuilder: (selected) => Icon(
                  Icons.circle_outlined,
                  size: 22,
                  color: selected ? TurnaColors.primary : TurnaColors.textMuted,
                ),
                onTap: () => onSelect(0),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Aramalar',
                selected: selectedIndex == 1,
                iconBuilder: (selected) => Icon(
                  Icons.call_outlined,
                  size: 22,
                  color: selected ? TurnaColors.primary : TurnaColors.textMuted,
                ),
                onTap: () => onSelect(1),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Araçlar',
                selected: selectedIndex == 2,
                iconBuilder: (selected) => Icon(
                  Icons.business_center_outlined,
                  size: 22,
                  color: selected ? TurnaColors.primary : TurnaColors.textMuted,
                ),
                onTap: () => onSelect(2),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Sohbetler',
                selected: selectedIndex == 3,
                iconBuilder: (selected) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 22,
                      color: selected
                          ? TurnaColors.primary
                          : TurnaColors.textMuted,
                    ),
                    if (unreadChats > 0)
                      Positioned(
                        right: -18,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          constraints: const BoxConstraints(minWidth: 24),
                          decoration: BoxDecoration(
                            color: TurnaColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unreadChats > 999 ? '999+' : '$unreadChats',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () => onSelect(3),
              ),
            ),
            Expanded(
              child: _TurnaBottomBarItem(
                label: 'Siz',
                selected: selectedIndex == 4,
                iconBuilder: (selected) =>
                    _BottomProfileTabIcon(session: session, selected: selected),
                onTap: () => onSelect(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnaBottomBarItem extends StatelessWidget {
  const _TurnaBottomBarItem({
    required this.label,
    required this.selected,
    required this.iconBuilder,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Widget Function(bool selected) iconBuilder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? TurnaColors.primary : TurnaColors.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 28, child: Center(child: iconBuilder(selected))),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
    required this.label,
    required this.radius,
    this.avatarUrl,
    this.authToken,
  });

  final String label;
  final String? avatarUrl;
  final String? authToken;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = avatarUrl?.trim() ?? '';
    if (trimmedUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: TurnaColors.primary100,
        backgroundImage: NetworkImage(
          trimmedUrl,
          headers: authToken == null || authToken!.trim().isEmpty
              ? null
              : {'Authorization': 'Bearer ${authToken!.trim()}'},
        ),
      );
    }

    final safeLabel = label.trim();
    final initial = safeLabel.isEmpty
        ? '?'
        : safeLabel.characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: TurnaColors.primary100,
      child: Text(
        initial,
        style: TextStyle(
          color: TurnaColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.65,
        ),
      ),
    );
  }
}

Future<void> _openAvatarViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
  required String token,
}) async {
  final trimmedUrl = imageUrl.trim();
  if (trimmedUrl.isEmpty) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          AvatarViewerPage(imageUrl: trimmedUrl, title: title, token: token),
    ),
  );
}

class AvatarViewerPage extends StatelessWidget {
  const AvatarViewerPage({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.token,
  });

  final String imageUrl;
  final String title;
  final String token;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(
          child: Image.network(
            imageUrl,
            headers: {'Authorization': 'Bearer $token'},
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Gorsel yuklenemedi.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.session,
    required this.onProfileUpdated,
  });

  final AuthSession session;
  final void Function(AuthSession session) onProfileUpdated;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _displayNameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  TurnaUserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _avatarBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _displayNameController.addListener(_refreshPreview);
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.removeListener(_refreshPreview);
    _displayNameController.dispose();
    _aboutController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await ProfileApi.fetchMe(widget.session);
      final updatedSession = widget.session.copyWith(
        displayName: profile.displayName,
        phone: profile.phone,
        avatarUrl: profile.avatarUrl,
        clearAvatarUrl: profile.avatarUrl == null,
      );
      await updatedSession.save();
      if (!mounted) return;
      _applyProfile(profile);
      setState(() {
        _profile = profile;
        _loading = false;
      });
      widget.onProfileUpdated(updatedSession);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _applyProfile(TurnaUserProfile profile) {
    _displayNameController.text = profile.displayName;
    _aboutController.text = profile.about ?? '';
    _phoneController.text = profile.phone ?? '';
    _emailController.text = profile.email ?? '';
  }

  Future<void> _commitProfile(
    TurnaUserProfile updatedProfile, {
    String? successMessage,
  }) async {
    _applyProfile(updatedProfile);
    setState(() {
      _profile = updatedProfile;
    });

    final updatedSession = widget.session.copyWith(
      displayName: updatedProfile.displayName,
      phone: updatedProfile.phone,
      avatarUrl: updatedProfile.avatarUrl,
      clearAvatarUrl: updatedProfile.avatarUrl == null,
    );
    await updatedSession.save();
    widget.onProfileUpdated(updatedSession);
    await TurnaAnalytics.logEvent('profile_updated', {
      'user_id': updatedSession.userId,
    });

    if (!mounted || successMessage == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  String? _guessImageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return null;
  }

  Future<void> _pickAvatar() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1400,
    );
    if (file == null) return;

    final contentType = _guessImageContentType(file.name);
    if (contentType == null) {
      setState(() => _error = 'Desteklenmeyen görsel formatı.');
      return;
    }

    setState(() {
      _avatarBusy = true;
      _error = null;
    });

    try {
      final upload = await ProfileApi.createAvatarUpload(
        widget.session,
        contentType: contentType,
        fileName: file.name,
      );

      final bytes = await file.readAsBytes();
      final uploadRes = await http.put(
        Uri.parse(upload.uploadUrl),
        headers: upload.headers,
        body: bytes,
      );
      if (uploadRes.statusCode >= 400) {
        throw TurnaApiException('Avatar yüklenemedi.');
      }

      final updatedProfile = await ProfileApi.completeAvatarUpload(
        widget.session,
        objectKey: upload.objectKey,
      );
      if (!mounted) return;
      await _commitProfile(
        updatedProfile,
        successMessage: 'Avatar güncellendi.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() {
      _avatarBusy = true;
      _error = null;
    });

    try {
      final updatedProfile = await ProfileApi.deleteAvatar(widget.session);
      if (!mounted) return;
      await _commitProfile(
        updatedProfile,
        successMessage: 'Avatar kaldırıldı.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.length < 2) {
      setState(() => _error = 'Ad en az 2 karakter olmalı.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updatedProfile = await ProfileApi.updateMe(
        widget.session,
        displayName: displayName,
        about: _aboutController.text,
        phone: _phoneController.text,
        email: _emailController.text,
      );
      if (!mounted) return;

      await _commitProfile(
        updatedProfile,
        successMessage: 'Profil güncellendi.',
      );
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (_loading && profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Profil yüklenemedi.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadProfile,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: () {
                final avatarUrl = profile.avatarUrl ?? widget.session.avatarUrl;
                if (avatarUrl == null || avatarUrl.trim().isEmpty) return;
                _openAvatarViewer(
                  context,
                  imageUrl: avatarUrl,
                  title: _displayNameController.text.trim().isEmpty
                      ? widget.session.displayName
                      : _displayNameController.text.trim(),
                  token: widget.session.token,
                );
              },
              child: _ProfileAvatar(
                label: _displayNameController.text.trim().isEmpty
                    ? widget.session.displayName
                    : _displayNameController.text.trim(),
                avatarUrl: profile.avatarUrl ?? widget.session.avatarUrl,
                authToken: widget.session.token,
                radius: 58,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: (_saving || _avatarBusy) ? null : _pickAvatar,
                icon: _avatarBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(_avatarBusy ? 'Yükleniyor...' : 'Galeriden seç'),
              ),
              if ((profile.avatarUrl ?? widget.session.avatarUrl) != null)
                OutlinedButton.icon(
                  onPressed: (_saving || _avatarBusy) ? null : _removeAvatar,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Fotoğrafı kaldır'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _displayNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Ad',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aboutController,
            maxLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'Hakkında',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            readOnly: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Telefon',
              helperText: 'Numara degisikligi dogrulama ile yapilir.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: (_saving || _avatarBusy) ? null : _saveProfile,
            child: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: (_saving || _avatarBusy) ? null : _loadProfile,
            child: const Text('Sunucudan yenile'),
          ),
        ],
      ),
    );
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.session,
    required this.userId,
    required this.fallbackName,
    this.fallbackAvatarUrl,
    required this.callCoordinator,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final String userId;
  final String fallbackName;
  final String? fallbackAvatarUrl;
  final TurnaCallCoordinator callCoordinator;
  final VoidCallback onSessionExpired;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  TurnaUserProfile? _profile;
  _UserConversationStats? _conversationStats;
  bool _loading = true;
  bool _statsLoading = true;
  bool _chatLockEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    await Future.wait([_loadProfile(), _loadConversationStats()]);
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await ProfileApi.fetchUser(widget.session, widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadConversationStats() async {
    final chatId = ChatApi.buildDirectChatId(
      widget.session.userId,
      widget.userId,
    );
    if (mounted) {
      setState(() {
        _statsLoading = true;
      });
    }

    try {
      final allMessages = <ChatMessage>[];
      String? before;
      var hasMore = true;

      while (hasMore) {
        final page = await ChatApi.fetchMessagesPage(
          widget.session.token,
          chatId,
          before: before,
          limit: 100,
        );
        allMessages.addAll(page.items);
        hasMore = page.hasMore;
        before = page.nextBefore;
        if (page.items.isEmpty) break;
      }

      var attachmentCount = 0;
      var totalBytes = 0;
      for (final message in allMessages) {
        totalBytes += utf8.encode(message.text).length;
        for (final attachment in message.attachments) {
          attachmentCount += 1;
          totalBytes += attachment.sizeBytes;
        }
      }

      if (!mounted) return;
      setState(() {
        _conversationStats = _UserConversationStats(
          attachmentCount: attachmentCount,
          totalBytes: totalBytes,
        );
        _statsLoading = false;
      });
    } catch (error) {
      turnaLog('user profile conversation stats failed', {
        'userId': widget.userId,
        'error': error.toString(),
      });
      if (!mounted) return;
      setState(() {
        _statsLoading = false;
      });
    }
  }

  Future<void> _startCall(TurnaCallType type) async {
    try {
      final started = await CallApi.startCall(
        widget.session,
        calleeId: widget.userId,
        type: type,
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OutgoingCallPage(
            session: widget.session,
            coordinator: widget.callCoordinator,
            initialCall: started,
            onSessionExpired: widget.onSessionExpired,
          ),
        ),
      );
    } on TurnaUnauthorizedException {
      if (!mounted) return;
      widget.onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showPlaceholderAction(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label yakinda eklenecek.')));
  }

  String _formatConversationCount() {
    if (_statsLoading) return '...';
    return '${_conversationStats?.attachmentCount ?? 0}';
  }

  String _formatConversationStorage() {
    if (_statsLoading) return '...';
    final bytes = _conversationStats?.totalBytes ?? 0;
    return formatBytesLabel(bytes).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final name = profile?.displayName ?? widget.fallbackName;
    final avatarUrl = profile?.avatarUrl ?? widget.fallbackAvatarUrl;

    if (_loading && profile == null) {
      return Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          backgroundColor: TurnaColors.backgroundSoft,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('Kisi bilgisi'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: TurnaColors.backgroundSoft,
        appBar: AppBar(
          backgroundColor: TurnaColors.backgroundSoft,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('Kisi bilgisi'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Kullanici profili yuklenemedi.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadProfile,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final about = profile.about?.trim();
    final phone = profile.phone?.trim();
    final subtitle = about == null || about.isEmpty
        ? 'Merhaba! Ben Turna kullaniyorum.'
        : about;
    final displayedPhone = phone == null || phone.isEmpty
        ? widget.userId
        : phone;

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        backgroundColor: TurnaColors.backgroundSoft,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Kisi bilgisi',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => _showPlaceholderAction('Duzenle'),
            child: const Text(
              'Duzenle',
              style: TextStyle(
                color: Color(0xFF202124),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Center(
            child: GestureDetector(
              onTap: avatarUrl == null || avatarUrl.trim().isEmpty
                  ? null
                  : () => _openAvatarViewer(
                      context,
                      imageUrl: avatarUrl,
                      title: name,
                      token: widget.session.token,
                    ),
              child: _ProfileAvatar(
                label: name,
                avatarUrl: avatarUrl,
                authToken: widget.session.token,
                radius: 56,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              displayedPhone,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF68706C),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF727A76),
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.call_outlined,
                  label: 'Sesli',
                  onTap: () => _startCall(TurnaCallType.audio),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.videocam_outlined,
                  label: 'Goruntulu',
                  onTap: () => _startCall(TurnaCallType.video),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UserProfileActionButton(
                  icon: Icons.search_outlined,
                  label: 'Ara',
                  onTap: () => _showPlaceholderAction('Sohbet ici arama'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.photo_library_outlined,
                title: 'Medya, baglanti ve belgeler',
                trailingText: _formatConversationCount(),
                onTap: () => _showPlaceholderAction('Medya listesi'),
              ),
              _UserProfileRow(
                icon: Icons.folder_outlined,
                title: 'Depolama alanini yonet',
                trailingText: _formatConversationStorage(),
                onTap: () => _showPlaceholderAction('Depolama alani'),
              ),
              _UserProfileRow(
                icon: Icons.star_border_rounded,
                title: 'Yildizli',
                trailingText: 'Yok',
                onTap: () => _showPlaceholderAction('Yildizli mesajlar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.notifications_none_outlined,
                title: 'Bildirimler',
                onTap: () => _showPlaceholderAction('Bildirim ayarlari'),
              ),
              _UserProfileRow(
                icon: Icons.palette_outlined,
                title: 'Sohbet temasi',
                onTap: () => _showPlaceholderAction('Sohbet temasi'),
              ),
              _UserProfileRow(
                icon: Icons.photo_outlined,
                title: "Fotograflar'a Kaydet",
                trailingText: 'Varsayilan',
                onTap: () => _showPlaceholderAction("Fotograflar'a kaydet"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UserProfileGroupCard(
            children: [
              _UserProfileRow(
                icon: Icons.timer_outlined,
                title: 'Sureli mesajlar',
                trailingText: 'Kapali',
                onTap: () => _showPlaceholderAction('Sureli mesajlar'),
              ),
              _UserProfileSwitchRow(
                icon: Icons.lock_outline_rounded,
                title: 'Sohbeti kilitle',
                subtitle: 'Bu sohbeti bu cihazda kilitleyin ve gizleyin.',
                value: _chatLockEnabled,
                onChanged: (value) => setState(() => _chatLockEnabled = value),
              ),
              _UserProfileRow(
                icon: Icons.shield_outlined,
                title: 'Gelismis sohbet gizliligi',
                trailingText: 'Kapali',
                onTap: () =>
                    _showPlaceholderAction('Gelismis sohbet gizliligi'),
              ),
              _UserProfileRow(
                icon: Icons.lock_person_outlined,
                title: 'Sifreleme',
                subtitle: 'Kisisel mesajlar ve aramalar uctan uca sifrelidir.',
                onTap: () => _showPlaceholderAction('Sifreleme bilgisi'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _refreshData,
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaColors.primary,
              side: const BorderSide(color: Color(0xFFB7D9C4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('Sunucudan yenile'),
          ),
        ],
      ),
    );
  }
}

class _UserProfileActionButton extends StatelessWidget {
  const _UserProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: TurnaColors.primary, size: 23),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF202124),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserConversationStats {
  const _UserConversationStats({
    required this.attachmentCount,
    required this.totalBytes,
  });

  final int attachmentCount;
  final int totalBytes;
}

class _UserProfileGroupCard extends StatelessWidget {
  const _UserProfileGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 54, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _UserProfileRow extends StatelessWidget {
  const _UserProfileRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, size: 22, color: const Color(0xFF2B2F2D)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF202124),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.22,
                  color: Color(0xFF7A817D),
                ),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(
              trailingText!,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF7A817D),
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF979D99)),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _UserProfileSwitchRow extends StatelessWidget {
  const _UserProfileSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 22, color: const Color(0xFF2B2F2D)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF202124),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.22,
                    color: Color(0xFF7A817D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: TurnaColors.primary,
            activeTrackColor: TurnaColors.primary100,
          ),
        ],
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Security notifications'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SecurityNotificationsPage(),
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.key_outlined),
            title: Text('Passkeys'),
          ),
          const ListTile(
            leading: Icon(Icons.email_outlined),
            title: Text('Email address'),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Two-step verification'),
          ),
          const ListTile(
            leading: Icon(Icons.numbers_outlined),
            title: Text('Change number'),
          ),
          const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('Request account info'),
          ),
          const ListTile(
            leading: Icon(Icons.person_add_alt_outlined),
            title: Text('Add account'),
          ),
          const ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete account'),
          ),
        ],
      ),
    );
  }
}

class SecurityNotificationsPage extends StatefulWidget {
  const SecurityNotificationsPage({super.key});

  @override
  State<SecurityNotificationsPage> createState() =>
      _SecurityNotificationsPageState();
}

class _SecurityNotificationsPageState extends State<SecurityNotificationsPage> {
  bool enabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.lock, size: 54, color: TurnaColors.primary),
          const SizedBox(height: 12),
          const Text(
            'Security features for your account',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Turna uses secure connections and device protections today. End-to-end encryption for chats and calls is planned for a future update.',
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.message_outlined),
            title: Text('Text and voice messages'),
          ),
          const ListTile(
            leading: Icon(Icons.call_outlined),
            title: Text('Audio and video calls'),
          ),
          const ListTile(
            leading: Icon(Icons.photo_outlined),
            title: Text('photos, videos and documents'),
          ),
          const ListTile(
            leading: Icon(Icons.location_on_outlined),
            title: Text('Location sharing'),
          ),
          const ListTile(
            leading: Icon(Icons.circle_outlined),
            title: Text('Status updates'),
          ),
          SwitchListTile(
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
            title: const Text('Show Security notifications on this device'),
          ),
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title is coming in V1 build.')),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF7D8380)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF5C625F)),
            ),
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenteredListState extends StatelessWidget {
  const _CenteredListState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF7D8380)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5C625F)),
          ),
        ],
      ),
    );
  }
}
