import 'package:flutter/material.dart';

class CameraSessionProvider extends ChangeNotifier {
  final int maxPhotos = 10;
  final List<String> _photos = [];

  List<String> get photos => List.unmodifiable(_photos);

  bool get canTakePicture => _photos.length < maxPhotos;
  int get photosCount => _photos.length;

  /// Retorna a fase de captura atual. 
  /// Ex: 0 = Frente, 1 = Lateral Direita, etc.
  String get currentStageGuide {
    if (_photos.isEmpty) return 'Frente / Placa';
    if (_photos.length == 1) return 'Lateral Esquerda';
    if (_photos.length == 2) return 'Traseira / Placa';
    if (_photos.length == 3) return 'Lateral Direita';
    if (_photos.length == 4) return 'Painel (Odômetro)';
    return 'Danos/Avarias Livres';
  }

  void addPhoto(String path) {
    if (_photos.length < maxPhotos) {
      _photos.add(path);
      notifyListeners();
    }
  }

  void removePhoto(int index) {
    if (index >= 0 && index < _photos.length) {
      _photos.removeAt(index);
      notifyListeners();
    }
  }

  void resetSession() {
    _photos.clear();
    notifyListeners();
  }
}
