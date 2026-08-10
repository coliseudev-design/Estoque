class Vehicle {
  final int? idCliente;
  final int? idVeiculo;
  final String? brand; // MARCA
  final String? model; // MODELO
  final String? plate; // PLACA
  final int? anoFabrica;
  final int? anoModelo;
  final String? cor;
  final String? obs;
  final String? numero;
  final String? numeroChassi;
  final int? idSeguradora;
  final int? status;
  final String? numero1;
  final String? numero2;
  final String? combustivel;
  final String? customerName; // Opcional, cacheado localmente

  Vehicle({
    this.idCliente,
    this.idVeiculo,
    this.brand,
    this.model,
    this.plate,
    this.anoFabrica,
    this.anoModelo,
    this.cor,
    this.obs,
    this.numero,
    this.numeroChassi,
    this.idSeguradora,
    this.status,
    this.numero1,
    this.numero2,
    this.combustivel,
    this.customerName,
  });

  Vehicle copyWith({
    int? idCliente,
    String? customerName,
  }) {
    return Vehicle(
      idCliente: idCliente ?? this.idCliente,
      idVeiculo: idVeiculo,
      brand: brand,
      model: model,
      plate: plate,
      anoFabrica: anoFabrica,
      anoModelo: anoModelo,
      cor: cor,
      obs: obs,
      numero: numero,
      numeroChassi: numeroChassi,
      idSeguradora: idSeguradora,
      status: status,
      numero1: numero1,
      numero2: numero2,
      combustivel: combustivel,
      customerName: customerName ?? this.customerName,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_cliente': idCliente,
      'id_veiculo': idVeiculo,
      'brand': brand,
      'model': model,
      'plate': plate,
      'ano_fabrica': anoFabrica,
      'ano_modelo': anoModelo,
      'cor': cor,
      'obs': obs,
      'numero': numero,
      'numero_chassi': numeroChassi,
      'id_seguradora': idSeguradora,
      'status': status,
      'numero_1': numero1,
      'numero_2': numero2,
      'combustivel': combustivel,
    };
  }

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      idCliente: map['id_cliente'],
      idVeiculo: map['id_veiculo'],
      brand: map['brand'],
      model: map['model'],
      plate: map['plate'],
      anoFabrica: map['ano_fabrica'],
      anoModelo: map['ano_modelo'],
      cor: map['cor'],
      obs: map['obs'],
      numero: map['numero'],
      numeroChassi: map['numero_chassi'],
      idSeguradora: map['id_seguradora'],
      status: map['status'],
      numero1: map['numero_1'],
      numero2: map['numero_2'],
      combustivel: map['combustivel'],
      customerName: map['customerName'],
    );
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    // Handling ApiBrasil response wrapping
    Map<String, dynamic> data = json;
    if (json.containsKey('data') && json['data'] is Map && json['data']['resultados'] is List) {
      final list = json['data']['resultados'] as List;
      if (list.isNotEmpty) {
        data = list.first as Map<String, dynamic>;
      }
    }

    return Vehicle(
      idCliente: data['ID_CLIENTE'] ?? data['id_cliente'],
      idVeiculo: data['ID_VEICULO'] ?? data['id_veiculo'],
      brand: data['MARCA'] ?? data['marca'],
      model: data['MODELO'] ?? data['modelo'],
      plate: data['PLACA'] ?? data['placa'],
      anoFabrica: data['ANO_FABRICA'] ?? data['ano_fabrica'] ?? data['anoFabricacao'],
      anoModelo: int.tryParse(data['ANO_MODELO']?.toString() ?? data['ano_modelo']?.toString() ?? data['anoModelo']?.toString() ?? ''),
      cor: data['COR'] ?? data['cor'],
      obs: data['OBS'] ?? data['obs'],
      numero: data['NUMERO'] ?? data['numero'],
      numeroChassi: data['NUMERO_CHASSI'] ?? data['numero_chassi'] ?? data['chassi'],
      idSeguradora: data['ID_SEGURADORA'] ?? data['id_seguradora'],
      status: data['STATUS'] ?? data['status'],
      numero1: data['NUMERO1'] ?? data['numero1'],
      numero2: data['NUMERO2'] ?? data['numero2'],
      combustivel: data['COMBUSTIVEL'] ?? data['combustivel'],
    );
  }
}
