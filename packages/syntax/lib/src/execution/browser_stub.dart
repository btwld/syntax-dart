import 'executor.dart';

/// Native applications should use the native isolate executor.
HighlightExecutor createBrowserHighlightExecutor({Uri? workerUri}) =>
    CooperativeHighlightExecutor();
