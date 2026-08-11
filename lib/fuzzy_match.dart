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

/// A word is a run of letters and digits. Everything else — spaces, brackets,
/// colons, slashes, underscores — is the gap between two words, on both sides
/// of the search: `fix(merge):` is `fix` and `merge`, and so is a query typed
/// or pasted the same way.
final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// `name hover` finds `name a clipped ref … on hover`: each word of the query
/// has to sit inside some word of the candidate, and which word it lands in —
/// or in what order — is not asked. Letters scattered across a whole sentence
/// are not a word, so this finds what [fuzzyMatch] would find plus nothing
/// else: it is the reading for prose, where [fuzzyMatch] is the reading for a
/// single name.
///
/// Returns the code units to light — every occurrence of every query word —
/// or null when one of the words is nowhere, which is when the candidate is
/// not a result at all. A query with no letters or digits in it finds nothing.
List<int>? wordMatchPositions(String candidate, String query) {
  final terms = _word.allMatches(query.toLowerCase());
  if (terms.isEmpty) return null;
  final haystack = candidate.toLowerCase();
  final words = _word.allMatches(haystack).toList();
  final positions = <int>{};
  for (final term in terms) {
    final needle = term.group(0)!;
    var found = false;
    for (final word in words) {
      for (
        var at = word.group(0)!.indexOf(needle);
        at >= 0;
        at = word.group(0)!.indexOf(needle, at + 1)
      ) {
        found = true;
        for (var unit = 0; unit < needle.length; unit++) {
          positions.add(word.start + at + unit);
        }
      }
    }
    if (!found) return null;
  }
  return positions.toList()..sort();
}
