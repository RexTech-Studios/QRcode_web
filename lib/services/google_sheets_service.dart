import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sends feedback and shop-setup calls to a Google Apps Script Web App,
/// which creates a separate Google Spreadsheet per shop in the Drive account
/// salebayinformation48@gmail.com and appends feedback rows to it.
///
/// ─── ONE-TIME SETUP ────────────────────────────────────────────────────────
/// 1. Sign in to Google as salebayinformation48@gmail.com.
///
/// 2. Go to https://script.google.com → New project.
///
/// 3. Paste the script below, then save (Ctrl+S).
///
/// 4. Click Deploy → New deployment → Web app.
///      Execute as: Me  (salebayinformation48@gmail.com)
///      Who has access: Anyone
///    Copy the Web app URL and paste it as [_scriptUrl] below.
///
/// ─── APPS SCRIPT CODE (paste into the editor) ──────────────────────────────
///
/// function doPost(e) {
///   try {
///     const data = JSON.parse(e.postData.contents);
///
///     // ── CREATE: one new spreadsheet per shop ─────────────────────────────
///     if (data.action === 'create_sheet') {
///       const name = data.shopName.substring(0, 100);
///       const ss   = SpreadsheetApp.create(name);
///       const sheet = ss.getActiveSheet();
///       sheet.setName('Feedback');
///       sheet.appendRow(['Shop Name', 'QR Code', 'Date', 'Time', 'Rating', 'Comment']);
///       sheet.setFrozenRows(1);
///
///       // Make it viewable by anyone with the link
///       DriveApp.getFileById(ss.getId()).setSharing(
///         DriveApp.Access.ANYONE_WITH_LINK,
///         DriveApp.Permission.VIEW
///       );
///
///       return ContentService
///         .createTextOutput(JSON.stringify({ success: true, url: ss.getUrl() }))
///         .setMimeType(ContentService.MimeType.JSON);
///     }
///
///     // ── RENAME: keep the spreadsheet title in sync with the shop name ────
///     if (data.action === 'rename_sheet') {
///       SpreadsheetApp.openById(data.spreadsheetId)
///         .rename(data.shopName.substring(0, 100));
///       return ContentService
///         .createTextOutput(JSON.stringify({ success: true, renamed: true }))
///         .setMimeType(ContentService.MimeType.JSON);
///     }
///
///     // ── FEEDBACK: append a row using the spreadsheet ID ──────────────────
///     if (data.action === 'submit_feedback') {
///       const ss    = SpreadsheetApp.openById(data.spreadsheetId);
///       const sheet = ss.getSheetByName('Feedback') || ss.getSheets()[0];
///       const now   = new Date();
///       sheet.appendRow([
///         data.shopName,
///         data.qrCode || '',
///         now.toLocaleDateString(),
///         now.toLocaleTimeString(),
///         data.rating + ' / 5',
///         data.comment || '',
///       ]);
///       return ok();
///     }
///
///     return ok();
///   } catch (err) {
///     return ContentService
///       .createTextOutput(JSON.stringify({ error: err.message }))
///       .setMimeType(ContentService.MimeType.JSON);
///   }
/// }
///
/// function ok() {
///   return ContentService
///     .createTextOutput(JSON.stringify({ success: true }))
///     .setMimeType(ContentService.MimeType.JSON);
/// }
///
/// ────────────────────────────────────────────────────────────────────────────

const _scriptUrl =
    'https://script.google.com/macros/s/AKfycbyJdIi4WKBNTD9DSAuOnc9fv3uQsD9u9gssGMRGmum25XVmB4lOrfCl66ihy5ObhspopQ/exec';

/// Result of a sheet-creation attempt. Carries either the new sheet [url]
/// or a human-readable [error] describing why it failed, so callers can
/// surface the failure instead of silently ending up with no sheet.
class SheetResult {
  final String? url;
  final String? error;
  const SheetResult({this.url, this.error});

  bool get isSuccess => url != null && url!.isNotEmpty;
}

