import { fetchTasks, type Category } from '@/lib/api'
import { TasksList } from './tasks-list'

export const dynamic = 'force-dynamic'

export default async function TasksPage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string }>
}) {
  const params = await searchParams
  const category = (params.category as Category) || 'personal'
  const tasks = await fetchTasks(category)

  return (
    <div>
      <h1 className="text-3xl font-bold mb-8">
        {category === 'personal' ? 'Personal' : 'Business'} Tasks
      </h1>
      <TasksList initialTasks={tasks} />
    </div>
  )
}
