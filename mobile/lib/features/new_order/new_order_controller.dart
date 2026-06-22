/// NewOrderController — Lógica de carregamento e estado da tela de novo pedido.
///
/// Extrai a responsabilidade de dados de [_NewOrderScreenState],
/// seguindo a Regra 06 (Clean Architecture).
///
/// Responsabilidades:
/// - Carregar opções de pagamento, condições, naturezas e tabelas de preço
/// - Manter as seleções ativas (espécie, condição, natureza, tabela)
/// - Salvar pedidos (draft e confirmado)
/// - Notificar a UI via ChangeNotifier
///
/// A UI (NewOrderScreen) apenas observa e chama os métodos públicos.
library;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:coliseu_sales/core/config/app_config_service.dart';

import '../../core/cart/cart_notifier.dart';
import '../../core/database/database_helper.dart';
import '../../core/repositories/models/payment_species.dart';
import '../../core/repositories/models/payment_condition.dart';
import '../../core/repositories/models/natureza_operacao.dart';
import '../../core/repositories/payment_species_repository.dart';
import '../../core/repositories/payment_condition_repository.dart';
import '../../core/repositories/natureza_operacao_repository.dart';
import '../../core/services/company_settings_service.dart';
import '../../core/session/session_service.dart';
import '../../core/sync/sync_service.dart';
import '../../core/network/auto_sync_service.dart';

/// Estado do controller para a tela de novo pedido.
///
/// Encapsula todas as seleções e flags de carregamento.
class NewOrderController extends ChangeNotifier {
  final CartNotifier cart;
  final SessionService _session;

  AutoSyncService? _autoSync;

  NewOrderController({
    required this.cart,
    SessionService? session,
  }) : _session = session ?? GetIt.I<SessionService>() {
    if (GetIt.I.isRegistered<AutoSyncService>()) {
      _autoSync = GetIt.I<AutoSyncService>();
      _autoSync?.stateNotifier.addListener(_onSyncStateChanged);
    }
  }

  @override
  void dispose() {
    _autoSync?.stateNotifier.removeListener(_onSyncStateChanged);
    super.dispose();
  }

  void _onSyncStateChanged() {
    final state = _autoSync?.stateNotifier.value;
    if (state == AutoSyncState.success) {
      loadOptions();
    }
  }

  // ── Estado público ──────────────────────────────────────────────────────

  /// Opções disponíveis de espécie de pagamento.
  List<PaymentSpecies> paymentOptions = [];

  /// Espécie de pagamento selecionada.
  PaymentSpecies? selectedPayment;

  /// Todas as condições de pagamento (não filtradas).
  List<PaymentCondition> conditionOptions = [];

  /// Condição de pagamento selecionada.
  PaymentCondition? selectedCondition;

  /// Naturezas de operação disponíveis (deduplicadas).
  List<NaturezaOperacao> naturezas = [];

  /// Natureza de operação selecionada.
  NaturezaOperacao? selectedNatureza;

  /// Tabelas de preço disponíveis (somente no modo 'prompt').
  List<Map<String, dynamic>> priceTables = [];

  /// Tabela de preço selecionada manualmente (modo prompt).
  Map<String, dynamic>? selectedPriceTable;

  /// True enquanto as opções estão sendo carregadas do banco.
  bool isLoading = true;

  /// True enquanto o pedido está sendo salvo.
  bool isSaving = false;

  /// Mensagem de erro a ser exibida pela UI, ou null se não houver erro.
  String? errorMessage;

  // ── Computed ────────────────────────────────────────────────────────────

  /// Condições filtradas pela espécie selecionada, deduplicadas por descrição.
  List<PaymentCondition> get filteredConditions {
    if (selectedPayment == null) return conditionOptions;
    final bySpecies = conditionOptions
        .where((c) => c.specieId == selectedPayment!.id)
        .toList();
    final seen = <String>{};
    return bySpecies.where((c) {
      final key = c.descricao.toUpperCase().trim();
      return seen.add(key);
    }).toList();
  }

  // ── Carregamento inicial ─────────────────────────────────────────────────

