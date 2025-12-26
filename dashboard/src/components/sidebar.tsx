'use client'

import Link from 'next/link'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { cn } from '@/lib/utils'
import { Brain, CheckSquare, Zap, Home, Building2 } from 'lucide-react'
import type { Category } from '@/lib/api'

const navigation = [
  { name: 'Thoughts', href: '/thoughts', icon: Brain },
  { name: 'Tasks', href: '/tasks', icon: CheckSquare },
  { name: 'Actions', href: '/actions', icon: Zap },
]

export function Sidebar() {
  const pathname = usePathname()
  const router = useRouter()
  const searchParams = useSearchParams()
  const category = (searchParams.get('category') as Category) || 'personal'

  const toggleCategory = () => {
    const newCategory = category === 'personal' ? 'business' : 'personal'
    const params = new URLSearchParams(searchParams)
    params.set('category', newCategory)
    router.push(`${pathname}?${params.toString()}`)
  }

  return (
    <div className="flex h-full w-64 flex-col border-r bg-card">
      <div className="flex h-16 items-center justify-between border-b px-6">
        <h1 className="text-xl font-bold">Thoughtbot</h1>
        <button
          onClick={toggleCategory}
          className="flex items-center justify-center h-9 w-9 rounded-lg transition-colors bg-muted text-muted-foreground hover:bg-accent hover:text-accent-foreground"
          title={category === 'personal' ? 'Personal' : 'Business'}
        >
          {category === 'personal' ? (
            <Home className="h-5 w-5" />
          ) : (
            <Building2 className="h-5 w-5" />
          )}
        </button>
      </div>
      <nav className="flex-1 space-y-1 p-4">
        {navigation.map((item) => {
          const isActive = pathname.startsWith(item.href)
          const href = `${item.href}?category=${category}`
          return (
            <Link
              key={item.name}
              href={href}
              className={cn(
                'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground'
              )}
            >
              <item.icon className="h-5 w-5" />
              {item.name}
            </Link>
          )
        })}
      </nav>
    </div>
  )
}
