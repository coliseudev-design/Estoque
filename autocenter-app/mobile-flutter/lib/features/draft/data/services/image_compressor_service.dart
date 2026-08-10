import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CompressJob {
  final String filePath;
  final String targetPath;

  CompressJob(this.filePath, this.targetPath);
}

class ImageCompressorService {
  /// Reduz tamanho das imagens prevenindo OOM.
  /// Roda a lógica de compressão em outro Isolate usando `compute`.
  static Future<String?> compressAndGetFile(String originalPath) async {
    final tempDir = await getTemporaryDirectory();
    final basename = p.basenameWithoutExtension(originalPath);
    final targetPath = p.join(tempDir.path, '${basename}_compressed.jpg');

    // Executa em uma Thread separada (Isolate)
    final result = await compute(_compressTask, CompressJob(originalPath, targetPath));
    return result;
  }

  // Função pura/top-level obrigatória para Isolate
  static Future<String?> _compressTask(CompressJob job) async {
    final result = await FlutterImageCompress.compressAndGetFile(
      job.filePath,
      job.targetPath,
      quality: 80, // WebP/Jpeg 80% como ditado na SPEC
      format: CompressFormat.jpeg,
    );
    return result?.path;
  }
}
