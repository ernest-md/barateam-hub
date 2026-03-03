import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm"

const SUPABASE_URL = "https://ceunhkqhskwnsoqyunze.supabase.co"
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNldW5oa3Foc2t3bnNvcXl1bnplIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI0NDQ0ODcsImV4cCI6MjA4ODAyMDQ4N30.qBGXYYQXlyQwFGeyaeMOtLPHrjBy-eU05AO37yLvi5o"

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)