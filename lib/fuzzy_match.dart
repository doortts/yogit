/// `notsp` finds `notes-split-pane`: every character of the query appears in
/// the candidate, in order, with anything allowed in between. Case is ignored
/// and whitespace in the query is dropped, so `no sp` searches the same way.
///
/// An empty query matches everything, which keeps the filter fields showing
/// their whole list until the user types.
bool fuzzyMatch(String candidate, String query) {
  final needle = query.toLowerCase();
  final haystack = candidate.toLowerCase();
  var index = 0;
  for (final rune in needle.runes) {
    if (_isSpace(rune)) continue;
    final found = haystack.indexOf(String.fromCharCode(rune), index);
    if (found < 0) return false;
    index = found + 1;
  }
  return true;
}

bool _isSpace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
