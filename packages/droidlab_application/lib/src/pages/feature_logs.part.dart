part of 'feature_pages.dart';

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  Future<void> _openLogDirectory(BuildContext context) async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? Directory.current.path;
    final directory = Directory(
      '$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}logs',
    );
    try {
      await directory.create(recursive: true);
      final executable = Platform.isWindows
          ? 'explorer'
          : Platform.isMacOS
              ? 'open'
              : 'xdg-open';
      await Process.start(
        executable,
        [directory.path],
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open log folder: $error')),
        );
      }
    }
  }


  Future<void> _saveLogs(BuildContext context, WidgetRef ref) async {
    final location = await getSaveLocation(
      suggestedName: 'droidlab-logs.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'DroidLab log files', extensions: ['log', 'txt']),
      ],
    );
    if (location == null) return;
    try {
      final diagnostics = ref.read(backendClientProvider).diagnostics;
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ?? Directory.current.path;
      final operationLog = File(
        '$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}logs${Platform.pathSeparator}operations.log',
      );
      final contents = StringBuffer()
        ..writeln('DroidLab application logs')
        ..writeln('Exported: ${DateTime.now().toIso8601String()}')
        ..writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
        ..writeln()
        ..writeln('===== OPERATION CONSOLE =====');
      if (await operationLog.exists()) {
        contents.write(redactDiagnosticText(await operationLog.readAsString()));
      } else {
        contents.writeln('No persisted operation-console log is available yet.');
      }
      contents
        ..writeln()
        ..writeln('===== BACKEND DIAGNOSTICS =====');
      if (diagnostics.isEmpty) {
        contents.writeln('No backend stderr diagnostics have been captured.');
      } else {
        contents.write(redactDiagnosticText(diagnostics.join('\n')));
        contents.writeln();
      }
      final file = File(location.path);
      await file.parent.create(recursive: true);
      await file.writeAsString(contents.toString(), flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logs saved to ${file.path}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save logs: $error')),
        );
      }
    }
  }

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    final location = await getSaveLocation(
      suggestedName: 'DroidLab-diagnostics.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Diagnostic text report', extensions: ['txt', 'log']),
      ],
    );
    if (location == null) return;
    try {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ?? Directory.current.path;
      final logDirectory = Directory(
        '$home${Platform.pathSeparator}DroidLab${Platform.pathSeparator}logs',
      );
      final logFile = File(
        '${logDirectory.path}${Platform.pathSeparator}droidlab.log',
      );
      final diagnostics = ref.read(backendClientProvider).diagnostics;
      final pythonExecutable = Platform.environment['DROIDLAB_PYTHON'] ??
          (Platform.isWindows ? 'python' : 'python3');
      String pythonVersion = 'Unavailable';
      try {
        final version = await Process.run(pythonExecutable, ['--version']);
        pythonVersion = (version.stdout.toString() + version.stderr.toString()).trim();
      } catch (_) {
        // Preserve the report if Python cannot be queried independently.
      }
      final report = StringBuffer()
        ..writeln('DroidLab diagnostic report')
        ..writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
        ..writeln('Python: $pythonVersion')
        ..writeln('Build type: desktop')
        ..writeln()
        ..writeln('--- Operation console (latest file) ---');
      final operationLog = File(
        '${logDirectory.path}${Platform.pathSeparator}operations.log',
      );
      if (await operationLog.exists()) {
        report.write(redactDiagnosticText(await operationLog.readAsString()));
      } else {
        report.writeln('No persisted operation-console log found.');
      }
      report.writeln();
      report.writeln('--- Backend application log (latest file) ---');
      if (await logFile.exists()) {
        report.write(redactDiagnosticText(await logFile.readAsString()));
      } else {
        report.writeln('No application log file found.');
        report.writeln();
        report.writeln('--- Backend diagnostics ---');
        if (diagnostics.isEmpty) {
          report.writeln('No backend stderr diagnostics captured.');
        } else {
          report.write(redactDiagnosticText(diagnostics.join('\n')));
        }
      }
      final file = File(location.path);
      await file.parent.create(recursive: true);
      await file.writeAsString(report.toString(), flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostic report saved to ${file.path}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export diagnostic report: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendReadyProvider);
    final diagnostics = ref.read(backendClientProvider).diagnostics;
    final raw = diagnostics.join('\n');
    final sanitized = redactDiagnosticText(raw);
    Widget previewCard(String title, String subtitle, String value, {bool safe = false}) => Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 14),
          Expanded(child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: SingleChildScrollView(child: SelectableText(
              value.isEmpty ? 'No diagnostic lines are available yet.' : value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.55,
                color: safe ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.onSurface,
              ),
            )),
          )),
        ]),
      ),
    );
    return _PageFrame(
      title: 'Logs, Logcat & Diagnostic Redactor',
      subtitle: 'Centralized redaction strips serials, MACs, 15-digit IMEIs, bearer tokens, and host user paths before export',
      actions: [
        OutlinedButton.icon(
          onPressed: () => _openLogDirectory(context),
          icon: const Icon(Icons.folder_open),
          label: const Text('Open logs folder'),
        ),
        OutlinedButton.icon(
          onPressed: () => _saveLogs(context, ref),
          icon: const Icon(Icons.save_alt),
          label: const Text('Save logs'),
        ),
        OutlinedButton.icon(
          onPressed: () => _exportReport(context, ref),
          icon: const Icon(Icons.save_alt),
          label: const Text('Export report'),
        ),
      ],
      child: backend.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorPanel(
          message: error.toString(),
          retry: () => ref.invalidate(backendReadyProvider),
        ),
        data: (_) {
          if (MediaQuery.sizeOf(context).width < 950) {
            return Column(children: [
              Expanded(child: previewCard('Raw Diagnostics', 'Unredacted local backend diagnostics. Review before sharing.', raw)),
              const SizedBox(height: 14),
              Expanded(child: previewCard('Sanitized Export Preview', 'Redacted output for bug reports and issue attachments.', sanitized, safe: true)),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: previewCard('Raw Logcat / Diagnostics', 'Unredacted local diagnostic input. Review before sharing.', raw)),
            const SizedBox(width: 24),
            Expanded(child: previewCard('Sanitized Export Preview', 'Redacted output for bug reports and issue attachments.', sanitized, safe: true)),
          ]);
        },
      ),
    );
  }
}


