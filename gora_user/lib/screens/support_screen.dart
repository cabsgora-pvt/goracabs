import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/call_util.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  Map<String, dynamic>? _cfg;
  // The helpline of the zone the rider is in, when its zone admin set one.
  String? _zonePhone, _zoneName;
  // FAQs the admin wrote (Support → FAQ in the panel), when there are any.
  List<Map<String, String>> _serverFaqs = const [];

  @override
  void initState() {
    super.initState();
    ApiService.getAppConfig().then((c) {
      if (mounted) setState(() => _cfg = c);
    });
    ApiService.getFaqs().then((f) {
      if (mounted && f.isNotEmpty) setState(() => _serverFaqs = f);
    });
    _loadZoneHelpline();
  }

  Future<void> _loadZoneHelpline() async {
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos == null) return;
      final r = await ApiService.get('/zones/support?lat=${pos.latitude}&lng=${pos.longitude}');
      final phone = _str(r['supportPhone']);
      if (phone != null && mounted) setState(() { _zonePhone = phone; _zoneName = _str(r['zone']); });
    } catch (_) {/* the app-wide number stays */}
  }

  @override
  Widget build(BuildContext context) {
    final support = _cfg?['support'] as Map<String, dynamic>?;
    // No made-up fallback number: with none configured the Call row is hidden.
    final phone = _zonePhone ?? _str(support?['phone']);
    final email = _str(support?['email']) ?? 'support@goracabs.com';
    final whatsapp = _str(support?['whatsapp']);
    final address = _str(support?['address']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildQuickActionCard(
            context,
            'Create Support Ticket',
            'Report an issue or complaint',
            Icons.support_agent,
            Colors.blue,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateTicketScreen())),
          ),
          const SizedBox(height: 12),
          _buildQuickActionCard(
            context,
            'My Tickets',
            'View your support requests',
            Icons.confirmation_number,
            Colors.orange,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen())),
          ),
          const SizedBox(height: 12),
          _buildQuickActionCard(
            context,
            'Any Enquiry',
            'Custom requests and queries',
            Icons.question_answer,
            Colors.green,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EnquiryScreen())),
          ),
          const SizedBox(height: 24),
          const Text('Frequently Asked Questions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._buildFAQs(),
          const SizedBox(height: 24),
          const Text('Contact Us', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Every row used to be plain text: tapping Call / Email / WhatsApp
          // did nothing, and "Live Chat · Available 24/7" did not exist.
          if (phone != null) ...[
            _buildContactCard(context, Icons.phone, _zoneName != null ? 'Call $_zoneName helpline' : 'Call Us', phone,
                onTap: () => dialPhone(phone, context: context)),
          ],
          const SizedBox(height: 10),
          _buildContactCard(context, Icons.email, 'Email Us', email,
              onTap: () => _open(Uri(scheme: 'mailto', path: email, queryParameters: {'subject': 'Gora Cabs support'}))),
          if (whatsapp != null) ...[
            const SizedBox(height: 10),
            _buildContactCard(context, Icons.chat, 'WhatsApp', whatsapp,
                onTap: () => _open(Uri.parse('https://wa.me/${whatsappDigits(whatsapp)}'))),
          ],
          if (address != null) ...[
            const SizedBox(height: 10),
            _buildContactCard(context, Icons.location_on, 'Visit Us', address,
                onTap: () => _open(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'))),
          ],
          const SizedBox(height: 10),
          _buildContactCard(context, Icons.chat_bubble, 'Chat with support', 'Replies in My Tickets',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTicketsScreen()))),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textGrey),
          ],
        ),
      ),
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  List<Widget> _buildFAQs() {
    const fallbackFaqs = [
      {'q': 'How do I cancel a ride?', 'a': 'You can cancel a ride from the trip tracking screen before the driver arrives.'},
      {'q': 'Is there a cancellation fee?', 'a': 'Cancelling before a driver accepts is free. Once a driver is on the way a fee may apply — the app shows the exact amount before you confirm the cancellation.'},
      {'q': 'How do I add money to wallet?', 'a': 'Go to Wallet section and tap on Add Money. Choose amount and payment method.'},
      {'q': 'How do I report a problem with a trip?', 'a': 'Open Help & Support → Create Support Ticket (or Trip Details → Get help). Our team replies in My Tickets.'},
    ];

    List<Map<String, String>> faqs = _serverFaqs;
    final cfgFaqs = _cfg?['faqs'];
    if (faqs.isEmpty && cfgFaqs is List && cfgFaqs.isNotEmpty) {
      faqs = cfgFaqs
          .whereType<Map>()
          .map((f) => {'q': _str(f['q']) ?? '', 'a': _str(f['a']) ?? ''})
          .where((f) => f['q']!.isNotEmpty)
          .toList();
    }
    if (faqs.isEmpty) faqs = fallbackFaqs;

    return faqs.map((faq) {
      return ExpansionTile(
        title: Text(faq['q']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(faq['a']!, style: const TextStyle(fontSize: 13, color: AppTheme.textGrey)),
          ),
        ],
      );
    }).toList();
  }

  Future<void> _open(Uri uri) async {
    var ok = false;
    try { ok = await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app found to open this')));
    }
  }

  Widget _buildContactCard(BuildContext context, IconData icon, String title, String value, {VoidCallback? onTap}) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('contact-$title'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryBlue, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right, color: AppTheme.textGrey),
            ],
          ),
        ),
      ),
    );
  }
}

