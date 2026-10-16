import 'package:flutter/material.dart';

/// WhatsApp-style delivery ticks:
/// 1 grey tick = sent, 2 grey ticks = delivered, 2 blue ticks = read.
class TickWidget extends StatelessWidget {
  const TickWidget({
    super.key,
    this.delivered = false,
    this.read = false,
    this.size = 16,
  });

  final bool delivered;
  final bool read;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (read) {
      return Icon(Icons.done_all,
          size: size, color: const Color(0xFF53BDEB));
    }
    if (delivered) {
      return Icon(Icons.done_all, size: size, color: Colors.grey[500]);
    }
    return Icon(Icons.done, size: size, color: Colors.grey[500]);
  }
}
