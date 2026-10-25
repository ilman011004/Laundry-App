import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_error.dart';
import 'customer_models.dart';
import 'customers_repository.dart';

class CustomerFormPage extends ConsumerStatefulWidget {
  const CustomerFormPage({super.key, this.customerId});

  /// null = tambah pelanggan baru, isi = ubah pelanggan tersebut.
  final int? customerId;

  @override
  ConsumerState<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends ConsumerState<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  final _addressLabel = TextEditingController(text: 'Rumah');
  final _address = TextEditingController();

  bool get _isEdit => widget.customerId != null;
  bool _loadingData = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExisting();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _notes, _addressLabel, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loadingData = true);
    try {
      final d = await ref.read(customersRepositoryProvider).detail(widget.customerId!);
      final Customer c = d.customer;
      _name.text = c.name;
      _phone.text = c.phone;
      _notes.text = c.notes ?? '';
    } catch (e) {
      _error = errorMessage(e);
    }
    if (mounted) setState(() => _loadingData = false);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(customersRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(widget.customerId!,
            name: _name.text, phone: _phone.text, notes: _notes.text);
      } else {
        await repo.create(
          name: _name.text,
          phone: _phone.text,
          notes: _notes.text,
          addressLabel: _addressLabel.text,
          address: _address.text,
        );
      }
      if (mounted) context.pop(true);
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
      appBar: AppBar(title: Text(_isEdit ? 'Ubah Pelanggan' : 'Pelanggan Baru')),
      body: _loadingData
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Nama'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phone,
                      enabled: !_saving,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nomor HP',
                        hintText: '0812xxxxxxx',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Nomor HP wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notes,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
                    ),
                    if (!_isEdit) ...[
                      const SizedBox(height: 24),
                      Text('Alamat (opsional)',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _addressLabel,
                        enabled: !_saving,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Label (Rumah, Kantor, ...)'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _address,
                        enabled: !_saving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Alamat lengkap'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          textAlign: TextAlign.center,
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
                                child: CircularProgressIndicator(strokeWidth: 2))
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