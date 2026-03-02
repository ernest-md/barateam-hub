import { getPlayers, getMatchesByPlayer, getExpansions } from './api.js'

const playerSelect = document.getElementById("playerSelect")
const expansionSelect = document.getElementById("expansionSelect")

let allMatches = []
let allExpansions = []
let currentFilteredMatches = []

async function init() {

  const players = await getPlayers()

  players.forEach(player => {
    const option = document.createElement("option")
    option.value = player.id
    option.textContent = player.name
    playerSelect.appendChild(option)
  })

  const expansions = await getExpansions()
  allExpansions = expansions

  const allOption = document.createElement("option")
  allOption.value = "all"
  allOption.textContent = "Todas"
  expansionSelect.appendChild(allOption)

  expansions.forEach(exp => {
    const option = document.createElement("option")
    option.value = exp.id
    option.textContent = exp.name
    expansionSelect.appendChild(option)
  })

  if (players.length > 0) {
    await loadPlayer(players[0].id)
  }
}

async function loadPlayer(playerId) {
  allMatches = await getMatchesByPlayer(playerId)
  calculateStats()
}

function calculateStats() {

  let filteredMatches = [...allMatches]

  const selectedExpansion = expansionSelect.value

  if (selectedExpansion !== "all") {
    const expansion = allExpansions.find(e => e.id === selectedExpansion)

    if (expansion) {
      const start = new Date(expansion.start_date)
      const end = new Date(expansion.end_date)

      filteredMatches = filteredMatches.filter(m => {
        const matchDate = new Date(m.match_date)
        return matchDate >= start && matchDate <= end
      })
    }
  }

  currentFilteredMatches = filteredMatches
  document.getElementById("leaderDetail").innerHTML = ""

  const total = filteredMatches.length
  const wins = filteredMatches.filter(m => m.result === "Won").length
  const losses = total - wins
  const winRate = total > 0 ? ((wins / total) * 100).toFixed(1) : 0

  document.getElementById("total").textContent = total
  document.getElementById("wins").textContent = wins
  document.getElementById("losses").textContent = losses
  document.getElementById("wr").textContent = winRate + "%"

  buildLeaderStats(filteredMatches)
  buildGlobalMatchups(filteredMatches)
}

function buildLeaderStats(matches) {

  const container = document.getElementById("leaderStats")
  container.innerHTML = ""

  const leaderMap = {}

  matches.forEach(m => {

    if (!leaderMap[m.player_leader]) {
      leaderMap[m.player_leader] = {
        games: 0,
        wins: 0,
        matchups: {}
      }
    }

    const leader = leaderMap[m.player_leader]

    leader.games++
    if (m.result === "Won") leader.wins++

    if (!leader.matchups[m.opponent_leader]) {
      leader.matchups[m.opponent_leader] = { games: 0, wins: 0 }
    }

    leader.matchups[m.opponent_leader].games++
    if (m.result === "Won") {
      leader.matchups[m.opponent_leader].wins++
    }
  })

  Object.entries(leaderMap).forEach(([leaderCode, data]) => {

    const losses = data.games - data.wins
    const wr = data.games > 0
      ? ((data.wins / data.games) * 100).toFixed(1)
      : 0

    const validMatchups = Object.entries(data.matchups)
      .filter(([_, m]) => m.games >= 3)
      .map(([opp, m]) => ({
        opp,
        wr: m.wins / m.games
      }))

    let fav = "-"
    let desf = "-"

    if (validMatchups.length > 0) {

    validMatchups.sort((a,b) => b.wr - a.wr)
    const best = validMatchups[0]

    validMatchups.sort((a,b) => a.wr - b.wr)
    const worst = validMatchups[0]

    fav = `
        <div style="display:flex; flex-direction:column; align-items:center;">
        <img src="https://res.cloudinary.com/dlbhgbxbf/image/upload/v1767894619/${best.opp}_jp.png" width="40">
        <span style="font-size:12px;">${(best.wr * 100).toFixed(1)}%</span>
        </div>
    `

    desf = `
        <div style="display:flex; flex-direction:column; align-items:center;">
        <img src="https://res.cloudinary.com/dlbhgbxbf/image/upload/v1767894619/${worst.opp}_jp.png" width="40">
        <span style="font-size:12px;">${(worst.wr * 100).toFixed(1)}%</span>
        </div>
    `
    }

    const row = document.createElement("tr")
    row.style.cursor = "pointer"
    row.style.borderBottom = "1px solid #eee"
    row.onclick = () => window.selectLeader(leaderCode)

    row.innerHTML = `
      <td>
        <img src="https://res.cloudinary.com/dlbhgbxbf/image/upload/v1767894619/${leaderCode}_jp.png" width="45">
      </td>
      <td><strong>${leaderCode}</strong></td>
      <td>${data.games}</td>
      <td>${data.wins}</td>
      <td>${losses}</td>
      <td>${wr}%</td>
      <td>${fav}</td>
      <td>${desf}</td>
    `

    container.appendChild(row)
  })
}

