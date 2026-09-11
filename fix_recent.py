import re

with open("lib/screens/contacts/contacts_screen.dart", "r", encoding="utf-8") as f:
    text = f.read()

target = """    return recentAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('RECENT',
                  style: textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant)),
            ),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: contacts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final contact = contacts[i];"""

replacement = """    return recentAsync.when(
      data: (contacts) {
        // Strict Filter: Only show recent users if they still exist and are valid in allUsers
        final filteredContacts = contacts.where((c) {
          final uid = c['uid'] as String? ?? '';
          return allUsers.any((u) => u.uid == uid);
        }).toList();

        if (filteredContacts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('RECENT',
                  style: textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant)),
            ),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: filteredContacts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final contact = filteredContacts[i];"""

if target in text:
    text = text.replace(target, replacement)
    with open("lib/screens/contacts/contacts_screen.dart", "w", encoding="utf-8") as f:
        f.write(text)
    print("Success")
else:
    print("Target not found")
