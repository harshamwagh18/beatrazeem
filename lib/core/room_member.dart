String roomText(String value, {required int limit, required String label}) {
  final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty ||
      text.runes.length > limit ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
    throw FormatException('$label must be between 1 and $limit characters.');
  }
  return text;
}

class RoomMember {
  const RoomMember({required this.id, required this.name, this.isHost = false});
  final String id;
  final String name;
  final bool isHost;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'host': isHost};

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    if (id.isEmpty || id.length > 48 || json['host'] is! bool) {
      throw const FormatException('Invalid room member.');
    }
    return RoomMember(
      id: id,
      name: roomText(json['name'] as String, limit: 24, label: 'Username'),
      isHost: json['host'] as bool,
    );
  }
}
