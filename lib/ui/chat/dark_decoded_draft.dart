/// Text body used to compare [decoded] with a backlog line (`You: …`, `Name: …`, or plain incoming).
String _exchangeLineBody(String line) {
  final L = line.trim();
  if (L.startsWith('You: ')) {
    return L.substring(5).trim();
  }
  final idx = L.indexOf(': ');
  if (idx >= 0) {
    return L.substring(idx + 2).trim();
  }
  return L;
}

/// Whether to show the tap-decoded draft row without duplicating anything already
/// listed in [exchangeBacklog] (any line: plain incoming, `Name: text`, or `You: text`).
///
/// Previously we always showed the draft when the *last* line was `You: …`, which
/// duplicated an *earlier* incoming line still held in the decoder buffer.
bool shouldShowTapDecoderDraft(String decoded, List<String> exchangeBacklog) {
  final d = decoded.trim();
  if (d.isEmpty) return false;
  for (final raw in exchangeBacklog) {
    if (_exchangeLineBody(raw) == d) return false;
  }
  return true;
}
