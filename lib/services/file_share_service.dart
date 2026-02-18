import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileShareService {
  static Future<File> writeTempText({
    required String filename,
    required String text,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(text, flush: true);
    return file;
  }

  static Future<File> writeTempBytes({
    required String filename,
    required List<int> bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> shareFile({
    required File file,
    required String filename,
    required String mimeType,
    String? text,
  }) async {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType, name: filename)],
      text: text,
    );
  }
}
