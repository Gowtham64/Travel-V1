// Stub for non-web platforms to allow cross-platform compiling
class window {
  static dynamic get speechSynthesis => null;
}

class SpeechSynthesisUtterance {
  String text;
  String lang = 'en-US';
  double rate = 1.0;
  SpeechSynthesisUtterance(this.text);
}
