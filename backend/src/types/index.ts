export type ClassificationType = 'thought' | 'task_create' | 'task_update';
export type TaskStatus = 'open' | 'done' | 'cancelled';
export type TaskUpdateOperation = 'complete' | 'cancel' | 'postpone' | 'set_due_date' | 'rename';

export interface ThoughtPayload {
  text: string;
}

export interface TaskCreatePayload {
  title: string;
  due_date: string | null;
}

export interface TaskUpdatePayload {
  operation: TaskUpdateOperation;
  target_hint: string;
  new_due_date: string | null;
}

export interface ClassificationResult {
  type: ClassificationType;
  thought?: ThoughtPayload;
  task_create?: TaskCreatePayload;
  task_update?: TaskUpdatePayload;
}

export interface Capture {
  id: string;
  created_at: Date;
  audio_url: string | null;
  transcript: string | null;
  classification: ClassificationType | null;
  raw_llm_output: ClassificationResult | null;
}

export interface Thought {
  id: string;
  created_at: Date;
  text: string;
  canonical_text: string | null;
  capture_id: string | null;
}

export interface Task {
  id: string;
  created_at: Date;
  title: string;
  canonical_title: string | null;
  due_date: Date;
  status: TaskStatus;
  last_updated_at: Date;
  capture_id: string | null;
}
