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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'isDirty': isDirty,
      };

  factory TabData.fromJson(Map<String, dynamic> json) => TabData(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String? ?? '',
        isDirty: json['isDirty'] as bool? ?? false,
      );
}