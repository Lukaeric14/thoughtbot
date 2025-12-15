'use client'

import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import { ChevronDown, ChevronUp } from 'lucide-react'
import type { Thought } from '@/lib/api'

function formatRelativeTime(dateString: string): string {
  const date = new Date(dateString)
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  const diffDays = Math.floor(diffMs / 86400000)

  if (diffMins < 1) return 'just now'
  if (diffMins < 60) return `${diffMins}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays < 7) return `${diffDays}d ago`
  return date.toLocaleDateString()
}

function ThoughtCard({ thought }: { thought: Thought }) {
  const [isOpen, setIsOpen] = useState(false)
  const hasTranscript = thought.transcript && thought.transcript !== thought.text

  return (
    <Card>
      <CardContent className="pt-6">
        <div className="space-y-3">
          <p className="font-semibold text-lg">{thought.text}</p>

          {hasTranscript && (
            <Collapsible open={isOpen} onOpenChange={setIsOpen}>
              <CollapsibleTrigger className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors">
                {isOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                {isOpen ? 'Hide transcript' : 'Show transcript'}
              </CollapsibleTrigger>
              <CollapsibleContent className="pt-2">
                <p className="text-sm text-muted-foreground bg-muted p-3 rounded-md">
                  {thought.transcript}
                </p>
              </CollapsibleContent>
            </Collapsible>
          )}

          <p className="text-xs text-muted-foreground">
            {formatRelativeTime(thought.created_at)}
          </p>
        </div>
      </CardContent>
    </Card>
  )
}

export function ThoughtsList({ thoughts }: { thoughts: Thought[] }) {
  if (thoughts.length === 0) {
    return (
      <div className="text-center py-12 text-muted-foreground">
        <p className="text-lg">No thoughts yet</p>
        <p className="text-sm">Use the app to capture your first thought</p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {thoughts.map((thought) => (
        <ThoughtCard key={thought.id} thought={thought} />
      ))}
    </div>
  )
}
