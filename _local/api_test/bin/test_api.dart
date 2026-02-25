import 'package:sci_tercen_client/sci_client.dart';
import 'package:sci_tercen_client/src/sci_client_extensions.dart';
import 'package:sci_http_client/http_client.dart' as http_api;
import 'package:sci_http_client/http_io_client.dart';
import 'package:sci_http_client/http_auth_client.dart';

const token =
    'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vMTI3LjAuMC4xOjU0MDAiLCJleHAiOjE3NzM5MjU3OTUsImRhdGEiOnsiZCI6IiIsInUiOiJ0ZXN0IiwiZSI6MTc3MzkyNTc5NTg2MX19.sn-f1W1MM_pAdd4Wgx0dAxsCoLp2nO18hDOEJAL77yw';
const serviceUri = 'http://127.0.0.1:5400';
const teamId = 'test';

Future<ServiceFactory> createFactory() async {
  HttpIOClient.setAsCurrent();
  var httpClient = HttpAuthClient(token) as http_api.HttpClient;
  var factory = ServiceFactory();
  await factory.initializeWith(Uri.parse(serviceUri), httpClient);
  return factory;
}

void main() async {
  print('=== Tercen API Test ===');
  print('Server: $serviceUri');
  print('Team: $teamId');
  print('');

  late ServiceFactory factory;
  try {
    factory = await createFactory();
    print('OK: Factory created');
  } catch (e) {
    print('FAIL: Factory creation: $e');
    return;
  }

  // --- Test 1: findByIsPublicAndLastModifiedDate ---
  print('\n--- Test 1: findByIsPublicAndLastModifiedDate ---');
  try {
    final projects =
        await factory.projectService.findByIsPublicAndLastModifiedDate(
      startKey: [false, ''],
      endKey: [true, '\uf000'],
      limit: 20,
      descending: false,
    );
    print('OK: ${projects.length} projects');
    for (final p in projects) {
      print('  - ${p.name} (id=${p.id}, owner=${p.acl.owner}, public=${p.isPublic})');
    }
  } catch (e) {
    print('FAIL: $e');
  }

  // --- Test 2: findByTeamAndIsPublicAndLastModifiedDate ---
  print('\n--- Test 2: findByTeamAndIsPublicAndLastModifiedDate ---');
  try {
    final projects =
        await factory.projectService.findByTeamAndIsPublicAndLastModifiedDate(
      startKey: [teamId, false, ''],
      endKey: [teamId, true, '\uf000'],
      limit: 20,
      descending: false,
    );
    print('OK: ${projects.length} projects');
    for (final p in projects) {
      print('  - ${p.name} (id=${p.id}, owner=${p.acl.owner})');
    }
  } catch (e) {
    print('FAIL: $e');
  }

  // --- Test 3: findByIsPublicAndLastModifiedDateStream (extension) ---
  print('\n--- Test 3: findByIsPublicAndLastModifiedDateStream ---');
  try {
    final projects = await factory.projectService
        .findByIsPublicAndLastModifiedDateStream(
          descending: false,
        )
        .take(20)
        .toList();
    print('OK: ${projects.length} projects (stream)');
    for (final p in projects) {
      print('  - ${p.name} (owner=${p.acl.owner})');
    }
  } catch (e) {
    print('FAIL: $e');
  }

  // --- Test 4: findByTeamAndIsPublicAndLastModifiedDateStream (extension) ---
  print('\n--- Test 4: findByTeamAndIsPublicAndLastModifiedDateStream ---');
  try {
    final projects = await factory.projectService
        .findByTeamAndIsPublicAndLastModifiedDateStream(
          startKeyOwner: teamId,
          endKeyOwner: teamId,
        )
        .take(20)
        .toList();
    print('OK: ${projects.length} projects (stream)');
    for (final p in projects) {
      print('  - ${p.name} (owner=${p.acl.owner})');
    }
  } catch (e) {
    print('FAIL: $e');
  }

  // --- Test 5: findProjectObjectsByFolderAndName (workflows) ---
  print('\n--- Test 5: findProjectObjectsByFolderAndName ---');
  try {
    // Use first "test" project from test 2
    final projects =
        await factory.projectService.findByTeamAndIsPublicAndLastModifiedDate(
      startKey: [teamId, false, ''],
      endKey: [teamId, true, '\uf000'],
      limit: 1,
      descending: false,
    );
    if (projects.isEmpty) {
      print('SKIP: No projects found');
    } else {
      final projectId = projects.first.id;
      print('Using project: ${projects.first.name} ($projectId)');

      final docs = await factory.projectDocumentService
          .findProjectObjectsByFolderAndName(
        startKey: [projectId, '', ''],
        endKey: [projectId, '\uf000', '\uf000'],
        limit: 50,
        descending: false,
        useFactory: true,
      );
      print('OK: ${docs.length} documents');
      for (final d in docs) {
        final kind = d is Workflow
            ? 'Workflow'
            : d is FileDocument
                ? 'File'
                : d.runtimeType.toString();
        print('  - [$kind] ${d.name} (id=${d.id})');
      }

      // --- Test 6: Get workflow steps ---
      final workflows = docs.whereType<Workflow>().toList();
      if (workflows.isNotEmpty) {
        print('\n--- Test 6: workflowService.get (steps) ---');
        final wf = await factory.workflowService.get(workflows.first.id);
        print('Workflow: ${wf.name}, ${wf.steps.length} steps');
        for (final step in wf.steps) {
          final isData = step is DataStep ? ' [DataStep]' : '';
          print('  - ${step.name} (${step.runtimeType})$isData');
        }
      }
    }
  } catch (e) {
    print('FAIL: $e');
  }

  print('\n=== Done ===');
}
