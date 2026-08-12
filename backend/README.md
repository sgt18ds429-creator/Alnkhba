# EliteRadIq backend

This is the production API contract used by the Flutter app. It has no npm
runtime dependencies and requires Node.js 20 or newer.

## Required deployment order

1. Apply all SQL files in `../supabase/migrations/` in filename order.
2. Set the variables from `.env.example` in the Render service dashboard.
3. Set the Render root directory to `backend` and the start command to
   `npm start`.
4. Never place `SUPABASE_SERVICE_ROLE_KEY` or `GEMINI_API_KEY` in Flutter,
   source control, a screenshot, or a client-visible build variable.
5. Verify `GET /health`, then exercise activation, chat, transcription, TTS
   and reporting with a dedicated test account.

`GOOGLE_TTS_API_KEY` must be a server-only key authorized for the official
Google Cloud Text-to-Speech API. Restrict it to that API and to the backend's
deployment environment.

The API validates the bearer activation token against Supabase before any AI
request. The `systemPrompt` field sent by an older client is deliberately
ignored; room instructions are selected on the server.

For abuse resistance, also apply an IP-based rate limit at Render/Cloudflare or
a Supabase Edge gateway. The in-process limiter is only a second layer and does
not coordinate across multiple server instances.
