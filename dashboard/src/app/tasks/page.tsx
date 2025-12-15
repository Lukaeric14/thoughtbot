import { fetchTasks } from '@/lib/api'
import { TasksList } from './tasks-list'

export const dynamic = 'force-dynamic'

export default async function TasksPage() {
  const tasks = await fetchTasks()

  return (
    <div>
      <h1 className="text-3xl font-bold mb-8">Tasks</h1>
      <TasksList initialTasks={tasks} />
    </div>
  )
}
