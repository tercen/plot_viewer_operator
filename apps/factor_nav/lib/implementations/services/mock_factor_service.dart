import '../../domain/models/factor.dart';
import '../../domain/services/data_service.dart';

/// Mock implementation of DataService.
/// Returns 12 hardcoded factors in 3 namespaces.
class MockFactorService implements DataService {
  @override
  Future<List<Factor>> loadFactors(String workflowId, String stepId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    return const [
      // Import namespace (5 factors)
      Factor(name: 'Import.gene_id', type: 'string'),
      Factor(name: 'Import.sample_name', type: 'string'),
      Factor(name: 'Import.expression_value', type: 'double'),
      Factor(name: 'Import.batch_id', type: 'int'),
      Factor(name: 'Import.tissue_type', type: 'string'),

      // Normalize namespace (3 factors)
      Factor(name: 'Normalize.mean', type: 'double'),
      Factor(name: 'Normalize.sd', type: 'double'),
      Factor(name: 'Normalize.method', type: 'string'),

      // PCA namespace (4 factors)
      Factor(name: 'PCA.PC1', type: 'double'),
      Factor(name: 'PCA.PC2', type: 'double'),
      Factor(name: 'PCA.PC3', type: 'double'),
      Factor(name: 'PCA.variance_explained', type: 'double'),
    ];
  }
}
