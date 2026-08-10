import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/service_order.dart';

class OrderPdfService {
  Future<String> generateA4Pdf(ServiceOrder os) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('COLISEU AUTOCENTER', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
              ),
              pw.Center(
                child: pw.Text('ORDEM DE SERVIÇO', style: pw.TextStyle(fontSize: 12)),
              ),
              pw.SizedBox(height: 15),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('OS ID: #${os.id.length > 8 ? os.id.substring(0, 8) : os.id}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Status: ${os.status}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Text('Placa: ${os.plate}'),
              pw.Text('Data de Abertura: ${os.createdAt.replaceAll('T', ' ').substring(0, 16)}'),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 5),
              pw.Text('DADOS DO CLIENTE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.SizedBox(height: 5),
              pw.Text('Nome: ${os.customerName ?? "Não Informado"}'),
              pw.Text('Telefone: ${os.customerPhone ?? "Não Informado"}'),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 5),
              pw.Text('SINTOMAS / DIAGNÓSTICO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.SizedBox(height: 5),
              pw.Text(os.observation ?? 'Nenhum sintoma ou diagnóstico informado.', style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 5),

              // Checklist
              if (os.checklist.isNotEmpty) ...[
                pw.Text('CHECKLIST DE ENTRADA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.SizedBox(height: 5),
                for (var check in os.checklist)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Text('• ${check.itemName}: [${check.status}] ${check.observation != null && check.observation!.isNotEmpty ? "(${check.observation})" : ""}'),
                  ),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 5),
              ],

              // Items Table
              pw.Text('PEÇAS E SERVIÇOS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.SizedBox(height: 8),
              if (os.items.isEmpty)
                pw.Text('Nenhum item faturado na Ordem de Serviço.', style: const pw.TextStyle(fontSize: 12))
              else
                pw.TableHelper.fromTextArray(
                  headers: ['Código', 'Descrição', 'Qtd', 'Vlr. Unitário', 'Vlr. Total'],
                  data: os.items.map((item) {
                    return [
                      item.productCode,
                      item.productDescription,
                      item.quantity.toStringAsFixed(0),
                      'R\$ ${item.unitPrice.toStringAsFixed(2)}',
                      'R\$ ${item.totalPrice.toStringAsFixed(2)}',
                    ];
                  }).toList(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellAlignments: {
                    2: pw.Alignment.center,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                  },
                ),
              pw.SizedBox(height: 15),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('VALOR TOTAL DA OS: R\$ ${os.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              ),
              if (os.photos.any((p) => p.photoType == 'SIGNATURE')) ...[
                pw.SizedBox(height: 20),
                pw.Center(
                  child: pw.Column(
                    children: [
                      _buildPdfSignatureImage(os),
                      pw.SizedBox(height: 2),
                      pw.Container(width: 180, height: 0.5, color: PdfColors.grey500),
                      pw.SizedBox(height: 2),
                      pw.Text('Assinatura do Cliente', style: pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/os_${os.id}_a4.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  Future<String> generate58mmReceipt(ServiceOrder os) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 1.5 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('COLISEU AUTOCENTER', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ),
              pw.Center(
                child: pw.Text('CUPOM DE ENTRADA / OS', style: pw.TextStyle(fontSize: 7)),
              ),
              pw.Divider(thickness: 0.5),
              pw.Text('OS: #${os.id.length > 8 ? os.id.substring(0, 8) : os.id}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
              pw.Text('Placa: ${os.plate}', style: pw.TextStyle(fontSize: 7)),
              pw.Text('Data: ${os.createdAt.replaceAll('T', ' ').substring(0, 16)}', style: pw.TextStyle(fontSize: 7)),
              pw.Text('Cliente: ${os.customerName ?? "N/D"}', style: pw.TextStyle(fontSize: 7)),
              pw.Divider(thickness: 0.5),
              pw.Text('Reclamações:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
              pw.Text(os.observation ?? 'Sem reclamações.', style: const pw.TextStyle(fontSize: 6)),
              pw.Divider(thickness: 0.5),
              if (os.items.isNotEmpty) ...[
                pw.Text('Itens:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                for (var item in os.items)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            '${item.productDescription.substring(0, item.productDescription.length > 22 ? 22 : item.productDescription.length)}...',
                            style: const pw.TextStyle(fontSize: 6),
                          ),
                        ),
                        pw.Text(
                          '${item.quantity.toStringAsFixed(0)}x R\$ ${item.totalPrice.toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 6),
                        ),
                      ],
                    ),
                  ),
                pw.Divider(thickness: 0.5),
              ],
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('TOTAL: R\$ ${os.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/os_${os.id}_58mm.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  String generateWhatsAppText(ServiceOrder os) {
    final sb = StringBuffer();
    sb.writeln('🚨 *COLISEU AUTOCENTER - RESUMO DE OS* 🚨');
    sb.writeln('-----------------------------------');
    sb.writeln('📌 *OS:* #${os.id.length > 8 ? os.id.substring(0, 8) : os.id}');
    sb.writeln('🚗 *Placa:* ${os.plate}');
    sb.writeln('👤 *Cliente:* ${os.customerName ?? "Não Informado"}');
    sb.writeln('📋 *Status:* ${os.status}');
    sb.writeln('-----------------------------------');
    sb.writeln('🛠️ *Problemas / Diagnóstico:*');
    sb.writeln(os.observation ?? 'Sem observações.');
    sb.writeln('-----------------------------------');
    if (os.items.isNotEmpty) {
      sb.writeln('📦 *Peças & Serviços:*');
      for (var item in os.items) {
        sb.writeln('• ${item.productDescription} (x${item.quantity.toStringAsFixed(0)}): R\$ ${item.totalPrice.toStringAsFixed(2)}');
      }
      sb.writeln('-----------------------------------');
    }
    sb.writeln('💰 *Valor Total: R\$ ${os.totalAmount.toStringAsFixed(2)}*');
    return sb.toString();
  }

  pw.Widget _buildPdfSignatureImage(ServiceOrder os) {
    try {
      final sigPhoto = os.photos.firstWhere((p) => p.photoType == 'SIGNATURE');
      final file = File(sigPhoto.photoUrl);
      if (file.existsSync()) {
        final image = pw.MemoryImage(file.readAsBytesSync());
        return pw.Image(image, width: 120, height: 60);
      }
    } catch (_) {}
    return pw.SizedBox(width: 120, height: 60);
  }
}