  /// Carrega todas as opções necessárias para o formulário.
  ///
  /// Deve ser chamado no [initState] da tela.
  Future<void> loadOptions() async {
    try {
      final paymentRepo = GetIt.I<PaymentSpeciesRepository>();
      final conditionRepo = GetIt.I<PaymentConditionRepository>();
      final naturezaRepo = GetIt.I<NaturezaOperacaoRepository>();

      List<PaymentSpecies> species = [];
      try {
        species = await paymentRepo.getAll();
      } catch (e, st) {
        debugPrint('[NewOrderController] Error loading species: $e\n$st');
      }

      List<PaymentCondition> conditions = [];
      try {
        conditions = await conditionRepo.getAll();
      } catch (e, st) {
        debugPrint('[NewOrderController] Error loading conditions: $e\n$st');
      }

      List<NaturezaOperacao> rawNaturezas = [];
      try {
        rawNaturezas = await naturezaRepo.getAll();
      } catch (e, st) {
        debugPrint('[NewOrderController] Error loading naturezas: $e\n$st');
      }

      // Carrega tabelas de preço se modo = prompt
      final loadedTables = await _loadPriceTables();

      // Deduplica naturezas: mantém somente as que têm código fiscal
      final naturezaMap = <String, NaturezaOperacao>{};
      for (final n in rawNaturezas) {
        final key = n.descricao.toUpperCase().trim();
        final existing = naturezaMap[key];
        if (existing == null) {
          naturezaMap[key] = n;
        } else if ((existing.codigoFiscal == null ||
                existing.codigoFiscal!.isEmpty) &&
            (n.codigoFiscal != null && n.codigoFiscal!.isNotEmpty)) {
          naturezaMap[key] = n;
        }
      }
      final dedupedNaturezas = naturezaMap.values.toList();

      // Restaura seleções salvas no cart
      PaymentSpecies? restoredPayment;
      if (cart.paymentSpeciesId != null) {
        restoredPayment = species.cast<PaymentSpecies?>().firstWhere(
              (s) => s?.id == cart.paymentSpeciesId,
              orElse: () => null,
            );
      }

      PaymentCondition? restoredCondition;
      final cleanConditions = conditions.where((c) => c.id.isNotEmpty).toList();
      if (cart.paymentConditionId != null) {
        restoredCondition =
            cleanConditions.cast<PaymentCondition?>().firstWhere(
                  (c) => c?.id == cart.paymentConditionId,
                  orElse: () => null,
                );
      }

      NaturezaOperacao? restoredNatureza;
      if (cart.naturezaId != null) {
        restoredNatureza =
            dedupedNaturezas.cast<NaturezaOperacao?>().firstWhere(
                  (n) => n?.id == cart.naturezaId,
                  orElse: () => null,
                );
      }

      paymentOptions = species;
      conditionOptions = cleanConditions;
      naturezas = dedupedNaturezas;
      priceTables = loadedTables;

      selectedPayment = restoredPayment;
      if (selectedPayment != null && !paymentOptions.any((s) => s.id == selectedPayment!.id)) {
        selectedPayment = null;
      }

      selectedCondition = restoredCondition;
      if (selectedCondition != null) {
        // Validação estrita: deve estar nas condições filtradas finais (evita AssertionError no Dropdown)
        final isCompatible = filteredConditions.any((c) => c.id == selectedCondition!.id);
        if (!isCompatible) {
          selectedCondition = null;
        }
      }

      selectedNatureza = restoredNatureza;
      if (selectedNatureza != null && !naturezas.any((n) => n.id == selectedNatureza!.id)) {
        selectedNatureza = null;
      }
    } catch (e, st) {
      debugPrint('[NewOrderController] Fatal erro ao carregar opções: $e\n$st');
      errorMessage = 'Falha ao carregar opções do pedido';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Carrega tabelas de preço se o modo da empresa for 'prompt'.
  Future<List<Map<String, dynamic>>> _loadPriceTables() async {
    final settings = GetIt.I.isRegistered<CompanySettingsService>()
        ? GetIt.I<CompanySettingsService>()
        : null;

    if (settings?.promptPriceTable != true) return [];

    try {
      final db = GetIt.I<DatabaseHelper>();
      final rawDb = await db.database;
      return await rawDb.query('price_tables', orderBy: 'name ASC');
    } catch (e) {
      debugPrint('[NewOrderController] Erro ao carregar tabelas de preço: $e');
      return [];
    }
  }

  // ── Ações de seleção ─────────────────────────────────────────────────────

  /// Atualiza a espécie de pagamento selecionada.
  ///
  /// Limpa a condição se ela não for compatível com a nova espécie.
  void selectPayment(PaymentSpecies? species) {
    selectedPayment = species;

    if (selectedCondition != null) {
      // Must exist in the final filtered list, which accounts for both species filtering and deduplication
      final isCompatible = filteredConditions.any((c) => c.id == selectedCondition!.id);
      if (!isCompatible) {
        selectedCondition = null;
        cart.setPaymentCondition(null);
      }
    }

    if (species != null) {
      cart.setPaymentSpecies(
        id: species.id,
        name: species.name,
        days: species.days,
      );
    }
    notifyListeners();
  }

  /// Atualiza a condição de pagamento selecionada.
  void selectCondition(PaymentCondition? condition) {
    selectedCondition = condition;
    if (condition != null) cart.setPaymentCondition(condition);
    notifyListeners();
  }

  /// Atualiza a natureza de operação selecionada.
  void selectNatureza(NaturezaOperacao? natureza) {
    selectedNatureza = natureza;
    cart.setNatureza(
      id: natureza?.id,
      descricao: natureza?.descricao,
    );
    notifyListeners();
  }

  /// Atualiza a tabela de preço selecionada manualmente (modo prompt).
  void selectPriceTable(Map<String, dynamic>? table) {
    selectedPriceTable = table;
    cart.setPriceTableManual(
      table?['id']?.toString(),
      table?['name']?.toString(),
    );
    notifyListeners();
  }

  // ── Salvar pedido ────────────────────────────────────────────────────────

  /// Valida e salva o pedido ou orçamento.
  ///
  /// Retorna null em caso de sucesso, ou uma mensagem de erro de validação.
  ///
  /// [prazo] e [obs] são os textos dos campos adicionais do formulário.
  /// [isDraft] = true → salva como orçamento sem sincronizar.
  Future<String?> saveOrder({
    required String prazo,
    required String obs,
    bool isDraft = false,
  }) async {
    // ── Validações ──────────────────────────────────────────────────────────
    if (cart.customerName.isEmpty) {
      return 'Selecione um cliente';
    }
    if (!isDraft) {
      if (selectedPayment == null) {
        return 'Selecione a espécie de pagamento (Ex: Dinheiro/Boleto)';
      }
      if (selectedCondition == null) {
        return 'Selecione a condição de pagamento (Parcelamento)';
      }
      if (selectedNatureza == null) {
        return 'Selecione a Natureza de Operação';
      }
    }
    if (!cart.hasItems) {
      return 'Adicione pelo menos um item';
    }

    isSaving = true;
    notifyListeners();

    try {
      final fullNotes = [
        if (prazo.isNotEmpty) 'Prazo: $prazo',
        if (obs.isNotEmpty) obs,
      ].join('\n');
      cart.setNotes(fullNotes.isEmpty ? null : fullNotes);

      final session = _session.activeSession;
      if (session == null) return 'Sessão expirada. Faça login novamente.';

      if (isDraft) {
        await cart.saveAsQuote();
      } else {
        final config = GetIt.I<AppConfigService>();
        final companyId = await config.getBranchId() ?? session.companyId;
        await cart.confirmOrder(
          sellerId: session.sellerId,
          companyId: companyId,
        );
        try {
          await GetIt.I<SyncService>().syncPendingOrders();
        } catch (e) {
          debugPrint(
              '[NewOrderController] Sync imediato falhou (será reenviado): $e');
        }
      }

      return null; // sucesso
    } catch (e) {
      return 'Erro ao salvar: $e';
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }
}