function buildGlobalMatchups(matches) {

  const winContainer = document.getElementById("topWins")
  const lossContainer = document.getElementById("topLosses")

  winContainer.innerHTML = ""
  lossContainer.innerHTML = ""

  const globalMap = {}

  matches.forEach(m => {

    if (!globalMap[m.opponent_leader]) {
      globalMap[m.opponent_leader] = { games: 0, wins: 0 }
    }

    globalMap[m.opponent_leader].games++
    if (m.result === "Won") globalMap[m.opponent_leader].wins++
  })

  const array = Object.entries(globalMap).map(([code, data]) => ({
    code,
    games: data.games,
    wins: data.wins,
    losses: data.games - data.wins
  }))

  const topWins = [...array]
    .sort((a,b) => b.wins - a.wins)
    .slice(0,4)

  const topLosses = [...array]
    .sort((a,b) => b.losses - a.losses)
    .slice(0,4)

  // 🔹 TABLA VICTORIAS
  topWins.forEach(item => {

    const tr = document.createElement("tr")

    tr.innerHTML = `
      <td>
        <img src="https://res.cloudinary.com/dlbhgbxbf/image/upload/v1767894619/${item.code}_jp.png" width="50">
      </td>
      <td>${item.wins}</td>
      <td>${item.games}</td>
    `

    winContainer.appendChild(tr)
  })

  // 🔹 TABLA DERROTAS
  topLosses.forEach(item => {

    const tr = document.createElement("tr")

    tr.innerHTML = `
      <td>
        <img src="https://res.cloudinary.com/dlbhgbxbf/image/upload/v1767894619/${item.code}_jp.png" width="50">
      </td>
      <td>${item.losses}</td>
      <td>${item.games}</td>
    `

    lossContainer.appendChild(tr)
  })
}

window.selectLeader = function(leaderCode) {
  buildLeaderDetail(leaderCode)
}

function buildLeaderDetail(leaderCode) {

  const container = document.getElementById("leaderDetail")
  container.innerHTML = ""

  const matches = currentFilteredMatches.filter(m => m.player_leader === leaderCode)

  if (matches.length === 0) return

  const total = matches.length
  const wins = matches.filter(m => m.result === "Won").length
  const losses = total - wins
  const wr = ((wins / total) * 100).toFixed(1)

  const firstMatches = matches.filter(m => m.turn_order === 1)
  const secondMatches = matches.filter(m => m.turn_order === 2)

  const wrFirst = firstMatches.length > 0
    ? ((firstMatches.filter(m => m.result === "Won").length / firstMatches.length) * 100).toFixed(1)
    : "-"

  const wrSecond = secondMatches.length > 0
    ? ((secondMatches.filter(m => m.result === "Won").length / secondMatches.length) * 100).toFixed(1)
    : "-"

  const matchupMap = {}

  matches.forEach(m => {

    if (!matchupMap[m.opponent_leader]) {
      matchupMap[m.opponent_leader] = {
        games: 0,
        wins: 0,
        firstGames: 0,
        firstWins: 0,
        secondGames: 0,
        secondWins: 0
      }
    }

    const entry = matchupMap[m.opponent_leader]

    entry.games++
    if (m.result === "Won") entry.wins++

    if (m.turn_order === 1) {
      entry.firstGames++
      if (m.result === "Won") entry.firstWins++
    }

    if (m.turn_order === 2) {
      entry.secondGames++
      if (m.result === "Won") entry.secondWins++
    }
  })

  const matchupArray = Object.entries(matchupMap)
    .map(([code, data]) => {

      const wr = (data.wins / data.games) * 100

      const wrFirst = data.firstGames > 0
        ? (data.firstWins / data.firstGames) * 100
        : null

      const wrSecond = data.secondGames > 0
        ? (data.secondWins / data.secondGames) * 100
        : null

      return {
        code,
        games: data.games,
        wins: data.wins,
        losses: data.games - data.wins,
        wr: wr.toFixed(1),
        firstGames: data.firstGames,
        wrFirst: wrFirst !== null ? wrFirst.toFixed(1) : "-",
        secondGames: data.secondGames,
        wrSecond: wrSecond !== null ? wrSecond.toFixed(1) : "-"
      }
    })
    .sort((a,b) => b.games - a.games)

  let matchupsHTML = ""

  matchupArray.forEach(m => {
    matchupsHTML += `
      <div style="margin-bottom:15px;">
        <img src="https://res.cloudinary.com/dlbhgbxbf/image/upload/v1767894619/${m.code}_jp.png" width="50">
        <div>
          Partidas: ${m.games} |
          Victorias: ${m.wins} |
          Derrotas: ${m.losses} |
          WR: ${m.wr}%
          <br>
          First: ${m.firstGames} | WR: ${m.wrFirst}%
          <br>
          Second: ${m.secondGames} | WR: ${m.wrSecond}%
        </div>
      </div>
    `
  })

  container.innerHTML = `
    <h3>Detalle líder ${leaderCode}</h3>

    <div style="display:flex; align-items:center; gap:15px;">
      <img src="https://res.cloudinary.com/dlbhgbxbf/image/upload/v1767894619/${leaderCode}_jp.png" width="80">
      <div>
        Partidas: ${total} <br>
        Victorias: ${wins} <br>
        Derrotas: ${losses} <br>
        WR: ${wr}% <br>
        WR First: ${wrFirst}% <br>
        WR Second: ${wrSecond}%
      </div>
    </div>

    <hr>
    <h4>Matchups</h4>
    ${matchupsHTML}
  `
}

playerSelect.addEventListener("change", (e) => {
  loadPlayer(e.target.value)
})

expansionSelect.addEventListener("change", () => {
  calculateStats()
})

init()