class CreateTicketScreen extends StatefulWidget {
  /// The ride the problem is about, when opened from a trip.
  final String? rideId;
  const CreateTicketScreen({super.key, this.rideId});

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

/// Ticket category shown to the rider → the key the server stores.
const Map<String, String> kTicketCategories = {
  'Ride Issue': 'ride',
  'Payment Issue': 'payment',
  'Driver Complaint': 'driver',
  'Safety': 'safety',
  'App Issue': 'app',
  'Account': 'account',
  'Other': 'general',
};

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  String? _selectedCategory;
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // Used to only show "created successfully" — nothing reached the server.
  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final message = _descriptionController.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add a subject and describe the problem')));
      return;
    }
    setState(() => _sending = true);
    final res = await ApiService.createSupportTicket(
      subject: subject,
      message: message,
      category: kTicketCategories[_selectedCategory] ?? 'general',
      rideId: widget.rideId,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['success'] == true) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(const SnackBar(content: Text('Ticket sent. Our team will reply in My Tickets.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((res['error'] ?? 'Could not send the ticket. Please try again.').toString()),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration box(String? hint) => InputDecoration(
          fillColor: Theme.of(context).cardColor,
          filled: true,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Create Support Ticket'), elevation: 0, centerTitle: false),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: box(null),
                initialValue: _selectedCategory,
                hint: const Text('Select category'),
                items: kTicketCategories.keys.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
              const SizedBox(height: 20),
              const Text('Subject', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('ticket-subject'),
                controller: _subjectController,
                maxLength: 140,
                decoration: box('Brief description of the issue'),
              ),
              const SizedBox(height: 12),
              const Text('Description', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('ticket-message'),
                controller: _descriptionController,
                maxLines: 5,
                maxLength: 2000,
                decoration: box('Provide detailed information'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                key: const ValueKey('ticket-submit'),
                onPressed: _sending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _sending
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Submit Ticket', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String ticketStatusLabel(String s) => switch (s) {
      'in_progress' => 'In Progress',
      'resolved' => 'Resolved',
      'closed' => 'Closed',
      _ => 'Open',
    };

Color _ticketStatusColor(String s) => switch (s) {
      'resolved' || 'closed' => Colors.green,
      'in_progress' => Colors.orange,
      _ => AppTheme.primaryBlue,
    };

String _ticketDate(dynamic v) {
  final d = DateTime.tryParse((v ?? '').toString())?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${m[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// The rider's own tickets from the server. Used to show three hard-coded
/// sample tickets ("#TKT1234 Driver was rude" …) to every rider.
class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await ApiService.getSupportTickets();
    if (!mounted) return;
    final list = res['tickets'];
    setState(() {
      _loading = false;
      if (list is List) {
        _tickets = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _error = (res['error'] ?? 'Could not load your tickets').toString();
      }
    });
  }

  Future<void> _newTicket() async {
    final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CreateTicketScreen()));
    if (sent == true) _load();
  }

  Widget _card(Map<String, dynamic> t) {
    final status = (t['status'] ?? 'open').toString();
    final color = _ticketStatusColor(status);
    final msgs = (t['messages'] as List?) ?? const [];
    final adminReplied = msgs.any((m) => m is Map && m['sender'] != 'user');
    return InkWell(
      key: ValueKey('ticket-${t['id']}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TicketDetailScreen(ticketId: t['id'].toString())));
        if (mounted) _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text((t['subject'] ?? '').toString(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(ticketStatusLabel(status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(_ticketDate(t['updatedAt'] ?? t['createdAt']), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          if (adminReplied) ...[
            const SizedBox(height: 6),
            const Text('Support replied — tap to read',
                style: TextStyle(fontSize: 12.5, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    } else if (_tickets.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.support_agent, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('No tickets yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Raise a ticket and our team will reply here.',
                style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _newTicket, child: const Text('Create ticket')),
          ]),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [for (final t in _tickets) _card(t)]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tickets'),
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'New ticket', onPressed: _newTicket)],
      ),
      body: body,
    );
  }
}

/// One ticket's conversation with Gora Support, with a reply box.
class TicketDetailScreen extends StatefulWidget {
  final String ticketId;
  const TicketDetailScreen({super.key, required this.ticketId});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  Map<String, dynamic>? _ticket;
  String? _error;
  bool _sending = false;
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await ApiService.getSupportTicket(widget.ticketId);
    if (!mounted) return;
    setState(() {
      if (res['ticket'] is Map) {
        _ticket = Map<String, dynamic>.from(res['ticket'] as Map);
        _error = null;
      } else {
        _error = (res['error'] ?? 'Could not load this ticket').toString();
      }
    });
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await ApiService.replySupportTicket(widget.ticketId, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['ticket'] is Map) {
      _reply.clear();
      setState(() => _ticket = Map<String, dynamic>.from(res['ticket'] as Map));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((res['error'] ?? 'Could not send').toString())));
    }
  }

  Widget _bubble(Map m) {
    final mine = m['sender'] == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? AppTheme.primaryBlue.withValues(alpha: 0.10) : Colors.grey.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mine ? 'You' : 'Gora Support', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text((m['message'] ?? '').toString(), style: const TextStyle(fontSize: 14.5)),
          const SizedBox(height: 4),
          Text(_ticketDate(m['sentAt']), style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket'), elevation: 0),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ]),
        ),
      );
    }
    final status = (t['status'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: Text((t['subject'] ?? 'Ticket').toString()), elevation: 0),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _ticketStatusColor(status).withValues(alpha: 0.08),
          child: Text('Status: ${ticketStatusLabel(status)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [for (final m in ((t['messages'] as List?) ?? const []).whereType<Map>()) _bubble(m)],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ticket-reply'),
                  controller: _reply,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Write a reply', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class EnquiryScreen extends StatefulWidget {
  const EnquiryScreen({super.key});

  @override
  State<EnquiryScreen> createState() => _EnquiryScreenState();
}

class _EnquiryScreenState extends State<EnquiryScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // Used to only show "submitted successfully" — nothing was sent. It now
  // reaches the admin as a support ticket.
  Future<void> _sendEnquiry() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please write your message')));
      return;
    }
    final contact = [
      if (_nameController.text.trim().isNotEmpty) 'Name: ${_nameController.text.trim()}',
      if (_phoneController.text.trim().isNotEmpty) 'Phone: ${_phoneController.text.trim()}',
      if (_emailController.text.trim().isNotEmpty) 'Email: ${_emailController.text.trim()}',
    ].join('\n');
    setState(() => _sending = true);
    final res = await ApiService.createSupportTicket(
      subject: 'Enquiry',
      message: contact.isEmpty ? msg : '$msg\n\n$contact',
      category: 'general',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['success'] == true) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Enquiry sent. We will reply in My Tickets.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((res['error'] ?? 'Could not send. Please try again.').toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Any Enquiry'),
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.primaryBlue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Have a custom request? Fill out the form below and our team will get back to you.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  fillColor: Theme.of(context).cardColor,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  fillColor: Theme.of(context).cardColor,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  fillColor: Theme.of(context).cardColor,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Your Message',
                  fillColor: Theme.of(context).cardColor,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _sending ? null : _sendEnquiry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Submit Enquiry', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// WhatsApp wants the number in international form, digits only: an Indian
/// 10-digit number gets 91 in front.
String whatsappDigits(String raw) {
  final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return d.length == 10 ? '91$d' : d;
}
