import 'dart:io';

import 'package:sci_tercen_client/sci_client.dart';
import 'package:sci_http_client/http_client.dart' as http_api;
import 'package:sci_http_client/http_io_client.dart';
import 'package:sci_http_client/http_auth_client.dart';

const token =
    'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOi8vMTI3LjAuMC4xOjU0MDAiLCJleHAiOjE3NzM5MjEzMTksImRhdGEiOnsiZCI6IiIsInUiOiJ0ZXN0IiwiZSI6MTc3MzkyMTMxOTQ1M319.EJH25KY56XnzLLFbBe9K10PS4KFjGLWvVn4B07b_SOM';
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
  final factory = await createFactory();
  print('=== CubeQuery Table Inspector ===\n');

  // Find all projects
  final projects =
      await factory.projectService.findByTeamAndIsPublicAndLastModifiedDate(
    startKey: [teamId, false, ''],
    endKey: [teamId, true, '\uf000'],
    limit: 50,
    descending: false,
  );

  // Find GGRS Test project
  Project? ggrsProject;
  for (final p in projects) {
    if (p.name.contains('GGRS')) {
      ggrsProject = p;
      break;
    }
  }
  if (ggrsProject == null) {
    print('ERROR: GGRS Test project not found');
    exit(1);
  }
  print('Project: ${ggrsProject.name} (${ggrsProject.id})\n');

  // Find workflows
  final docs = await factory.projectDocumentService
      .findProjectObjectsByFolderAndName(
    startKey: [ggrsProject.id, '', ''],
    endKey: [ggrsProject.id, '\uf000', '\uf000'],
    limit: 50,
    descending: false,
    useFactory: true,
  );
  final workflows = docs.whereType<Workflow>().toList();

  for (final wfDoc in workflows) {
    final wf = await factory.workflowService.get(wfDoc.id);
    print('=== Workflow: ${wf.name} (${wf.id}) ===');
    print('Steps: ${wf.steps.length}\n');

    // Find DataSteps with taskIds
    final dataSteps = wf.steps.whereType<DataStep>().toList();
    for (final ds in dataSteps) {
      final crosstab = ds.model;
      if (crosstab.taskId.isEmpty) continue;

      print('--- DataStep: "${ds.name}" (${ds.id}) ---');
      print('  taskId: ${crosstab.taskId}');

      // Print axis info
      for (int i = 0; i < crosstab.axis.xyAxis.length; i++) {
        final xy = crosstab.axis.xyAxis[i];
        print('  xyAxis[$i]:');
        try {
          print('    xAxis: "${xy.xAxis.graphicalFactor.factor.name}" (${xy.xAxis.graphicalFactor.factor.type})');
        } catch (_) {
          print('    xAxis: (none)');
        }
        try {
          print('    yAxis: "${xy.yAxis.graphicalFactor.factor.name}" (${xy.yAxis.graphicalFactor.factor.type})');
        } catch (_) {
          print('    yAxis: (none)');
        }
      }

      // Fetch task
      try {
        final task = await factory.taskService.get(crosstab.taskId);
        if (task is! CubeQueryTask) {
          print('  Task type: ${task.runtimeType} (not CubeQueryTask)');
          continue;
        }

        final schemaIds = task.schemaIds.toList();
        print('  schemaIds (${schemaIds.length}): $schemaIds');

        final labels = [
          'qt_hash',
          'col_hash',
          'row_hash',
          'x_domain',
          'y_domain',
        ];

        for (int i = 0; i < schemaIds.length; i++) {
          final id = schemaIds[i];
          if (id.isEmpty) continue;
          final label = i < labels.length ? labels[i] : 'extra[$i]';

          try {
            final schema = await factory.tableSchemaService.get(id);
            print('');
            print('  [$i] $label (${schema.runtimeType})');
            print('      nRows: ${schema.nRows}');
            print('      columns:');
            for (final col in schema.columns) {
              print('        "${col.name}" : ${col.type}');
            }

            // Sample first 3 rows
            if (schema.nRows > 0) {
              final sampleN = schema.nRows < 3 ? schema.nRows : 3;
              final colNames = schema.columns.map((c) => c.name).toList();
              try {
                final table = await factory.tableSchemaService.select(
                  id, colNames, 0, sampleN,
                );
                print('      sample ($sampleN rows):');
                for (int r = 0; r < table.nRows; r++) {
                  final row = <String, dynamic>{};
                  for (final col in table.columns) {
                    final v = col.values;
                    if (v is List && r < v.length) {
                      row[col.name] = v[r];
                    }
                  }
                  print('        [$r] $row');
                }
              } catch (e) {
                print('      sample: ERROR $e');
              }
            }
          } catch (e) {
            print('  [$i] $label: ERROR $e');
          }
        }
      } catch (e) {
        print('  Task fetch ERROR: $e');
      }
      print('');
    }
  }

  exit(0);
}
