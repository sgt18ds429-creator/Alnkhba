import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:appnukba/services/api_service.dart';
import 'package:appnukba/services/secure_session_store.dart';
import 'package:appnukba/models/message.dart';
import 'package:appnukba/models/chat_session.dart';

class _FakeSessionStore extends SecureSessionStore {
  @override
  Future<String?> readToken() async => 'test-token';

  @override
  Future<String?> readRegistrationId() async => 'registration-1';
}

void main() {
  group('ApiService metadata parsing', () {
    final api = ApiService();

    test('extracts positioning, quiz and YouTube metadata', () {
      final result = api.parseResponseMetadata(
        'شرح الفحص\n[POSITIONING: true]\n[QUIZ_MODE: true]\n[YOUTUBE_QUERY: PA chest X-ray positioning]',
      );

      expect(result['reply'], 'شرح الفحص');
      expect(result['isPositioningQuery'], isTrue);
      expect(result['quizMode'], isTrue);
      expect(result['youtubeQuery'], 'PA chest X-ray positioning');
    });

    test('removes generated image metadata from visible reply', () {
      final result = api.parseResponseMetadata(
        'صورة تعليمية\n[GENERATE_IMAGE: professional chest x-ray anatomy]',
      );

      expect(result['reply'], 'صورة تعليمية');
      expect(result['generateImagePrompt'], 'professional chest x-ray anatomy');
      expect(result.containsKey('generatedImageUrl'), isFalse);
    });

    test('removes horizontal separators', () {
      final result = api.parseResponseMetadata('أولاً\n---\nثانياً\n***');
      expect(result['reply'], 'أولاً\nثانياً');
    });
  });

  group('Model resilience', () {
    test('loads malformed cached message data without throwing', () {
      final message = Message.fromJson({'text': 'اختبار', 'attachments': 'invalid'});
      expect(message.text, 'اختبار');
      expect(message.role, 'user');
      expect(message.attachments, isNull);
    });

    test('loads malformed history/session data with safe defaults', () {
      final session = ChatSession.fromJson({
        'title': 'جلسة',
        'messages': 'invalid',
        'history': 'invalid',
      });
      expect(session.title, 'جلسة');
      expect(session.messages, isEmpty);
      expect(session.history, isEmpty);
      expect(session.createdAt, greaterThan(0));
    });
  });

  group('ApiService backend contract', () {
    test('routes activation through the public rate-limited gateway', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'user': {'id': 'registration-1'},
            'access_token': List.filled(64, 'a').join(),
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = ApiService(
        baseUrl: 'https://example.test',
        client: client,
        sessionStore: _FakeSessionStore(),
      );

      final result = await api.activateRegistration(
        fullName: 'طالب اختبار كامل',
        code: 'ELITE-TESTCODE1234',
        deviceId: '0123456789abcdef0123456789abcdef',
      );

      expect(result['ok'], isTrue);
      expect(captured.url.path, '/api/activate');
      expect(captured.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(captured.body), {
        'fullName': 'طالب اختبار كامل',
        'code': 'ELITE-TESTCODE1234',
        'deviceId': '0123456789abcdef0123456789abcdef',
      });
    });

    test('streams a JSON reply and attaches activation headers', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'reply': 'إجابة آمنة [QUIZ_MODE: true]'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = ApiService(
        baseUrl: 'https://example.test',
        client: client,
        sessionStore: _FakeSessionStore(),
      );

      final chunks = await api
          .sendChatStream(message: 'اشرح الفحص', history: const [], userId: 'user-1')
          .toList();

      expect(chunks.join(), 'إجابة آمنة [QUIZ_MODE: true]');
      expect(captured.headers['authorization'], 'Bearer test-token');
      expect(captured.headers['x-registration-id'], 'registration-1');
      expect(captured.url.path, '/api/chat');
    });

    test('maps an unauthorized response to a session error', () async {
      final api = ApiService(
        baseUrl: 'https://example.test',
        client: MockClient((_) async => http.Response('{}', 401)),
        sessionStore: _FakeSessionStore(),
      );

      expect(
        api.sendChat(message: 'سؤال', history: const [], userId: 'user-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('submits an in-app safety report', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/report');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['reason'], 'معلومات مضللة');
        return http.Response('', 204);
      });
      final api = ApiService(
        baseUrl: 'https://example.test',
        client: client,
        sessionStore: _FakeSessionStore(),
      );

      await api.reportMessage(
        messageId: 'm1',
        messageText: 'نص الإجابة',
        reason: 'معلومات مضللة',
        userId: 'user-1',
      );
    });

    test('loads generated images only from the authenticated backend', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/image');
        expect(request.headers['authorization'], 'Bearer test-token');
        return http.Response(jsonEncode({'imageBase64': 'YWJj', 'mimeType': 'image/png'}), 200);
      });
      final api = ApiService(
        baseUrl: 'https://example.test',
        client: client,
        sessionStore: _FakeSessionStore(),
      );

      expect(await api.fetchGeneratedImage('educational anatomy diagram'), {
        'base64': 'YWJj',
        'mime': 'image/png',
      });
    });
  });
}
