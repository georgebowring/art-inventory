import { useSession } from '@clerk/clerk-react';
import { useMemo } from 'react';
import { createClerkSupabaseClient } from '../lib/supabase';

export function useSupabase() {
  const { session } = useSession();

  const client = useMemo(() => {
    return createClerkSupabaseClient(async () => {
      return session?.getToken({ template: 'supabase' }) ?? null;
    });
  }, [session]);

  return client;
}
