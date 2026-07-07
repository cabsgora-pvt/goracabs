import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

// In-ride chat between the rider and the assigned driver. Polls every 3s.
// Includes ready-made quick replies (like Ola/Rapido).
class RideChatScreen extends StatefulWidget {
  final String rideId;
  final String otherName; // driver's name
  const RideChatScreen({super.key, required this.rideId, this.otherName = 'Driver'});
  @override
  State<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends State<RideChatScreen> {
  static const _brand = Color(0xFF1C2656);
  static const _quickReplies = [
    "I'm at the pickup point",
    "Please wait 2 minutes",
    "Where are you?",
    "Coming in a moment",
    "Please call me",
    "Okay, thank you",
  ];

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.getRideMessages(widget.rideId);
      final list = ((res['messages'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      final grew = list.length != _messages.length;
      setState(() => _messages = list);
      if (grew) _scrollToEnd();
    } catch (_) {}
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      // optimistic
      _messages = [..._messages, {'sender': 'user', 'text': t, 'createdAt': ''}];
    });
    _controller.clear();
    _scrollToEnd();
    try {
      final res = await ApiService.sendRideMessage(widget.rideId, t);
      final list = ((res['messages'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted && list.isNotEmpty) setState(() => _messages = list);
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        title: Text(widget.otherName, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Text('Say hi to ${widget.otherName} 👋', style: TextStyle(color: Colors.grey[500])))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _bubble(_messages[i]),
                ),
        ),
        // Quick replies
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _quickReplies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _send(_quickReplies[i]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _brand.withOpacity(0.3)),
                ),
                child: Text(_quickReplies[i], style: const TextStyle(fontSize: 12.5, color: _brand, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
        // Input
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  filled: true,
                  fillColor: const Color(0xFFF0F2F6),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(_controller.text),
              child: CircleAvatar(radius: 22, backgroundColor: _brand, child: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['sender'] == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine ? _brand : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 2),
            bottomRight: Radius.circular(mine ? 2 : 14),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
        ),
        child: Text(m['text']?.toString() ?? '',
            style: TextStyle(color: mine ? Colors.white : const Color(0xFF1A1A1A), fontSize: 14)),
      ),
    );
  }
}
