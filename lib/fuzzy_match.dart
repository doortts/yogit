/// `notsp` finds `notes-split-pane`: every character of the query appears in
/// the candidate, in order, with anything allowed in between. Case is ignored
/// and whitespace in the query is dropped, so `no sp` searches the same way.
///
/// An empty query matches everything, which keeps the filter fields showing
/// their whole list until the user types.
bool fuzzyMatch(String candidate, String query) =>
    fuzzyMatchPositions(candidate, query) != null;

/// Where [query] landed in [candidate] — the indexes a search paints its
/// highlight over — or null when the candidate does not match. The indexes
/// count code units, so a character written as a surrogate pair contributes
/// both of its halves and never gets split across two spans.
List<int>? fuzzyMatchPositions(String candidate, String query) {
  final needle = query.toLowerCase();
  final haystack = candidate.toLowerCase();
  final positions = <int>[];
  var index = 0;
  for (final rune in needle.runes) {
    if (_isSpace(rune)) continue;
    final character = String.fromCharCode(rune);
    final found = haystack.indexOf(character, index);
    if (found < 0) return null;
    for (var unit = 0; unit < character.length; unit++) {
      positions.add(found + unit);
    }
    index = found + character.length;
  }
  return positions;
}

bool _isSpace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
