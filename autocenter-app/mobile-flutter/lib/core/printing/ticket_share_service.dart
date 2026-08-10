import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class TicketShareService {
  static final TicketShareService _instance = TicketShareService._internal();
  factory TicketShareService() => _instance;
  TicketShareService._internal();

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  /// Gera a string do recibo e dispara o evento de compartilhamento do S.O.
  Future<void> shareQuoteTicket({
    required String plate,
    required String customerName,
    required List<dynamic> items,
    required double totalAmount,
    required String status,
  }) async {
    String dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    StringBuffer buffer = StringBuffer();
    
    // --- Header ---
    buffer.writeln('================================');
    buffer.writeln('       COLISEU AUTOCENTER       ');
    buffer.writeln('================================');
    buffer.writeln('     Comprovante de Vistoria    ');
    buffer.writeln('');
    buffer.writeln('Veiculo: \$plate');
    buffer.writeln('Status: \$status');
    buffer.writeln('Data: \$dateStr');
    buffer.writeln('Cliente: \$customerName');
    buffer.writeln('');
    
    // --- Body ---
    buffer.writeln('--------------------------------');
    buffer.writeln('ITENS AVALIADOS');
    buffer.writeln('--------------------------------');
    
    for (var item in items) {
       final name = item['productDescription'] ?? item['product_name'] ?? 'Item';
       final qty = item['quantity'] ?? 1;
       final price = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
       
       String line1 = '\${qty}x \$name';
       if (line1.length > 30) line1 = line1.substring(0, 30);
       buffer.writeln(line1);
       buffer.writeln('   Sub: \${_currencyFormat.format(price * qty)}');
    }
    
    buffer.writeln('--------------------------------');
    buffer.writeln('TOTAL PREVISTO: \${_currencyFormat.format(totalAmount)}');
    buffer.writeln('');
    
    // --- Footer / Signature ---
    buffer.writeln('--------------------------------');
    buffer.writeln('Declaro estar ciente dos servicos');
    buffer.writeln('e pecas apontadas na vistoria');
    buffer.writeln('');
    buffer.writeln('');
    buffer.writeln('________________________________');
    buffer.writeln('     Assinatura do Cliente      ');
    buffer.writeln('');
    buffer.writeln('================================');
    
    // Dispara via nativo (Envia para o RawBT ou Apps de Mensagem)
    await Share.share(buffer.toString(), subject: 'Vistoria AutoCenter - \$plate');
  }
}
