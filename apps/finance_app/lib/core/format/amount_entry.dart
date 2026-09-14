/// Shared text-based amount entry for the amount pads.
///
/// Kept as a string rather than a number so a trailing decimal point survives
/// while the user types, and parsed by hand rather than through a `double`
/// round-trip — that round-trip is exactly how a finance app loses a paisa.
class AmountEntry {
  AmountEntry({String initial = ''}) : _text = initial;

  String _text;

  /// The raw typed text, for display.
  String get text => _text;

  /// True when nothing has been entered.
  bool get isEmpty => _text.isEmpty;

  /// The entered value in minor units (paise).
  int get minor => parseMinor(_text);

  /// Replaces the entry with [minor], rendered for editing.
  void setMinor(int minor) {
    _text = toEditableText(minor);
  }

  /// Converts a stored value back into editable text.
  ///
  /// Whole rupees drop their decimals: a budget is a round number in practice,
  /// and showing "18000.00" makes it look like a computed value rather than
  /// something the user chooses.
  static String toEditableText(int minor) {
    if (minor == 0) {
      return '';
    }
    final rupees = minor ~/ 100;
    final paise = minor % 100;
    return paise == 0
        ? '$rupees'
        : '$rupees.${paise.toString().padLeft(2, '0')}';
  }

  /// Parses typed text into integer paise.
  ///
  /// Handles a partial value like `12.` and rounds a single decimal digit to
  /// the nearest ten paise, so the field never has to reject input mid-typing.
  static int parseMinor(String text) {
    if (text.isEmpty) {
      return 0;
    }
    final parts = text.split('.');
    final rupees = int.tryParse(parts.first) ?? 0;
    var paise = 0;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      paise = int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0;
    }
    return rupees * 100 + paise;
  }

  /// Applies a keypad press: `0`-`9`, `.`, or `del`.
  ///
  /// [maxDigits] caps the whole-rupee part so a stuck key cannot produce an
  /// absurd amount.
  void press(String key, {int maxDigits = 8}) {
    if (key == 'del') {
      if (_text.isNotEmpty) {
        _text = _text.substring(0, _text.length - 1);
      }
      return;
    }
    if (key == '.') {
      // One decimal point only, and never as the first character.
      if (!_text.contains('.') && _text.isNotEmpty) {
        _text = '$_text.';
      }
      return;
    }
    if (_text.length >= maxDigits) {
      return;
    }
    if (key == '0' && _text.isEmpty) {
      return; // No leading zeroes.
    }
    _text = _text == '0' ? key : '$_text$key';
  }
}
