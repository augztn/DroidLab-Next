part of 'feature_pages.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}';
    return _PageFrame(
      title: 'About DroidLab',
      subtitle: 'Android engineering workstation',
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'DL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DroidLab', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          Text('Flutter desktop · Version 0.1.0'),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Text(
                    'A toolkit for Android device engineering and firmware workflows.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Discover and manage ADB and Fastboot devices, run guarded device operations, inspect and extract OTA payloads, capture logcat output, and review diagnostics.',
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.computer),
                    title: const Text('Platform'),
                    subtitle: Text(platform),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.code),
                    title: Text('Application'),
                    subtitle: Text('DroidLab Flutter Desktop'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.shield_outlined),
                    title: Text('Local-first'),
                    subtitle: Text('Device operations and diagnostic files are handled on this computer.'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

