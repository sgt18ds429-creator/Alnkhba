import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'arabic_reshaper.dart';

class FileExportHelper {
  static const String signature =
      "Eliteradiq\nالطالب محمد جبار ابراهيم — قسم تقنيات الأشعة والسونار";

  static String _safeFileName(String title, String extension) {
    var clean = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (clean.isEmpty) clean = 'EliteRadIq_Report';
    if (clean.length > 80) clean = clean.substring(0, 80);
    return '$clean.$extension';
  }

  static Future<String?> _saveBytes({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  }) {
    // Uses Storage Access Framework on Android and the native document picker
    // on iOS. This is compatible with scoped storage and needs no broad storage
    // permission.
    return FilePicker.platform.saveFile(dialogTitle: dialogTitle, fileName: fileName, bytes: bytes);
  }

  /// Export text content to a Microsoft Word (.doc) file
  static Future<String?> exportToWord(String title, String content) async {
    try {
      final safeTitle = htmlContentEscape(title);
      final safeContent = htmlContentEscape(content).replaceAll('\n', '<br>');
      final safeSignature = htmlContentEscape(signature).replaceAll('\n', '<br>');
      final docContent =
          '''<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
  <meta charset="UTF-8">
  <title>$safeTitle</title>
  <style>
    body { font-family: Arial, sans-serif; direction: rtl; line-height: 1.8; margin: 42px; color: #172033; }
    h1 { color: #0b6fb8; border-bottom: 2px solid #d9a441; padding-bottom: 12px; }
    .notice { margin: 18px 0; padding: 12px; background: #fff8e7; border-right: 4px solid #d9a441; }
    footer { margin-top: 36px; color: #53657a; font-size: 12px; }
  </style>
</head>
<body>
  <h1>$safeTitle</h1>
  <div class="notice">محتوى تعليمي مولّد بالذكاء الاصطناعي، غير مخصص للتشخيص أو للاعتماد كتقرير طبي رسمي.</div>
  <div>$safeContent</div>
  <footer>$safeSignature</footer>
</body>
</html>''';
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$docContent'));
      return _saveBytes(
        dialogTitle: 'حفظ مستند Word متوافق',
        fileName: _safeFileName(title, 'doc'),
        bytes: bytes,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint("Error exporting to Word: $e\n$stack");
      }
      return null;
    }
  }