class GoogleSheetsService {
  GoogleSheetsService._();

  /// Called when a new shop is created.
  /// Creates a brand-new Google Spreadsheet in salebayinformation48@gmail.com's
  /// Drive and returns a [SheetResult] with its URL, or an error description.
  static Future<SheetResult> createShopSheet(String shopName) async {
    if (_scriptUrl == 'YOUR_APPS_SCRIPT_WEB_APP_URL') {
      debugPrint('GoogleSheetsService: script URL not configured.');
      return const SheetResult(
        error: 'Google Sheets is not configured (missing Apps Script URL).',
      );
    }
    try {
      // Omit Content-Type to avoid a CORS preflight on Flutter web.
      // Apps Script receives the raw body and JSON.parse still works.
      final response = await http.post(
        Uri.parse(_scriptUrl),
        body: jsonEncode({'action': 'create_sheet', 'shopName': shopName}),
      );
      debugPrint('GoogleSheetsService.createShopSheet status: ${response.statusCode} body: ${response.body}');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final url = decoded['url'] as String?;
        if (url != null && url.isNotEmpty) return SheetResult(url: url);
        final scriptError = decoded['error'] as String?;
        debugPrint('GoogleSheetsService.createShopSheet: no url in response: ${response.body}');
        return SheetResult(
          error: scriptError != null
              ? 'Apps Script error: $scriptError'
              : 'Sheet service returned no URL. Response: ${response.body}',
        );
      }
      return SheetResult(
        error: 'Sheet service responded with HTTP ${response.statusCode}.',
      );
    } catch (e) {
      debugPrint('GoogleSheetsService.createShopSheet error: $e');
      return SheetResult(error: 'Could not reach the sheet service: $e');
    }
  }

  /// Renames the shop's spreadsheet file to match its new shop name.
  static Future<bool> renameShopSheet({
    required String? googleSheetsUrl,
    required String shopName,
  }) async {
    final spreadsheetId = _extractSpreadsheetId(googleSheetsUrl);
    if (spreadsheetId == null) return false;
    try {
      // Omit Content-Type to avoid a CORS preflight on Flutter web.
      final response = await http.post(
        Uri.parse(_scriptUrl),
        body: jsonEncode({
          'action': 'rename_sheet',
          'spreadsheetId': spreadsheetId,
          'shopName': shopName,
        }),
      );
      if (response.statusCode != 200) return false;
      // An older script answers unknown actions with success, so require
      // the explicit `renamed` flag.
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return decoded['renamed'] == true;
    } catch (e) {
      debugPrint('GoogleSheetsService.renameShopSheet error: $e');
      return false;
    }
  }

  /// Appends a low-rating feedback row to the shop's own spreadsheet.
  static Future<bool> submitFeedback({
    required String shopName,
    required String? googleSheetsUrl,
    required int rating,
    required String? comment,
    String? qrCode,
  }) async {
    final spreadsheetId = _extractSpreadsheetId(googleSheetsUrl);
    if (spreadsheetId == null) {
      debugPrint('GoogleSheetsService: no spreadsheet ID for $shopName');
      return false;
    }
    return _post({
      'action': 'submit_feedback',
      'shopName': shopName,
      'spreadsheetId': spreadsheetId,
      'rating': rating,
      'comment': comment ?? '',
      'qrCode': qrCode ?? '',
    });
  }

  static String? _extractSpreadsheetId(String? url) {
    if (url == null || url.isEmpty) return null;
    final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  static Future<bool> _post(Map<String, dynamic> body) async {
    if (_scriptUrl == 'YOUR_APPS_SCRIPT_WEB_APP_URL') {
      debugPrint('GoogleSheetsService: script URL not configured.');
      return false;
    }
    try {
      // Omit Content-Type to avoid a CORS preflight on Flutter web.
      final response = await http.post(
        Uri.parse(_scriptUrl),
        body: jsonEncode(body),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('GoogleSheetsService error: $e');
      return false;
    }
  }
}
