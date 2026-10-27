import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_error.dart';
import '../../core/api_providers.dart';
import 'business_repository.dart';

class BusinessPage extends ConsumerStatefulWidget {
  const BusinessPage({super.key});

  @override
  ConsumerState<BusinessPage> createState() => _BusinessPageState();
}

class _BusinessPageState extends ConsumerState<BusinessPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await ref.read(businessProvider.future);
      _name.text = b.name;
      _phone.text = b.phone;
      _address.text = b.address;
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/api/business', data: {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
      });
      ref.invalidate(businessProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profil usaha tersimpan')));
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil Usaha')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Nama usaha tampil di bagian atas Beranda dan nanti di nota '
                      'untuk pelanggan.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nama usaha'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Nama usaha wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Nomor telepon / WhatsApp'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _address,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Alamat'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}