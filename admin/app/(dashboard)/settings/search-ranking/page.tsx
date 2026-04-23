import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { getRankingConfig } from '@/app/actions/search-ranking'
import SearchRankingForm from './search-ranking-form'

export default async function SearchRankingPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const config = await getRankingConfig()

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Search Ranking Weights</h1>
        <p className="mt-1 text-sm text-gray-500">
          Configure how merchants are ranked in Near Me results.
          Five factors are combined with adjustable weights.
        </p>
      </div>
      <SearchRankingForm config={config} />
    </div>
  )
}
