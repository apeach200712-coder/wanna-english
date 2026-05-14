class Announcement {
  final String id;
  final String? classId;
  final String className;
  final String title;
  final String content;
  final DateTime createdAt;
  final int? sentCount;
  final DateTime? lastSentTime;

  const Announcement({
    required this.id,
    this.classId,
    required this.className,
    required this.title,
    required this.content,
    required this.createdAt,
    this.sentCount,
    this.lastSentTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'classId': classId,
      'className': className,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'sentCount': sentCount,
      'lastSentTime': lastSentTime?.toIso8601String(),
    };
  }

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String,
      classId: json['classId'] as String?,
      className: json['className'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sentCount: json['sentCount'] as int?,
      lastSentTime: json['lastSentTime'] != null
          ? DateTime.parse(json['lastSentTime'] as String)
          : null,
    );
  }

  Announcement copyWith({
    String? id,
    String? classId,
    String? className,
    String? title,
    String? content,
    DateTime? createdAt,
    int? sentCount,
    DateTime? lastSentTime,
  }) {
    return Announcement(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      sentCount: sentCount ?? this.sentCount,
      lastSentTime: lastSentTime ?? this.lastSentTime,
    );
  }
}

class SMSLog {
  final String id;
  final String studentId;
  final String? parentPhone;
  final String announcementId;
  final DateTime sentTime;
  final bool isSuccess;
  final String? errorMessage;
  final DateTime? expectedTime;

  const SMSLog({
    required this.id,
    required this.studentId,
    this.parentPhone,
    required this.announcementId,
    required this.sentTime,
    required this.isSuccess,
    this.errorMessage,
    this.expectedTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'parentPhone': parentPhone,
      'announcementId': announcementId,
      'sentTime': sentTime.toIso8601String(),
      'isSuccess': isSuccess,
      'errorMessage': errorMessage,
      'expectedTime': expectedTime?.toIso8601String(),
    };
  }

  factory SMSLog.fromJson(Map<String, dynamic> json) {
    return SMSLog(
      id: json['id'] as String,
      studentId: json['studentId'] as String,
      parentPhone: json['parentPhone'] as String?,
      announcementId: json['announcementId'] as String,
      sentTime: DateTime.parse(json['sentTime'] as String),
      isSuccess: json['isSuccess'] as bool,
      errorMessage: json['errorMessage'] as String?,
      expectedTime: json['expectedTime'] != null
          ? DateTime.parse(json['expectedTime'] as String)
          : null,
    );
  }
}
