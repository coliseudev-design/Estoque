import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../core/repositories/models/models.dart';
import '../core/services/order_pdf_service.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_typography.dart';

class OrderShareSheet {
  /// Mostra opções de compartilhamento: texto (WhatsApp), PDF Profissional ou Impressora Térmica(58mm)
  static void show(BuildContext context, Order order) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Compartilhar Pedido', style: AppTypography.sectionTitle),
            ),
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: AppColors.success),
              title: const Text('Texto (WhatsApp)'),
              subtitle: const Text('Formato texto para mensagens'),
              onTap: () {
                Navigator.pop(ctx);
                _shareAsText(order);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error),
              title: const Text('PDF Profissional (A4)'),
              subtitle: const Text('Documento com layout Coliseu'),
              onTap: () {
                Navigator.pop(ctx);
                _shareAsPdf(context, order);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
              title: const Text('Recibo Térmico (58mm)'),
              subtitle: const Text('Bobina para mini Impressoras Bluetooth'),
              onTap: () {
                Navigator.pop(ctx);
                _shareAsThermalPdf(context, order);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static void _shareAsText(Order order) {
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    final cur     = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final dt      = DateTime.tryParse(order.createdAt) ?? DateTime.now();

    final buf = StringBuffer();
    buf.writeln('🛒 *PEDIDO — COLISEU VENDAS*');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('*Cliente:* ${order.customerName}');
    buf.writeln('*Data:* ${dateFmt.format(dt.toLocal())}');
    if (order.erpOrderId != null) buf.writeln('*N° ERP:* ${order.erpOrderId}');
    if (order.naturezaDescricao != null) buf.writeln('*Tipo:* ${order.naturezaDescricao}');
    if (order.paymentSpeciesName != null) {
      buf.write('*Pagamento:* ${order.paymentSpeciesName}');
      if (order.paymentConditionName != null) {
        buf.write(' (${order.paymentConditionName})');
      }
      buf.writeln();
    }
    buf.writeln();
    buf.writeln('*ITENS*');
    for (final item in order.items) {
      final qty = item.quantity == item.quantity.truncate()
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      buf.writeln('• ${item.productName}');
      buf.writeln('  $qty × ${cur.format(item.unitPrice)} = ${cur.format(item.totalPrice)}');
      if (item.discount > 0) buf.writeln('  (Desc. ${item.discount.toStringAsFixed(1)}%)');
    }
    buf.writeln();
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━');
    if (order.discountValue > 0) {
      buf.writeln('Bruto:    ${cur.format(order.totalAmount + order.discountValue)}');
      buf.writeln('Desconto: -${cur.format(order.discountValue)}');
    }
    buf.writeln('*Total:   ${cur.format(order.totalAmount)}*');

    Share.share(buf.toString(), subject: 'Pedido — ${order.customerName}', sharePositionOrigin: const Rect.fromLTWH(0, 0, 10, 10));
  }

  static Future<void> _shareAsPdf(BuildContext context, Order order) async {
    final pdfSvc = GetIt.I<OrderPdfService>();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gerando PDF...'), duration: Duration(seconds: 2)),
    );
    try {
      await pdfSvc.shareOrder(order);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  static Future<void> _shareAsThermalPdf(BuildContext context, Order order) async {
    final pdfSvc = GetIt.I<OrderPdfService>();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gerando Recibo Térmico...'), duration: Duration(seconds: 2)),
    );
    try {
      await pdfSvc.shareThermalOrder(order);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar Recibo: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}
