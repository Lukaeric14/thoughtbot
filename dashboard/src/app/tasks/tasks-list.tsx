'use client'

import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import { ChevronDown, ChevronUp, Calendar } from 'lucide-react'
import { updateTaskStatus, type Task } from '@/lib/api'
import { cn } from '@/lib/utils'

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

function formatDueDate(dateString: string): string {
  const date = new Date(dateString)
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const dueDate = new Date(date)
  dueDate.setHours(0, 0, 0, 0)

  const diffDays = Math.floor((dueDate.getTime() - today.getTime()) / 86400000)

  if (diffDays === 0) return 'Today'
  if (diffDays === 1) return 'Tomorrow'
  if (diffDays === -1) return 'Yesterday'
  if (diffDays < -1) return `${Math.abs(diffDays)} days overdue`
  return date.toLocaleDateString()
}

function isOverdue(dateString: string): boolean {
  const date = new Date(dateString)
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  date.setHours(0, 0, 0, 0)
  return date < today
}

function TaskCard({ task, onStatusChange }: { task: Task; onStatusChange: (task: Task) => void }) {
  const [isOpen, setIsOpen] = useState(false)
  const [isUpdating, setIsUpdating] = useState(false)
  const hasTranscript = task.transcript && task.transcript !== task.title
  const isDone = task.status === 'done' || task.status === 'cancelled'

  const handleCheckChange = async (checked: boolean) => {
    setIsUpdating(true)
    try {
      const newStatus = checked ? 'done' : 'open'
      const updatedTask = await updateTaskStatus(task.id, newStatus)
      onStatusChange(updatedTask)
    } catch (error) {
      console.error('Failed to update task:', error)
    }
    setIsUpdating(false)
  }

  return (
    <Card className={cn(isDone && 'opacity-60')}>
      <CardContent className="pt-6">
        <div className="flex gap-4">
          <Checkbox
            checked={isDone}
            onCheckedChange={handleCheckChange}
            disabled={isUpdating}
            className="mt-1"
          />
          <div className="flex-1 space-y-3">
            <div className="flex items-center gap-2">
              <p className={cn(
                "font-semibold text-lg",
                isDone && "line-through text-muted-foreground"
              )}>
                {task.title}
              </p>
              {/* Mention count badge (only show if > 1) */}
              {task.mention_count && task.mention_count > 1 && (
                <span className="inline-flex items-center px-2 py-0.5 text-xs font-bold text-white bg-primary rounded-full">
                  x{task.mention_count}
                </span>
              )}
            </div>

            {hasTranscript && (
              <Collapsible open={isOpen} onOpenChange={setIsOpen}>
                <CollapsibleTrigger className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors">
                  {isOpen ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                  {isOpen ? 'Hide transcript' : 'Show transcript'}
                </CollapsibleTrigger>
                <CollapsibleContent className="pt-2">
                  <p className="text-sm text-muted-foreground bg-muted p-3 rounded-md">
                    {task.transcript}
                  </p>
                </CollapsibleContent>
              </Collapsible>
            )}

            <div className="flex items-center gap-4 text-xs text-muted-foreground">
              {!isDone && (
                <span className={cn(
                  "flex items-center gap-1",
                  isOverdue(task.due_date) && "text-destructive"
                )}>
                  <Calendar className="h-3 w-3" />
                  {formatDueDate(task.due_date)}
                </span>
              )}
              <span>{formatRelativeTime(task.created_at)}</span>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

export function TasksList({ initialTasks }: { initialTasks: Task[] }) {
  const [tasks, setTasks] = useState(initialTasks)

  const handleStatusChange = (updatedTask: Task) => {
    setTasks(tasks.map(t => t.id === updatedTask.id ? updatedTask : t))
  }

  if (tasks.length === 0) {
    return (
      <div className="text-center py-12 text-muted-foreground">
        <p className="text-lg">No tasks yet</p>
        <p className="text-sm">Use the app to capture your first task</p>
      </div>
    )
  }

  const openTasks = tasks.filter(t => t.status === 'open')
  const completedTasks = tasks.filter(t => t.status !== 'open')

  return (
    <div className="space-y-8">
      {openTasks.length > 0 && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-muted-foreground">Open ({openTasks.length})</h2>
          {openTasks.map((task) => (
            <TaskCard key={task.id} task={task} onStatusChange={handleStatusChange} />
          ))}
        </div>
      )}

      {completedTasks.length > 0 && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-muted-foreground">Completed ({completedTasks.length})</h2>
          {completedTasks.map((task) => (
            <TaskCard key={task.id} task={task} onStatusChange={handleStatusChange} />
          ))}
        </div>
      )}
    </div>
  )
}
