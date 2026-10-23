import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_html/html.dart' as html;

/// Transaction photos for Budget Web (stored as data-URLs in local JSON).
class TxImageHelper {
  TxImageHelper._();

  static const maxPhotos = 5;
  static final _picker = ImagePicker();

  static List<String> parseFromBackup(Map<String, dynamic> e) {
    final out = <String>[];

    void addRaw(dynamic raw) {
      if (raw == null) return;
      try {
        final list = raw is String
            ? (raw.trim().isEmpty || raw == '[]'
                ? <dynamic>[]
                : jsonDecode(raw))
            : raw;
        if (list is! List) return;
        for (final item in list) {
          final s = item.toString().trim();
          if (s.isEmpty) continue;
          if (s.startsWith('data:image')) {
            out.add(s);
          } else if (s.length > 64 && !s.contains('/') && !s.contains('\\')) {
            out.add('data:image/jpeg;base64,$s');
          }
          if (out.length >= maxPhotos) return;
        }
      } catch (_) {}
    }

    addRaw(e['imgs_base64']);
    if (out.isEmpty) addRaw(e['imgs']);
    if (out.isEmpty && e['images'] is List) addRaw(e['images']);
    return out.take(maxPhotos).toList();
  }

  static ImageProvider? provider(String dataUrl) {
    try {
      final i = dataUrl.indexOf('base64,');
      if (i < 0) return null;
      final bytes = base64Decode(dataUrl.substring(i + 7));
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Opens camera or gallery. Call this **immediately** from a button press
  /// (no `setState` / `await` before it) or the browser will block the dialog.
  static Future<String?> pickOne({required bool fromCamera}) async {
    if (kIsWeb) {
      try {
        return await _pickWeb(fromCamera: fromCamera);
      } catch (_) {
        // Fallback: gallery-style file picker (always works on desktop web).
        return _pickWithFilePicker();
      }
    }
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 68,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return _toDataUrl(bytes, file.mimeType ?? 'image/jpeg');
  }

  static Future<String?> _pickWeb({required bool fromCamera}) async {
    final completer = Completer<String?>();
    final input = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..multiple = false;

    // Mobile browsers: open camera. Desktop ignores capture → file dialog.
    if (fromCamera) {
      input.setAttribute('capture', 'environment');
    }

    input.style.display = 'none';
    html.document.body?.append(input);

    void cleanup() {
      try {
        input.remove();
      } catch (_) {}
    }

    input.onChange.listen((_) {
      final files = input.files;
      if (files == null || files.isEmpty) {
        if (!completer.isCompleted) completer.complete(null);
        cleanup();
        return;
      }
      final reader = html.FileReader();
      reader.onLoadEnd.listen((_) {
        final result = reader.result;
        if (!completer.isCompleted) {
          completer.complete(result is String ? result : null);
        }
        cleanup();
      });
      reader.onError.listen((_) {
        if (!completer.isCompleted) {
          completer.completeError('Could not read photo');
        }
        cleanup();
      });
      reader.readAsDataUrl(files.first);
    });

    // Must run in the same user-gesture turn as the button tap.
    input.click();

    return completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        cleanup();
        return null;
      },
    );
  }

  static Future<String?> _pickWithFilePicker() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    final f = files.first;
    final bytes = await f.readAsBytes();
    final mime = f.extension == 'png'
        ? 'image/png'
        : f.extension == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    return _toDataUrl(bytes, mime);
  }

  static String? _toDataUrl(List<int> bytes, String mime) {
    if (bytes.isEmpty) return null;
    if (bytes.length > 2 * 1024 * 1024) {
      throw 'Photo too large (max ~2 MB). Pick a smaller image.';
    }
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }
}
