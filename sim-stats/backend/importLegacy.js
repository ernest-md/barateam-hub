import fs from 'fs'
import { parse } from 'csv-parse/sync'
import { supabase } from './supabase.js'

const DEVICE_ID = "3dd9a13cff0605adf53e0597449e87651bc7a77e"

async function importLegacy() {

  console.log("📂 Leyendo RAW_MATCHES.csv...")

  const fileContent = fs.readFileSync('../RAW_MATCHES.csv', 'utf8')

  const records = parse(fileContent, {
    columns: true,
    delimiter: ';',
    skip_empty_lines: true
  })

  console.log(`📊 ${records.length} partidas encontradas`)

  const formatted = records.map(r => ({
    device_id: DEVICE_ID,
    player_id: "e108b4f2-3084-4eda-8577-507c8c6c4a17", // Coquito
    player_leader: r.Leader,
    opponent_leader: r.OppLeader,
    result: r.Win === "1" ? "Won" : "Lost",
    match_date: new Date(r.Date),
    turn_number: null,
    turn_order: r.First === "1" ? 1 : 2
  }))

  // 🔥 eliminar duplicados internos
  const uniqueMap = new Map()

  for (const match of formatted) {
    const key = `${match.device_id}_${match.match_date}_${match.opponent_leader}`
    if (!uniqueMap.has(key)) {
      uniqueMap.set(key, match)
    }
  }

  const uniqueMatches = Array.from(uniqueMap.values())

  console.log(`🧹 ${uniqueMatches.length} partidas únicas tras limpiar duplicados`)

  const { error } = await supabase
    .from('matches')
    .upsert(uniqueMatches, {
      onConflict: 'device_id,match_date,opponent_leader'
    })

  if (error) {
    console.error("❌ Error insertando:", error)
  } else {
    console.log("✅ Importación legacy completada")
  }

  process.exit()
}

importLegacy()