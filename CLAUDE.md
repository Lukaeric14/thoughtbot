# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Thoughtbot is a voice-first thought and task capture system. Users speak into the iOS or Mac app, and the backend transcribes (Whisper API), classifies (GPT-4o-mini), and stores the input as either a thought (non-actionable idea) or task (scheduled commitment).

## Architecture

- **iOS App** (`thoughtbot/`): SwiftUI app with voice recording, uploads audio to backend
- **Mac App** (`thoughtbotMac/`): macOS companion app with same functionality
- **Backend** (`backend/`): Node.js/Express + TypeScript, deployed on Railway
- **Dashboard** (`dashboard/`): Next.js web dashboard for viewing thoughts/tasks
- **Database**: PostgreSQL on Railway

Audio flow: iOS/Mac records → Backend receives → Whisper transcribes → GPT-4o-mini classifies → PostgreSQL stores

## Common Commands

### Backend Development
```bash
cd backend
npm install           # Install dependencies
npm run dev          # Start dev server with tsx watch
npm run build        # Compile TypeScript
npm run db:migrate   # Run database migrations
```

### Dashboard Development
```bash
cd dashboard
npm install
npm run dev          # Start Next.js dev server
npm run build        # Production build
npm run lint         # Run ESLint
```

### iOS/Mac App
Open `thoughtbot.xcodeproj` in Xcode. Configure `Config.swift` with the appropriate `apiBaseURL` (localhost:3000 for dev, Railway URL for production).

## Key Backend Services

- `src/services/transcription.ts`: Whisper API integration
- `src/services/classification.ts`: GPT-4o-mini prompt for classifying transcripts into thought/task_create/task_update with category (personal/business)
- `src/services/taskMatcher.ts`: Matches task updates to existing tasks
- `src/services/embeddings.ts`: Semantic similarity for deduplication
- `src/services/semanticMatcher.ts`: Task matching using embeddings

## API Routes

- `POST /api/captures`: Upload audio file (multipart/form-data), returns capture ID
- `GET /api/captures/:id`: Get capture status and result
- `GET /api/thoughts`: List thoughts (supports `?category=personal|business&slim=true`)
- `GET /api/tasks`: List tasks (supports `?status=open|completed&category=personal|business&slim=true`)
- `PATCH /api/tasks/:id`: Update task (status, due_date)
- `DELETE /api/thoughts/:id`, `DELETE /api/tasks/:id`: Delete items

## Database Schema

Three main tables:
- `captures`: Raw audio log with transcripts and LLM output
- `thoughts`: Non-actionable ideas with category and mention_count
- `tasks`: Actionable commitments with due_date, status, category

PostgreSQL extensions: `uuid-ossp` (UUIDs), `pg_trgm` (trigram similarity for fuzzy matching)

## Environment Variables

Backend requires:
- `DATABASE_URL`: PostgreSQL connection string
- `OPENAI_API_KEY`: For Whisper and GPT-4o-mini APIs
- `NODE_ENV`: development/production
- `PORT`: Server port (default 3000)

## Classification Logic

Transcripts are classified as:
- **thought**: Non-actionable observations ("I think...", "Maybe we should...")
- **task_create**: New commitments ("I need to...", "Remind me to...")
- **task_update**: Modifications to existing tasks ("Done with...", "Postpone...")

Categories:
- **personal**: Personal life, family, health, hobbies
- **business**: Work, clients, professional tasks
