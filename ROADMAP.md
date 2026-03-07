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

- [x] **Search/filter entries** — search by text, filter by category, show only active items, view completed items
- [x] **Create entries directly** — add new brain entries from the app (not just voice capture)
- [x] **Edit session cards** — add edit button to HomeScreen thought cards so you can tweak a capture before it disappears into history
- [x] **Archive (swipe right)** — swipe right to archive entries (vs. swipe left to delete), plus an archive filter to browse archived items
- [x] **STT settings toggle** — settings switch for speech-to-text auto-send; driving mode that keeps mic hot and reads back results automatically
- [x] **Consolidate brain tools into becoming-mcp** — add brain_search, brain_recent, brain_get, brain_stats, brain_tags, brain_update, brain_create, brain_delete tools to the becoming MCP server (retire standalone brain-mcp). One MCP server, one auth token, full read+write.
- [x] **Offline queue** — capture thoughts when offline, sync when connection returns
- [x] **Notification reminders** — surface due-date entries as local notifications
- [x] **Quick actions from notification** — mark done, snooze, open entry directly
- [x] **Home screen widget** — at-a-glance today's actions + due items, with a mic button for instant voice capture straight from the widget

## Medium Term

- [ ] **GitHub Copilot SDK integration** — agentic actions from your phone:
  - **Study mode**: ask a scripture question on the fly, get cross-references and insights right from your phone
  - Bug fixes: describe a bug, get a PR draft
  - New features: describe what you want, kick off implementation
  - Code review: summarize open PRs, approve/comment from mobile
- [ ] **Multi-model support** — choose between local (LM Studio) and cloud models for classification
- [ ] **Rich text / markdown body** — format entry bodies with basic markdown
- [ ] **Entry linking** — connect related entries (e.g., action → project → idea)
- [ ] **Attachments** — photos, screenshots, voice memos attached to entries
- [ ] **Becoming-MCP → brain.exe direct connection** — becoming-mcp can optionally connect directly to brain.exe for semantic vector search and full entry access, even without ibeco.me relay. Maximum flexibility: use ibeco.me, brain.exe, or both.
- [ ] **Semantic search relay** — ibeco.me relays search queries to brain.exe's vector store when the agent is online, falling back to SQL text search when offline
- [ ] **brain.exe study document search** — index local study documents (markdown studies, lessons, talks) in brain.exe's vector store so scripture study content is searchable alongside brain entries. Fills the local search gap.

## Long Term

- [ ] **Proactive agent** — brain.exe learns your patterns and surfaces relevant entries at the right time
- [ ] **Calendar integration** — sync due dates with Google Calendar / device calendar
- [ ] **Habit tracking bridge** — connect brain actions to ibeco.me practices for accountability
- [ ] **Shared brains** — family/team brain spaces with shared entries and assignments
- [ ] **Copilot SDK self-healing** — brain.exe uses Copilot SDK to self-update, fix bugs on the fly, redeploy, and respond to feature requests across brain.exe, brain-app, and ibeco.me
- [ ] **Wear OS / Watch** — quick capture from your wrist

## Far Term — Play Store & Public Release

- [ ] **GitHub CI for Android builds** — automated APK/AAB builds on push (reference: games app CI)
- [ ] **Google Play Store listing** — publish brain-app to the Play Store for public download
- [ ] **Bring Your Own Key (BYOK)** — users supply their own OpenAI / Gemini / Claude API key for classification, no brain.exe required
- [ ] **Productize as a standalone app** — brain-app + ibeco.me as a public product anyone can use:
  - BYOK cloud AI classification (no GPU, no brain.exe)
  - Manual category assignment when no AI is available
  - Full CRUD, search, notifications, widget — all working against ibeco.me alone
  - Gradual upgrade path: start standalone → add brain.exe later for power features
- [ ] **Cloud AI classification** — support OpenAI / Gemini / Claude API keys as an alternative to brain.exe + local GPU, so anyone can use classification without hosting their own model
- [ ] **Standalone mode (no brain.exe)** — brain-app + ibeco.me features that work without brain.exe:
  - ibeco.me-hosted classification using a cloud AI provider
  - Manual category assignment when no AI is available
  - Full CRUD, search, notifications, widget — all working against ibeco.me alone
  - Gradual upgrade path: start standalone → add brain.exe later for power features
