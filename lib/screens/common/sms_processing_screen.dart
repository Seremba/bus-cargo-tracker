import 'package:flutter/material.dart';

import 'outbound_messages_screen.dart';

class SmsProcessingScreen extends StatelessWidget {
  const SmsProcessingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const OutboundMessagesScreen(
      channelFilter: 'sms',
      title: 'SMS Processing',
    );
  }
}