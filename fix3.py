import re

with open("lib/screens/call/call_screen.dart", "r", encoding="utf-8") as f:
    text = f.read()

# 1. Imports
if "import '../../services/user_service.dart';" not in text:
    text = text.replace("import '../../services/calling_service.dart';", "import '../../services/calling_service.dart';\nimport '../../services/user_service.dart';\nimport '../../widgets/common_button.dart';")

# 2. Build Method logic
target_build = """  @override
  Widget build(BuildContext context) {
    final isVideo   = widget.callType == 'video';
    final otherName = widget.isCaller ? widget.calleeName : widget.callerName;"""

replacement_build = """  @override
  Widget build(BuildContext context) {
    final isVideo   = widget.callType == 'video';
    final otherName = widget.isCaller ? widget.calleeName : widget.callerName;
    
    final allUsersAsync = ref.watch(allUsersProvider);
    final otherUserList = allUsersAsync.value?.where((u) => u.name == otherName).toList();
    final otherPhotoUrl = (otherUserList != null && otherUserList.isNotEmpty) ? otherUserList.first.photoUrl : null;"""
text = text.replace(target_build, replacement_build)

# 3. Avatar replacing
target_avatar = """                      child: CircleAvatar(
                        radius: 58,
                        backgroundColor: Colors.deepPurple,
                        child: Text(
                          otherName.isNotEmpty
                              ? otherName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                              fontSize: 46, color: Colors.white),
                        ),
                      ),"""

replacement_avatar = """                      child: AvatarCircle(
                        radius: 58,
                        name: otherName,
                        photoUrl: otherPhotoUrl,
                      ),"""
text = text.replace(target_avatar, replacement_avatar)

# 4. Control Bar Background
target_control = """            Positioned(
              bottom: 28,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08)),
                ),"""

replacement_control = """            Positioned(
              bottom: 28,
              left: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
                  ],
                ),"""
text = text.replace(target_control, replacement_control)

with open("lib/screens/call/call_screen.dart", "w", encoding="utf-8") as f:
    f.write(text)
print("CallScreen patched")
