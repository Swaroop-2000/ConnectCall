import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../services/notification_service.dart';
import '../../theme/theme_provider.dart';
import '../auth/login_screen.dart';
import '../splash/splash_screen.dart';

import 'dart:async';

// ─── Real-time Stats Providers ────────────────────────────────────────────────

final _callStatsProvider = StreamProvider.autoDispose<Map<String, int>>((ref) {
  final auth = ref.watch(authServiceProvider);
  final uid = auth.currentUser?.uid ?? '';
  if (uid.isEmpty) return Stream.value({'totalCalls': 0, 'totalSeconds': 0});

  final controller = StreamController<Map<String, int>>();
  List<QueryDocumentSnapshot> callerDocs = [];
  List<QueryDocumentSnapshot> calleeDocs = [];

  void emit() {
    int totalSeconds = 0;
    final allDocs = [...callerDocs, ...calleeDocs];
    for (final doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      totalSeconds += (data['durationSeconds'] as num?)?.toInt() ?? 0;
    }
    controller.add({'totalCalls': allDocs.length, 'totalSeconds': totalSeconds});
  }

  final sub1 = FirebaseFirestore.instance
      .collection('call_history')
      .where('callerId', isEqualTo: uid)
      .snapshots()
      .listen((snap) {
    callerDocs = snap.docs;
    emit();
  });

  final sub2 = FirebaseFirestore.instance
      .collection('call_history')
      .where('calleeId', isEqualTo: uid)
      .snapshots()
      .listen((snap) {
    calleeDocs = snap.docs;
    emit();
  });

  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
    controller.close();
  });

  return controller.stream;
});

final _contactsCountProvider = StreamProvider.autoDispose<int>((ref) {
  final auth = ref.watch(authServiceProvider);
  final currentUid = auth.currentUser?.uid ?? '';
  return FirebaseFirestore.instance
      .collection('users')
      .snapshots()
      .map((snap) => snap.docs.where((d) => d.id != currentUid).length);
});

