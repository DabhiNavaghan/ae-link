import 'package:flutter/material.dart';
import 'package:ae_link/ae_link.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize AE-LINK SDK
  await AeLinkSdk.initialize(
    AeLinkConfig(
      apiBaseUrl: 'https://allevents.in', // Replace with actual API URL
      tenantApiKey: 'your-api-key-here', // Replace with actual API key
      debug: true,
    ),
  );

  // Listen for deep links (both deferred and direct)
  AeLinkSdk.onDeepLink.listen((deepLinkData) {
    print('Deep link received:');
    print('  Event ID: ${deepLinkData.eventId}');
    print('  Action: ${deepLinkData.action}');
    print('  Is Deferred: ${deepLinkData.isDeferred}');
    print('  UTM Params: ${deepLinkData.utmParams}');
    print('  Coupon: ${deepLinkData.couponCode}');
    // TODO: Navigate to event details screen based on deepLinkData
  });

  // Check for deferred deep link on first launch
  final deferredLink = await AeLinkSdk.checkDeferredLink();
  if (deferredLink != null) {
    print('Deferred link found! Event ID: ${deferredLink.eventId}');
    // TODO: Navigate to the deferred link
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AE-LINK Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DeepLinkData? _currentDeepLink;

  @override
  void initState() {
    super.initState();
    _setupDeepLinkListener();
  }

  void _setupDeepLinkListener() {
    // Listen for deep links
    AeLinkSdk.onDeepLink.listen((deepLinkData) {
      setState(() {
        _currentDeepLink = deepLinkData;
      });
      _handleDeepLink(deepLinkData);
    });
  }

  void _handleDeepLink(DeepLinkData deepLinkData) {
    // Handle different actions
    switch (deepLinkData.action) {
      case 'view_event':
        _navigateToEvent(deepLinkData.eventId);
        break;
      case 'view_ticket':
        _navigateToTicket(deepLinkData.eventId);
        break;
      case 'buy_ticket':
        _navigateToBuyTicket(deepLinkData.eventId);
        break;
      default:
        break;
    }

    // If this is a deferred link, confirm it was shown
    if (deepLinkData.isDeferred && deepLinkData.deferredLinkId != null) {
      AeLinkSdk.confirmDeepLink(deepLinkData.deferredLinkId!);
    }
  }

  void _navigateToEvent(String? eventId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Navigating to event: $eventId')),
    );
  }

  void _navigateToTicket(String? eventId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Navigating to ticket for event: $eventId')),
    );
  }

  void _navigateToBuyTicket(String? eventId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Navigating to buy ticket for event: $eventId')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AE-LINK Example'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Deep Link Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _currentDeepLink != null
                ? _buildDeepLinkInfo(_currentDeepLink!)
                : const Text(
                    'No deep link received yet.\n\n'
                    'Try opening the app with a deep link URL:\n'
                    'allevents://event?event_id=123&utm_source=test',
                    style: TextStyle(color: Colors.grey),
                  ),
            const SizedBox(height: 32),
            const Text(
              'Device Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<String?>(
              future: Future.value(AeLinkSdk.getDeviceId()),
              builder: (context, snapshot) {
                return Text('Device ID: ${snapshot.data ?? "Loading..."}');
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                final link = await AeLinkSdk.forceCheckDeferredLink();
                if (link != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Deferred link found!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No deferred link found')),
                  );
                }
              },
              child: const Text('Force Check Deferred Link'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                AeLinkSdk.processDeepLink(
                  'allevents://event?event_id=12345&action=view_event&utm_source=manual&utm_campaign=test',
                );
              },
              child: const Text('Test Deep Link'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeepLinkInfo(DeepLinkData deepLink) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Link ID', deepLink.linkId),
            _buildInfoRow('Event ID', deepLink.eventId),
            _buildInfoRow('Action', deepLink.action),
            _buildInfoRow('Is Deferred', deepLink.isDeferred.toString()),
            if (deepLink.isDeferred)
              _buildInfoRow('Deferred Link ID', deepLink.deferredLinkId),
            _buildInfoRow('User Email', deepLink.userEmail),
            _buildInfoRow('Coupon Code', deepLink.couponCode),
            if (deepLink.utmParams.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('UTM Parameters:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...deepLink.utmParams.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text('  ${e.key}: ${e.value}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value ?? 'N/A',
              textAlign: TextAlign.end,
              style: TextStyle(color: value == null ? Colors.grey : Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up when app is closed
    AeLinkSdk.dispose();
    super.dispose();
  }
}
