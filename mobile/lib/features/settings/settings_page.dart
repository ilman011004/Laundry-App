import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_error.dart';
import '../../core/api_providers.dart';
import '../../core/labels.dart';
import '../auth/auth_controller.dart';
import 'business_repository.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final r = await showDialog<({String oldPassword, String newPassword})>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (r == null) return;

    String message = 'Password berhasil diganti';
    try {
      await ref.read(dioProvider).patch('/api/auth/password', data: {
        'oldPassword': r.oldPassword,
        'newPassword': r.newPassword,
      });
    } catch (e) {
      message = errorMessage(e);
    }
    if (context.mounted) _snack(context, message);
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final bizName = ref.watch(businessProvider).asData?.value.name;
    final theme = Theme.of(context);
    final isOwner = user?.isOwner ?? false;

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Akun yang sedang dipakai
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 24,
                child: Text(
                  (user?.name.isNotEmpty ?? false)
                      ? user!.name[0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(
                user?.name ?? '-',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${labelOf(roleLabel, user?.role)} • @${user?.username ?? '-'}',
              ),
            ),
          ),

          // ---- Keuangan (Pemilik dan Kasir)
          header('Keuangan'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(isOwner ? 'Kas Usaha' : 'Kas Saya'),
              subtitle: Text(
                isOwner
                    ? 'Total kas, kas tiap kasir, dan konfirmasi setoran'
                    : 'Kas yang Anda pegang dan setoran ke pemilik',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/cash'),
            ),
          ),

          // ---- Usaha (khusus Pemilik)
          if (isOwner) ...[
            header('Usaha'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront),
                title: const Text('Profil Usaha'),
                subtitle: Text(
                  bizName == null || bizName.isEmpty
                      ? 'Nama usaha, nomor telepon, dan alamat'
                      : '$bizName • nama, telepon, dan alamat',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/business'),
              ),
            ),
          ],

          // ---- Akun
          header('Akun'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Ganti password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changePassword(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout, color: theme.colorScheme.error),
                  title: Text(
                    'Keluar',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () => _logout(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ganti password'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _old,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password lama'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Password lama wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _new,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password baru',
                  helperText: 'Minimal 8 karakter',
                ),
                validator: (v) => (v == null || v.length < 8)
                    ? 'Password baru minimal 8 karakter'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Ulangi password baru'),
                validator: (v) =>
                    v != _new.text ? 'Password tidak sama' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              oldPassword: _old.text,
              newPassword: _new.text,
            ));
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}