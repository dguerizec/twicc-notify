/// Model representing a TwiCC process state notification.
///
/// Maps directly to the `process_state` WebSocket message from TwiCC.
class ProcessStateInfo {
  final String sessionId;
  final String projectId;
  final String state;
  final double startedAt;
  final double stateChangedAt;
  final String? sessionTitle;
  final String? projectName;
  final String? error;
  final PendingRequest? pendingRequest;

  const ProcessStateInfo({
    required this.sessionId,
    required this.projectId,
    required this.state,
    required this.startedAt,
    required this.stateChangedAt,
    this.sessionTitle,
    this.projectName,
    this.error,
    this.pendingRequest,
  });

  factory ProcessStateInfo.fromJson(Map<String, dynamic> json) {
    return ProcessStateInfo(
      sessionId: json['session_id'] as String,
      projectId: json['project_id'] as String,
      state: json['state'] as String,
      startedAt: (json['started_at'] as num).toDouble(),
      stateChangedAt: (json['state_changed_at'] as num).toDouble(),
      sessionTitle: json['session_title'] as String?,
      projectName: json['project_name'] as String?,
      error: json['error'] as String?,
      pendingRequest: json['pending_request'] != null
          ? PendingRequest.fromJson(json['pending_request'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Whether this process is waiting for user input (full turn ended).
  bool get isUserTurn => state == 'user_turn';

  /// Whether this process is actively running (Claude is working).
  bool get isAssistantTurn => state == 'assistant_turn';

  /// Whether this process has ended.
  bool get isDead => state == 'dead';

  /// Whether this process needs user attention.
  ///
  /// True when:
  /// - The process is in `user_turn` (Claude finished, waiting for next message)
  /// - The process has a pending request (tool approval, user question, etc.)
  ///   during `assistant_turn` — common in CLI sessions where AskUserQuestion
  ///   and permission prompts don't transition to `user_turn`.
  bool get needsAttention => isUserTurn || pendingRequest != null;

  /// Build the deep-link URL to open this session in TwiCC.
  ///
  /// Uses the route format `/project/<projectId>/session/<sessionId>`.
  String deepLinkUrl(String baseUrl) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base/project/$projectId/session/$sessionId';
  }
}

/// Pending permission or input request from Claude.
class PendingRequest {
  final String requestId;
  final String requestType;
  final String? toolName;
  final Map<String, dynamic>? toolInput;
  final double createdAt;

  const PendingRequest({
    required this.requestId,
    required this.requestType,
    this.toolName,
    this.toolInput,
    required this.createdAt,
  });

  factory PendingRequest.fromJson(Map<String, dynamic> json) {
    return PendingRequest(
      requestId: json['request_id'] as String,
      requestType: json['request_type'] as String,
      toolName: json['tool_name'] as String?,
      toolInput: json['tool_input'] as Map<String, dynamic>?,
      createdAt: (json['created_at'] as num).toDouble(),
    );
  }
}
