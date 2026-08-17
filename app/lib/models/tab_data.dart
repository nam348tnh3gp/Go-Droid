class TabData {
  final String id;
  String name;
  String code;
  bool isDirty;

  TabData({
    required this.id,
    required this.name,
    this.code = '',
    this.isDirty = false,
  });

  TabData copyWith({
    String? name,
    String? code,
    bool? isDirty,
  }) {
    return TabData(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}