import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'currency_service.dart';

class ReportPdfService {
  static Future<Uint8List> buildAccountPdf(Map<String, dynamic> report) async {
    final money = CurrencyService.instance;
    final fmt = DateFormat('dd MMM yyyy');
    final account = report['account']?.toString() ?? 'Account';
    final from = report['from']?.toString() ?? '';
    final to = report['to']?.toString() ?? '';
    final opening = (report['opening'] as num?)?.toDouble() ?? 0;
    final totalIn = (report['totalIn'] as num?)?.toDouble() ?? 0;
    final totalOut = (report['totalOut'] as num?)?.toDouble() ?? 0;
    final closing = (report['closing'] as num?)?.toDouble() ?? 0;
    final rows = (report['rows'] as List? ?? []).cast<Map>();

    // PDF rows oldest-first for reading
    final chronological = rows.reversed.toList();

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Budget Web - Account statement',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Account: $account'),
            pw.Text(
                'Period: $from to $to - Currency: ${money.code}'),
            pw.Text(
                'Generated: ${fmt.format(DateTime.now())} ${DateFormat('HH:mm').format(DateTime.now())}'),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _sumCell('Opening', money.format(opening)),
                _sumCell('In', money.format(totalIn)),
                _sumCell('Out', money.format(totalOut)),
                _sumCell('Closing', money.format(closing)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          if (chronological.isEmpty)
            pw.Text('No transactions in this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Type', 'Description', 'Amount', 'Balance'],
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(1.4),
                1: const pw.FlexColumnWidth(1.0),
                2: const pw.FlexColumnWidth(2.2),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(1.2),
              },
              data: chronological.map((r) {
                final signed = (r['signed'] as num?)?.toDouble() ?? 0;
                final run =
                    (r['running_balance'] as num?)?.toDouble() ?? 0;
                final date = (r['date'] ?? '').toString();
                final day = date.length >= 10 ? date.substring(0, 10) : date;
                final desc = (r['desc'] ?? r['description'] ?? '')
                    .toString()
                    .trim();
                final detail = desc.isNotEmpty
                    ? desc
                    : (r['title'] ?? '').toString();
                return [
                  day,
                  (r['type'] ?? '').toString(),
                  detail,
                  money.format(signed),
                  money.format(run),
                ];
              }).toList(),
            ),
        ],
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> buildAllAccountsPdf(
      List<Map<String, dynamic>> reports) async {
    final money = CurrencyService.instance;
    final fmt = DateFormat('dd MMM yyyy');
    final from = reports.isNotEmpty ? reports.first['from'] : '';
    final to = reports.isNotEmpty ? reports.first['to'] : '';

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          pw.Text('Budget Web - All accounts summary',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Period: $from to $to - ${money.code}'),
          pw.Text('Generated: ${fmt.format(DateTime.now())}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Account',
              'Opening',
              'In',
              'Out',
              'Closing',
            ],
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            data: reports
                .map((r) => [
                      r['account']?.toString() ?? '',
                      money.format((r['opening'] as num?)?.toDouble() ?? 0),
                      money.format((r['totalIn'] as num?)?.toDouble() ?? 0),
                      money.format((r['totalOut'] as num?)?.toDouble() ?? 0),
                      money.format((r['closing'] as num?)?.toDouble() ?? 0),
                    ])
                .toList(),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _sumCell(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      );
}
