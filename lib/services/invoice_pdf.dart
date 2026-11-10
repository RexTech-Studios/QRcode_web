import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/invoice_model.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';

/// Who the invoice is from. Shown at the top and in the footer.
const String invoiceBusinessName = 'Full Star QR';
const String invoiceBusinessWebsite = 'fullstarqr.com';
const String invoiceBusinessPhone = 'WhatsApp +91 96057 98763';

const PdfColor _gold = PdfColor.fromInt(0xFF9D7644);
const PdfColor _goldLight = PdfColor.fromInt(0xFFF3EBDB);
const PdfColor _ink = PdfColor.fromInt(0xFF1C1917);
const PdfColor _muted = PdfColor.fromInt(0xFF6B635A);

/// What the invoice charges for. One line, one QR.
String invoiceDescription(Invoice invoice) =>
    'Full Star QR review stand with QR code ${invoice.qrCode}';

/// Builds the one-page A4 invoice. Plain built-in fonts only, so amounts say
/// "Rs." (the rupee sign is not in them).
Future<Uint8List> buildInvoicePdf(Invoice invoice) async {
  final doc = pw.Document(
    title: 'Invoice ${invoice.numberText}',
    author: invoiceBusinessName,
  );

  final issued = invoice.issuedAt ?? invoice.soldAt ?? DateTime.now();
  final amount = 'Rs. ${formatRupees(invoice.amount)}';

  pw.Widget label(String text) => pw.Text(
    text,
    style: pw.TextStyle(fontSize: 9, color: _muted, letterSpacing: 0.6),
  );

  pw.Widget cell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor color = _ink,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 11,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(height: 6, color: _gold),
          pw.SizedBox(height: 22),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    invoiceBusinessName,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _gold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    invoiceBusinessWebsite,
                    style: const pw.TextStyle(fontSize: 10, color: _muted),
                  ),
                  pw.Text(
                    invoiceBusinessPhone,
                    style: const pw.TextStyle(fontSize: 10, color: _muted),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'INVOICE',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    invoice.numberText,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  pw.Text(
                    'Date: ${formatShortDate(issued)}',
                    style: const pw.TextStyle(fontSize: 10, color: _muted),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 34),
          label('BILLED TO'),
          pw.SizedBox(height: 5),
          pw.Text(
            invoice.clientName,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          if (invoice.clientPhone.isNotEmpty)
            pw.Text(
              invoice.clientPhone,
              style: const pw.TextStyle(fontSize: 11, color: _muted),
            ),
          if (invoice.clientAddress.isNotEmpty)
            pw.Text(
              invoice.clientAddress,
              style: const pw.TextStyle(fontSize: 11, color: _muted),
            ),
          pw.SizedBox(height: 30),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(5),
              1: pw.FixedColumnWidth(50),
              2: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _goldLight),
                children: [
                  cell('Description', bold: true),
                  cell('Qty', bold: true, align: pw.TextAlign.center),
                  cell('Amount', bold: true, align: pw.TextAlign.right),
                ],
              ),
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _goldLight, width: 1),
                  ),
                ),
                children: [
                  cell(invoiceDescription(invoice)),
                  cell('1', align: pw.TextAlign.center),
                  cell(amount, align: pw.TextAlign.right),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 210,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: const pw.BoxDecoration(color: _gold),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Text(
                    amount,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.Spacer(),
          pw.Divider(color: _goldLight),
          pw.SizedBox(height: 6),
          pw.Text(
            'Thank you for choosing $invoiceBusinessName.',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _gold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Questions about this invoice? Message us on $invoiceBusinessPhone.',
            style: const pw.TextStyle(fontSize: 9.5, color: _muted),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

/// "Invoice-FSQ-0001-Sunrise-Bakery.pdf", with anything unsafe for a file
/// name turned into dashes.
String invoiceFileName(Invoice invoice) {
  final client = invoice.clientName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final shortClient = client.length > 40 ? client.substring(0, 40) : client;
  return 'Invoice-${invoice.numberText}'
      '${shortClient.isEmpty ? '' : '-$shortClient'}.pdf';
}

/// Saves the PDF to the browser's downloads.
Future<void> downloadInvoicePdf(Invoice invoice) async {
  final bytes = await buildInvoicePdf(invoice);
  await Printing.sharePdf(bytes: bytes, filename: invoiceFileName(invoice));
}

/// What the screens call to save an invoice. Tests replace it, because the
/// real one needs a browser.
Future<void> Function(Invoice invoice) invoiceDownloader = downloadInvoicePdf;
