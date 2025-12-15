# Implementation Plan: Voice-First Thought & Task Capture System

## Architecture Overview

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

**Tech Stack**:
- **iOS**: Swift/SwiftUI, AVFoundation
- **Backend**: Node.js/Express, PostgreSQL (Railway)
- **APIs**: OpenAI Whisper (transcription), GPT-4o-mini (classification)

---

## Phase 1: Backend Foundation

### 1.1 Project Setup
- Initialize Node.js project in `/backend` directory
- Configure TypeScript for type safety
- Set up Express server with CORS
- Configure environment variables (OpenAI API key, database URL)
- Set up Railway deployment configuration

### 1.2 Database Schema
Create PostgreSQL tables:

```sql
-- captures: raw audio input log
CREATE TABLE captures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  audio_url TEXT,
  transcript TEXT,
  classification VARCHAR(20), -- 'thought' | 'task_create' | 'task_update'
  raw_llm_output JSONB
);

-- thoughts: non-actionable ideas
CREATE TABLE thoughts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  text TEXT NOT NULL,
  canonical_text TEXT, -- normalized for dedup
  capture_id UUID REFERENCES captures(id)
);

-- tasks: actionable commitments
CREATE TABLE tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  title TEXT NOT NULL,
  canonical_title TEXT, -- normalized for dedup/matching
  due_date DATE NOT NULL,
  status VARCHAR(20) DEFAULT 'open', -- 'open' | 'done' | 'cancelled'
  last_updated_at TIMESTAMPTZ DEFAULT NOW(),
  capture_id UUID REFERENCES captures(id)
);

-- indexes for task matching
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_due_date ON tasks(due_date);
CREATE INDEX idx_tasks_canonical ON tasks(canonical_title);
```

### 1.3 API Endpoints

**POST /api/captures**
- Accepts multipart/form-data with audio file
- Returns 202 Accepted immediately (fire-and-forget from client perspective)
- Processes asynchronously

---

## Phase 2: Processing Pipeline

### 2.1 Audio Upload & Storage
- Receive audio file (m4a/wav from iOS)
- Store in Railway's persistent storage or S3-compatible storage
- Create `captures` record with `audio_url`

### 2.2 Transcription Service
- Send audio to OpenAI Whisper API
- Update `captures.transcript`
- Handle errors gracefully (retry logic)

### 2.3 LLM Classification Service
- Build prompt with strict JSON schema enforcement
- Send transcript to GPT-4o-mini
- Parse and validate response

**Classification Prompt Structure**:
```
You are a classifier for a voice capture system. Given a transcript,
classify it as exactly ONE of: thought, task_create, task_update.

Rules:
- thought: Non-actionable observations, ideas, reflections
- task_create: Commitments to do something (has action verb)
- task_update: References completing, canceling, or rescheduling an existing task

Output ONLY valid JSON matching this schema:
{
  "type": "thought | task_create | task_update",
  "thought": { "text": "..." },
  "task_create": { "title": "...", "due_date": "YYYY-MM-DD | null" },
  "task_update": {
    "operation": "complete | cancel | postpone | set_due_date",
    "target_hint": "...",
    "new_due_date": "YYYY-MM-DD | null"
  }
}

Today's date: {current_date}
Transcript: "{transcript}"
```

### 2.4 Entity Creation/Update Logic

**For `thought`**:
- Create thought record with text
- Generate `canonical_text` (lowercase, strip punctuation)

**For `task_create`**:
- Extract title (convert to imperative form if needed)
- Parse due_date (default to today if null)
- Check for duplicates against open tasks from last 14 days
- Create task if not duplicate

**For `task_update`**:
- Query open tasks
- Match `target_hint` against `canonical_title` using similarity
- If confident match (>0.7 similarity): apply operation
- If no match: create new task from the update intent

### 2.5 Deduplication Logic
- Normalize text: lowercase, remove punctuation, stem common words
- Compare using Levenshtein distance or trigram similarity
- Threshold: 0.85 for exact match, 0.7 for likely match
- PostgreSQL `pg_trgm` extension for efficient similarity queries

---

## Phase 3: iOS App

### 3.1 Project Structure
```
thoughtbot/
├── App/
│   └── thoughtbotApp.swift
├── Views/
│   └── CaptureView.swift          # Main recording UI
├── Services/
│   ├── AudioRecorder.swift        # AVFoundation wrapper
│   ├── APIClient.swift            # Backend communication
│   └── CaptureQueue.swift         # Offline queue management
├── Models/
│   └── Capture.swift              # Data models
└── Utilities/
    └── Config.swift               # API endpoints, keys
```

