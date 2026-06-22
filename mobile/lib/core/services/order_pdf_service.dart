/// OrderPdfService — Gera PDF profissional de pedido/orçamento para compartilhamento.
///
/// Usa `pdf` package para gerar o documento e `share_plus` para compartilhar
/// via WhatsApp, e-mail ou outros apps.
///
/// Layout corporativo B2B:
///   1. Cabeçalho institucional (navy dark)
///   2. Dados do cliente + informações comerciais (duas colunas)
///   3. Tabela de produtos (header navy, linhas alternadas)
///   4. Resumo financeiro (subtotal, desconto, total destacado)
///   5. Observações do pedido
///   6. Área de assinatura do cliente
///   7. Rodapé profissional
///
/// Arquivo salvo temporariamente em `path_provider` temp dir.
library;

import 'dart:io';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../repositories/models/models.dart';
import '../database/database_helper.dart';
import '../sync/sync_service.dart';

/// Serviço para gerar e compartilhar PDFs profissionais de pedidos.
class OrderPdfService {
  final DatabaseHelper _db;

  OrderPdfService(this._db);

  // ── Formatadores ──────────────────────────────────────────────────────────
  static final _cur = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _dateFmtShort = DateFormat('dd/MM/yyyy', 'pt_BR');

  // ── Paleta de cores corporativa ───────────────────────────────────────────
  static const _navyDark  = PdfColor.fromInt(0xFF0F1B3D);
  static const _navyMid   = PdfColor.fromInt(0xFF1A2E5A);
  static const _accentBlue = PdfColor.fromInt(0xFF2563EB);
  static const _lightGray = PdfColor.fromInt(0xFFF5F7FA);
  static const _medGray   = PdfColor.fromInt(0xFFE5E7EB);
  static const _textDark  = PdfColor.fromInt(0xFF111827);
  static const _textMid   = PdfColor.fromInt(0xFF4B5563);
  static const _textLight = PdfColor.fromInt(0xFF9CA3AF);
  static const _red       = PdfColor.fromInt(0xFFDC2626);
  static const _amberBg   = PdfColor.fromInt(0xFFFFF8E1);
  static const _amberBdr  = PdfColor.fromInt(0xFFFFE082);
  static const _amberText = PdfColor.fromInt(0xFF92400E);

  /// Gera um PDF profissional do pedido e retorna o caminho do arquivo temporário.
  ///
  /// Args:
  ///   order: Pedido a ser exportado.
  ///
  /// Returns:
  ///   Caminho absoluto do PDF gerado.
  Future<String> generatePdf(Order order) async {
    // Busca itens do pedido
    final db = await _db.database;
    final itemRows = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [order.id],
    );

    // Busca dados completos do cliente no cache SQLite
    Map<String, dynamic>? customer;
    try {
      final customerRows = await db.query(
        'customers',
        where: 'id = ?',
        whereArgs: [order.customerId],
        limit: 1,
      );
      if (customerRows.isNotEmpty) customer = customerRows.first;
    } catch (_) {
      // Se não encontrar, usamos apenas os dados do Order
    }

    // Busca nome do vendedor e empresa da sessão ativa
    String sellerName = '';
    String companyName = '';
    try {
      final sessionRows = await db.query(
        'seller_sessions',
        where: 'active = 1',
        limit: 1,
      );
      if (sessionRows.isNotEmpty) {
        sellerName = sessionRows.first['seller_name'] as String? ?? '';
        companyName = sessionRows.first['company_name'] as String? ?? '';
      }
    } catch (_) {}

    // Fallback: busca nome da empresa de server_config
    if (companyName.isEmpty) {
      try {
        final configRows = await db.query(
          'server_config',
          columns: ['company_name'],
          limit: 1,
        );
        if (configRows.isNotEmpty) {
          companyName = configRows.first['company_name'] as String? ?? '';
        }
      } catch (_) {}
    }

