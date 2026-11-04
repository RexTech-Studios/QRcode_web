import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Replace these three values with your EmailJS credentials.
/// Sign up free at https://www.emailjs.com
/// Dashboard → Email Services → Service ID
///           → Email Templates → Template ID
///           → Account → Public Key
const _serviceId = 'YOUR_SERVICE_ID';
const _templateId = 'YOUR_TEMPLATE_ID';
const _publicKey = 'YOUR_PUBLIC_KEY';

class EmailJsService {
  EmailJsService._();

  /// Sends a low-rating feedback notification to the shop owner.
  /// Returns true if the email was sent successfully.
  static Future<bool> sendFeedbackEmail({
    required String toEmail,
    required String shopName,
    required int rating,
    required String? comment,
  }) async {
    final stars = '${'★' * rating}${'☆' * (5 - rating)}';
    final commentText =
        (comment != null && comment.trim().isNotEmpty) ? comment : 'No comment';
    final submittedAt = DateTime.now().toLocal().toString().split('.').first;

    try {
      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _publicKey,
          'template_params': {
            'to_email': toEmail,
            'shop_name': shopName,
            'rating': '$rating / 5  $stars',
            'comment': commentText,
            'submitted_at': submittedAt,
          },
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('EmailJsService.sendFeedbackEmail error: $e');
      return false;
    }
  }
}
