import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/google_drive_backup_service.dart';
import '../theme/app_palette.dart';

class GoogleDriveBackupScreen extends StatelessWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive Backup')),
      body: const _Body(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<GoogleDriveBackupService>();

    return ListView(
      children: [
        _SetupCard(),
        const Divider(height: 1),
        _AccountSection(service: service),
        if (service.isSignedIn) ...[
          const Divider(height: 1),
          _BackupRestoreSection(service: service),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Setup prerequisites card
// ---------------------------------------------------------------------------

class _SetupCard extends StatefulWidget {
  @override
  State<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends State<_SetupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(Icons.info_outline, color: context.palette.accent),
      title: const Text('Setup requirements'),
      subtitle: const Text(
        'Google Cloud Console configuration needed before first sign-in',
      ),
      onExpansionChanged: (v) => setState(() => _expanded = v),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To enable Google Drive backup, a one-time setup in the '
                'Google Cloud Console is required:\n',
              ),
              _Step(
                n: '1',
                text: 'Create or open a project in Google Cloud Console and '
                    'enable the Google Drive API.',
              ),
              _Step(
                n: '2',
                text: 'Under "Credentials", create an Android OAuth 2.0 client '
                    'with:\n'
                    '  • Package name: com.example.todo_app\n'
                    '  • SHA-1 fingerprint of your debug or release keystore.',
              ),
              _Step(
                n: '3',
                text: 'Add your Google account to the OAuth test users list '
                    '(while the app is in "Testing" mode).',
              ),
              const SizedBox(height: 8),
              Text(
                'Your data is stored in a private app folder in Google Drive '
                'that only this app can access. It is deleted automatically if '
                'the app is uninstalled.',
                style: TextStyle(
                  color: context.palette.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;

  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$n. ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.palette.accent,
            ),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account sign-in / sign-out
// ---------------------------------------------------------------------------

class _AccountSection extends StatelessWidget {
  final GoogleDriveBackupService service;

  const _AccountSection({required this.service});

  @override
  Widget build(BuildContext context) {
    final user = service.currentUser;

    if (user == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Google Account',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              onPressed: service.isBusy ? null : () => _signIn(context),
            ),
          ],
        ),
      );
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
        child: user.photoUrl == null
            ? Text(
                (user.displayName?.isNotEmpty == true
                        ? user.displayName![0]
                        : user.email[0])
                    .toUpperCase(),
              )
            : null,
      ),
      title: Text(user.displayName ?? user.email),
      subtitle: Text(user.email),
      trailing: TextButton(
        onPressed: service.isBusy ? null : () => service.signOut(),
        child: const Text('Sign out'),
      ),
    );
  }

  Future<void> _signIn(BuildContext context) async {
    final ok = await service.signIn();
    if (!ok && context.mounted && service.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(service.lastError!)),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Backup and restore actions
// ---------------------------------------------------------------------------

class _BackupRestoreSection extends StatelessWidget {
  final GoogleDriveBackupService service;

  const _BackupRestoreSection({required this.service});

  @override
  Widget build(BuildContext context) {
    final lastBackup = service.lastBackupAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Backup & Restore',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        if (service.lastError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 14, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    service.lastError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ListTile(
          leading: service.isBusy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined),
          title: const Text('Back up now'),
          subtitle: Text(
            lastBackup == null
                ? 'Never backed up'
                : 'Last backup: ${_formatAge(lastBackup)}',
          ),
          onTap: service.isBusy ? null : () => _backup(context),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: const Text('Restore from Drive'),
          subtitle: const Text(
            'Downloads your Drive backup and replaces all local data',
          ),
          onTap: service.isBusy ? null : () => _restore(context),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            'Backups run automatically once per hour while you are signed in.',
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ),
      ],
    );
  }

  Future<void> _backup(BuildContext context) async {
    final ok = await service.backup();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Backup saved to Google Drive' : (service.lastError ?? 'Backup failed'),
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore from Google Drive?'),
        content: const Text(
          'This will replace all your current goals, settings, and today\'s '
          'focus list with the data from your Drive backup. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await service.restore();
    if (!context.mounted) return;
    if (result.ok) {
      final msg = result.skipped == 0
          ? 'Restored ${result.imported} goals from Google Drive'
          : 'Restored ${result.imported} goals (${result.skipped} skipped)';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(service.lastError ?? 'Restore failed')),
      );
    }
  }

  static String _formatAge(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays} days ago';
  }
}