// ─── Profile Screen ───────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isUploadingPhoto = false;

  Future<void> _pickAndUploadImage(User user, ImageSource source) async {
    Navigator.pop(context);
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
          source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85);
      if (image == null) return;

      setState(() => _isUploadingPhoto = true);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_profiles')
          .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await storageRef.putData(
            bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await storageRef.putFile(File(image.path));
      }

      final downloadUrl = await storageRef.getDownloadURL();

      // Update Auth
      await user.updatePhotoURL(downloadUrl);
      await user.reload();

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'photoUrl': downloadUrl,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload image: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _removePhoto(User user) async {
    Navigator.pop(context);
    try {
      setState(() => _isUploadingPhoto = true);
      // Update Auth (some platforms ignore null, so we use empty string)
      await user.updatePhotoURL('');
      await user.reload();

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'photoUrl': '', // Use empty string instead of delete() for consistency
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _showPhotoOptions(BuildContext context, User user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(height: 24),
            Text('Profile Photo',
                style: TextStyle(
                    color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: Theme.of(context).colorScheme.primary),
              title: Text('Take a Photo', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black))),
              onTap: () => _pickAndUploadImage(user, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: Theme.of(context).colorScheme.primary),
              title: Text('Choose from Gallery', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black))),
              onTap: () => _pickAndUploadImage(user, ImageSource.gallery),
            ),
            if (user.photoURL != null && user.photoURL!.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text('Remove Photo', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () => _removePhoto(user),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authServiceProvider).currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    final displayName = user.displayName ?? 'Unknown User';
    final email = user.email ?? 'No Email';
    final initial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final photoUrl = user.photoURL;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _ProfileHeader(
              displayName: displayName,
              email: email,
              initial: initial,
              photoUrl: photoUrl,
              isUploading: _isUploadingPhoto,
              onAvatarTap: () => _showPhotoOptions(context, user),
              onEditTap: () => _showEditNameDialog(context, ref, user, displayName),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatsRow(),
                  SizedBox(height: 28),

                  // Account
                  _SectionLabel('Account'),
                  SizedBox(height: 10),
                  _SettingsCard(items: [
                    _SettingsItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Display Name',
                      value: displayName,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(displayName, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
                          const SizedBox(width: 8),
                          Icon(Icons.edit_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                      color: Theme.of(context).colorScheme.primary,
                      onTap: () =>
                          _showEditNameDialog(context, ref, user, displayName),
                    ),
                    _SettingsItem(
                      icon: Icons.email_outlined,
                      label: 'Email Address',
                      value: email,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    _SettingsItem(
                      icon: Icons.lock_outline_rounded,
                      label: 'Password',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('********', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
                          const SizedBox(width: 8),
                          Icon(Icons.edit_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                      color: Colors.amber,
                      onTap: () async {
                        if (user.email == null || user.email!.isEmpty) return;
                        try {
                          await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password reset email sent! Check your inbox.'),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              )
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.toString().replaceAll(RegExp(r'\[.*?\]\s*'), '')),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              )
                            );
                          }
                        }
                      },
                    ),
                    _SettingsItem(
                      icon: Icons.verified_user_outlined,
                      label: 'Account Type',
                      value: 'Free Tier',
                      color: AppColors.callGreen,
                    ),
                  ]),
                  SizedBox(height: 24),

                  // Preferences
                  _SectionLabel('Preferences'),
                  SizedBox(height: 10),
                  _SettingsCard(items: [
                    const _DarkModeToggleItem(),
                    const _NotificationToggleItem(),
                    _SettingsItem(
                      icon: Icons.mic_outlined,
                      label: 'Microphone Quality',
                      value: 'High',
                      color: Theme.of(context).colorScheme.primary,
                      onTap: () =>
                          _showComingSoon(context, 'Microphone Quality'),
                    ),
                    _SettingsItem(
                      icon: Icons.videocam_outlined,
                      label: 'Camera Resolution',
                      value: '720p',
                      color: Theme.of(context).colorScheme.secondary,
                      onTap: () =>
                          _showComingSoon(context, 'Camera Resolution'),
                    ),
                  ]),
                  SizedBox(height: 24),

                  // App
                  _SectionLabel('App'),
                  SizedBox(height: 10),
                  _SettingsCard(items: [
                    _SettingsItem(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy Policy',
                      color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey),
                      onTap: () => _showComingSoon(context, 'Privacy Policy'),
                    ),
                    _SettingsItem(
                      icon: Icons.info_outline_rounded,
                      label: 'App Version',
                      value: '1.0.0',
                      color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey),
                    ),
                  ]),
                  SizedBox(height: 32),

                  _LogoutButton(user: user),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(
      BuildContext context, WidgetRef ref, User user, String currentName) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => _EditProfileSheet(user: user, ref: ref),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _showComingSoon(BuildContext context, String feature) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.construction_rounded,
                  color: Theme.of(context).colorScheme.primary, size: 32),
            ),
            SizedBox(height: 16),
            Text(feature,
                style: TextStyle(
                    color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              'This feature is coming soon.\nStay tuned for future updates!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey), fontSize: 14, height: 1.6),
            ),
            SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

// ─── Edit Profile Sheet ───────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final User user;
  final WidgetRef ref;
  const _EditProfileSheet({required this.user, required this.ref});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.user.displayName ?? '');
    _emailCtrl =
        TextEditingController(text: widget.user.email ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName = _nameCtrl.text.trim();
    final newEmail = _emailCtrl.text.trim();
    if (newName.isEmpty) {
      setState(() => _error = 'Name cannot be empty');
      return;
    }
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Update Firebase Auth profile
      if (newName != widget.user.displayName) {
        await widget.user.updateDisplayName(newName);
      }
      if (newEmail != widget.user.email) {
        // Use verifyBeforeUpdateEmail since updateEmail is removed in newer firebase_auth
        await widget.user.verifyBeforeUpdateEmail(newEmail);
      }
      await widget.user.reload();

      // Update Firestore users collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({
        'name': newName,
        'email': newEmail,
      });

      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = 'Auth Error: ${e.message}';
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to update profile: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(height: 20),

          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.edit_rounded,
                    color: Theme.of(context).colorScheme.primary, size: 20),
              ),
              SizedBox(width: 12),
              Text(
                'Edit Profile',
                style: TextStyle(
                    color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Name field
          Text(
            'Display Name',
            style: TextStyle(
                color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black)),
            decoration: InputDecoration(
              hintText: 'Enter your display name',
              prefixIcon: Icon(Icons.person_outline_rounded,
                  color: Theme.of(context).colorScheme.primary),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: 16),

          // Email field
          Text(
            'Email Address',
            style: TextStyle(
                color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black)),
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Enter your email address',
              prefixIcon: Icon(Icons.email_outlined,
                  color: Theme.of(context).colorScheme.primary),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
              ),
            ),
          ),

          if (_error != null) ...[
            SizedBox(height: 10),
            Text(_error!,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],

          SizedBox(height: 24),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey),
                    side: BorderSide(color: Color(0xFF2A2A4A)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text('Cancel'),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    minimumSize: Size.zero,
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Save Changes',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Profile Header ───────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String displayName;
  final String email;
  final String initial;
  final String? photoUrl;
  final bool isUploading;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditTap;

  const _ProfileHeader({
    required this.displayName,
    required this.email,
    required this.initial,
    required this.photoUrl,
    required this.isUploading,
    required this.onAvatarTap,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F3460), Theme.of(context).scaffoldBackgroundColor],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          child: Column(
            children: [
              // Avatar with edit overlay
              Stack(
                alignment: Alignment.center,
                children: [
                  // Glow ring
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  // Avatar
                  GestureDetector(
                    onTap: onAvatarTap,
                    child: Stack(
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: photoUrl != null && photoUrl!.isNotEmpty
                                ? Image.network(
                                    photoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _InitialText(initial),
                                  )
                                : _InitialText(initial),
                          ),
                        ),
                        if (isUploading)
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.6),
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Edit Camera Badge
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: onAvatarTap,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text(
                displayName,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3),
              ),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.email_outlined,
                      size: 14, color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey)),
                  SizedBox(width: 6),
                  Text(email,
                      style: TextStyle(
                          color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey), fontSize: 14)),
                ],
              ),
              SizedBox(height: 12),
              // Online badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.callGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.callGreen.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: AppColors.callGreen, size: 8),
                    SizedBox(width: 6),
                    Text('Online',
                        style: TextStyle(
                            color: AppColors.callGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              SizedBox(height: 16),
                          ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> items;
  const _SettingsCard({required this.items});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(children: items),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? color;
  final String? value;
  final bool isDestructive;
  final Widget? trailing;
  
  const _SettingsItem({required this.icon, required this.label, this.subtitle, this.onTap, this.color, this.value, this.isDestructive=false, this.trailing});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: isDestructive ? Colors.red : null)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? (value != null ? Text(value!) : null),
      onTap: onTap,
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  final user;
  const _LogoutButton({this.user});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.logout, color: Colors.white),
          label: const Text('Log Out', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 10),
                    const Text('Log Out'),
                  ],
                ),
                content: const Text('Are you sure you want to log out of ConnectCall?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final navigator = Navigator.of(context);
                      await ref.read(authServiceProvider).signOut();
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    child: const Text('Log Out'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InitialText extends StatelessWidget {
  final String initial;
  const _InitialText(this.initial);
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary,
      child: Center(
        child: Text(initial, style: TextStyle(color: Colors.white, fontSize: 32)),
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_callStatsProvider);
    final contactsAsync = ref.watch(_contactsCountProvider);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            context,
            icon: Icons.call_outlined,
            title: 'Total Calls',
            value: statsAsync.when(
              data: (data) => data['totalCalls'].toString(),
              loading: () => '-',
              error: (_, __) => '0',
            ),
          ),
          _buildDivider(context),
          _buildStatItem(
            context,
            icon: Icons.timer_outlined,
            title: 'Minutes Spoke',
            value: statsAsync.when(
              data: (data) => (data['totalSeconds']! / 60).ceil().toString(),
              loading: () => '-',
              error: (_, __) => '0',
            ),
          ),
          _buildDivider(context),
          _buildStatItem(
            context,
            icon: Icons.people_outline,
            title: 'Total Contacts',
            value: contactsAsync.when(
              data: (count) => count.toString(),
              loading: () => '-',
              error: (_, __) => '0',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, {required IconData icon, required String title, required String value}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7))),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      height: 40,
      width: 1,
      color: Theme.of(context).dividerColor.withOpacity(0.2),
    );
  }
}

