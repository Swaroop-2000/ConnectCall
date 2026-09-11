import re

with open("lib/screens/home/home_screen.dart", "r", encoding="utf-8") as f:
    text = f.read()

target = """              Text(
                label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 14),
              ),
      child: ListTile("""

replacement = """              Text(
                label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  final dynamic user;

  const _UserTile({required this.user});

  Future<void> _initiateCall(BuildContext context, String calleeId, String calleeName, String callType, String currentUserId, String currentUserName) async {
    
    // Fetch real-time status just before calling to ensure accuracy
    bool isOnline = user.isOnline;
    try {
      final doc = await FirebaseFirestore.instance.collection("users").doc(calleeId).get();
      if (doc.exists) {
        isOnline = doc.data()?["isOnline"] == true;
      }
    } catch (_) {}

    if (!isOnline && context.mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.orange),
          title: const Text("User Offline"),
          content: Text("$calleeName appears to be offline right now and may not answer. Do you still want to call them?"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
              ),
              child: const Text("Call Anyway"),
            ),
          ],
        ),
      );
      
      // If user dismissed dialog or clicked Cancel, stop the call
      if (proceed != true) return;
    }
    
    if (!context.mounted) return;

    final callId = FirebaseFirestore.instance.collection("calls").doc().id;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: callId,
          isCaller: true,
          callType: callType,
          callerId: currentUserId,
          callerName: currentUserName,
          calleeId: calleeId,
          calleeName: calleeName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveUserAsync = ref.watch(currentUserProvider);
    final authUser = ref.watch(authServiceProvider).currentUser;
    final currentUserName = liveUserAsync.value?.name ?? "Unknown";
    final currentUserId = authUser?.uid ?? "";
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile("""

if target in text:
    new_text = text.replace(target, replacement)
    with open("lib/screens/home/home_screen.dart", "w", encoding="utf-8") as f:
        f.write(new_text)
    print("Success")
else:
    print("Target not found")
