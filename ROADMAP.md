# Brain App Roadmap

The vision: a pocket-sized brain that captures thoughts, learns from you, and increasingly acts on your behalf.

## Completed

- [x] Voice capture → brain.exe classification via relay
- [x] TTS readback of classification results
- [x] Brain entry list with category badges, status, done toggle
- [x] Swipe-to-delete with confirmation
- [x] Full entry editing (title, body, category, status, due date, next action, tags)
- [x] Relay mode (ibeco.me) and direct LAN mode (brain.exe)
- [x] CRUD through both relay and direct connections
- [x] Connection status indicator
- [x] Pull-to-refresh

## Near Term

- [ ] **Search/filter entries** — search by text, filter by category, show only active items
- [ ] **Create entries directly** — add new brain entries from the app (not just voice capture)
- [ ] **Offline queue** — capture thoughts when offline, sync when connection returns
- [ ] **Notification reminders** — surface due-date entries as local notifications
- [ ] **Quick actions from notification** — mark done, snooze, open entry directly

## Medium Term

- [ ] **GitHub Copilot SDK integration** — agentic actions from your phone:
  - Study on the fly: ask a scripture question, get cross-references and insights
  - Bug fixes: describe a bug, get a PR draft
  - New features: describe what you want, kick off implementation
  - Code review: summarize open PRs, approve/comment from mobile
- [ ] **Multi-model support** — choose between local (LM Studio) and cloud models for classification
- [ ] **Rich text / markdown body** — format entry bodies with basic markdown
- [ ] **Entry linking** — connect related entries (e.g., action → project → idea)
- [ ] **Attachments** — photos, screenshots, voice memos attached to entries

## Long Term

- [ ] **Proactive agent** — brain.exe learns your patterns and surfaces relevant entries at the right time
- [ ] **Calendar integration** — sync due dates with Google Calendar / device calendar
- [ ] **Habit tracking bridge** — connect brain actions to ibeco.me practices for accountability
- [ ] **Shared brains** — family/team brain spaces with shared entries and assignments
- [ ] **Widget** — Android/iOS home screen widget showing today's actions and due items
- [ ] **Wear OS / Watch** — quick capture from your wrist
