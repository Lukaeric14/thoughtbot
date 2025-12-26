const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'https://backend-production-4605.up.railway.app';

export type Category = 'personal' | 'business';

export interface Thought {
  id: string;
  created_at: string;
  text: string;
  canonical_text: string | null;
  mention_count: number | null;
  capture_id: string | null;
  transcript: string | null;
  audio_url: string | null;
  category: Category | null;
}

export interface Task {
  id: string;
  created_at: string;
  title: string;
  canonical_title: string | null;
  due_date: string;
  status: 'open' | 'done' | 'cancelled';
  mention_count: number | null;
  last_updated_at: string;
  capture_id: string | null;
  transcript: string | null;
  category: Category | null;
}

export async function fetchThoughts(category?: Category): Promise<Thought[]> {
  const url = category
    ? `${API_BASE_URL}/api/thoughts?category=${category}`
    : `${API_BASE_URL}/api/thoughts`;
  const res = await fetch(url, {
    cache: 'no-store',
  });
  if (!res.ok) throw new Error('Failed to fetch thoughts');
  return res.json();
}

export async function fetchTasks(category?: Category): Promise<Task[]> {
  const url = category
    ? `${API_BASE_URL}/api/tasks?category=${category}`
    : `${API_BASE_URL}/api/tasks`;
  const res = await fetch(url, {
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
