import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class CameraEngineService {
  /// Executa a compressão da imagem capturada em background, prevenindo gargalo
  /// de IO (Payload Too Large) antes do Sync Service.
  Future<String?> compressAndSave(String originalPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final compressedPath = '${tempDir.path}/compress_${DateTime.now().millisecondsSinceEpoch}.webp';
      
      final result = await FlutterImageCompress.compressAndGetFile(
        originalPath,
        compressedPath,
        quality: 80, // Limite ótimo recomendado na spec
        minWidth: 1080,
        minHeight: 1920,
        format: CompressFormat.webp,
      );
      
      // Prevenção de OutOfMemory: Apagar a gigantesca foto bruta original da memória Flash.
      _deleteIfExist(originalPath);

      return result?.path;
    } catch (e) {
      // Falha fallback: retorna o original se o compressor falhar (raro)
      return originalPath; 
    }
  }

  Future<void> _deleteIfExist(String path) async {
    final originalFile = File(path);
    if (await originalFile.exists()) {
      await originalFile.delete();
    }
  }
}
