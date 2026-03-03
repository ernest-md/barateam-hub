import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {

    const { playerId } = await req.json()

    if (!playerId) {
      return new Response(
        JSON.stringify({ error: "Missing playerId" }),
        { status: 400, headers: corsHeaders }
      )
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const { data: devices, error: deviceError } = await supabase
      .from("devices")
      .select("device_id")
      .eq("player_id", playerId)

    if (deviceError) throw deviceError
    if (!devices || devices.length === 0) {
      return new Response(
        JSON.stringify({ inserted: 0 }),
        { headers: corsHeaders }
      )
    }

    let insertedCount = 0

    for (const device of devices) {

      const response = await fetch(
        `https://api.cardkaizoku.com/matches?deviceId=${device.device_id}`
      )

      if (!response.ok) continue

      const matches = await response.json()
      if (!Array.isArray(matches)) continue

      for (const match of matches) {

        const normalizedDate = new Date(match.date).toISOString()
        const externalId = `${device.device_id}_${normalizedDate}`

        const { data: existing } = await supabase
          .from("matches")
          .select("id")
          .eq("external_id", externalId)
          .maybeSingle()

        if (existing) continue

        await supabase.from("matches").insert({
          player_id: playerId,
          device_id: device.device_id,
          external_id: externalId,
          match_date: normalizedDate,
          player_leader: match.playerLeader,
          opponent_leader: match.oppLeader,
          result: match.result,
          turn_number: match.turnNumber,
          turn_order: match.turnOrder === 0 ? 2 : 1
        })

        insertedCount++
      }
    }

    return new Response(
      JSON.stringify({ inserted: insertedCount }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json"
        }
      }
    )

  } catch (error: any) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: corsHeaders }
    )
  }
})