import { supabase } from './supabaseClient.js'

export async function getPlayers() {
  const { data, error } = await supabase
    .from('players')
    .select('id, name')
    .order('name')

  if (error) {
    console.error('Error cargando jugadores:', error)
    return []
  }

  return data
}

export async function getExpansions() {
  const { data, error } = await supabase
    .from('expansions')
    .select('*')
    .order('start_date')

  if (error) {
    console.error('Error cargando expansiones:', error)
    return []
  }

  return data
}

export async function getMatchesByPlayer(playerId) {
  const { data, error } = await supabase
    .from('matches')
    .select('*')
    .eq('player_id', playerId)

  if (error) {
    console.error('Error cargando partidas:', error)
    return []
  }

  return data
}