### 3.2 Audio Recording Service
- Use `AVAudioRecorder` for high-quality audio capture
- Record in m4a format (good compression, Whisper compatible)
- Request microphone permissions
- Handle interruptions (phone calls, etc.)

### 3.3 Main UI (CaptureView)
**Design**: Single-screen, single-button interface

```
┌─────────────────────────┐
│                         │
│                         │
│                         │
│      ┌─────────┐        │
│      │         │        │
│      │   🎤    │        │  ← Tap to record
│      │         │        │     Hold to record
│      └─────────┘        │     Release to send
│                         │
│                         │
│                         │
└─────────────────────────┘
```

**Interaction States**:
- Idle: Gray microphone icon
- Recording: Red pulsing indicator, vibration feedback
- Uploading: Brief spinner (optional, can skip per PRD "no feedback")
- Done: Return to idle immediately

### 3.4 API Client
- POST audio to `/api/captures`
- Fire-and-forget (no waiting for response)
- Automatic retry on network failure
- Queue failed uploads for later

### 3.5 Offline Queue
- Persist failed uploads to UserDefaults/FileManager
- Retry when network becomes available
- Maximum retry attempts before discard (with local backup)

---

## Phase 4: Integration & Testing

### 4.1 End-to-End Flow Testing
- Record audio on device
- Verify transcription accuracy
- Verify classification accuracy
- Verify task/thought creation
- Verify task update matching

### 4.2 Edge Cases
- Empty/silent audio
- Background noise only
- Very long recordings (>2 min)
- Rapid successive captures
- Network disconnection mid-upload

---

## Implementation Order

1. **Backend: Database & API skeleton**
   - Set up Express server
   - Create database schema
   - Implement POST /api/captures endpoint (stub)

2. **Backend: Transcription integration**
   - Integrate Whisper API
   - Test with sample audio files

3. **Backend: Classification integration**
   - Implement GPT-4o-mini classification
   - Test with sample transcripts
   - Tune prompt for accuracy

4. **Backend: Entity logic**
   - Implement thought creation
   - Implement task creation with deduplication
   - Implement task update with matching

5. **iOS: Audio recording**
   - Implement AudioRecorder service
   - Test recording quality

6. **iOS: API integration**
   - Implement APIClient
   - Connect to backend

7. **iOS: UI**
   - Build CaptureView
   - Add recording states
   - Add haptic feedback

8. **iOS: Offline support**
   - Implement CaptureQueue
   - Test offline scenarios

9. **Deploy & Test**
   - Deploy backend to Railway
   - TestFlight build
   - End-to-end testing

---

## File Manifest

### Backend (to create in /backend)
```
/backend
├── package.json
├── tsconfig.json
├── .env.example
├── src/
│   ├── index.ts                 # Express server entry
│   ├── config.ts                # Environment config
│   ├── db/
│   │   ├── schema.sql           # Database schema
│   │   └── client.ts            # PostgreSQL client
│   ├── routes/
│   │   └── captures.ts          # /api/captures endpoint
│   ├── services/
│   │   ├── transcription.ts     # Whisper API integration
│   │   ├── classification.ts    # GPT-4o-mini integration
│   │   ├── taskMatcher.ts       # Task matching logic
│   │   └── deduplication.ts     # Deduplication logic
│   └── types/
│       └── index.ts             # TypeScript types
└── railway.json                 # Railway deployment config
```

### iOS App (to create/modify in /thoughtbot)
```
/thoughtbot/thoughtbot
├── App/
│   └── thoughtbotApp.swift      # (modify existing)
├── Views/
│   └── CaptureView.swift        # NEW
├── Services/
│   ├── AudioRecorder.swift      # NEW
│   ├── APIClient.swift          # NEW
│   └── CaptureQueue.swift       # NEW
├── Models/
│   └── Capture.swift            # NEW
└── Config.swift                 # NEW
```

---

## Key Design Decisions

1. **Fire-and-forget uploads**: Client sends audio and immediately returns to idle. No waiting for processing result.

2. **Backend-side transcription**: Using Whisper API server-side (not Apple Speech on-device) for better accuracy and consistency.

3. **Synchronous processing pipeline**: Transcription → Classification → Entity creation happens sequentially per capture. Can be made async with queues later if needed.

4. **Simple similarity matching**: Using PostgreSQL trigram similarity (`pg_trgm`) for task matching instead of embeddings. Simpler, sufficient for v1.

5. **Minimal UI**: Single button, no task list, no history view. Pure input primitive as per PRD.

---

## Questions Resolved

- **Backend**: Node.js/Express with PostgreSQL on Railway
- **Transcription**: OpenAI Whisper API
- **LLM**: OpenAI GPT-4o-mini
- **Platform**: iOS only for v1
