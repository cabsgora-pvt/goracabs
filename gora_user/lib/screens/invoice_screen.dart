import 'package:flutter/material.dart';
import 'home_screen.dart';

class InvoiceScreen extends StatelessWidget {
  final String vehicleName;
  final int? selectedTip;

  const InvoiceScreen({
    super.key,
    required this.vehicleName,
    this.selectedTip,
  });

  @override
  Widget build(BuildContext context) {
    // Pricing logic based on the vehicle selected
    final Map<String, int> prices = {
      'Bike': 49,
      'Auto': 76,
      'Cab Economy': 144,
      'SUV': 250,
      'Premium': 320,
    };

    final int basePrice = prices[vehicleName] ?? 0;
    final int tip = selectedTip ?? 0;
    final int total = basePrice + tip;
    final double cgst = total * 0.025;
    final double sgst = total * 0.025;
    final double finalTotal = total + cgst + sgst;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Invoice', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.share_outlined, color: Colors.black),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gora-Cabs Invoice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  const Text('MAHENDRA KUMAR -', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const Text(
                    'Pick up address: UIT Rd, Ratanada, Jodhpur,\nRajasthan 342011, India',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Invoice Number: FHACCBFC25000697', style: TextStyle(fontSize: 12)),
                          Text('Invoice Date: 11/08/2025', style: TextStyle(fontSize: 12)),
                          Text('Place of supply: Rajasthan', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: const [
                          Text('Gora Cabs Private Limited', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('SURENDRA SHARMA', style: TextStyle(fontSize: 12)),
                          Text(
                            'Jodhpur, Rajasthan 342011',
                            style: TextStyle(fontSize: 10),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Table(
                    border: TableBorder(bottom: BorderSide(color: Colors.grey[200]!)),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(3),
                      2: FlexColumnWidth(1),
                      3: FlexColumnWidth(2),
                    },
                    children: [
                      const TableRow(
                        children: [
                          Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Qty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Amount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                        ],
                      ),
                      TableRow(
                        children: [
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('11/08/2025', style: TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Transportation ($vehicleName)', style: const TextStyle(fontSize: 12))),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('1', style: TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('₹$total', style: const TextStyle(fontSize: 12), textAlign: TextAlign.right)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Subtotal: ₹$total', style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('CGST 2.5%: ₹${cgst.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('SGST 2.5%: ₹${sgst.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(width: 150, child: Divider()),
                        ),
                        Text(
                          'Total Amount: ₹${finalTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                  const Center(
                    child: Column(
                      children: [
                        Text('Details of ECO under GST:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        SizedBox(height: 4),
                        Text(
                          'Gora cabs & travels Pvt Ltd 1st Floor, Nanak Bhavan , Tempo Stand , Airforce Area ,Jodhpur, Rajasthan 342011',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Go Home',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
