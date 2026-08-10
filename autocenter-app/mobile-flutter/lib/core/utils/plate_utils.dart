import 'package:flutter/services.dart';

class PlateValidator {
  /// Valida se a placa está no formato antigo (AAA-0000) ou Mercosul (AAA0A00)
  static bool isValid(String plate) {
    final cleanPlate = plate.replaceAll('-', '').toUpperCase();
    if (cleanPlate.length != 7) return false;

    // Regex para Padrão Antigo: AAA-0000 ou AAA0000 -> 3 letras, 4 números
    final RegExp oldPattern = RegExp(r'^[A-Z]{3}[0-9]{4}$');
    // Regex para Padrão Mercosul: AAA0A00 -> 3 letras, 1 número, 1 letra, 2 números
    final RegExp mercosulPattern = RegExp(r'^[A-Z]{3}[0-9][A-Z][0-9]{2}$');

    return oldPattern.hasMatch(cleanPlate) || mercosulPattern.hasMatch(cleanPlate);
  }
}

class PlateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String text = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (text.length > 7) {
      text = text.substring(0, 7);
    }

    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      if (i == 3 && PlateValidator.isValid(text) == false) {
        // Apenas adiciona hífen visualmente se ainda estiver no padrão antigo ao digitar.
        // No Brasil, a placa placa mercosul nao tem hifen, a antiga tem.
        // Para simplificar a UI, forçaremos o formato visual da antiga com hifen, 
        // e deixaremos a mercosul sem hífen, ou tudo com/sem baseado na 5ª letra.
        final fifthChar = text.length > 4 ? text[4] : null;
        bool isMercosul = fifthChar != null && RegExp(r'[A-Z]').hasMatch(fifthChar);
        if (!isMercosul && i == 3) {
           formatted += '-';
        }
      }
      formatted += text[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
