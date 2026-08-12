enum VoiceAssistantState {
  idle, // خامل / في الانتظار
  wake, // تفعيل المساعد الصوتي
  releasingAudio, // تحرير مخرج الصوت والتركيز
  startingRecorder, // بدء تسجيل الصوت عالي الدقة (Dual Capture)
  startingRecognition, // بدء محرك التعرف الصوتي (STT)
  listening, // أنا أستمع... تحدث الآن
  detectingSilence, // اكتشاف السكوت (2.5s Silence Detector)
  processing, // جاري معالجة الصوت والنص
  waitingGemini, // انتظار إجابة الذكاء الاصطناعي
  speaking, // أتحدث...
  error, // حدث خطأ
}

enum VoiceCommandType {
  wakeGreeting, // مساعد النخبة -> أهلاً أستاذ
  thankYou, // شكراً -> تدلل أستاذ
  openChat, // افتح المحادثة
  newChat, // ابدأ محادثة جديدة
  readLastResponse, // اقرأ آخر إجابة
  stopSpeaking, // أوقف الكلام
  clearChat, // امسح المحادثة
  none, // ليس أمراً تنظيمياً (سؤال عادي)
}
