import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';

// ── Status helpers ──────────────────────────────────────────
Color _statusColor(String status) {
  switch (status) {
    case 'open':
      return AppColors.orange;
    case 'in_progress':
      return AppColors.primary;
    case 'resolved':
    case 'closed':
      return AppColors.green;
    default:
      return AppColors.textGrey;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'in_progress':
      return 'In Progress';
    default:
      return status.isEmpty ? '' : '${status[0].toUpperCase()}${status.substring(1)}';
  }
}

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final d = dt.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
}

class SupportPage extends StatefulWidget {
  static const route = '/support-tickets';
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _tickets = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await DriverApiService.getSupportTickets();
      final list = (res['tickets'] as List? ?? [])
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _tickets = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Support Tickets', actions: [
        IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: _newTicket),
      ]),
      backgroundColor: AppColors.cardBg,
      body: _loading
          ? const AppLoader()
          : _tickets.isEmpty
              ? const EmptyState(message: 'No support tickets yet', icon: Icons.support_agent)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _tickets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ticketCard(_tickets[i]),
                  ),
                ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> t) {
    final status = (t['status'] as String?) ?? 'open';
    final messages = (t['messages'] as List? ?? []);
    final lastMessage = messages.isNotEmpty
        ? (Map<String, dynamic>.from(messages.last as Map)['message'] as String? ?? '')
        : '';
    final date = _fmtDate((t['updatedAt'] ?? t['createdAt']) as String?);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openTicket(t['_id'] as String),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                (t['subject'] as String?) ?? 'Ticket',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _statusChip(status),
          ]),
          if (lastMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(lastMessage, style: const TextStyle(fontSize: 12, color: AppColors.textGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          Text(date, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
        ]),
      ),
    );
  }

  Widget _statusChip(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(_statusLabel(status), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Future<void> _openTicket(String id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SupportTicketDetailPage(ticketId: id)));
    if (mounted) _load();
  }

  void _newTicket() {
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Future<void> submit() async {
              final subject = subjectCtrl.text.trim();
              final message = messageCtrl.text.trim();
              if (subject.isEmpty || message.isEmpty) {
                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                  const SnackBar(content: Text('Please enter a subject and a message'), backgroundColor: AppColors.red),
                );
                return;
              }
              setSheet(() => submitting = true);
              try {
                final res = await DriverApiService.createSupportTicket(subject, message);
                if (res['success'] == true || res['ticket'] != null) {
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  if (!mounted) return;
                  await _load();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ticket created'), backgroundColor: AppColors.green),
                  );
                } else {
                  setSheet(() => submitting = false);
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                      SnackBar(content: Text(res['message']?.toString() ?? 'Failed to create ticket'), backgroundColor: AppColors.red),
                    );
                  }
                }
              } catch (_) {
                setSheet(() => submitting = false);
                if (sheetCtx.mounted) {
                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                    const SnackBar(content: Text('Something went wrong'), backgroundColor: AppColors.red),
                  );
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('New Support Ticket', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 16),
                TextField(
                  controller: subjectCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Subject', hintText: 'Brief summary of the issue'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Message', hintText: 'Describe your issue...', alignLabelWithHint: true),
                ),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Submit Ticket', loading: submitting, onTap: submit),
                const SizedBox(height: 20),
              ]),
            );
          },
        );
      },
    );
  }
}

// ── Ticket detail (conversation thread) ─────────────────────
class SupportTicketDetailPage extends StatefulWidget {
  final String ticketId;
  const SupportTicketDetailPage({super.key, required this.ticketId});

  @override
  State<SupportTicketDetailPage> createState() => _SupportTicketDetailPageState();
}

class _SupportTicketDetailPageState extends State<SupportTicketDetailPage> {
  bool _loading = true;
  bool _sending = false;
  Map<String, dynamic>? _ticket;
  final _replyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _replyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final res = await DriverApiService.getSupportTicket(widget.ticketId);
      final ticket = res['ticket'] == null ? null : Map<String, dynamic>.from(res['ticket'] as Map);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      if (!silent) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _reply() async {
    final message = _replyCtrl.text.trim();
    if (message.isEmpty) return;
    setState(() => _sending = true);
    try {
      final res = await DriverApiService.replySupportTicket(widget.ticketId, message);
      if (!mounted) return;
      if (res['success'] == true || res['ticket'] != null) {
        _replyCtrl.clear();
      }
      await _load(silent: true);
    } catch (_) {
      // ignore; user can retry
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (_ticket?['status'] as String?) ?? 'open';
    final messages = (_ticket?['messages'] as List? ?? [])
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    return Scaffold(
      appBar: blueAppBar(
        (_ticket?['subject'] as String?) ?? 'Ticket',
        actions: _ticket == null ? null : [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: _statusPill(status)))],
      ),
      backgroundColor: AppColors.cardBg,
      body: _loading
          ? const AppLoader()
          : Column(children: [
              Expanded(
                child: messages.isEmpty
                    ? const EmptyState(message: 'No messages yet', icon: Icons.chat_bubble_outline)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => _bubble(messages[i]),
                      ),
              ),
              _replyBar(status),
            ]),
    );
  }

  Widget _statusPill(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
      child: Text(_statusLabel(status), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final isMe = (m['sender'] as String?) == 'driver';
    final text = (m['message'] as String?) ?? '';
    final time = _fmtDate(m['sentAt'] as String?);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMe ? 14 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 14),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(fontSize: 13.5, color: isMe ? Colors.white : AppColors.textDark)),
          if (time.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(time, style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : AppColors.textGrey)),
          ],
        ]),
      ),
    );
  }

  Widget _replyBar(String status) {
    final closed = status == 'closed' || status == 'resolved';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
        ),
        child: closed
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'This ticket is ${_statusLabel(status).toLowerCase()}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
              )
            : Row(children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Type a reply...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      filled: true,
                      fillColor: AppColors.cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _sending
                    ? const SizedBox(width: 44, height: 44, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))))
                    : Material(
                        color: AppColors.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _reply,
                          child: const SizedBox(width: 44, height: 44, child: Icon(Icons.send, color: Colors.white, size: 20)),
                        ),
                      ),
              ]),
      ),
    );
  }
}
