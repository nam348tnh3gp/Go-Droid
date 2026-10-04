class TabData {
  final String id;
  String name;
  String code;
  bool isDirty;

  /// Nội dung file go.mod (tuỳ chọn). `null` = chế độ single-file,
  /// backend sẽ tự tạo go.mod skeleton nếu cần.
  String? goMod;

  TabData({
    required this.id,
    required this.name,
    this.code = '',
    this.isDirty = false,
    this.goMod,
  });

  TabData copyWith({
    String? name,
    String? code,
    bool? isDirty,
    String? goMod,
    bool clearGoMod = false,
  }) {
    return TabData(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      isDirty: isDirty ?? this.isDirty,
      goMod: clearGoMod ? null : (goMod ?? this.goMod),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'isDirty': isDirty,
        if (goMod != null) 'goMod': goMod,
      };

  factory TabData.fromJson(Map<String, dynamic> json) => TabData(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String? ?? '',
        isDirty: json['isDirty'] as bool? ?? false,
        goMod: json['goMod'] as String?,
      );
}