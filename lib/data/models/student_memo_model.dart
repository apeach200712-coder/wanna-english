class StudentMemo {
  final String id;
  final String studentId;
  final String content;
  final int createdAt;
  final int updatedAt;

  const StudentMemo({
    required this.id,
    required this.studentId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'content': content,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory StudentMemo.fromJson(Map<String, dynamic> json) {
    return StudentMemo(
      id: json['id'] as String,
      studentId: json['studentId'] as String,
      content: json['content'] as String,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
    );
  }
}
