import { fetchThoughts } from '@/lib/api'
import { ThoughtsList } from './thoughts-list'

export const dynamic = 'force-dynamic'

export default async function ThoughtsPage() {
  const thoughts = await fetchThoughts()

  return (
    <div>
      <h1 className="text-3xl font-bold mb-8">Thoughts</h1>
      <ThoughtsList thoughts={thoughts} />
    </div>
  )
}
