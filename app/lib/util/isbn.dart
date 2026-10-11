/// Whether [text] is an ISBN-10 or ISBN-13 with a correct check digit. Hyphens and spaces are ignored.
bool looksLikeIsbn(String text) {
  final digits = text.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();
  if (RegExp(r'^\d{13}$').hasMatch(digits)) {
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(digits[i]) * (i.isEven ? 1 : 3);
    }
    return sum % 10 == 0;
  }
  if (RegExp(r'^\d{9}[\dX]$').hasMatch(digits)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += (digits[i] == 'X' ? 10 : int.parse(digits[i])) * (10 - i);
    }
    return sum % 11 == 0;
  }
  return false;
}
