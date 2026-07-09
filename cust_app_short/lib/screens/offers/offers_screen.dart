import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/jago_theme.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});
  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  List<dynamic> _offers = [];
  bool _loading = true;

  static const Color _blue = Color(0xFF2F7BFF);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final headers = await AuthService.getHeaders();
      final r = await http.get(Uri.parse(ApiConfig.customerOffers),
          headers: headers);
      if (r.statusCode == 200) {
        if (mounted) setState(() { _offers = jsonDecode(r.body); _loading = false; });
      } else {
        if (mounted) setState(() { _loading = false; });
      }
    } catch (_) { if (mounted) setState(() { _loading = false; }); }
  }

  bool _isPercent(String? type) => type == 'percentage' || type == 'percent';

  Color _discountColor(String? type) =>
      _isPercent(type) ? const Color(0xFF2C95F1) : const Color(0xFF0D9488);

  IconData _discountIcon(String? type) =>
      _isPercent(type) ? Icons.percent_rounded : Icons.currency_rupee_rounded;

  String _discountLabel(dynamic offer) {
    final type = offer['discountType']?.toString();
    final val = (offer['discountValue'] ?? offer['discountAmount'])?.toString() ?? '0';
    if (_isPercent(type)) return '$val% OFF';
    return '₹$val OFF';
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Code "$code" copied!'),
      backgroundColor: const Color(0xFF16A34A),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: JT.textPrimary, size: 20),
        ),
        title: const Text('Offers & Coupons',
            style: TextStyle(color: JT.textPrimary, fontSize: 18, fontWeight: FontWeight.w400)),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JT.primary))
          : _offers.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _blue,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildTopBanner(),
                      const SizedBox(height: 16),
                      ..._offers.map((o) => _buildOfferCard(o)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTopBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), JT.primary],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        const Icon(Icons.local_offer_rounded, color: Colors.amber, size: 28),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Exclusive Offers', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w400)),
            SizedBox(height: 2),
            Text('Tap "Copy" and apply at booking', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${_offers.length} Active', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Widget _buildOfferCard(dynamic offer) {
    final name = offer['name']?.toString() ?? 'Special Offer';
    final code = (offer['code'] ?? offer['couponCode'])?.toString() ?? '';
    final type = offer['discountType']?.toString();
    final minAmount = (offer['minTripAmount'] ?? offer['min_trip_amount'])?.toString() ?? '0';
    final maxDiscount = offer['maxDiscountAmount'] ?? offer['maxDiscount'];
    final expiry = (offer['endDate'] ?? offer['expiryDate'])?.toString();
    final desc = offer['description']?.toString();
    final color = _discountColor(type);

    String? expiryText;
    Color? expiryColor;
    if (expiry != null && expiry.isNotEmpty) {
      try {
        final dt = DateTime.parse(expiry);
        final now = DateTime.now();
        final days = dt.difference(now).inDays;
        
        if (days < 0) {
          expiryText = 'EXPIRED';
          expiryColor = JT.error;
        } else if (days == 0) {
          expiryText = 'Expires today!';
          expiryColor = const Color(0xFFEA580C);
        } else if (days == 1) {
          expiryText = 'Expires tomorrow';
          expiryColor = const Color(0xFFEA580C);
        } else if (days < 7) {
          expiryText = 'Expires in $days days';
          expiryColor = const Color(0xFFEA580C);
        } else if (days < 30) {
          final weeks = (days / 7).ceil();
          expiryText = 'Expires in $weeks week${weeks > 1 ? 's' : ''}';
          expiryColor = const Color(0xFFD97706);
        } else if (days < 365) {
          final months = (days / 30).ceil();
          expiryText = 'Expires in $months month${months > 1 ? 's' : ''}';
          expiryColor = const Color(0xFF059669);
        } else {
          final years = (days / 365).floor();
          expiryText = 'Expires in $years year${years > 1 ? 's' : ''}';
          expiryColor = const Color(0xFF059669);
        }
      } catch (e) {
        expiryText = 'Expiry date unknown';
        expiryColor = const Color(0xFF64748B);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        // Top section
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_discountIcon(type), color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: JT.textPrimary)),
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  if (double.tryParse(minAmount) != null && double.parse(minAmount) > 0) ...[
                    _tag('Min ₹$minAmount', const Color(0xFFEFF6FF), JT.primary),
                    const SizedBox(width: 6),
                  ],
                  if (maxDiscount != null && maxDiscount.toString() != '0') ...[
                    _tag('Max ₹$maxDiscount', const Color(0xFFFFF7ED), const Color(0xFFD97706)),
                    const SizedBox(width: 6),
                  ],
                  if (expiryText != null)
                    _tag(expiryText, expiryColor?.withValues(alpha: 0.1) ?? const Color(0xFFFFF1F2), expiryColor ?? const Color(0xFFE11D48)),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_discountLabel(offer),
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
        // Dashed divider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: List.generate(30, (i) =>
            Expanded(child: Container(
              height: 1, margin: const EdgeInsets.symmetric(horizontal: 2),
              color: i.isEven ? const Color(0xFFE2E8F0) : Colors.transparent,
            )),
          )),
        ),
        // Bottom: coupon code + copy button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5, style: BorderStyle.solid),
                ),
                child: Text(code,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, color: color,
                    letterSpacing: 2, fontFamily: 'monospace',
                  )),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () => _copyCode(code),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _tag(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w400)),
  );

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.local_offer_outlined, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 12),
      const Text('No offers right now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: Color(0xFF64748B))),
      const SizedBox(height: 6),
      const Text('Check back later for exciting deals!', style: TextStyle(fontSize: 13, color: Color(0xFFADB5BD))),
    ]),
  );
}
