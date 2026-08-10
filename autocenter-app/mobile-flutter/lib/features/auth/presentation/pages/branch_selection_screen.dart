import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth/auth_token_manager.dart';
import '../../../../core/di/injection.dart';
import '../../../home/presentation/pages/home_scaffold.dart';
import 'setup_page.dart';
import 'auth_gate.dart';

class BranchItem {
  final int id;
  final String name;
  final String? document;
  final int deptoId;
  final int empresaErp;
  final bool isDefault;

  const BranchItem({
    required this.id,
    required this.name,
    this.document,
    required this.deptoId,
    required this.empresaErp,
    this.isDefault = false,
  });

  factory BranchItem.fromJson(Map<String, dynamic> json) {
    return BranchItem(
      id: json['id'] as int,
      name: json['nome'] as String,
      document: json['documento'] as String?,
      deptoId: (json['deptoId'] ?? 1) as int,
      empresaErp: (json['empresaErp'] ?? 1) as int,
      isDefault: (json['isDefault'] ?? false) as bool,
    );
  }
}

class BranchSelectionScreen extends StatefulWidget {
  const BranchSelectionScreen({super.key});

  @override
  State<BranchSelectionScreen> createState() => _BranchSelectionScreenState();
}

class _BranchSelectionScreenState extends State<BranchSelectionScreen>
    with SingleTickerProviderStateMixin {
  final _tokenManager = getIt<AuthTokenManager>();
  final _apiClient = getIt<ApiClient>();

  List<BranchItem> _branches = [];
  BranchItem? _selected;
  bool _isLoading = true;
  bool _isConfirming = false;
  String? _errorMsg;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward(); // Inicia a animação imediatamente para mostrar os estados de loading/erro
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBranches();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final dio = _apiClient.instance;
      final response = await dio.get('filiais');

      if (response.statusCode == 200) {
        final list = (response.data as List<dynamic>)
            .map((e) => BranchItem.fromJson(e as Map<String, dynamic>))
            .toList();

        final defaultBranch = list.where((b) => b.isDefault).firstOrNull ?? list.firstOrNull;

        setState(() {
          _branches = list;
          _selected = defaultBranch;
          _isLoading = false;
        });
        _animController.forward();
      } else {
        throw Exception('Código de resposta HTTP: ${response.statusCode}');
      }
    } on DioException catch (e) {
      _handleOfflineFallback(e.message ?? 'Falha na conexão.');
    } catch (e) {
      _handleOfflineFallback(e.toString());
    }
  }

  Future<void> _handleOfflineFallback(String originalError) async {
    final cachedId = await _tokenManager.getBranchId();
    final cachedName = await _tokenManager.getBranchName();
    final cachedDepto = await _tokenManager.getDeptoId();
    final cachedEmpresa = await _tokenManager.getEmpresaErpId();

    if (cachedId != null && cachedName != null && cachedDepto != null) {
      setState(() {
        _selected = BranchItem(
          id: int.tryParse(cachedId) ?? 1,
          name: cachedName,
          deptoId: cachedDepto,
          empresaErp: cachedEmpresa ?? 1,
          isDefault: true,
        );
        _branches = [_selected!];
        _isLoading = false;
      });
      _animController.forward();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo offline: Usando filial salva no cache.'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      setState(() {
        _errorMsg = 'Falha ao buscar filiais: $originalError.\nPor favor, verifique sua conexão.';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleConfirm() async {
    final branch = _selected;
    if (branch == null) return;

    setState(() => _isConfirming = true);
    try {
      // Salva a filial selecionada no SecureStorage
      await _tokenManager.setBranch(
        branchId: branch.id.toString(),
        branchName: branch.name,
        deptoId: branch.deptoId,
        empresaId: branch.empresaErp,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthGate()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar filial: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF5F7FF) : const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: isLight ? const Color(0xFF64748B) : const Color(0xFF8B9AB1),
            ),
            tooltip: 'Configurações de Rede',
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const SetupPage()),
              );
              if (changed == true) {
                _loadBranches();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Icon ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C6EF2).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.storefront_rounded, size: 36, color: Color(0xFF1C6EF2)),
                ),
                const SizedBox(height: 24),
                
                Text(
                  'Bem-vindo de volta!',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isLight ? const Color(0xFF1A1A2E) : Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Selecione a empresa/filial que você irá operar agora.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isLight ? const Color(0xFF64748B) : const Color(0xFF8B9AB1),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Content ──────────────────────────────────────────────
                Expanded(child: _buildContent(isLight, theme)),

                // ── Footer Button ────────────────────────────────────────
                if (!_isLoading && _branches.isNotEmpty)
                  _buildConfirmButton(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isLight, ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1C6EF2)),
      );
    }

    if (_errorMsg != null) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFDC2626)),
              ),
              const SizedBox(height: 20),
              Text(
                'Falha na Conexão',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isLight ? const Color(0xFF1A1A2E) : Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMsg!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isLight ? const Color(0xFF64748B) : const Color(0xFF8B9AB1),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 180,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _loadBranches,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1C6EF2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('Tentar Novamente'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_branches.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma filial cadastrada no sistema.\nContate o administrador.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isLight ? const Color(0xFF64748B) : const Color(0xFF8B9AB1),
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: _branches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final branch = _branches[index];
        final isSelected = _selected?.id == branch.id;

        return _BranchTile(
          branch: branch,
          isSelected: isSelected,
          isLight: isLight,
          theme: theme,
          onTap: () => setState(() => _selected = branch),
        );
      },
    );
  }

  Widget _buildConfirmButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _selected != null && !_isConfirming ? _handleConfirm : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1C6EF2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
        ),
        child: _isConfirming
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : const Text(
                'Prosseguir para o AutoCenter',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  final BranchItem branch;
  final bool isSelected;
  final bool isLight;
  final ThemeData theme;
  final VoidCallback onTap;

  const _BranchTile({
    required this.branch,
    required this.isSelected,
    required this.isLight,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF1C6EF2).withValues(alpha: 0.05)
            : (isLight ? Colors.white : const Color(0xFF161B26)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF1C6EF2) : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF2D3748)),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF1C6EF2) : (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1F2937)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.apartment_rounded,
                    color: isSelected ? Colors.white : (isLight ? const Color(0xFF64748B) : const Color(0xFF9CA3AF)),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              branch.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isLight ? const Color(0xFF1A1A2E) : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (branch.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Padrão',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        branch.document?.isNotEmpty == true
                            ? 'CNPJ: ${branch.document}'
                            : 'Código Depto: ${branch.deptoId}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isLight ? const Color(0xFF64748B) : const Color(0xFF8B9AB1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF1C6EF2) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF4B5563)),
                      width: isSelected ? 6 : 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
