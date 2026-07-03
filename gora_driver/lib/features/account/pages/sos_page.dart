import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';

class SosPage extends StatefulWidget {
  static const route = '/sos';
  const SosPage({super.key});
  @override State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  final contacts = List<SOSContact>.from(mockSOSContacts);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('SOS Contacts', actions: [
        IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: _addContact),
      ]),
      backgroundColor: AppColors.cardBg,
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.red.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.sos, color: AppColors.red, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text('In an emergency, press SOS to alert all contacts instantly.', style: TextStyle(fontSize: 13, color: AppColors.textDark))),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
              child: Row(children: [
                CircleAvatar(backgroundColor: AppColors.red.withOpacity(0.12), radius: 22,
                  child: Text(contacts[i].name[0], style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(contacts[i].name, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  Text('${contacts[i].phone}  •  ${contacts[i].relation}', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                ])),
                IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red), onPressed: () => setState(() => contacts.removeAt(i))),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.sos, size: 22),
            label: const Text('SEND SOS ALERT', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOS alert sent to all contacts!'), backgroundColor: AppColors.red)),
          ),
        ),
      ]),
    );
  }

  void _addContact() {
    showDialog(context: context, builder: (_) {
      final name = TextEditingController(), phone = TextEditingController(), rel = TextEditingController();
      return AlertDialog(
        title: const Text('Add SOS Contact', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
          const SizedBox(height: 8),
          TextField(controller: rel, decoration: const InputDecoration(labelText: 'Relation')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            setState(() => contacts.add(SOSContact(name: name.text, phone: phone.text, relation: rel.text)));
            Navigator.pop(_);
          }, child: const Text('Add')),
        ],
      );
    });
  }
}
