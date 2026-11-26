import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'home_screen.dart';

class InquiryScreen extends StatefulWidget {
  const InquiryScreen({super.key});

  @override
  State<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends State<InquiryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController();
  
  String? _selectedPurpose;
  String? _selectedEventType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  final List<String> _purposes = [
    'Family tour package',
    'Marriage,Event cabs',
    'Airport pick up drop',
    'Luxury car',
    'Tempo travels, luxury bus',
    'Hotels room booking',
    'Corporate work car',
    'Monthly cars booking',
  ];

  final List<String> _eventTypes = [
    'Personal',
    'Business',
    'Wedding',
    'Sightseeing',
    'Other',
  ];

  // Which contact fields were already filled from the profile — each is
  // filled once, so a value the rider clears or edits is left alone.
  final _prefilled = <TextEditingController>{};

  /// The inquiry is from the signed-in rider: fill their name, phone and email
  /// from the profile (and again once the profile finishes loading).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final u = Provider.of<UserProvider>(context);
    void fill(TextEditingController c, String v) {
      if (_prefilled.contains(c) || v.trim().isEmpty) return;
      if (c.text.isEmpty) c.text = v.trim();
      _prefilled.add(c);
    }
    fill(_nameController, u.name);
    fill(_mobileController, u.phone);
    fill(_emailController, u.email);
  }

  @override
  void dispose() {
    for (final c in [_nameController, _emailController, _mobileController, _descriptionController, _durationController]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0A3CC8),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0A3CC8),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: Column(children: [
        const ServiceBackBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ServiceTitle(title: 'Any inquiry', subtitle: 'Tours, events, airport transfers and more'),
                  _buildTextField('Full Name', 'Enter your full name', _nameController, icon: Icons.person_outline),
                  const SizedBox(height: 16),
                  _buildTextField('Email', 'Enter your email', _emailController, keyboardType: TextInputType.emailAddress, icon: Icons.mail_outline),
                  const SizedBox(height: 16),
                  _buildTextField('Mobile Number', 'Enter your mobile number', _mobileController, keyboardType: TextInputType.phone, icon: Icons.phone_outlined),
                  const SizedBox(height: 16),
                  _buildDropdown('Purpose', _purposes, _selectedPurpose, (val) => setState(() => _selectedPurpose = val)),
                  const SizedBox(height: 16),
                  _buildDropdown('Event Type', _eventTypes, _selectedEventType, (val) => setState(() => _selectedEventType = val)),
                  const SizedBox(height: 16),
                  _buildTextField('Short Description', 'What do you need?', _descriptionController, maxLines: 3),
                  const SizedBox(height: 16),
                  _buildTextField('Time Duration', 'How long do you need it for?', _durationController, icon: Icons.timelapse),
                  const SizedBox(height: 16),
                  const FieldLabel('Date & time'),
                  PickerPill(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: _selectedDate == null ? 'Select date' : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                    placeholder: _selectedDate == null,
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 10),
                  PickerPill(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: _selectedTime == null ? 'Select time' : _selectedTime!.format(context),
                    placeholder: _selectedTime == null,
                    onTap: _pickTime,
                  ),
                ],
              ),
            ),
          ),
        ),
        PrimaryCtaBar(
          label: _sending ? 'Sending…' : 'Request Inquiry',
          onPressed: _sending ? null : _submit,
        ),
      ]),
    );
  }

  Widget _buildTextField(String label, String hint, TextEditingController controller, {TextInputType? keyboardType, int maxLines = 1, IconData? icon}) {
    return LabeledField(
      label: label,
      hint: hint,
      controller: controller,
      icon: icon,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter $label';
        }
        return null;
      },
    );
  }

  Widget _buildDropdown(String label, List<String> items, String? currentValue, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: RideUi.fieldBox(context),
          child: DropdownButtonFormField<String>(
            // Without isExpanded a dropdown sizes to its LONGEST item, so a long
            // option overflowed the field on narrow screens. Expanding it makes
            // the selected label ellipsise inside the decoration instead.
            isExpanded: true,
            initialValue: currentValue,
            items: items.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: onChanged,
            decoration: RideUi.bareInput(context, 'Select ${label.toLowerCase()}', vertical: 14),
            style: RideUi.body(context, size: 14.5, weight: FontWeight.w600),
            borderRadius: BorderRadius.circular(12),
            icon: Icon(Icons.keyboard_arrow_down, color: RideUi.muted(context)),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please select $label';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  bool _sending = false;

  // Used to show "Inquiry Submitted" without sending anything. It now reaches
  // the admin as a support ticket with every field the rider filled in.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final lines = <String>[
      _descriptionController.text.trim(),
      '',
      'Purpose: ${_selectedPurpose ?? '-'}',
      'Event type: ${_selectedEventType ?? '-'}',
      if (_selectedDate != null) 'Date: ${DateFormat('d MMM yyyy').format(_selectedDate!)}',
      if (_selectedTime != null) 'Time: ${_selectedTime!.format(context)}',
      if (_durationController.text.trim().isNotEmpty) 'Duration: ${_durationController.text.trim()}',
      'Name: ${_nameController.text.trim()}',
      'Mobile: ${_mobileController.text.trim()}',
      if (_emailController.text.trim().isNotEmpty) 'Email: ${_emailController.text.trim()}',
    ];
    setState(() => _sending = true);
    final res = await ApiService.createSupportTicket(
      subject: 'Inquiry: ${_selectedPurpose ?? 'General'}',
      message: lines.join('\n'),
      category: 'general',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['success'] == true) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((res['error'] ?? 'Could not send. Please try again.').toString())));
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inquiry Submitted'),
        content: const Text('Your inquiry has been sent. Our team will contact you, and you can follow it in Support → My Tickets.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
