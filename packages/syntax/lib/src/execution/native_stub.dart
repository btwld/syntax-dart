import 'executor.dart';

/// Browsers use cooperative execution unless a worker asset is configured.
HighlightExecutor createNativeHighlightExecutor() =>
    CooperativeHighlightExecutor();
