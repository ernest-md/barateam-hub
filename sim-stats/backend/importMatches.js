import fetch from 'node-fetch'
import { supabase } from './supabase.js'

export async function importMatches() {
  console.log("🔄 Iniciando importación...")

  // 1️⃣ Obtener todos los devices desde la base de datos
  const { data: devices, error: deviceError } = await supabase
    .from('devices')
    .select('device_id, player_id')

  if (deviceError) {
    console.error("Error obteniendo devices:", deviceError)
    return
  }

  for (const device of devices) {
    const { device_id, player_id } = device

    console.log(`📥 Importando device: ${device_id}`)

    try {
      const response = await fetch(
        `https://api.cardkaizoku.com/matches?deviceId=${device_id}`
      )

      const matches = await response.json()

      if (!Array.isArray(matches)) {
        console.log("No hay partidas o formato incorrecto")
        continue
      }

      const formatted = matches.map(m => ({
        player_id: player_id,
        device_id: device_id,
        player_leader: m.playerLeader,
        opponent_leader: m.oppLeader,
        result: m.result,
        match_date: new Date(m.date),
        turn_number: m.turnNumber,
        turn_order: m.turnOrder === 1 ? 1 : 2
      }))

      // 🔥 Eliminar duplicados internos antes del upsert
        const uniqueMap = new Map()

        for (const match of formatted) {
        const key = `${match.device_id}_${match.match_date}_${match.opponent_leader}`
        if (!uniqueMap.has(key)) {
            uniqueMap.set(key, match)
        }
        }

const uniqueMatches = Array.from(uniqueMap.values())

    const { error: insertError } = await supabase
    .from('matches')
    .upsert(uniqueMatches, {
        onConflict: 'device_id,match_date,opponent_leader'
    })

      if (insertError) {
        console.error("Error insertando partidas:", insertError)
      } else {
        console.log(`✅ Device ${device_id} importado`)
      }

    } catch (err) {
      console.error("Error llamando a la API:", err)
    }
  }

  console.log("🏁 Importación finalizada")
}