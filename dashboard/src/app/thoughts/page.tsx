import { fetchThoughts, type Category } from '@/lib/api'
import { ThoughtsList } from './thoughts-list'

export const dynamic = 'force-dynamic'

export default async function ThoughtsPage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string }>
}) {
  const params = await searchParams
  const category = (params.category as Category) || 'personal'
  const thoughts = await fetchThoughts(category)

  return (
    <div>
      <h1 className="text-3xl font-bold mb-8">
        {category === 'personal' ? 'Personal' : 'Business'} Thoughts
      </h1>
      <ThoughtsList thoughts={thoughts} />
    </div>
  )
}
