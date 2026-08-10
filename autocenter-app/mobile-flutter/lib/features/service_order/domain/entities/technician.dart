class Technician {
  final int id;
  final String name;
  final bool active;

  Technician({
    required this.id,
    required this.name,
    this.active = true,
  });
}
