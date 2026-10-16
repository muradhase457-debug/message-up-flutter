import 'package:flutter/material.dart';
import 'package:message_up/models/message_model.dart';
import 'package:message_up/utils/time_format.dart';
import 'package:message_up/widgets/tick_widget.dart';

/// A single chat bubble. Own messages are green (#D9FDD3) on the right,
/// others are white on the left. Long-press opens the message menu.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onReply,
    this.onForward,
    this.onStar,
    this.onDelete,
    this.onTapImage,
  });

  final Message message;
  final bool isMine;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onStar;
  final VoidCallback? onDelete;
  final VoidCallback? onTapImage;

  @override
  Widget build(BuildContext context) {
    final bubbleColor =
        isMine ? const Color(0xFFD9FDD3) : Colors.white;
    final align =
        isMine ? Alignment.centerRight : Alignment.centerLeft;
    return Align(
      alignment: align,
      child: GestureDetector(
        onLongPress: () => _showMenu(context),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(10),
              topRight: const Radius.circular(10),
              bottomLeft: Radius.circular(isMine ? 10 : 2),
              bottomRight: Radius.circular(isMine ? 2 : 10),
            ),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 1, offset: Offset(0, 1)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.forwarded)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forward, size: 13, color: Colors.grey),
                    SizedBox(width: 4),
                    Text('Forwarded',
                        style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey)),
                  ],
                ),
              if (message.replyToText != null &&
                  message.replyToText!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                      vertical: 4, horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: const Border(
                      left: BorderSide(
                          color: Color(0xFF25D366), width: 3),
                    ),
                  ),
                  child: Text(
                    message.replyToText!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54),
                  ),
                ),
              if (message.imageUrl != null &&
                  message.imageUrl!.isNotEmpty)
                GestureDetector(
                  onTap: onTapImage,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      message.imageUrl!,
                      width: 220,
                      fit: BoxFit.cover,
                      loadingBuilder: (ctx, child, progress) =>
                          progress == null
                              ? child
                              : const SizedBox(
                                  height: 140,
                                  child: Center(
                                      child: CircularProgressIndicator())),
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 120,
                        child: Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.grey)),
                      ),
                    ),
                  ),
                ),
              if (message.displayText.isNotEmpty)
                Text(
                  message.displayText,
                  style: TextStyle(
                    fontSize: 15,
                    fontStyle: message.deleted
                        ? FontStyle.italic
                        : FontStyle.normal,
                    color: message.deleted ? Colors.grey : Colors.black87,
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.starred)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.star,
                          size: 12, color: Colors.amber),
                    ),
                  Text(
                    formatMessageTime(message.createdAt),
                    style:
                        const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    TickWidget(
                        delivered: message.delivered, read: message.read),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(ctx);
                onReply?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(ctx);
                onForward?.call();
              },
            ),
            ListTile(
              leading: Icon(
                  message.starred ? Icons.star : Icons.star_border),
              title: Text(message.starred ? 'Unstar' : 'Star'),
              onTap: () {
                Navigator.pop(ctx);
                onStar?.call();
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}
