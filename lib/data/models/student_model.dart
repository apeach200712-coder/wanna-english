class Student {
  static const Object _undefined = Object();

  final String id;
  final String name;
  final String classId;
  final String? className;
  final String? phone;
  final String? parentPhone;
  final int createdAt;
  final int updatedAt;

  const Student({
    required this.id,
    required this.name,
    required this.classId,
    this.className,
    this.phone,
    this.parentPhone,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'classId': classId,
      'phone': phone,
      'parentPhone': parentPhone,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Student.fromJson(
    Map<String, dynamic> json, {
    String? resolvedClassName,
  }) {
    final classId = (json['classId'] is String)
        ? json['classId'] as String
        : (json['className']?.toString() ?? '');
    return Student(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      classId: classId,
      className: resolvedClassName ?? json['className']?.toString(),
      phone: json['phone']?.toString(),
      parentPhone: json['parentPhone']?.toString(),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Student copyWith({
    String? id,
    String? name,
    String? classId,
    String? className,
    Object? phone = _undefined,
    Object? parentPhone = _undefined,
    int? createdAt,
    int? updatedAt,
  }) {
    return Student(
      id: id ?? this.id,
      name: name ?? this.name,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      phone: identical(phone, _undefined) ? this.phone : phone as String?,
      parentPhone: identical(parentPhone, _undefined)
          ? this.parentPhone
          : parentPhone as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
