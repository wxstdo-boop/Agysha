import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:agysha/services/forge_service.dart';

/// Жалоба: «ИИ не может редактировать/видеть GitHub Actions». Проверяем,
/// что инструменты агента действительно читают Actions, проверки и PR —
/// на настоящем разборе ответов GitHub, а не на заглушках сервиса.
MockClient _github() => MockClient((request) async {
  final path = request.url.path;
  Map<String, dynamic> body;
  if (path.endsWith('/actions/runs')) {
    body = {
      'workflow_runs': [
        {
          'id': 42,
          'name': 'CI',
          'status': 'completed',
          'conclusion': 'failure',
          'head_branch': 'main',
          'created_at': '2026-11-21T10:00:00Z',
          'html_url': 'https://github.com/x/y/actions/runs/42',
        },
        {'id': 41, 'display_title': 'Ship', 'status': 'queued'},
      ],
    };
  } else if (path.endsWith('/jobs')) {
    body = {
      'jobs': [
        {
          'name': 'build',
          'status': 'completed',
          'conclusion': 'failure',
          'steps': [
            {'name': 'Set up JDK', 'conclusion': 'success'},
            {'name': 'Gradle assembleRelease', 'conclusion': 'failure'},
          ],
        },
      ],
    };
  } else if (path.endsWith('/check-runs')) {
    body = {
      'check_runs': [
        {'name': 'analyze', 'conclusion': 'success'},
        {
          'name': 'test',
          'conclusion': 'failure',
          'output': {'summary': 'Expected: 2\n  Actual: 3'},
        },
      ],
    };
  } else if (path.endsWith('/pulls')) {
    return http.Response(
      jsonEncode([
        {
          'number': 66,
          'title': 'Кузница: правка',
          'head': {'ref': 'forge/fix'},
          'html_url': 'https://github.com/x/y/pull/66',
        },
      ]),
      200,
      headers: {'content-type': 'application/json'},
    );
  } else if (path.endsWith('/commits')) {
    return http.Response(
      jsonEncode([
        {
          'sha': 'abcdef1234567',
          'commit': {'message': 'feat: правка\n\nподробности'},
        },
      ]),
      200,
      headers: {'content-type': 'application/json'},
    );
  } else if (request.method == 'PUT') {
    // GitHub так отвечает на правку workflow токеном без scope `workflow`.
    return http.Response(
      jsonEncode({'message': 'Not Found'}),
      404,
      headers: {'content-type': 'application/json'},
    );
  } else {
    return http.Response('{}', 200);
  }
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
});

ForgeService _service() =>
    ForgeService(client: _github(), store: InMemoryForgeTokenStore());

void main() {
  group('инструменты GitHub для агента', () {
    test('workflowRuns показывает прогоны и их статусы', () async {
      final runs = await _service().workflowRuns(
        'wxstdo-boop',
        'agysha',
        token: 'ghp_x',
      );
      expect(runs, hasLength(2));
      expect(runs.first, contains('run 42'));
      expect(runs.first, contains('CI'));
      expect(runs.first, contains('completed/failure'));
      expect(runs.first, contains('ветка main'));
      // Прогон без name берёт display_title, а не «?».
      expect(runs.last, contains('Ship'));
    });

    test('runJobs перечисляет упавшие шаги', () async {
      final jobs = await _service().runJobs(
        'wxstdo-boop',
        'agysha',
        42,
        token: 'ghp_x',
      );
      expect(jobs.first, contains('build'));
      expect(jobs.any((l) => l.contains('Gradle assembleRelease')), isTrue);
    });

    test('checkAnnotations отдаёт текст ошибки упавшей проверки', () async {
      final checks = await _service().checkAnnotations(
        'wxstdo-boop',
        'agysha',
        'main',
        token: 'ghp_x',
      );
      expect(checks, hasLength(2));
      expect(checks.first, contains('test'));
      expect(checks.last, contains('Actual: 3'));
    });

    test('pullRequests и recentCommits видят открытые PR и коммиты', () async {
      final service = _service();
      final prs = await service.pullRequests(
        'wxstdo-boop',
        'agysha',
        token: 'ghp_x',
      );
      expect(prs.single, contains('#66'));
      expect(prs.single, contains('forge/fix'));

      final commits = await service.recentCommits(
        'wxstdo-boop',
        'agysha',
        token: 'ghp_x',
      );
      expect(commits.single, startsWith('abcdef1 '));
      expect(commits.single, contains('feat: правка'));
    });

    test('правка workflow без scope подсказывает причину, а не «404»', () async {
      final service = _service();
      await expectLater(
        service.writeFile(
          'wxstdo-boop',
          'agysha',
          '.github/workflows/ci.yml',
          content: 'name: CI',
          message: 'Кузница: правка CI',
          branch: 'forge/fix',
          token: 'ghp_x',
        ),
        throwsA(
          isA<ForgeException>().having(
            (e) => e.message,
            'message',
            contains('scope `workflow`'),
          ),
        ),
      );
    });
  });
}
