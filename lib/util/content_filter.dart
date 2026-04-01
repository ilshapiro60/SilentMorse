/// Lightweight client-side profanity filter.
/// Replaces known offensive words with asterisks in outgoing messages.
library;

final _offensiveWords = RegExp(
  r'\b('
  r'ass|asshole|bastard|bitch|bullshit|cock|crap|cunt|damn|dick|'
  r'douche|fag|fuck|fucking|goddamn|hell|jackass|motherfucker|'
  r'nigger|nigga|piss|prick|pussy|shit|slut|twat|whore'
  r')\b',
  caseSensitive: false,
);

/// Returns [text] with offensive words replaced by asterisks.
String filterProfanity(String text) {
  return text.replaceAllMapped(_offensiveWords, (match) {
    return '*' * match.group(0)!.length;
  });
}

/// Returns true if [text] contains any words from the blocklist.
bool containsProfanity(String text) => _offensiveWords.hasMatch(text);
