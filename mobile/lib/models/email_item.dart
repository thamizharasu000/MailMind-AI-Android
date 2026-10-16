class EmailItem {
  const EmailItem({
    required this.id,
    required this.sender,
    required this.subject,
    required this.preview,
    required this.body,
    required this.date,
    this.isImportant = false,
    this.isDemo = false,
  });

  final String id;
  final String sender;
  final String subject;
  final String preview;
  final String body;
  final String date;
  final bool isImportant;
  final bool isDemo;

  factory EmailItem.fromJson(Map<String, dynamic> json) {
    return EmailItem(
      id: (json['id'] ?? '').toString(),
      sender: (json['from'] ?? json['sender'] ?? 'Unknown sender').toString(),
      subject: (json['subject'] ?? '(No subject)').toString(),
      preview: (json['snippet'] ?? json['preview'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      isImportant: (json['isImportant'] ?? false) == true,
      isDemo: (json['isDemo'] ?? false) == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': sender,
        'subject': subject,
        'snippet': preview,
        'body': body,
        'date': date,
      };
}
