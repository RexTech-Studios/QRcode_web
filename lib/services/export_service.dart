import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/qr_code_model.dart';
import '../models/shop_model.dart';

class ExportService {
  ExportService._();

  // ── JSON ─────────────────────────────────────────────────────────────────

  static void downloadJson({
    required List<ShopModel> shops,
    required List<QRCodeModel> qrCodes,
  }) {
    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'shops': shops.map((s) => s.toMap()).toList(),
      'qrCodes': qrCodes.map((q) => q.toMap()).toList(),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    _triggerDownload(
      content: jsonStr,
      fileName: 'reviewqr_export_${_dateStamp()}.json',
      mimeType: 'application/json',
    );
  }

  // ── PDF ──────────────────────────────────────────────────────────────────

  static Future<void> downloadPdf({
    required List<ShopModel> shops,
    required List<QRCodeModel> qrCodes,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Text(
          'Full Star QR — Data Export  •  ${_readableDate(DateTime.now())}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
        build: (ctx) => [
          _pdfTitle('Shops (${shops.length})'),
          pw.SizedBox(height: 8),
          if (shops.isEmpty)
            _pdfNote('No shops saved yet.')
          else
            _shopsTable(shops),
          pw.SizedBox(height: 24),
          _pdfTitle('QR Codes (${qrCodes.length})'),
          pw.SizedBox(height: 8),
          if (qrCodes.isEmpty)
            _pdfNote('No QR codes saved yet.')
          else
            _qrTable(shops, qrCodes),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'reviewqr_export_${_dateStamp()}.pdf',
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  static pw.Widget _pdfTitle(String text) => pw.Text(
        text,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      );

  static pw.Widget _pdfNote(String text) => pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
      );

  static pw.Widget _shopsTable(List<ShopModel> shops) {
    const headers = ['Shop Name', 'Review URL', 'Created'];
    final rows = shops
        .map(
          (s) => [
            s.shopName,
            s.googleReviewUrl,
            _readableDate(s.createdAt),
          ],
        )
        .toList();

    return _buildTable(headers, rows);
  }

  static pw.Widget _qrTable(
    List<ShopModel> shops,
    List<QRCodeModel> qrCodes,
  ) {
    final shopNames = {for (final s in shops) s.shopId: s.shopName};
    const headers = ['Label', 'Shop', 'Style', 'QR URL', 'Created'];
    final rows = qrCodes
        .map(
          (q) => [
            q.qrLabel,
            shopNames[q.shopId] ?? q.shopId,
            q.qrStyle.name,
            q.qrContent,
            _readableDate(q.createdAt),
          ],
        )
        .toList();

    return _buildTable(headers, rows);
  }

  static pw.Widget _buildTable(
    List<String> headers,
    List<List<String>> rows,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        for (int i = 0; i < headers.length; i++)
          i: const pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers
              .map(
                (h) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        ...rows.map(
          (row) => pw.TableRow(
            children: row
                .map(
                  (cell) => pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(
                      cell,
                      style: const pw.TextStyle(fontSize: 9),
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  static void _triggerDownload({
    required String content,
    required String fileName,
    required String mimeType,
  }) {
    if (!kIsWeb) {
      debugPrint('ExportService: download only supported on web');
      return;
    }
    final bytes = utf8.encode(content);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.setAttribute('download', fileName);
    anchor.click();
    web.URL.revokeObjectURL(url);
  }

  static String _dateStamp() {
    final now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}';
  }

  static String _readableDate(DateTime dt) =>
      '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
