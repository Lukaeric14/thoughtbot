const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'https://postgres-production-46d5.up.railway.app';

export interface Thought {
  id: string;
  created_at: string;
  text: string;
  canonical_text: string | null;
  capture_id: string | null;
  transcript: string | null;
}

export interface Task {
  id: string;
  created_at: string;
  title: string;
  canonical_title: string | null;
  due_date: string;
  status: 'open' | 'done' | 'cancelled';
  last_updated_at: string;
  capture_id: string | null;
  transcript: string | null;
}

export async function fetchThoughts(): Promise<Thought[]> {
  const res = await fetch(`${API_BASE_URL}/api/thoughts`, {
    cache: 'no-store',
  });
  if (!res.ok) throw new Error('Failed to fetch thoughts');
  return res.json();
}

export async function fetchTasks(): Promise<Task[]> {
  const res = await fetch(`${API_BASE_URL}/api/tasks`, {
    cache: 'no-store',
  });
  if (!res.ok) throw new Error('Failed to fetch tasks');
  return res.json();
}

export async function updateTaskStatus(taskId: string, status: 'open' | 'done' | 'cancelled'): Promise<Task> {
  const res = await fetch(`${API_BASE_URL}/api/tasks/${taskId}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ status }),
  });
  if (!res.ok) throw new Error('Failed to update task');
  return res.json();
}
