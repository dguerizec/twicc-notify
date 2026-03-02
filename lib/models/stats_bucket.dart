/// A 5-minute time bucket for WebSocket message statistics.
///
/// Uses compact JSON keys to minimize serialized size in SharedPreferences.
class StatsBucket {
  /// Epoch timestamp in seconds, floored to the nearest 5-minute boundary.
  final int timestamp;
  int messagesSent;
  int messagesReceived;
  int bytesSent;
  int bytesReceived;

  StatsBucket({
    required this.timestamp,
    this.messagesSent = 0,
    this.messagesReceived = 0,
    this.bytesSent = 0,
    this.bytesReceived = 0,
  });

  int get totalMessages => messagesSent + messagesReceived;
  int get totalBytes => bytesSent + bytesReceived;

  Map<String, dynamic> toJson() => {
        't': timestamp,
        'ms': messagesSent,
        'mr': messagesReceived,
        'bs': bytesSent,
        'br': bytesReceived,
      };

  factory StatsBucket.fromJson(Map<String, dynamic> json) => StatsBucket(
        timestamp: json['t'] as int,
        messagesSent: json['ms'] as int? ?? 0,
        messagesReceived: json['mr'] as int? ?? 0,
        bytesSent: json['bs'] as int? ?? 0,
        bytesReceived: json['br'] as int? ?? 0,
      );
}

/// Aggregated statistics over a time window.
class StatsAggregate {
  final int messagesSent;
  final int messagesReceived;
  final int bytesSent;
  final int bytesReceived;

  const StatsAggregate({
    this.messagesSent = 0,
    this.messagesReceived = 0,
    this.bytesSent = 0,
    this.bytesReceived = 0,
  });

  int get totalMessages => messagesSent + messagesReceived;
  int get totalBytes => bytesSent + bytesReceived;
}
