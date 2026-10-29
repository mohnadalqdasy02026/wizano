import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/models.dart';

/// إنشاء كشف حساب قابل للطباعة أو المشاركة من هاتف صاحب المحل.
class StatementPdfService {
  const StatementPdfService._();

  static Future<void> share({
    required String shopName,
    required String customerName,
    required String currency,
    required CustomerStatement statement,
    required String filterLabel,
  }) async {
    final bytes = await build(
      shopName: shopName,
      customerName: customerName,
      currency: currency,
      statement: statement,
      filterLabel: filterLabel,
    );
    final date = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'wizano_statement_${_safeFileName(customerName)}_$date.pdf',
    );
  }

  static Future<Uint8List> build({
    required String shopName,
    required String customerName,
    required String currency,
    required CustomerStatement statement,
    required String filterLabel,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/arial.ttf');
    final font = pw.Font.ttf(fontData);
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    final generatedAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 32),
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                'WIZANO | وزانو',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF0B2A4A),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(height: 2, color: PdfColor.fromInt(0xFF16A39A)),
              pw.SizedBox(height: 16),
            ],
          ),
        ),
        footer: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('تم الإنشاء: $generatedAt', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('صفحة ${context.pageNumber} من ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
        build: (_) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text('كشف حساب عميل', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0B2A4A))),
                pw.SizedBox(height: 12),
                _infoRow('المحل', shopName),
                _infoRow('العميل', customerName),
                _infoRow('العمليات المعروضة', filterLabel),
                pw.SizedBox(height: 14),
                _summary(statement, currency),
                pw.SizedBox(height: 18),
                pw.Text('تفاصيل العمليات', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0B2A4A))),
                pw.SizedBox(height: 8),
                _entriesTable(statement.entries, currency),
              ],
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _infoRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: value),
          ]),
        ),
      );

  static pw.Widget _summary(CustomerStatement statement, String currency) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF1F8F7),
          border: pw.Border.all(color: PdfColor.fromInt(0xFFB9E1DD)),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _summaryRow('إجمالي المشتريات', statement.totalPurchases, currency),
            _summaryRow('إجمالي المدفوعات', statement.totalPayments, currency),
            _summaryRow('إجمالي المرتجعات', statement.totalReturns, currency),
            _summaryRow('صافي التصحيحات', statement.totalAdjustments, currency),
            pw.Divider(color: PdfColor.fromInt(0xFF8CCFC8)),
            _summaryRow('الرصيد المستحق', statement.balance, currency, emphasize: true),
          ],
        ),
      );

  static pw.Widget _summaryRow(String label, int amount, String currency, {bool emphasize = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text('${_money(amount)} $currency', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: emphasize ? 14 : 11, color: emphasize ? PdfColor.fromInt(0xFF0B2A4A) : null)),
        ],
      );

  static pw.Widget _entriesTable(List<StatementEntry> entries, String currency) {
    if (entries.isEmpty) return pw.Text('لا توجد عمليات مطابقة لهذا الاختيار.');
    return pw.TableHelper.fromTextArray(
      headers: const ['التاريخ والوقت', 'النوع', 'الوصف', 'المبلغ', 'الرصيد'],
      data: entries.map((entry) => [
        _date(entry.occurredAt),
        _typeLabel(entry),
        entry.description.isEmpty ? '—' : entry.description,
        '${entry.effect >= 0 ? '+' : '−'}${_money(entry.effect.abs())} $currency',
        '${_money(entry.balanceAfter)} $currency',
      ]).toList(growable: false),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF0B2A4A)),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.centerRight,
      cellPadding: const pw.EdgeInsets.all(5),
      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFD4E4E3), width: .5),
      oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF6FAFA)),
    );
  }

  static String _typeLabel(StatementEntry entry) => switch (entry.type) {
        'purchase' => 'شراء',
        'return' => 'مرتجع',
        'adjustment' => entry.adjustmentKind == 'cancellation' ? 'إلغاء' : 'تصحيح',
        _ => 'دفعة',
      };

  static String _date(String iso) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  static String _money(int value) => NumberFormat.decimalPattern().format(value);

  static String _safeFileName(String text) => text.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
}
