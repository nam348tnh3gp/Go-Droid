class RunResult {
  final String? output;
  final String? error;
  final String? gemini;
  final bool success;

  RunResult({this.output, this.error, this.gemini, required this.success});

  factory RunResult.fromJson(Map<String, dynamic> json, bool success) {
    return RunResult(
      output: json['output'],
      error: json['error'],
      gemini: json['gemini'],
      success: success,
    );
  }
}