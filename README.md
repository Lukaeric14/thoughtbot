# Thoughtbot - Voice-First Thought & Task Capture

A voice-only input system that captures user intent and converts it into thoughts (non-committal ideas) or tasks (scheduled commitments).

## Architecture

```
┌─────────────────┐     ┌─────────────────────────────────────────┐
│   iOS App       │     │   Backend (Node.js/Express on Railway)  │
│   (SwiftUI)     │     │                                         │
│                 │     │  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
│  ┌───────────┐  │     │  │ Whisper │  │ GPT-4o  │  │ Postgres│ │
│  │ Record    │──┼────▶│  │   API   │─▶│  mini   │─▶│   DB    │ │
│  │ Button    │  │     │  └─────────┘  └─────────┘  └─────────┘ │
│  └───────────┘  │     │                                         │
└─────────────────┘     └─────────────────────────────────────────┘
```

## Setup

### Backend (Railway)

1. **Create Railway Project**
   ```bash
   cd backend
   npm install
   ```

2. **Set up PostgreSQL on Railway**
   - Create a new PostgreSQL service in Railway
   - Copy the `DATABASE_URL` connection string

3. **Configure Environment Variables**
   ```bash
   cp .env.example .env
   # Edit .env with your values:
   # - DATABASE_URL (from Railway PostgreSQL)
   # - OPENAI_API_KEY (from platform.openai.com)
   ```

4. **Run Database Migration**
   ```bash
   npm run db:migrate
   ```

5. **Deploy to Railway**
   ```bash
   # Connect your GitHub repo or use Railway CLI
   railway link
   railway up
   ```

6. **Set Production Environment Variables in Railway Dashboard**
   - `DATABASE_URL` - Auto-configured if using Railway PostgreSQL
   - `OPENAI_API_KEY` - Your OpenAI API key
   - `NODE_ENV` - `production`

### iOS App

1. **Open in Xcode**
   ```bash
   open thoughtbot.xcodeproj
   ```

2. **Update API URL**

   Edit `thoughtbot/Config.swift` and update `apiBaseURL` to your Railway deployment URL:
   ```swift
   static let apiBaseURL = "https://your-app.railway.app"
   ```

3. **Build & Run**
   - Select your target device/simulator
   - Press Cmd+R to build and run

### Local Development

1. **Start Backend**
   ```bash
   cd backend
   npm run dev
   ```

2. **iOS Simulator**
   - Keep `apiBaseURL` as `http://localhost:3000`
   - Run the app in Simulator

## Usage

1. **Tap** the microphone button to start recording
2. **Speak** your thought or task
3. **Tap again** to stop and send

The system will automatically:
- Transcribe your voice using Whisper API
- Classify as thought, task, or task update using GPT-4o-mini
- Store appropriately in the database

### Examples

**Thoughts** (non-actionable):
- "We should make more content for LinkedIn"
- "AI bootcamps are going to be oversaturated"

**Tasks** (creates new task):
- "I need to make a LinkedIn post today"
- "Post the LinkedIn update tomorrow"

**Task Updates** (modifies existing task):
- "LinkedIn post complete"
- "Postpone LinkedIn post for tomorrow"
- "No need to post today"

## Project Structure

```
thoughtbot/
├── backend/                    # Node.js/Express backend
│   ├── src/
│   │   ├── index.ts           # Express server entry
│   │   ├── config.ts          # Environment config
│   │   ├── db/
│   │   │   ├── schema.sql     # PostgreSQL schema
│   │   │   ├── client.ts      # Database client
│   │   │   └── migrate.ts     # Migration script
│   │   ├── routes/
│   │   │   └── captures.ts    # /api/captures endpoint
│   │   ├── services/
│   │   │   ├── transcription.ts    # Whisper API
│   │   │   ├── classification.ts   # GPT-4o-mini
│   │   │   ├── taskMatcher.ts      # Task CRUD
│   │   │   └── deduplication.ts    # Similarity matching
│   │   └── types/
│   │       └── index.ts       # TypeScript types
│   └── railway.json           # Railway deployment config
│
├── thoughtbot/                 # iOS SwiftUI app
│   ├── thoughtbotApp.swift    # App entry point
│   ├── Config.swift           # API configuration
│   ├── Info.plist             # Microphone permission
│   ├── Models/
│   │   └── Capture.swift      # Data models
│   ├── Services/
│   │   ├── AudioRecorder.swift    # AVFoundation wrapper
│   │   ├── APIClient.swift        # Backend communication
│   │   └── CaptureQueue.swift     # Offline queue
│   └── Views/
│       └── CaptureView.swift      # Main recording UI
│
└── thoughtbot.xcodeproj       # Xcode project
```

## API Reference

### POST /api/captures

Upload audio for processing.

**Request:**
- Content-Type: `multipart/form-data`
- Body: `audio` file (m4a, mp3, wav, webm)

**Response (202 Accepted):**
```json
{
  "id": "uuid",
  "status": "processing"
}
```

### GET /api/captures/:id

Get capture status (for debugging).

**Response:**
```json
{
  "id": "uuid",
  "created_at": "2024-01-01T00:00:00Z",
  "audio_url": "/uploads/file.m4a",
  "transcript": "transcribed text",
  "classification": "thought|task_create|task_update",
  "raw_llm_output": { ... }
}
```

## Database Schema

- **captures**: Raw audio input log with transcripts
- **thoughts**: Non-actionable ideas
- **tasks**: Actionable commitments with due dates and status
