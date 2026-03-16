import { Button } from '@/components/ui/button';
import { Plus } from 'lucide-react';

export default function Artists() {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold tracking-tight">Artists</h1>
        <Button>
          <Plus className="mr-2 h-4 w-4" />
          Add New
        </Button>
      </div>
      <div className="flex min-h-[40vh] items-center justify-center rounded-lg border border-dashed">
        <p className="text-sm text-muted-foreground">
          No artists yet. Add your first artist to get started.
        </p>
      </div>
    </div>
  );
}