  /// Helper to escape HTML characters
  static String htmlContentEscape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// Export text content to a PDF document using the pdf package
  static Future<String?> exportToPdf(String title, String content) async {
    try {
      final pdf = pw.Document();

      // Load local Amiri font files (Regular & Bold) to prevent Helvetica fallback and support full RTL Arabic layout
      final regularData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
      final regularFont = pw.Font.ttf(regularData);
      final boldFont = pw.Font.ttf(boldData);

      final now = DateTime.now();
      final dateStr =
          '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

      // Prepare shaped Arabic texts for clinical document template
      final shapedHeaderUni = ArabicReshaper.reshape('جامعة النخبة - قسم تقنيات الأشعة والسونار');
      final shapedHeaderTitle = ArabicReshaper.reshape('تقرير تعليمي ذكي (EliteRadIq)');
      final shapedMetaDateLabel = ArabicReshaper.reshape('تاريخ التقرير:');
      final shapedMetaDateValue = ArabicReshaper.reshape(dateStr);
      final shapedMetaTypeLabel = ArabicReshaper.reshape('نوع المستند:');
      final shapedMetaTypeValue = ArabicReshaper.reshape('مستند تعليمي غير تشخيصي');
      final shapedMetaSourceLabel = ArabicReshaper.reshape('المصدر:');
      final shapedMetaSourceValue = ArabicReshaper.reshape('مساعد الذكاء الاصطناعي الأكاديمي');

      final shapedTitle = ArabicReshaper.reshape(title);
      final shapedSignature = ArabicReshaper.reshape(signature);

      // Process content line by line to structure paragraphs, bullet lists, and numbered lists
      final List<pw.Widget> bodyWidgets = [];
      final lines = content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        final shapedLine = ArabicReshaper.reshape(trimmed);

        if (trimmed.startsWith('-') || trimmed.startsWith('*') || trimmed.startsWith('•')) {
          // Bullet point
          final cleanLineText = trimmed.replaceFirst(RegExp(r'^[-*•]\s*'), '');
          final shapedCleanLine = ArabicReshaper.reshape(cleanLineText);
          bodyWidgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(right: 12, bottom: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 4,
                    height: 4,
                    margin: const pw.EdgeInsets.only(top: 6, left: 6),
                    decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFC5A059),
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      shapedCleanLine,
                      style: pw.TextStyle(
                        font: regularFont,
                        fontSize: 10.5,
                        lineSpacing: 1.4,
                        color: PdfColor.fromInt(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (RegExp(r'^\d+\.').hasMatch(trimmed)) {
          // Numbered point
          bodyWidgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(right: 6, bottom: 6),
              child: pw.Text(
                shapedLine,
                style: pw.TextStyle(
                  font: regularFont,
                  fontSize: 10.5,
                  lineSpacing: 1.4,
                  color: PdfColor.fromInt(0xFF1E293B),
                ),
              ),
            ),
          );
        } else {
          // Normal paragraph
          bodyWidgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                shapedLine,
                style: pw.TextStyle(
                  font: regularFont,
                  fontSize: 11,
                  lineSpacing: 1.5,
                  color: PdfColor.fromInt(0xFF0F172A),
                ),
              ),
            ),
          );
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(35),
          build: (pw.Context context) {
            return [
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Header branding Area
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              shapedHeaderUni,
                              style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 10,
                                color: PdfColor.fromInt(0xFF64748B),
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              shapedHeaderTitle,
                              style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 14,
                                color: PdfColor.fromInt(0xFF0B3C5D),
                              ),
                            ),
                          ],
                        ),
                        // Professional border logo placeholder
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColor.fromInt(0xFFC5A059), width: 1.5),
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                          ),
                          child: pw.Text(
                            'EliteRadIq',
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 11,
                              color: PdfColor.fromInt(0xFFC5A059),
                            ),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Container(height: 2.5, color: PdfColor.fromInt(0xFFC5A059)),
                    pw.SizedBox(height: 12),

                    // Patient / File Metadata Card
                    pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFF8FAFC),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Expanded(
                                child: pw.Row(
                                  children: [
                                    pw.Text(
                                      shapedMetaDateLabel,
                                      style: pw.TextStyle(
                                        font: boldFont,
                                        fontSize: 9,
                                        color: PdfColor.fromHex('#475569'),
                                      ),
                                    ),
                                    pw.SizedBox(width: 4),
                                    pw.Text(
                                      shapedMetaDateValue,
                                      style: pw.TextStyle(
                                        font: regularFont,
                                        fontSize: 9,
                                        color: PdfColor.fromHex('#0F172A'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              pw.Expanded(
                                child: pw.Row(
                                  children: [
                                    pw.Text(
                                      shapedMetaTypeLabel,
                                      style: pw.TextStyle(
                                        font: boldFont,
                                        fontSize: 9,
                                        color: PdfColor.fromHex('#475569'),
                                      ),
                                    ),
                                    pw.SizedBox(width: 4),
                                    pw.Text(
                                      shapedMetaTypeValue,
                                      style: pw.TextStyle(
                                        font: regularFont,
                                        fontSize: 9,
                                        color: PdfColor.fromHex('#0F172A'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 6),
                          pw.Divider(thickness: 0.5, color: PdfColor.fromHex('#E2E8F0')),
                          pw.SizedBox(height: 6),
                          pw.Row(
                            children: [
                              pw.Text(
                                shapedMetaSourceLabel,
                                style: pw.TextStyle(
                                  font: boldFont,
                                  fontSize: 9,
                                  color: PdfColor.fromHex('#475569'),
                                ),
                              ),
                              pw.SizedBox(width: 4),
                              pw.Text(
                                shapedMetaSourceValue,
                                style: pw.TextStyle(
                                  font: boldFont,
                                  fontSize: 9,
                                  color: PdfColor.fromHex('#0B3C5D'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 18),

                    // Document Title Section
                    pw.Text(
                      shapedTitle,
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 13,
                        color: PdfColor.fromHex('#0B3C5D'),
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Container(width: 40, height: 2, color: PdfColor.fromHex('#C5A059')),
                    pw.SizedBox(height: 14),

                    // Report content widgets
                    ...bodyWidgets,

                    pw.SizedBox(height: 25),
                    pw.Divider(thickness: 1, color: PdfColor.fromHex('#E2E8F0')),
                    pw.SizedBox(height: 10),

                    // Clinical signature block at the end
                    pw.Align(
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        shapedSignature,
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 8,
                          color: PdfColor.fromHex('#94A3B8'),
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      return _saveBytes(
        dialogTitle: 'حفظ مستند PDF',
        fileName: _safeFileName(title, 'pdf'),
        bytes: bytes,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint("Error exporting to PDF: $e\n$stack");
      }
      return null;
    }
  }
}
