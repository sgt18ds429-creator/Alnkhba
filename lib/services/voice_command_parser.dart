import '../models/voice_assistant_state.dart';

class VoiceCommandParser {
  /// Normalize Arabic text for command matching
  static String _normalize(String text) {
    String clean = text.trim().toLowerCase();
    clean = clean.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), ''); // remove diacritics
    clean = clean.replaceAll(RegExp(r'[أإآ]'), 'ا');
    clean = clean.replaceAll('ة', 'ه');
    clean = clean.replaceAll('ى', 'ي');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean;
  }

  static VoiceCommandType parseCommand(String text) {
    final clean = _normalize(text);
    final wordCount = clean.split(' ').length;

    // Only match system commands if the phrase is short (<= 5 words).
    // Otherwise, treat it as a conversational question meant for the AI.
    if (wordCount > 5) {
      return VoiceCommandType.none;
    }

    if (isWakeWord(clean)) {
      return VoiceCommandType.wakeGreeting;
    }

    if (clean.contains('شكرا') ||
        clean.contains('شكراً') ||
        clean.contains('مشكور') ||
        clean.contains('تسلم') ||
        clean.contains('شكر جزيل')) {
      return VoiceCommandType.thankYou;
    }

    if (clean.contains('افتح المحادثه') ||
        clean.contains('عرض المحادثه') ||
        clean.contains('الشاشه الرئيسيه')) {
      return VoiceCommandType.openChat;
    }

    if (clean.contains('ابدا محادثه جديده') ||
        clean.contains('محادثه جديده') ||
        clean.contains('سؤال جديد')) {
      return VoiceCommandType.newChat;
    }

    if (clean.contains('اقرا اخر اجابه') ||
        clean.contains('اقرا التقرير') ||
        clean.contains('اعد القراءه') ||
        clean.contains('اعد النطق')) {
      return VoiceCommandType.readLastResponse;
    }

    if (clean.contains('اوقف الكلام') ||
        clean.contains('توقف') ||
        clean.contains('اسكت') ||
        clean.contains('صمت') ||
        clean.contains('الغاء')) {
      return VoiceCommandType.stopSpeaking;
    }

    if (clean.contains('امسح المحادثه') ||
        clean.contains('تفريغ المحادثه') ||
        clean.contains('حذف المحادثه')) {
      return VoiceCommandType.clearChat;
    }

    return VoiceCommandType.none;
  }

  /// Check if the phrase contains or starts with any wake word variation
  static bool isWakeWord(String text) {
    final clean = _normalize(text);
    final wakeWords = [
      'hi ray',
      'hiray',
      'hi-ray',
      'hey ray',
      'heyray',
      'high ray',
      'hi rai',
      'hey rai',
      'هاي راي',
      'هاي ري',
      'هاي راى',
      'حي راي',
      'حي ري',
      'حي راى',
      'يا راي',
      'يا ري',
      'يا راى',
      'راي',
      'خيري',
      'هايراي',
      'هاي راي',
      'هيري',
      'هي ري',
      'هيرى',
      'هى رى',
      'hi sono',
      'hisono',
      'هاي سونو',
      'هيسونو',
      'هاي صونو',
      'هي صونو',
      'هصونو',
      'حي سونو',
      'سونو',
      'صونو',
      'هاي سانو',
      'هيسانو',
      'هاي غي',
      'هاي غاي',
      'هي غي',
      'hi ghay',
      'hi ghi',
      'highay',
      'حي غي',
      'غي',
      'غاي',
    ];

    for (final w in wakeWords) {
      if (clean == w ||
          clean.startsWith('$w ') ||
          clean.endsWith(' $w') ||
          clean.contains(' $w ')) {
        return true;
      }
    }
    return clean == 'ray' || clean == 'ري';
  }

  /// Strip wake word prefix from user query (e.g. "Hi Ray ما هي الأشعة" -> "ما هي الأشعة")
  static String cleanWakeWordPrefix(String text) {
    String clean = text.trim();
    final wakeRegex = RegExp(
      r'^(hi\s*ray|hiray|hi-ray|hey\s*ray|heyray|high\s*ray|هاي\s*راي|هاي\s*ري|حي\s*راي|حي\s*ري|يا\s*راي|راي|خيري|هيري|هي\s*ري|هيرى|هى\s*رى|hi\s*sono|hisono|هاي\s*سونو|هيسونو|هاي\s*صونو|هي\s*صونو|هصونو|حي\s*سونو|سونو|صونو|هاي\s*سانو|هيسانو|هاي\s*غي|هاي\s*غاي|هي\s*غي|hi\s*ghay|hi\s*ghi|highay|حي\s*غي|غي|غاي)\b[\s,؛!.]*',
      caseSensitive: false,
    );
    return clean.replaceFirst(wakeRegex, '').trim();
  }
}
