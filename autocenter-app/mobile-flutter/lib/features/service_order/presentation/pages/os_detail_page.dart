import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/sync_queue_service.dart';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/service_order.dart';
import '../../domain/repositories/service_order_repository.dart';
import '../../data/services/order_pdf_service.dart';
import '../widgets/signature_canvas.dart';

class OsDetailPage extends StatefulWidget {
  final String osId;

  const OsDetailPage({Key? key, required this.osId}) : super(key: key);

  @override
  State<OsDetailPage> createState() => _OsDetailPageState();
}

class _OsDetailPageState extends State<OsDetailPage> {
  final _repository = getIt<ServiceOrderRepository>();

  ServiceOrder? _os;
  bool _isLoading = false;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    final result = await _repository.getLocalServiceOrderById(widget.osId);
    setState(() {
      _os = result;
      _isLoading = false;
    });
  }

  void _showShareOptions(BuildContext context) {
    if (_os == null) return;
    
    final pdfService = OrderPdfService();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('Compartilhar Ordem de Serviço', style: AppTypography.bodyBold),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.message, color: Colors.green),
                title: const Text('Texto Formatado (WhatsApp)'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  final text = pdfService.generateWhatsAppText(_os!);
                  Share.share(text);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('PDF A4 Completo'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gerando PDF A4...')),
                  );
                  final path = await pdfService.generateA4Pdf(_os!);
                  await Share.shareXFiles([XFile(path)], text: 'Ordem de Serviço #${_os!.id.substring(0, 8)}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.print, color: Colors.blue),
                title: const Text('Recibo 58mm (Bobina)'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gerando Recibo 58mm...')),
                  );
                  final path = await pdfService.generate58mmReceipt(_os!);
                  await Share.shareXFiles([XFile(path)], text: 'Recibo OS #${_os!.id.substring(0, 8)}');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _collectSignature(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Assinatura do Cliente'),
          content: SignatureCanvas(
            onSave: (img) async {
              Navigator.of(dialogCtx).pop();
              if (img == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Assinatura em branco.')),
                );
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Processando assinatura...')),
              );

              try {
                final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
                final buffer = pngBytes!.buffer.asUint8List();
                
                final docDir = await getApplicationDocumentsDirectory();
                final signaturePath = '${docDir.path}/signature_${_os!.id}.png';
                final signatureFile = File(signaturePath);
                await signatureFile.writeAsBytes(buffer);

                await _repository.addCustomerSignature(_os!.id, signaturePath);
                await _loadDetails();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Assinatura registrada com sucesso!'), backgroundColor: AppColors.success),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro ao salvar assinatura: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
        );
      },
    );
  }

  Future<void> _transitionStatus(String newStatus) async {
    if (_os == null) return;
    setState(() => _isTransitioning = true);

    try {
      await _repository.updateStatus(_os!.id, newStatus);
      await SyncQueueService.instance.processQueue(); // Tenta sincronizar imediatamente

      await _loadDetails(); // Recarrega estado

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status alterado com sucesso para: ${_getStatusLabel(newStatus)}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar status: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTransitioning = false);
      }
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'ABERTA':
        return 'Aberta';
      case 'EM_EXECUCAO':
        return 'Em Execução';
      case 'AGUARDANDO_PECAS':
        return 'Aguardando Peças';
      case 'FINALIZADA':
        return 'Finalizada';
      case 'ENTREGUE':
        return 'Entregue';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ABERTA':
        return Colors.blue;
      case 'EM_EXECUCAO':
        return Colors.orange;
      case 'AGUARDANDO_PECAS':
        return Colors.purple;
      case 'FINALIZADA':
        return Colors.green;
      case 'ENTREGUE':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }

  Widget _buildPhotoWidget(String path) {
    if (path.startsWith('/') && !path.startsWith('/data/')) {
      // Remote path URL on middleware
      final fullUrl = 'https://autocenter.coliseusistemas.com.br$path';
      return Image.network(
        fullUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.red)),
      );
    } else {
      // Local SQLite file path
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
        );
      }
      return const Center(child: Icon(Icons.broken_image, color: Colors.grey));
    }
  }

  Widget _buildTransitionButtons() {
    if (_os == null) return const SizedBox.shrink();
    final status = _os!.status.toUpperCase();

    final buttons = <Widget>[];

    if (status == 'ABERTA') {
      buttons.add(_buildTransitionBtn('INICIAR EXECUÇÃO', 'EM_EXECUCAO'));
    } else if (status == 'EM_EXECUCAO') {
      buttons.add(_buildTransitionBtn('AGUARDAR PEÇAS', 'AGUARDANDO_PECAS'));
      buttons.add(const SizedBox(width: AppSpacing.md));
      buttons.add(_buildTransitionBtn('FINALIZAR SERVIÇO', 'FINALIZADA'));
    } else if (status == 'AGUARDANDO_PECAS') {
      buttons.add(_buildTransitionBtn('RETOMAR EXECUÇÃO', 'EM_EXECUCAO'));
      buttons.add(const SizedBox(width: AppSpacing.md));
      buttons.add(_buildTransitionBtn('FINALIZAR SERVIÇO', 'FINALIZADA'));
    } else if (status == 'FINALIZADA') {
      buttons.add(_buildTransitionBtn('REGISTRAR ENTREGA', 'ENTREGUE'));
    }

    if (buttons.isEmpty) {
      return const Center(child: Text('Nenhuma transição de status pendente (OS Entregue).', style: TextStyle(color: Colors.grey)));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: buttons,
    );
  }

  Widget _buildTransitionBtn(String label, String targetStatus) {
    return Expanded(
      child: ElevatedButton(
        onPressed: _isTransitioning ? null : () => _transitionStatus(targetStatus),
        style: ElevatedButton.styleFrom(
          backgroundColor: _getStatusColor(targetStatus),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _os == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_os == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalhes da OS')),
        body: const Center(child: Text('Não foi possível carregar os dados desta Ordem de Serviço.')),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Se a página detalhe fechar, passamos 'true' para o quadro atualizar se necessário
        if (didPop) return;
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Text('OS #${_os!.id.length > 8 ? _os!.id.substring(0, 8) : _os!.id}'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(true), // Indica modificação para recarga
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _showShareOptions(context),
              tooltip: 'Compartilhar OS',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    // Header Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('STATUS ATUAL', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _getStatusColor(_os!.status).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getStatusLabel(_os!.status),
                                style: AppTypography.bodyBold.copyWith(color: _getStatusColor(_os!.status)),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('VALOR TOTAL', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              'R\$ ${_os!.totalAmount.toStringAsFixed(2)}',
                              style: AppTypography.headingMedium.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),

                    // Vehicle Section
                    Text('Veículo', style: AppTypography.headingMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      elevation: 1,
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.directions_car)),
                        title: Text('Placa: ${_os!.plate}', style: AppTypography.bodyBold),
                        subtitle: Text('Modelo/Marca cached localmente.'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Customer Section
                    Text('Cliente', style: AppTypography.headingMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      elevation: 1,
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(_os!.customerName ?? 'Sem Cliente Vinculado', style: AppTypography.bodyBold),
                        subtitle: Text(_os!.customerPhone ?? 'Sem Telefone'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Observation
                    if (_os!.observation != null && _os!.observation!.isNotEmpty) ...[
                      Text('Sintomas / Reclamações', style: AppTypography.headingMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(_os!.observation!, style: const TextStyle(fontSize: 14)),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Checklist
                    if (_os!.checklist.isNotEmpty) ...[
                      Text('Checklist de Entrada', style: AppTypography.headingMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Card(
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: _os!.checklist.map((c) {
                              final isOk = c.status == 'OK';
                              final isWarn = c.status == 'WARN';
                              return ListTile(
                                leading: Icon(
                                  isOk
                                      ? Icons.check_circle_outline
                                      : isWarn
                                          ? Icons.warning_amber
                                          : Icons.error_outline,
                                  color: isOk
                                      ? AppColors.success
                                      : isWarn
                                          ? Colors.orange
                                          : Colors.red,
                                ),
                                title: Text(c.itemName, style: AppTypography.bodyBold),
                                subtitle: c.observation != null && c.observation!.isNotEmpty
                                    ? Text(c.observation!)
                                    : null,
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (isOk
                                            ? AppColors.success
                                            : isWarn
                                                ? Colors.orange
                                                : Colors.red)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    c.status == 'OK'
                                        ? 'OK'
                                        : c.status == 'WARN'
                                            ? 'ATENÇÃO'
                                            : 'DEFEITO',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: isOk
                                          ? AppColors.success
                                          : isWarn
                                              ? Colors.orange
                                              : Colors.red,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Pieces & Services
                    if (_os!.items.isNotEmpty) ...[
                      Text('Itens (Peças & Serviços)', style: AppTypography.headingMedium),
                      const SizedBox(height: AppSpacing.sm),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _os!.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _os!.items[index];
                          return Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.productDescription, style: AppTypography.bodyBold),
                                        Text('Código: ${item.productCode} • Qtd: ${item.quantity.toStringAsFixed(0)}'),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'R\$ ${item.totalPrice.toStringAsFixed(2)}',
                                    style: AppTypography.bodyBold.copyWith(color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Photos
                    if (_os!.photos.isNotEmpty) ...[
                      Text('Fotos Associadas', style: AppTypography.headingMedium),
                      const SizedBox(height: AppSpacing.sm),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpacing.sm,
                          mainAxisSpacing: AppSpacing.sm,
                          childAspectRatio: 1.3,
                        ),
                        itemCount: _os!.photos.length,
                        itemBuilder: (context, index) {
                          final photo = _os!.photos[index];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _buildPhotoWidget(photo.photoUrl),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    _buildSignatureSection(),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Transition Actions
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _buildTransitionButtons(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignatureSection() {
    final sigs = _os!.photos.where((p) => p.photoType == 'SIGNATURE');
    final signaturePhoto = sigs.isNotEmpty ? sigs.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Assinatura do Cliente', style: AppTypography.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        if (signaturePhoto != null)
          Center(
            child: Container(
              width: 300,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: _buildPhotoWidget(signaturePhoto.photoUrl),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: () => _collectSignature(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.gesture),
            label: const Text('COLETAR ASSINATURA DO CLIENTE'),
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
