import '../../domain/entities/technician.dart';

class TechnicianModel extends Technician {
  TechnicianModel({
    required super.id,
    required super.name,
    super.active,
  });

  factory TechnicianModel.fromJson(Map<String, dynamic> json) {
    return TechnicianModel(
      id: json['id'] as int? ?? json['erp_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      active: json['active'] == 1 || json['active'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'active': active ? 1 : 0,
    };
  }

  factory TechnicianModel.fromSqlMap(Map<String, dynamic> map) {
    return TechnicianModel(
      id: map['id'] as int,
      name: map['name'] as String,
      active: map['active'] == 1 || map['active'] == true,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'id': id,
      'name': name,
      'active': active ? 1 : 0,
    };
  }
}
