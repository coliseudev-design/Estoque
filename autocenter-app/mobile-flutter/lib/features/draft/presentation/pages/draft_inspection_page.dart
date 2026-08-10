import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/network/sync_service.dart';
import '../../../vehicle/domain/entities/vehicle.dart';
import '../../domain/entities/draft.dart';
import '../../data/datasources/draft_local_datasource.dart';
import '../../../camera/presentation/pages/camera_capture_page.dart';
import '../../../camera/presentation/providers/camera_session_provider.dart';
import '../../../../features/draft/presentation/pages/draft_cart_page.dart';

class DraftInspectionPage extends StatefulWidget {
  final Vehicle vehicle;

  const DraftInspectionPage({Key? key, required this.vehicle}) : super(key: key);

  @override
  State<DraftInspectionPage> createState() => _DraftInspectionPageState();
}

class _DraftInspectionPageState extends State<DraftInspectionPage> {
  bool _isSaving = false;

  Future<void> _openCameraSequence() async {
    final cameras = await availableCameras();
    if (!mounted) return;
    
    context.read<CameraSessionProvider>().resetSession();
    
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraCapturePage(vehicle: widget.vehicle),
      ),
    );
  }

  Future<void> _showCancelDialog() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Vistoria?'),
        content: const Text(
          'Todo o progresso de fotos será apagado. Uma notificação será enviada ao ERP indicando que o atendimento do pátio foi cancelado. Deseja prosseguir?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Cancelar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _abortDraft();
    }
  }

  Future<void> _abortDraft() async {
    setState(() => _isSaving = true);

    try {
      final dbHelper = DatabaseHelper.instance;
      final dataSource = DraftLocalDataSource(dbHelper: dbHelper);
      
      final draft = Draft(
        vehiclePlate: widget.vehicle.plate ?? 'SEM-PLACA',
        customerName: widget.vehicle.customerName ?? 'Balcão',
        status: 'CANCELADO',
        createdAt: DateTime.now().toIso8601String(),
      );

      // Insere draft abortado sem fotos e sem itens para gerar log de cancelamento no ERP
      await dataSource.insertDraft(draft, [], []);

      if (mounted) {
        context.read<CameraSessionProvider>().resetSession();
      }

      // Despacha o Aborto via Nuvem Background
      SyncService.registerOfflineSync();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Atendimento Encerrado. Auditando cancelamento...'), 
          backgroundColor: Colors.redAccent,
        ),
      );
      
      Navigator.of(context).popUntil((route) => route.isFirst);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha crítica ao gravar SQL Local: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _proceedToCart(List<String> photosList) {
    if (photosList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, tire pelo menos 1 foto para montar o rascunho.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DraftCartPage(
          vehicle: widget.vehicle,
          photosList: photosList,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = context.watch<CameraSessionProvider>();
    final List<String> currentPhotos = activeSession.photos;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F3A70),
        title: Text('Draft Vistoria: ${widget.vehicle.plate ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.white),
            tooltip: 'Cancelar Atendimento',
            onPressed: _showCancelDialog,
          )
        ],
      ),
      body: _isSaving 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFF26822)))
        : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                ]
              ),
              child: Column(
                children: [
                  const Icon(Icons.camera_enhance_rounded, size: 64, color: Color(0xFFF26822)),
                  const SizedBox(height: 16),
                  const Text(
                    'Iniciar Workflow do Pátio',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F3A70)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ao abrir a Engine de Câmera abaixo, fotografe o carro guiando-se pelas posições sugeridas. O algoritmo suporta no máximo 10 fotos compactadas para não saturar nossa rede.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _openCameraSequence,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F3A70),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('INICIAR CÂMERA (CONTÍNUA)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Pré-visualização do Laudo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${currentPhotos.length}/${activeSession.maxPhotos}',
                  style: TextStyle(
                    color: currentPhotos.length == activeSession.maxPhotos ? Colors.red : Colors.green.shade700,
                    fontWeight: FontWeight.bold
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: currentPhotos.isEmpty 
                ? const Center(
                    child: Text('Aguardando módulo de câmera rodar...', style: TextStyle(color: Colors.grey))
                  )
                : GridView.builder(
                    itemCount: currentPhotos.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                       crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10
                    ),
                    itemBuilder: (context, index) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(currentPhotos[index]), fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: 4, top: 4,
                            child: GestureDetector(
                              onTap: () => activeSession.removePhoto(index),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0, bottom: 0, right: 0,
                            child: Container(
                              color: Colors.black54,
                              child: Text(
                                index == 0 ? 'FRENTE' : index == 1 ? 'ESQUERDA' : index == 2 ? 'TRASEIRA' : 'DETALHES',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 8),
                              ),
                            )
                          ),
                        ],
                      );
                    },
                  )
            ),
            
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: currentPhotos.isEmpty ? null : () => _proceedToCart(currentPhotos),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                backgroundColor: currentPhotos.isEmpty ? Colors.grey.shade400 : const Color(0xFFF26822),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.shopping_cart_checkout_rounded),
              label: const Text('AVANÇAR PARA O CARRINHO (ORÇAMENTO)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _showCancelDialog,
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                minimumSize: const Size.fromHeight(50)
              ),
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Encerrar e Marcar Venda como Perdida'),
            ),
          ],
        ),
      ),
    );
  }
}
