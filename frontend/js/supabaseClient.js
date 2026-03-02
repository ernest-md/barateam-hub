import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm'

const SUPABASE_URL = 'https://ceunhkqhskwnsoqyunze.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_9h9RnRhobEifi9SQQkhwQA_kyyqi-hN'

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)