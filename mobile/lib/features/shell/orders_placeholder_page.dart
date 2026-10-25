import 'package:flutter/material.dart';

class OrdersPlaceholderPage extends StatelessWidget {
  const OrdersPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pesanan')),
      body: const Center(child: Text('Daftar pesanan hadir di tahap berikutnya.')),
    );
  }
}