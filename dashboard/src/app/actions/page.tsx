import { Zap } from 'lucide-react'

export default function ActionsPage() {
  return (
    <div>
      <h1 className="text-3xl font-bold mb-8">Actions</h1>
      <div className="text-center py-12 text-muted-foreground">
        <Zap className="h-12 w-12 mx-auto mb-4" />
        <p className="text-lg">Actions coming soon</p>
        <p className="text-sm">This is where automated actions will appear</p>
      </div>
    </div>
  )
}