    // Determina se é orçamento ou pedido
    final isQuote = order.syncStatus == OrderSyncStatus.draft;
    final docTitle = isQuote ? 'ORÇAMENTO' : 'PEDIDO DE VENDA';

    // Calcula subtotal bruto (soma dos itens antes de desconto geral)
    final subtotalBruto = order.totalAmount + order.discountValue;

    final pdf = pw.Document(
      title: '$docTitle - ${order.customerName}',
      author: 'Coliseu Sales',
    );

    // Carrega logo da empresa (se disponível via sync)
    pw.MemoryImage? companyLogo;
    try {
      final logoFile = await SyncService.getCompanyLogoFile();
      if (await logoFile.exists()) {
        final logoBytes = await logoFile.readAsBytes();
        if (logoBytes.isNotEmpty) {
          companyLogo = pw.MemoryImage(logoBytes);
        }
      }
    } catch (_) {
      // Fallback: sem logo, cabeçalho texto-only
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 24, 32, 24),
        footer: (_) => _buildFooter(),
        build: (context) => [
          _buildHeader(order, docTitle, sellerName, companyName, companyLogo),
          pw.SizedBox(height: 16),
          _buildInfoBlocks(order, customer, sellerName),
          pw.SizedBox(height: 16),
          _buildItemsTable(itemRows),
          pw.SizedBox(height: 14),
          _buildFinancialSummary(subtotalBruto, order.discountValue, order.totalAmount),
          if (order.notes != null && order.notes!.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _buildNotes(order.notes!),
          ],
          pw.SizedBox(height: 24),
          _buildSignatureArea(),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pedido_${order.id.substring(0, 8)}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  /// Gera e compartilha o PDF via apps do dispositivo (WhatsApp, e-mail, etc).
  Future<void> shareOrder(Order order) async {
    final path = await generatePdf(order);
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf')],
      subject: 'Pedido Coliseu Sales - ${order.customerName}',
      text: 'Segue o comprovante do pedido para ${order.customerName}.',
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 10, 10),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 👉 NOVO: IMPRESSÃO TÉRMICA 58mm (Roll)
  // ════════════════════════════════════════════════════════════════════════════

  /// Gera um Recibo Térmico (58mm) e retorna o caminho temporário.
  Future<String> generateThermalPdf(Order order) async {
    final db = await _db.database;
    final itemRows = await db.query('order_items', where: 'order_id = ?', whereArgs: [order.id]);

    String sellerName = '';
    String companyName = '';
    try {
      final sessionRows = await db.query('seller_sessions', where: 'active = 1', limit: 1);
      if (sessionRows.isNotEmpty) {
        sellerName = sessionRows.first['seller_name'] as String? ?? '';
        companyName = sessionRows.first['company_name'] as String? ?? '';
      }
    } catch (_) {}

    if (companyName.isEmpty) {
      try {
        final configRows = await db.query('server_config', columns: ['company_name'], limit: 1);
        if (configRows.isNotEmpty) {
          companyName = configRows.first['company_name'] as String? ?? '';
        }
      } catch (_) {}
    }

    final pdf = pw.Document(title: 'Recibo - ${order.customerName}', author: 'Coliseu Sales');

    // Largura 58mm = 58 * PdfPageFormat.mm (~164.4 points).
    // Roll (bobina) indica página infinita para baixo.
    final format = PdfPageFormat.roll57.copyWith(
      marginLeft: 2 * PdfPageFormat.mm,
      marginRight: 2 * PdfPageFormat.mm,
      marginTop: 2 * PdfPageFormat.mm,
      marginBottom: 5 * PdfPageFormat.mm,
    );

    final fontRegular = pw.Font.courier();
    final fontBold = pw.Font.courierBold();

    pw.Widget divider() => pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, style: pw.BorderStyle.dashed, width: 0.8)),
      ),
    );

    pw.Widget text(String val, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Text(
          val,
          textAlign: align,
          style: pw.TextStyle(
            font: bold ? fontBold : fontRegular,
            fontSize: 9,
            color: PdfColors.black,
          ),
        );

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              // Cabeçalho
              pw.Center(child: text(companyName.isNotEmpty ? companyName.toUpperCase() : 'COLISEU VENDAS', bold: true, align: pw.TextAlign.center)),
              pw.SizedBox(height: 2),
              pw.Center(child: text('Telefone(s): (67) 3423-2227', align: pw.TextAlign.center)),
              divider(),
              
              // Dados Pedido
              text('Vendedor: $sellerName'),
              text('Cliente : ${order.customerName}'),
              text('Emissao : ${_dateFmt.format(DateTime.tryParse(order.createdAt) ?? DateTime.now())}'),
              if (order.erpOrderId != null) text('N. ERP  : #${order.erpOrderId}'),
              divider(),

              // Tabela Itens (Condensada)
              text('Qtd x Vn.Unit = Vn.Total', bold: true),
              divider(),
              ...itemRows.map((item) {
                final prodName = item['product_name']?.toString() ?? '';
                final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
                final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
                final totalItem = (item['total_price'] as num?)?.toDouble() ?? (qty * unitPrice);
                
                final qtyStr = qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toStringAsFixed(2);
                final line2 = '${qtyStr.padRight(4)}x ${_cur.format(unitPrice).padRight(9)}= ${_cur.format(totalItem).padLeft(9)}';
                
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    text(prodName),
                    text(line2),
                    pw.SizedBox(height: 2),
                  ],
                );
              }),
              divider(),

              // Totais
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  text('Subtotal:'),
                  text(_cur.format(order.totalAmount + order.discountValue)),
                ],
              ),
              if (order.discountValue > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    text('Desconto:'),
                    text('- ${_cur.format(order.discountValue)}'),
                  ],
                ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  text('TOTAL:', bold: true),
                  text(_cur.format(order.totalAmount), bold: true),
                ],
              ),
              divider(),

              // Pagamento
              if (order.paymentSpeciesName != null) text('Pagam.: ${order.paymentSpeciesName}'),
              if (order.paymentConditionName != null) text('Cond. : ${order.paymentConditionName}'),
              
              pw.SizedBox(height: 4),
              pw.Center(child: text('DOCUMENTO NAO FISCAL', align: pw.TextAlign.center, bold: true)),
              pw.SizedBox(height: 4),
              pw.Center(child: text('Desenvolvido pela Coliseu Sistemas', align: pw.TextAlign.center)),
              pw.SizedBox(height: 10), // Folga pra guilhotina
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/recibo_${order.id.substring(0, 8)}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  /// Compartilha o recibo térmico (58mm) via apps do dispositivo.
  Future<void> shareThermalOrder(Order order) async {
    final path = await generateThermalPdf(order);
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf')],
      subject: 'Recibo Termico - ${order.customerName}',
      text: 'O impresso termico do pedido de ${order.customerName} esta disponivel para impressao via Bluetooth.',
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 10, 10),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 1. CABEÇALHO CORPORATIVO
  // ════════════════════════════════════════════════════════════════════════════

  pw.Widget _buildHeader(Order order, String docTitle, String sellerName, String companyName, [pw.MemoryImage? logo]) {
    final createdAt = DateTime.tryParse(order.createdAt);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: pw.BoxDecoration(
        color: _navyDark,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── Esquerda: Logo + Marca ────────────────────────────────────────
          pw.Expanded(
            flex: 3,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Container(
                    width: 55,
                    height: 55,
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(4),
                      color: PdfColors.white,
                    ),
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Text(
                    companyName.isNotEmpty ? companyName.toUpperCase() : 'PEDIDO',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                  ),
                ),
              ],
            ),
          ),

          // ── Direita: Dados do documento ─────────────────────────────────
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(docTitle,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.8,
                    )),
                pw.SizedBox(height: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: _navyMid,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    'Nº ${order.erpOrderId ?? order.id.substring(0, 8).toUpperCase()}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                if (createdAt != null)
                  pw.Text(
                    _dateFmt.format(createdAt),
                    style: const pw.TextStyle(
                      color: PdfColors.grey400,
                      fontSize: 9,
                    ),
                  ),
                if (order.erpOrderId != null && order.erpOrderId != order.id.substring(0, 8)) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'ERP #${order.erpOrderId}',
                    style: pw.TextStyle(
                      color: PdfColors.grey300,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 2. BLOCOS DE INFORMAÇÃO (Cliente + Comercial)
  // ════════════════════════════════════════════════════════════════════════════

  pw.Widget _buildInfoBlocks(
    Order order,
    Map<String, dynamic>? customer,
    String sellerName,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _lightGray,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _medGray, width: 0.5),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── Coluna esquerda: Dados do Cliente ────────────────────────────
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(14),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _sectionLabel('DADOS DO CLIENTE'),
                  pw.SizedBox(height: 8),
                  _infoRow('Cliente', order.customerName, bold: true),
                  if (customer != null) ...[
                    if (customer['cnpj'] != null && (customer['cnpj'] as String).trim().isNotEmpty)
                      _infoRow('CPF/CNPJ', customer['cnpj'] as String),
                    if (customer['phone'] != null && (customer['phone'] as String).trim().isNotEmpty)
                      _infoRow('Telefone', customer['phone'] as String),
                    if (customer['email'] != null && (customer['email'] as String).trim().isNotEmpty)
                      _infoRow('Email', customer['email'] as String),
                    _buildAddress(customer),
                  ],
                  if (order.customerId.isNotEmpty)
                    _infoRow('Código', order.customerId),
                ],
              ),
            ),
          ),

          // ── Divisor vertical ────────────────────────────────────────────
          pw.Container(width: 0.5, height: 130, color: _medGray),

          // ── Coluna direita: Informações Comerciais ──────────────────────
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(14),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _sectionLabel('INFORMAÇÕES COMERCIAIS'),
                  pw.SizedBox(height: 8),
                  if (sellerName.isNotEmpty)
                    _infoRow('Vendedor', sellerName),
                  if (order.paymentSpeciesName != null)
                    _infoRow('Espécie Pgto', order.paymentSpeciesName!),
                  if (order.paymentConditionName != null)
                    _infoRow('Condição', order.paymentConditionName!),
                  if (order.paymentDays != null && order.paymentDays! > 0)
                    _infoRow('Prazo', '${order.paymentDays} dias'),
                  if (order.naturezaDescricao != null)
                    _infoRow('Natureza', order.naturezaDescricao!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Monta a linha de endereço a partir dos campos do cliente.
  pw.Widget _buildAddress(Map<String, dynamic> c) {
    final parts = <String>[];
    final street = (c['street'] as String?)?.trim() ?? '';
    final neighborhood = (c['neighborhood'] as String?)?.trim() ?? '';
    final city = (c['city'] as String?)?.trim() ?? '';
    final state = (c['state'] as String?)?.trim() ?? '';
    final zipCode = (c['zip_code'] as String?)?.trim() ?? '';

    if (street.isNotEmpty) parts.add(street);
    if (neighborhood.isNotEmpty) parts.add(neighborhood);

    final cityState = <String>[];
    if (city.isNotEmpty) cityState.add(city);
    if (state.isNotEmpty) cityState.add(state);

    if (parts.isEmpty && cityState.isEmpty) return pw.SizedBox.shrink();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (parts.isNotEmpty)
          _infoRow('Endereço', parts.join(', ')),
        if (cityState.isNotEmpty)
          _infoRow('Cidade', cityState.join('/')),
        if (zipCode.isNotEmpty)
          _infoRow('CEP', zipCode),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 3. TABELA DE PRODUTOS
  // ════════════════════════════════════════════════════════════════════════════

  pw.Widget _buildItemsTable(List<Map<String, dynamic>> items) {
    // Cabeçalho da tabela
    final headerStyle = pw.TextStyle(
      color: PdfColors.white,
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
    );
    final cellStyle = const pw.TextStyle(fontSize: 8, color: _textDark);
    final cellStyleRight = const pw.TextStyle(fontSize: 8, color: _textDark);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionLabel('ITENS DO PEDIDO'),
        pw.SizedBox(height: 6),

        // ── Header row ──────────────────────────────────────────────────
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: pw.BoxDecoration(
            color: _navyDark,
            borderRadius: const pw.BorderRadius.only(
              topLeft: pw.Radius.circular(4),
              topRight: pw.Radius.circular(4),
            ),
          ),
          child: pw.Row(
            children: [
              _headerCell('#', 20, headerStyle),
              _headerCell('CÓDIGO', 50, headerStyle),
              _headerCell('PRODUTO', 0, headerStyle, flex: 1),
              _headerCell('QTD', 35, headerStyle, align: pw.Alignment.centerRight),
              _headerCell('UN', 25, headerStyle, align: pw.Alignment.center),
              _headerCell('PREÇO UNIT.', 65, headerStyle, align: pw.Alignment.centerRight),
              _headerCell('DESC.', 40, headerStyle, align: pw.Alignment.centerRight),
              _headerCell('TOTAL', 65, headerStyle, align: pw.Alignment.centerRight),
            ],
          ),
        ),

        // ── Data rows ───────────────────────────────────────────────────
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
          final discount = (item['discount'] as num?)?.toDouble() ?? 0;
          final totalItem = (item['total_price'] as num?)?.toDouble() ?? (qty * unitPrice * (1 - discount / 100));
          final isEven = idx % 2 == 0;

          return pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.white : _lightGray,
              border: pw.Border(
                left: pw.BorderSide(color: _medGray, width: 0.5),
                right: pw.BorderSide(color: _medGray, width: 0.5),
                bottom: pw.BorderSide(color: _medGray, width: 0.5),
              ),
            ),
            child: pw.Row(
              children: [
                _dataCell('${idx + 1}', 20, cellStyle),
                _dataCell(item['product_code']?.toString() ?? '', 50, cellStyle),
                _dataCell(item['product_name']?.toString() ?? '', 0, cellStyle, flex: 1),
                _dataCell(
                  qty == qty.roundToDouble()
                      ? qty.toInt().toString()
                      : qty.toStringAsFixed(2),
                  35, cellStyleRight, align: pw.Alignment.centerRight,
                ),
                _dataCell('UN', 25, cellStyle, align: pw.Alignment.center),
                _dataCell(_cur.format(unitPrice), 65, cellStyleRight, align: pw.Alignment.centerRight),
                _dataCell(
                  discount > 0 ? '${discount.toStringAsFixed(1)}%' : '-',
                  40,
                  discount > 0
                      ? const pw.TextStyle(fontSize: 8, color: _red)
                      : const pw.TextStyle(fontSize: 8, color: _textLight),
                  align: pw.Alignment.centerRight,
                ),
                _dataCell(_cur.format(totalItem), 65,
                    pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _textDark),
                    align: pw.Alignment.centerRight),
              ],
            ),
          );
        }),

        // ── Borda inferior arredondada ───────────────────────────────────
        pw.Container(
          height: 2,
          decoration: pw.BoxDecoration(
            color: _navyDark,
            borderRadius: const pw.BorderRadius.only(
              bottomLeft: pw.Radius.circular(4),
              bottomRight: pw.Radius.circular(4),
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 4. RESUMO FINANCEIRO
  // ════════════════════════════════════════════════════════════════════════════

  pw.Widget _buildFinancialSummary(
    double subtotal,
    double discount,
    double total,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 240,
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: _medGray, width: 0.8),
          ),
          child: pw.Column(
            children: [
              // Subtotal
              _summaryRow('Subtotal', _cur.format(subtotal), _textMid),
              pw.SizedBox(height: 6),

              // Desconto (se houver)
              if (discount > 0) ...[
                _summaryRow('Desconto', '- ${_cur.format(discount)}', _red),
                pw.SizedBox(height: 8),
              ],

              // Divider
              pw.Container(height: 1, color: _medGray),
              pw.SizedBox(height: 8),

              // Total destacado
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL DO PEDIDO',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: _textDark,
                      )),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: _navyDark,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      _cur.format(total),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 5. OBSERVAÇÕES
  // ════════════════════════════════════════════════════════════════════════════

  pw.Widget _buildNotes(String notes) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _amberBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _amberBdr, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('OBSERVAÇÕES',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _amberText,
                letterSpacing: 0.6,
              )),
          pw.SizedBox(height: 5),
          pw.Text(notes,
              style: const pw.TextStyle(
                fontSize: 9,
                color: _textDark,
              )),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 6. ÁREA DE ASSINATURA DO CLIENTE
  // ════════════════════════════════════════════════════════════════════════════

  pw.Widget _buildSignatureArea() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          // ── Assinatura ────────────────────────────────────────────────
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 40),
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: _textLight,
                        width: 0.8,
                        style: pw.BorderStyle.dashed,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Assinatura do Responsável',
                    style: const pw.TextStyle(fontSize: 8, color: _textLight)),
              ],
            ),
          ),

          pw.SizedBox(width: 30),

          // ── Nome ──────────────────────────────────────────────────────
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 40),
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: _textLight,
                        width: 0.8,
                        style: pw.BorderStyle.dashed,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Nome por extenso',
                    style: const pw.TextStyle(fontSize: 8, color: _textLight)),
              ],
            ),
          ),

          pw.SizedBox(width: 30),

          // ── Data ──────────────────────────────────────────────────────
          pw.SizedBox(
            width: 100,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 40),
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: _textLight,
                        width: 0.8,
                        style: pw.BorderStyle.dashed,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Data',
                    style: const pw.TextStyle(fontSize: 8, color: _textLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 7. RODAPÉ PROFISSIONAL
  // ════════════════════════════════════════════════════════════════════════════

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _navyDark, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Coliseu Sales | Desenvolvido pela Coliseu Sistemas (67) 3423-2227 | www.coliseusistemas.com.br',
            style: pw.TextStyle(
              fontSize: 8,
              color: _textMid,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'Gerado em ${_dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 7, color: _textLight),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPERS — building blocks reutilizáveis
  // ════════════════════════════════════════════════════════════════════════════

  /// Label de seção (e.g. "DADOS DO CLIENTE").
  pw.Widget _sectionLabel(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _accentBlue, width: 2),
        ),
      ),
      child: pw.Text(text,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: _navyDark,
            letterSpacing: 0.8,
          )),
    );
  }

  /// Linha label: valor para blocos de informação.
  pw.Widget _infoRow(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 65,
            child: pw.Text('$label:',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _textMid,
                )),
          ),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: bold ? _textDark : _textMid,
                )),
          ),
        ],
      ),
    );
  }

  /// Célula do header da tabela.
  pw.Widget _headerCell(
    String text,
    double width,
    pw.TextStyle style, {
    int flex = 0,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    final child = pw.Align(
      alignment: align,
      child: pw.Text(text, style: style),
    );
    return flex > 0
        ? pw.Expanded(flex: flex, child: child)
        : pw.SizedBox(width: width, child: child);
  }

  /// Célula de dados da tabela.
  pw.Widget _dataCell(
    String text,
    double width,
    pw.TextStyle style, {
    int flex = 0,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    final child = pw.Align(
      alignment: align,
      child: pw.Text(text, style: style, maxLines: 2, overflow: pw.TextOverflow.clip),
    );
    return flex > 0
        ? pw.Expanded(flex: flex, child: child)
        : pw.SizedBox(width: width, child: child);
  }

  /// Linha do resumo financeiro.
  pw.Widget _summaryRow(String label, String value, PdfColor valueColor) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 9, color: _textMid)),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: valueColor,
            )),
      ],
    );
  }
}