class _NotificationToggleItem extends ConsumerStatefulWidget {
  const _NotificationToggleItem();
  @override
  ConsumerState<_NotificationToggleItem> createState() => _NotificationToggleItemState();
}
class _NotificationToggleItemState extends ConsumerState<_NotificationToggleItem> {
  bool _isEnabled = false;
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadState();
  }
  Future<void> _loadState() async {
    final service = ref.read(notificationServiceProvider);
    final isEnabled = await service.isEnabled();
    if (mounted) setState(() { _isEnabled = isEnabled; _isLoading = false; });
  }
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_isEnabled ? Icons.notifications_active : Icons.notifications_off_outlined, color: _isEnabled ? Theme.of(context).colorScheme.primary : Colors.grey),
      title: const Text('Notifications'),
      subtitle: Text(_isLoading ? 'Loading...' : (_isEnabled ? 'Enabled' : 'Disabled')),
      trailing: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Switch(
        value: _isEnabled,
        activeColor: Theme.of(context).colorScheme.primary,
        onChanged: (val) async {
          setState(() => _isLoading = true);
          final service = ref.read(notificationServiceProvider);
          if (val) await service.requestPermissions();
          else await service.disableNotifications();
          await _loadState();
        },
      ),
    );
  }
}
class _DarkModeToggleItem extends ConsumerWidget {
  const _DarkModeToggleItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return ListTile(
      leading: Icon(
        isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
        color: isDark ? Colors.amber : Colors.orangeAccent,
      ),
      title: const Text('Dark Mode'),
      subtitle: Text(isDark ? 'Enabled' : 'Disabled'),
      trailing: Switch(
        value: isDark,
        activeColor: Theme.of(context).colorScheme.primary,
        onChanged: (_) {
          ref.read(themeProvider.notifier).toggleTheme();
        },
      ),
    );
  }
}
