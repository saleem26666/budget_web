import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

class BackupShare {
  /// Download JSON backup in browser (or share on native if ever used).
  static Future<void> exportJson(String json,
      {String fileName = 'BudgetWeb_backup.json'}) async {
    if (kIsWeb) {
      final bytes = utf8.encode(json);
      final blob = html.Blob([bytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: json, subject: fileName),
    );
  }

  static Future<void> shareText(String text, {String? subject}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: subject),
      );
    } catch (_) {
      await exportJson(text, fileName: subject ?? 'BudgetWeb_share.txt');
    }
  }

  /// Pick a .json / .budgetpro file and return UTF-8 content.
  static Future<String?> pickBackupText() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'budgetpro', 'txt'],
    );
    if (files.isEmpty) return null;
    final bytes = await files.first.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<void> downloadBytes(
    Uint8List bytes, {
    required String fileName,
    String mime = 'application/octet-stream',
  }) async {
    if (!kIsWeb) return;
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
