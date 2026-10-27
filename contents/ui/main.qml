import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.LocalStorage
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.icon: Qt.resolvedUrl("../images/pokeball.svg")

    compactRepresentation: Item {
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: Kirigami.Units.iconSizes.smallMedium

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: root.expanded = !root.expanded

            Kirigami.Icon {
                anchors.fill: parent
                source: Plasmoid.icon
            }
        }
    }

    fullRepresentation: Rectangle {
        id: popup
        implicitWidth: 210
        implicitHeight: 570
        
        property bool isDarkMode: {
            const bg = Kirigami.Theme.backgroundColor
            const luminance = (bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114)
            return luminance < 0.5
        }

        color: isDarkMode ? "#181818" : Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.largeSpacing
        border.color: isDarkMode ? "#333333" : "#111111"
        border.width: 2
        clip: true

        property string pokemonName: ""
        property string pokemonId: ""
        property string spriteUrl: ""
        property string shinyUrl: ""
        property string animatedUrl: ""
        property string animatedShinyUrl: ""
        property string heightText: ""
        property string weightText: ""
        property string flavorText: ""
        property string errorText: ""
        property string statusText: ""
        property var types: []
        property var typeDefenses: []
        property var stats: []
        property var evolutionRoot: null
        property var speciesNames: []
        property var searchSuggestions: []
        property bool searchEdited: false
        property int totalEvYield: 0
        property int lookupId: 0
        
        property var categorizedMoves: ({})
        property string selectedGeneration: ""
        property var availableGenerations: []
        property var learnableMoves: []

        // Sleek Auto-Saving Team Builder State
        property int activeTeamSlot: 1
        property var currentTeam: []
        property int selectedMemberIndex: -1
        property var teamWeaknesses: []
        property var teamOffensiveCoverage: []

        // Item Database & Search State
        property var itemNames: []
        property var itemSuggestions: []
        property string suggestionError: ""

        Component.onCompleted: {
            initTeamDatabase()
            loadPokemon("charmander")
            loadSpeciesNames()
            loadItemNames()
        }

        function getDatabase() {
            return LocalStorage.openDatabaseSync("TipsyDexTeamsDB", "1.0", "Persistent Pokemon Teams", 1000000)
        }

        function initTeamDatabase() {
            try {
                const db = getDatabase()
                db.transaction(function(tx) {
                    tx.executeSql('CREATE TABLE IF NOT EXISTS team_slots (slot INTEGER PRIMARY KEY, data TEXT);')
                })
                loadTeamSlot(1)
            } catch (e) {
                console.log("DB Error: " + e)
            }
        }

        function loadItemNames() {
            const xhr = new XMLHttpRequest()
            xhr.open("GET", "https://pokeapi.co/api/v2/item?limit=2000")
            xhr.setRequestHeader("Accept", "application/json")
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        const response = JSON.parse(xhr.responseText)
                        itemNames = response.results.map(function (entry) {
                            return entry.name
                        })
                    } catch (e) {}
                }
            }
            xhr.send()
        }

        function updateItemSuggestions(input) {
            const query = input.trim().toLowerCase().replace(/\s+/g, "-")
            if (query.length < 2) {
                itemSuggestions = []
                return
            }
            itemSuggestions = itemNames.filter(function (name) {
                return name.indexOf(query) === 0
            }).slice(0, 5)
        }

        function updateSuggestions(input) {
            if (!searchEdited) {
                searchSuggestions = []
                return
            }
            const query = input.trim().toLowerCase().replace(/\s+/g, "-")
            if (query.length < 2) {
                searchSuggestions = []
                return
            }
            searchSuggestions = speciesNames.filter(function (name) {
                return name.indexOf(query) === 0
            }).slice(0, 7)
        }

        function calculateTeamAnalysis() {
            if (!currentTeam || currentTeam.length === 0) {
                teamWeaknesses = []
                teamOffensiveCoverage = []
                return
            }

            let typeWeaknessMap = {
                "Normal": [], "Fire": [], "Water": [], "Electric": [], "Grass": [], "Ice": [],
                "Fighting": [], "Poison": [], "Ground": [], "Flying": [], "Psychic": [], "Bug": [],
                "Rock": [], "Ghost": [], "Dragon": [], "Dark": [], "Steel": [], "Fairy": []
            }

            let typeCoverageMap = {
                "Normal": [], "Fire": [], "Water": [], "Electric": [], "Grass": [], "Ice": [],
                "Fighting": [], "Poison": [], "Ground": [], "Flying": [], "Psychic": [], "Bug": [],
                "Rock": [], "Ghost": [], "Dragon": [], "Dark": [], "Steel": [], "Fairy": []
            }

            const weakChart = {
                "Normal": ["Fighting"],
                "Fire": ["Water", "Ground", "Rock"],
                "Water": ["Electric", "Grass"],
                "Electric": ["Ground"],
                "Grass": ["Fire", "Ice", "Poison", "Flying", "Bug"],
                "Ice": ["Fire", "Fighting", "Rock", "Steel"],
                "Fighting": ["Flying", "Psychic", "Fairy"],
                "Poison": ["Ground", "Psychic"],
                "Ground": ["Water", "Grass", "Ice"],
                "Flying": ["Electric", "Ice", "Rock"],
                "Psychic": ["Bug", "Ghost", "Dark"],
                "Bug": ["Fire", "Flying", "Rock"],
                "Rock": ["Water", "Grass", "Fighting", "Ground", "Steel"],
                "Ghost": ["Ghost", "Dark"],
                "Dragon": ["Ice", "Dragon", "Fairy"],
                "Dark": ["Fighting", "Bug", "Fairy"],
                "Steel": ["Fire", "Fighting", "Ground"],
                "Fairy": ["Poison", "Steel"]
            }

            const offenseChart = {
                "Normal": [],
                "Fire": ["Grass", "Ice", "Bug", "Steel"],
                "Water": ["Fire", "Ground", "Rock"],
                "Electric": ["Water", "Flying"],
                "Grass": ["Water", "Ground", "Rock"],
                "Ice": ["Grass", "Ground", "Flying", "Dragon"],
                "Fighting": ["Normal", "Ice", "Rock", "Dark", "Steel"],
                "Poison": ["Grass", "Fairy"],
                "Ground": ["Fire", "Electric", "Poison", "Rock", "Steel"],
                "Flying": ["Grass", "Fighting", "Bug"],
                "Psychic": ["Fighting", "Poison"],
                "Bug": ["Grass", "Psychic", "Dark"],
                "Rock": ["Fire", "Ice", "Flying", "Bug"],
                "Ghost": ["Psychic", "Ghost"],
                "Dragon": ["Dragon"],
                "Dark": ["Psychic", "Ghost"],
                "Steel": ["Ice", "Rock", "Fairy"],
                "Fairy": ["Fighting", "Dragon", "Dark"]
            }

            for (let i = 0; i < currentTeam.length; ++i) {
                const member = currentTeam[i]
                const mTypes = member.types || []
                let memberWeakTypes = {}

                for (let t = 0; t < mTypes.length; ++t) {
                    let tName = titleCase(mTypes[t])
                    let weaknesses = weakChart[tName] || []
                    for (let w = 0; w < weaknesses.length; ++w) {
                        memberWeakTypes[weaknesses[w]] = true
                    }
                }

                for (let wType in memberWeakTypes) {
                    if (typeWeaknessMap[wType]) {
                        typeWeaknessMap[wType].push(member.name)
                    }
                }

                // Base coverage on assigned moves' types
                const moves = member.moves || []
                if (moves.length > 0) {
                    for (let m = 0; m < moves.length; ++m) {
                        let mType = moves[m].moveType ? titleCase(moves[m].moveType) : ""
                        let superEffectiveAgainst = offenseChart[mType] || []
                        for (let s = 0; s < superEffectiveAgainst.length; ++s) {
                            let target = superEffectiveAgainst[s]
                            if (typeCoverageMap[target]) {
                                let entryName = member.name + " (" + moves[m].name + ")"
                                if (typeCoverageMap[target].indexOf(entryName) < 0) {
                                    typeCoverageMap[target].push(entryName)
                                }
                            }
                        }
                    }
                } else {
                    // Fallback to member's own type if no moves assigned yet
                    for (let t = 0; t < mTypes.length; ++t) {
                        let tName = titleCase(mTypes[t])
                        let superEffectiveAgainst = offenseChart[tName] || []
                        for (let s = 0; s < superEffectiveAgainst.length; ++s) {
                            let target = superEffectiveAgainst[s]
                            if (typeCoverageMap[target]) {
                                let entryName = member.name + " (" + tName + ")"
                                if (typeCoverageMap[target].indexOf(entryName) < 0) {
                                    typeCoverageMap[target].push(entryName)
                                }
                            }
                        }
                    }
                }
            }

            let weakRes = []
            for (let typeName in typeWeaknessMap) {
                if (typeWeaknessMap[typeName].length > 0) {
                    weakRes.push({
                        name: typeName,
                        count: typeWeaknessMap[typeName].length,
                        pokemonList: typeWeaknessMap[typeName].join(", "),
                        color: typeColor(typeName),
                        textColor: typeTextColor(typeName)
                    })
                }
            }
            weakRes.sort(function(a, b) { return b.count - a.count })
            teamWeaknesses = weakRes

            let covRes = []
            for (let typeName in typeCoverageMap) {
                if (typeCoverageMap[typeName].length > 0) {
                    covRes.push({
                        name: typeName,
                        count: typeCoverageMap[typeName].length,
                        sourcesList: typeCoverageMap[typeName].join(", "),
                        color: typeColor(typeName),
                        textColor: typeTextColor(typeName)
                    })
                }
            }
            covRes.sort(function(a, b) { return b.count - a.count })
            teamOffensiveCoverage = covRes
        }

        function syncSelectionWithLoadedPokemon() {
            if (!pokemonName)
                return
            if (selectedMemberIndex >= 0 && selectedMemberIndex < currentTeam.length) {
                if (currentTeam[selectedMemberIndex].name.toLowerCase() === pokemonName.toLowerCase())
                    return
            }
            for (let i = 0; i < currentTeam.length; ++i) {
                if (currentTeam[i].name.toLowerCase() === pokemonName.toLowerCase()) {
                    selectedMemberIndex = i
                    return
                }
            }
            selectedMemberIndex = -1
        }

        function loadTeamSlot(slotNum) {
            activeTeamSlot = slotNum
            try {
                const db = getDatabase()
                db.transaction(function(tx) {
                    const rs = tx.executeSql('SELECT data FROM team_slots WHERE slot = ?;', [slotNum])
                    if (rs.rows.length > 0) {
                        currentTeam = JSON.parse(rs.rows.item(0).data || "[]")
                    } else {
                        currentTeam = []
                    }
                })
            } catch (e) {
                currentTeam = []
            }
            syncSelectionWithLoadedPokemon()
            calculateTeamAnalysis()
        }

        function saveCurrentTeam() {
            try {
                const db = getDatabase()
                db.transaction(function(tx) {
                    tx.executeSql('INSERT OR REPLACE INTO team_slots (slot, data) VALUES (?, ?);',
                        [activeTeamSlot, JSON.stringify(currentTeam)])
                })
                calculateTeamAnalysis()
            } catch (e) {
                console.log("Save Error: " + e)
            }
        }

        function addPokemonToTeam() {
            if (!pokemonName || currentTeam.length >= 6)
                return
            let nextTeam = currentTeam.slice()
            let cleanSlug = pokemonName.toLowerCase().replace(/\s+/g, "-")
            nextTeam.push({
                name: pokemonName,
                types: JSON.parse(JSON.stringify(types)),
                sprite: spriteUrl.length > 0 ? spriteUrl : spriteForName(cleanSlug),
                fallbackSprite: spriteForName(cleanSlug),
                item: "",
                moves: []
            })
            currentTeam = nextTeam
            selectedMemberIndex = currentTeam.length - 1
            errorText = ""
            saveCurrentTeam()
        }

        function removePokemonFromTeam(idx) {
            if (idx < 0 || idx >= currentTeam.length)
                return
            let nextTeam = currentTeam.slice()
            nextTeam.splice(idx, 1)
            currentTeam = nextTeam
            syncSelectionWithLoadedPokemon()
            saveCurrentTeam()
        }

        function updateActiveMemberItem(itemName) {
            if (selectedMemberIndex < 0 || selectedMemberIndex >= currentTeam.length)
                return
            let nextTeam = JSON.parse(JSON.stringify(currentTeam))
            nextTeam[selectedMemberIndex].item = itemName
            currentTeam = nextTeam
            saveCurrentTeam()
        }

        function addMoveToActiveMember(moveObj) {
            if (selectedMemberIndex < 0 || selectedMemberIndex >= currentTeam.length)
                return

            let nextTeam = JSON.parse(JSON.stringify(currentTeam))
            let member = nextTeam[selectedMemberIndex]

            if (member.name.toLowerCase() !== pokemonName.toLowerCase()) {
                return
            }

            if (!member.moves)
                member.moves = []
            if (member.moves.length >= 4)
                return
            for (let i = 0; i < member.moves.length; ++i) {
                if (member.moves[i].name === moveObj.name)
                    return
            }
            member.moves.push({
                name: moveObj.name,
                power: moveObj.power,
                accuracy: moveObj.accuracy,
                description: moveObj.description,
                bgColor: moveObj.bgColor,
                classLabel: moveObj.classLabel,
                method: moveObj.method,
                moveType: moveObj.moveType || ""
            })
            currentTeam = nextTeam
            saveCurrentTeam()
        }

        function removeMoveFromActiveMember(moveIdx) {
            if (selectedMemberIndex < 0 || selectedMemberIndex >= currentTeam.length)
                return
            let nextTeam = JSON.parse(JSON.stringify(currentTeam))
            nextTeam[selectedMemberIndex].moves.splice(moveIdx, 1)
            currentTeam = nextTeam
            saveCurrentTeam()
        }

        function selectGeneration(genName) {
            if (!genName || !categorizedMoves[genName])
                return
            selectedGeneration = genName
            learnableMoves = categorizedMoves[genName]
        }

        function titleCase(value) {
            return value.split("-").map(function (part) {
                return part.length ? part.charAt(0).toUpperCase() + part.slice(1) : part
            }).join(" ")
        }

        function spriteForName(name) {
            return "https://img.pokemondb.net/sprites/home/normal/" + name.toLowerCase().replace(/\s+/g, "-") + ".png"
        }

        function typeColor(typeName) {
            const colors = {
                normal: "#A8A77A", fire: "#EE8130", water: "#6390F0", electric: "#F7D02C",
                grass: "#7AC74C", ice: "#96D9D6", fighting: "#C22E28", poison: "#A33EA1",
                ground: "#E2BF65", flying: "#A98FF3", psychic: "#F95587", bug: "#A6B91A",
                rock: "#B6A136", ghost: "#735797", dragon: "#6F35FC", dark: "#705746",
                steel: "#B7B7CE", fairy: "#D685AD"
            }
            return colors[typeName.toLowerCase()] || "#777777"
        }

        function typeTextColor(typeName) {
            return ["electric", "ice", "ground", "steel", "normal", "fairy"].indexOf(typeName.toLowerCase()) >= 0
                ? "#171717" : "#ffffff"
        }

        function loadTypeDefenses(typeEntries, requestId) {
            const matchups = [
                "normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
                "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"
            ].map(function (name) {
                return { name: name, multiplier: 1 }
            })
            if (!typeEntries.length) {
                typeDefenses = []
                return
            }

            const typeDetails = new Array(typeEntries.length)
            let remaining = typeEntries.length
            for (let i = 0; i < typeEntries.length; ++i) {
                requestJson(typeEntries[i].type.url, requestId, function (detail) {
                    typeDetails[i] = detail
                    remaining -= 1
                    if (remaining > 0)
                        return

                    for (let d = 0; d < typeDetails.length; ++d) {
                        const relations = typeDetails[d].damage_relations
                        for (let m = 0; m < matchups.length; ++m) {
                            const attackType = matchups[m].name
                            if (relations.no_damage_from.some(function (entry) { return entry.name === attackType }))
                                matchups[m].multiplier = 0
                            else if (relations.double_damage_from.some(function (entry) { return entry.name === attackType }))
                                matchups[m].multiplier *= 2
                            else if (relations.half_damage_from.some(function (entry) { return entry.name === attackType }))
                                matchups[m].multiplier *= 0.5
                        }
                    }
                    typeDefenses = matchups.filter(function (entry) {
                        return entry.multiplier !== 1
                    }).map(function (entry) {
                        return {
                            name: titleCase(entry.name),
                            multiplier: entry.multiplier,
                            color: typeColor(entry.name),
                            textColor: typeTextColor(entry.name)
                        }
                    })
                })
            }
        }

        function requestJson(url, requestId, onSuccess) {
            const xhr = new XMLHttpRequest()
            xhr.open("GET", url)
            xhr.setRequestHeader("Accept", "application/json")
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return
                if (requestId !== popup.lookupId)
                    return
                if (xhr.status < 200 || xhr.status >= 300) {
                    popup.statusText = ""
                    popup.errorText = "Could not load Pokémon data (HTTP " + xhr.status + ")."
                    return
                }
                try {
                    onSuccess(JSON.parse(xhr.responseText))
                } catch (error) {
                    popup.statusText = ""
                    popup.errorText = "The Pokémon data could not be read."
                }
            }
            xhr.onerror = function () {
                if (requestId !== popup.lookupId)
                    return
                popup.statusText = ""
                popup.errorText = "Network error. Check your connection and try again."
            }
            xhr.send()
        }

        function loadSpeciesNames() {
            const xhr = new XMLHttpRequest()
            xhr.open("GET", "https://pokeapi.co/api/v2/pokemon-species?limit=2000")
            xhr.setRequestHeader("Accept", "application/json")
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return
                if (xhr.status < 200 || xhr.status >= 300) {
                    popup.suggestionError = "Suggestions unavailable."
                    return
                }
                try {
                    const response = JSON.parse(xhr.responseText)
                    popup.speciesNames = response.results.map(function (entry) {
                        return entry.name
                    })
                    popup.suggestionError = ""
                    popup.updateSuggestions(searchField.text)
                } catch (error) {
                    popup.suggestionError = "Suggestions unavailable."
                }
            }
            xhr.onerror = function () {
                popup.suggestionError = "Suggestions unavailable."
            }
            xhr.send()
        }

        function parseEvolution(node) {
            const result = {
                name: node.species.name,
                spriteUrl: "https://img.pokemondb.net/sprites/home/normal/" + node.species.name + ".png",
                fallbackSpriteUrl: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/"
                    + node.species.url.split("/").filter(Boolean).pop() + ".png",
                requirements: (node.evolution_details || []).map(function (detail) {
                    return {
                        level: detail.min_level || 0,
                        item: detail.item ? detail.item.name : "",
                        heldItem: detail.held_item ? detail.held_item.name : "",
                        trigger: detail.trigger ? detail.trigger.name : "",
                        happiness: detail.min_happiness || 0,
                        timeOfDay: detail.time_of_day || "",
                        location: detail.location ? detail.location.name : "",
                        knownMove: detail.known_move ? detail.known_move.name : "",
                        knownMoveType: detail.known_move_type ? detail.known_move_type.name : "",
                        affection: detail.min_affection || 0,
                        beauty: detail.min_beauty || 0,
                        gender: detail.gender || 0,
                        partySpecies: detail.party_species ? detail.party_species.name : "",
                        partyType: detail.party_type ? detail.party_type.name : "",
                        tradeSpecies: detail.trade_species ? detail.trade_species.name : "",
                        relativeStats: detail.relative_physical_stats === null ? null : detail.relative_physical_stats,
                        rain: detail.needs_overworld_rain || false,
                        multiplayer: detail.needs_multiplayer || false,
                        upsideDown: detail.turn_upside_down || false
                    }
                }),
                children: []
            }
            for (let i = 0; i < node.evolves_to.length; ++i)
                result.children.push(parseEvolution(node.evolves_to[i]))
            return result
        }

        function loadPokemon(input, targetSlotIndex) {
            let normalized = input.trim().toLowerCase()
            if (normalized.startsWith("#")) {
                normalized = parseInt(normalized.substring(1), 10).toString()
            } else if (/^\d+$/.test(normalized)) {
                normalized = parseInt(normalized, 10).toString()
            } else {
                normalized = normalized.replace(/\s+/g, "-")
            }
            if (!normalized || normalized === "NaN")
                return

            lookupId += 1
            const requestId = lookupId
            statusText = "Looking up " + titleCase(normalized) + "…"
            errorText = ""
            pokemonName = ""
            pokemonId = ""
            types = []
            typeDefenses = []
            stats = []
            evolutionRoot = null
            searchSuggestions = []
            searchEdited = false
            totalEvYield = 0
            spriteUrl = ""
            shinyUrl = ""
            animatedUrl = ""
            animatedShinyUrl = ""
            flavorText = ""
            
            categorizedMoves = {}
            selectedGeneration = ""
            availableGenerations = []
            learnableMoves = []

            requestJson("https://pokeapi.co/api/v2/pokemon/" + encodeURIComponent(normalized), requestId, function (pokemon) {
                pokemonName = titleCase(pokemon.name)
                pokemonId = "#" + String(pokemon.id).padStart(4, "0")
                heightText = (pokemon.height / 10).toFixed(1) + " m"
                weightText = (pokemon.weight / 10).toFixed(1) + " kg"
                types = pokemon.types.map(function (entry) {
                    return titleCase(entry.type.name)
                })
                loadTypeDefenses(pokemon.types, requestId)
                
                const statAbbrMap = {
                    "hp": "HP",
                    "attack": "Atk",
                    "defense": "Def",
                    "special-attack": "Sp.Atk",
                    "special-defense": "Sp.Def",
                    "speed": "Speed"
                }

                stats = pokemon.stats.map(function (entry) {
                    return {
                        name: statAbbrMap[entry.stat.name] || titleCase(entry.stat.name),
                        base: entry.base_stat,
                        ev: entry.effort
                    }
                })
                let evTotal = 0
                for (let i = 0; i < stats.length; ++i) {
                    evTotal += stats[i].ev
                }
                totalEvYield = evTotal

                if (targetSlotIndex !== undefined && targetSlotIndex >= 0 && targetSlotIndex < currentTeam.length) {
                    selectedMemberIndex = targetSlotIndex
                } else {
                    syncSelectionWithLoadedPokemon()
                }
                
                const versionToGenMap = {
                    "red-blue": "Gen 1", "yellow": "Gen 1",
                    "gold-silver": "Gen 2", "crystal": "Gen 2",
                    "ruby-sapphire": "Gen 3", "emerald": "Gen 3", "firered-leafgreen": "Gen 3", "colosseum": "Gen 3", "xd": "Gen 3",
                    "diamond-pearl": "Gen 4", "platinum": "Gen 4", "heartgold-soulsilver": "Gen 4",
                    "black-white": "Gen 5", "black-2-white-2": "Gen 5",
                    "x-y": "Gen 6", "omega-ruby-alpha-sapphire": "Gen 6",
                    "sun-moon": "Gen 7", "ultra-sun-ultra-moon": "Gen 7", "lets-go-pikachu-lets-go-eevee": "Gen 7",
                    "sword-shield": "Gen 8", "brilliant-diamond-shining-pearl": "Gen 8", "legends-arceus": "Gen 8",
                    "scarlet-violet": "Gen 9"
                }

                let tempCategorized = {
                    "Gen 1": [], "Gen 2": [], "Gen 3": [],
                    "Gen 4": [], "Gen 5": [], "Gen 6": [],
                    "Gen 7": [], "Gen 8": [], "Gen 9": []
                }

                let seenPerGen = {
                    "Gen 1": {}, "Gen 2": {}, "Gen 3": {},
                    "Gen 4": {}, "Gen 5": {}, "Gen 6": {},
                    "Gen 7": {}, "Gen 8": {}, "Gen 9": {}
                }

                let pendingMovesCount = 0

                for (let m = 0; m < pokemon.moves.length; ++m) {
                    let entry = pokemon.moves[m]
                    let moveName = titleCase(entry.move.name.replace(/-/g, " "))
                    let moveUrl = entry.move.url

                    for (let d = 0; d < entry.version_group_details.length; ++d) {
                        let detail = entry.version_group_details[d]
                        let genName = versionToGenMap[detail.version_group.name]

                        if (genName) {
                            let methodRaw = detail.move_learn_method.name
                            let level = detail.level_learned_at || 0

                            if (seenPerGen[genName][moveName]) {
                                if (methodRaw === "level-up" && level > 0) {
                                    let existingObj = tempCategorized[genName].find(function(item) { return item.name === moveName })
                                    if (existingObj && existingObj.level === 0) {
                                        existingObj.method = "Level Up"
                                        existingObj.level = level
                                        existingObj.displayText = moveName + " · Lv. " + level
                                    }
                                }
                                continue
                            }

                            seenPerGen[genName][moveName] = true
                            pendingMovesCount++

                            (function(targetGen, mvName, learnMethod, lvl, url) {
                                const mxhr = new XMLHttpRequest()
                                mxhr.open("GET", url)
                                mxhr.setRequestHeader("Accept", "application/json")
                                mxhr.onreadystatechange = function () {
                                    if (mxhr.readyState !== XMLHttpRequest.DONE) return
                                    let classColor = "#a8a878"
                                    let classType = "Status"
                                    let mType = "Normal"
                                    let pwr = "-"
                                    let acc = "-"
                                    let desc = "No description available."

                                    if (mxhr.status >= 200 && mxhr.status < 300) {
                                        try {
                                            let moveDetails = JSON.parse(mxhr.responseText)
                                            if (moveDetails.power !== null && moveDetails.power !== undefined) pwr = moveDetails.power
                                            if (moveDetails.accuracy !== null && moveDetails.accuracy !== undefined) acc = moveDetails.accuracy + "%"
                                            if (moveDetails.type && moveDetails.type.name) {
                                                mType = titleCase(moveDetails.type.name)
                                                classColor = typeColor(moveDetails.type.name)
                                            }
                                            
                                            if (moveDetails.flavor_text_entries) {
                                                for (let f = 0; f < moveDetails.flavor_text_entries.length; ++f) {
                                                    if (moveDetails.flavor_text_entries[f].language.name === "en") {
                                                        desc = moveDetails.flavor_text_entries[f].flavor_text.replace(/[\n\f\r]/g, " ")
                                                        break
                                                    }
                                                }
                                            }

                                            if (moveDetails.damage_class) {
                                                let className = moveDetails.damage_class.name
                                                if (className === "physical") classType = "Physical"
                                                else if (className === "special") classType = "Special"
                                            }
                                        } catch (e) {}
                                    }

                                    let formattedDisplay = mvName
                                    if (learnMethod === "level-up" && lvl > 0) {
                                        formattedDisplay = mvName + " · Lv. " + lvl
                                    }

                                    targetGen.push({
                                        name: mvName,
                                        displayText: formattedDisplay,
                                        method: titleCase(learnMethod.replace(/-/g, " ")),
                                        level: lvl,
                                        power: pwr,
                                        accuracy: acc,
                                        description: desc,
                                        bgColor: classColor,
                                        classLabel: classType,
                                        moveType: mType
                                    })

                                    pendingMovesCount--
                                    if (pendingMovesCount === 0) {
                                        sortAndFinalizeAllGenerations()
                                    }
                                }
                                mxhr.send()
                            })(tempCategorized[genName], moveName, methodRaw, level, moveUrl)
                        }
                    }
                }

                if (pendingMovesCount === 0) {
                    sortAndFinalizeAllGenerations()
                }

                function sortAndFinalizeAllGenerations() {
                    let gens = []
                    for (let i = 1; i <= 9; ++i) {
                        let g = "Gen " + i
                        if (tempCategorized[g].length > 0) {
                            tempCategorized[g].sort(function(a, b) {
                                let aHasLevel = (a.level > 0 || a.method.toLowerCase().includes("level"));
                                let bHasLevel = (b.level > 0 || b.method.toLowerCase().includes("level"));

                                if (aHasLevel && bHasLevel) {
                                    return a.level - b.level;
                                }
                                if (aHasLevel) {
                                    return -1;
                                }
                                if (bHasLevel) {
                                    return 1;
                                }
                                return a.name.localeCompare(b.name);
                            });
                            gens.push(g)
                        }
                    }
                    categorizedMoves = tempCategorized
                    availableGenerations = gens
                    if (gens.length > 0) {
                        selectGeneration(gens[gens.length - 1])
                    }
                }

                const speciesName = pokemon.species.name
                spriteUrl = (pokemon.sprites && pokemon.sprites.front_default)
                    ? pokemon.sprites.front_default
                    : "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/" + pokemon.id + ".png"
                shinyUrl = (pokemon.sprites && pokemon.sprites.front_shiny)
                    ? pokemon.sprites.front_shiny
                    : "https://img.pokemondb.net/sprites/home/shiny/" + speciesName + ".png"
                animatedUrl = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/showdown/" + pokemon.id + ".gif"
                animatedShinyUrl = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/showdown/shiny/" + pokemon.id + ".gif"
                
                requestJson(pokemon.species.url, requestId, function (species) {
                    const entries = species.flavor_text_entries || []
                    let flavor = ""
                    for (let i = 0; i < entries.length; ++i) {
                        if (entries[i].language.name === "en") {
                            flavor = entries[i].flavor_text.replace(/[\n\f\r]/g, " ")
                            break
                        }
                    }
                    flavorText = flavor
                    requestJson(species.evolution_chain.url, requestId, function (chain) {
                        evolutionRoot = parseEvolution(chain.chain)
                        statusText = ""
                    })
                })
            })
        }

        function evolutionPaths(node, path, output) {
            if (!node)
                return output
            const nextPath = path.concat([node])
            if (node.children.length === 0) {
                output.push(nextPath)
                return output
            }
            for (let i = 0; i < node.children.length; ++i)
                evolutionPaths(node.children[i], nextPath, output)
            return output
        }

        function shortRequirement(requirements) {
            if (!requirements || requirements.length === 0)
                return "Trade"
            const first = requirements[0]
            if (first.level)
                return "Lv. " + first.level
            if (first.item)
                return titleCase(first.item)
            if (first.heldItem)
                return titleCase(first.heldItem)
            if (first.happiness)
                return "Friendship"
            if (first.trigger === "trade")
                return "Trade"
            return titleCase(first.trigger)
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: topPanel
                Layout.fillWidth: true
                Layout.preferredHeight: topContent.implicitHeight + Kirigami.Units.largeSpacing + 8
                color: "#e53935"
                radius: popup.radius

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: popup.radius
                    color: topPanel.color
                }

                ColumnLayout {
                    id: topContent
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    anchors.topMargin: Kirigami.Units.largeSpacing
                    anchors.bottomMargin: 8
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading {
                            text: "TipsyDex"
                            level: 2
                            Layout.fillWidth: true
                            color: "#ffffff"
                        }

                        Row {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter

                            ToolButton {
                                icon.name: "weather-clear"
                                display: AbstractButton.IconOnly
                                Accessible.name: "Light Mode"
                                ToolTip.text: "Light Mode"
                                opacity: popup.isDarkMode ? 0.4 : 1.0
                                implicitWidth: 28
                                implicitHeight: 28
                                onClicked: popup.isDarkMode = false
                            }

                            ToolButton {
                                icon.name: "weather-clear-night"
                                display: AbstractButton.IconOnly
                                Accessible.name: "Dark Mode"
                                ToolTip.text: "Dark Mode"
                                opacity: popup.isDarkMode ? 1.0 : 0.4
                                implicitWidth: 28
                                implicitHeight: 28
                                onClicked: popup.isDarkMode = true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            text: "charmander"
                            leftPadding: 38
                            placeholderText: "Search Name or #ID…"
                            focus: true
                            palette.text: popup.isDarkMode ? "#ffffff" : "#171717"
                            palette.placeholderText: popup.isDarkMode ? "#aaaaaa" : "#666666"
                            palette.base: popup.isDarkMode ? "#2d2d2d" : "#ffffff"
                            onAccepted: popup.loadPokemon(text)
                            onTextEdited: {
                                popup.searchEdited = true
                                suggestionTimer.restart()
                            }

                            Image {
                                anchors.left: parent.left
                                anchors.leftMargin: Kirigami.Units.smallSpacing
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                source: popup.spriteUrl
                                visible: popup.spriteUrl.length > 0
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                            }
                        }

                        ToolButton {
                            icon.name: "search"
                            display: AbstractButton.IconOnly
                            Accessible.name: "Search Pokémon"
                            ToolTip.text: "Search"
                            onClicked: {
                                suggestionTimer.stop()
                                popup.loadPokemon(searchField.text)
                            }
                        }
                    }

                    Timer {
                        id: suggestionTimer
                        interval: 180
                        onTriggered: popup.updateSuggestions(searchField.text)
                    }

                    ListView {
                        id: suggestionList
                        Layout.fillWidth: true
                        Layout.preferredHeight: popup.searchSuggestions.length
                            ? Math.min(popup.searchSuggestions.length, 5) * 34 : 0
                        visible: popup.searchSuggestions.length > 0
                        clip: true
                        model: popup.searchSuggestions
                        delegate: ItemDelegate {
                            required property string modelData
                            width: suggestionList.width
                            height: 34
                            background: Rectangle {
                                color: popup.isDarkMode ? "#2a2a2a" : "#ffffff"
                            }
                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Image {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    source: popup.spriteForName(modelData)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: popup.titleCase(modelData)
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    color: popup.isDarkMode ? "#ffffff" : "#171717"
                                }
                            }
                            onClicked: {
                                suggestionTimer.stop()
                                searchField.text = modelData
                                popup.loadPokemon(modelData)
                            }
                        }
                    }

                    Label {
                        visible: popup.suggestionError.length > 0 && searchField.text.length >= 2
                        text: popup.suggestionError
                        Layout.fillWidth: true
                        color: "#ffffff"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }

                    Label {
                        visible: popup.statusText.length > 0
                        text: popup.statusText
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        color: "#ffffff"
                    }

                    Label {
                        visible: popup.errorText.length > 0
                        text: popup.errorText
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: "#ffffff"
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 2
                    color: popup.isDarkMode ? "#333333" : "#111111"
                }
            }

            ScrollView {
                id: bodyScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: popup.pokemonName.length > 0
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                background: Rectangle {
                    color: popup.isDarkMode ? "#181818" : "#ffffff"
                }

                ColumnLayout {
                    width: bodyScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Heading {
                                text: popup.pokemonName
                                level: 2
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                color: popup.isDarkMode ? "#ffffff" : "#171717"
                            }
                            Label {
                                text: popup.pokemonId
                                color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Repeater {
                                    model: popup.types
                                    delegate: Rectangle {
                                        required property string modelData
                                        radius: height / 2
                                        height: typeLabel.implicitHeight + 8
                                        width: typeLabel.implicitWidth + 18
                                        color: popup.typeColor(modelData.toLowerCase())
                                        border.color: "#222222"
                                        border.width: 1

                                        Label {
                                            id: typeLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.bold: true
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            color: popup.typeTextColor(modelData.toLowerCase())
                                        }
                                    }
                                }
                            }
                        }

                        AnimatedImage {
                            width: 56
                            height: 56
                            source: popup.animatedUrl
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            playing: true
                        }
                        AnimatedImage {
                            width: 48
                            height: 48
                            source: popup.animatedShinyUrl
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            playing: true
                        }
                    }

                    ColumnLayout {
                        visible: popup.typeDefenses.length > 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Heading {
                            text: "Type defenses"
                            level: 3
                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Repeater {
                                model: popup.typeDefenses
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property string multiplierText: modelData.multiplier === 0
                                        ? "0×" : modelData.multiplier + "×"
                                    radius: 5
                                    height: defenseLabel.implicitHeight + 6
                                    width: defenseLabel.implicitWidth + 12
                                    color: modelData.color
                                    border.color: "#222222"
                                    border.width: 1

                                    Label {
                                        id: defenseLabel
                                        anchors.centerIn: parent
                                        text: parent.multiplierText + " " + modelData.name
                                        color: modelData.textColor
                                        font.bold: true
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        visible: popup.flavorText.length > 0
                        text: popup.flavorText
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: popup.isDarkMode ? "#ffffff" : "#171717"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: popup.heightText
                            Layout.fillWidth: true
                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                        }
                        Label {
                            text: popup.weightText
                            color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading {
                            text: "Stats"
                            level: 2
                            Layout.fillWidth: true
                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                        }
                        Label {
                            text: "EV yield " + popup.totalEvYield
                            color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Label { text: ""; Layout.preferredWidth: 48 }
                        Label { text: "BASE"; Layout.fillWidth: true; font.pixelSize: Kirigami.Theme.smallFont.pixelSize; color: popup.isDarkMode ? "#aaaaaa" : "#555555" }
                        Label { text: "EV"; Layout.preferredWidth: 32; font.pixelSize: Kirigami.Theme.smallFont.pixelSize; color: popup.isDarkMode ? "#aaaaaa" : "#555555" }
                        Label { text: "IV"; Layout.preferredWidth: 38; font.pixelSize: Kirigami.Theme.smallFont.pixelSize; color: popup.isDarkMode ? "#aaaaaa" : "#555555" }
                    }

                    Repeater {
                        model: popup.stats
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Label {
                                text: modelData.name
                                Layout.preferredWidth: 48
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                color: popup.isDarkMode ? "#ffffff" : "#171717"
                            }
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 20
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: popup.isDarkMode ? "#2d2d2d" : "#e5e5e5"
                                }
                                Rectangle {
                                    width: parent.width * modelData.base / 255
                                    height: parent.height
                                    radius: height / 2
                                    color: popup.isDarkMode ? "#5c93e8" : "#78a9e6"
                                    opacity: 0.8
                                }
                                Label {
                                    anchors.fill: parent
                                    text: modelData.base
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.bold: true
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: popup.isDarkMode ? "#ffffff" : "#171717"
                                }
                            }
                            Item {
                                Layout.preferredWidth: 32
                                implicitHeight: 20
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: popup.isDarkMode ? "#2d2d2d" : "#e5e5e5"
                                }
                                Rectangle {
                                    width: modelData.ev ? Math.max(parent.width * modelData.ev / 3, 14) : 0
                                    height: parent.height
                                    radius: height / 2
                                    color: popup.isDarkMode ? "#7cc965" : "#a6ce83"
                                    opacity: 0.8
                                }
                                Label {
                                    anchors.fill: parent
                                    text: "+" + modelData.ev
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.bold: true
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: popup.isDarkMode ? "#ffffff" : "#171717"
                                }
                            }
                            Item {
                                Layout.preferredWidth: 38
                                implicitHeight: 20
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: popup.isDarkMode ? "#2d2d2d" : "#e5e5e5"
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: popup.isDarkMode ? "#a07cc5" : "#c5a5d8"
                                }
                                Label {
                                    anchors.fill: parent
                                    text: "0–31"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.bold: true
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: popup.isDarkMode ? "#ffffff" : "#171717"
                                }
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    Kirigami.Heading {
                        text: "Evolution"
                        level: 2
                        color: popup.isDarkMode ? "#ffffff" : "#171717"
                    }

                    Repeater {
                        model: popup.evolutionPaths(popup.evolutionRoot, [], [])
                        delegate: Flow {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Repeater {
                                model: parent.modelData
                                delegate: Row {
                                    required property int index
                                    required property var modelData
                                    spacing: 2

                                    Row {
                                        visible: index > 0
                                        spacing: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        Label {
                                            text: "-"
                                            color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                                        }
                                        Label {
                                            text: popup.shortRequirement(modelData.requirements)
                                            font.pixelSize: 10
                                            color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                                        }
                                    }

                                    Item {
                                        width: 52
                                        height: 56
                                        Column {
                                            width: 52
                                            spacing: 0
                                            Image {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 38
                                                height: 38
                                                source: modelData.spriteUrl
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                cache: true
                                            }
                                            Label {
                                                width: parent.width
                                                text: popup.titleCase(modelData.name)
                                                horizontalAlignment: Text.AlignHCenter
                                                font.pixelSize: 9
                                                font.bold: modelData.name === popup.pokemonName.toLowerCase()
                                                elide: Text.ElideRight
                                                color: popup.isDarkMode ? "#ffffff" : "#171717"
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                searchField.text = popup.titleCase(modelData.name)
                                                searchEdited = false
                                                popup.loadPokemon(modelData.name)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading {
                            text: "Moves"
                            level: 2
                            Layout.fillWidth: true
                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                        }
                        Label {
                            visible: popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length
                            text: "Click move → Slot " + (popup.selectedMemberIndex + 1)
                            font.pixelSize: 10
                            color: "#e53935"
                            font.bold: true
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: popup.availableGenerations.length > 0

                        Repeater {
                            model: popup.availableGenerations
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool isSelected: modelData === popup.selectedGeneration
                                radius: 4
                                height: 22
                                width: genLbl.implicitWidth + 10
                                color: isSelected ? "#e53935" : (popup.isDarkMode ? "#2d2d2d" : "#eeeeee")

                                Label {
                                    id: genLbl
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: parent.isSelected ? "#ffffff" : (popup.isDarkMode ? "#ffffff" : "#171717")
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: popup.selectGeneration(modelData)
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: popup.learnableMoves
                            delegate: Rectangle {
                                required property var modelData
                                radius: 4
                                height: moveLbl.implicitHeight + 6
                                width: moveLbl.implicitWidth + 10
                                color: modelData.bgColor || "#a8a878"

                                Label {
                                    id: moveLbl
                                    anchors.centerIn: parent
                                    text: modelData.displayText
                                    color: "#171717"
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    ToolTip.visible: containsMouse
                                    ToolTip.delay: 200
                                    ToolTip.text: "[" + (modelData.moveType || "Normal") + "] " + modelData.classLabel + " · " + modelData.method + "\nPwr: " + modelData.power + " | Acc: " + modelData.accuracy + "\n" + modelData.description
                                    onClicked: popup.addMoveToActiveMember(modelData)
                                }
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Heading {
                            text: "Teams"
                            level: 2
                            Layout.fillWidth: true
                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                        }
                        Button {
                            text: "+ Add " + popup.pokemonName
                            implicitHeight: 24
                            enabled: popup.currentTeam.length < 6 && popup.pokemonName.length > 0
                            onClicked: popup.addPokemonToTeam()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [1, 2, 3]
                            delegate: Button {
                                required property int modelData
                                text: "Team " + modelData + (popup.activeTeamSlot === modelData ? " ★" : "")
                                Layout.fillWidth: true
                                implicitHeight: 26
                                onClicked: popup.loadTeamSlot(modelData)
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: 4
                        columnSpacing: 4

                        Repeater {
                            model: 6
                            delegate: Rectangle {
                                id: slotCard
                                required property int index
                                readonly property bool hasMember: index < popup.currentTeam.length
                                readonly property var member: hasMember ? popup.currentTeam[index] : null
                                readonly property bool isSelected: index === popup.selectedMemberIndex
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                radius: 4
                                color: hasMember ? (popup.isDarkMode ? "#242424" : "#f7f7f7") : (popup.isDarkMode ? "#1c1c1c" : "#fafafa")
                                border.color: isSelected ? "#e53935" : (popup.isDarkMode ? "#3a3a3a" : "#dddddd")
                                border.width: isSelected ? 2 : 1

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    onClicked: {
                                        if (slotCard.hasMember) {
                                            popup.selectedMemberIndex = slotCard.index
                                            popup.loadPokemon(slotCard.member.name, slotCard.index)
                                        } else {
                                            popup.addPokemonToTeam()
                                        }
                                    }
                                }

                                Label {
                                    visible: !slotCard.hasMember
                                    anchors.centerIn: parent
                                    text: "+"
                                    font.pixelSize: 18
                                    color: popup.isDarkMode ? "#555555" : "#bbbbbb"
                                }

                                RowLayout {
                                    visible: slotCard.hasMember
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 4

                                    Image {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        source: slotCard.member ? slotCard.member.sprite : ""
                                        fillMode: Image.PreserveAspectFit
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Label {
                                            text: slotCard.member ? slotCard.member.name : ""
                                            font.bold: true
                                            font.pixelSize: 9
                                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: slotCard.member && slotCard.member.item ? "@ " + slotCard.member.item : "No item"
                                            font.pixelSize: 8
                                            color: popup.isDarkMode ? "#aaaaaa" : "#777777"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Button {
                                        text: "✕"
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        z: 10
                                        onClicked: {
                                            popup.removePokemonFromTeam(slotCard.index)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length
                        Layout.fillWidth: true
                        implicitHeight: activeMemberCol.implicitHeight + 8
                        radius: 4
                        color: popup.isDarkMode ? "#222222" : "#f0f0f0"

                        ColumnLayout {
                            id: activeMemberCol
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length ? popup.currentTeam[popup.selectedMemberIndex].name + " Moves:" : ""
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: popup.isDarkMode ? "#ffffff" : "#171717"
                                }
                                Item { Layout.fillWidth: true }
                                TextField {
                                    id: itemInput
                                    Layout.preferredWidth: 100
                                    Layout.preferredHeight: 22
                                    placeholderText: "Held item..."
                                    font.pixelSize: 9
                                    text: popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length ? (popup.currentTeam[popup.selectedMemberIndex].item || "") : ""
                                    onTextChanged: {
                                        if (popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length) {
                                            popup.updateActiveMemberItem(text)
                                            popup.updateItemSuggestions(text)
                                        }
                                    }
                                }
                            }

                            // Item Autocomplete Suggestions
                            ListView {
                                id: itemSuggList
                                Layout.fillWidth: true
                                Layout.preferredHeight: popup.itemSuggestions.length > 0 ? Math.min(popup.itemSuggestions.length, 3) * 20 : 0
                                visible: popup.itemSuggestions.length > 0 && itemInput.activeFocus
                                clip: true
                                model: popup.itemSuggestions
                                delegate: ItemDelegate {
                                    required property string modelData
                                    width: itemSuggList.width
                                    height: 20
                                    background: Rectangle {
                                        color: popup.isDarkMode ? "#2a2a2a" : "#ffffff"
                                    }
                                    contentItem: Label {
                                        text: popup.titleCase(modelData)
                                        font.pixelSize: 9
                                        color: popup.isDarkMode ? "#ffffff" : "#171717"
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        itemInput.text = popup.titleCase(modelData)
                                        popup.itemSuggestions = []
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length ? popup.currentTeam[popup.selectedMemberIndex].moves : []
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        radius: 4
                                        height: 20
                                        width: memberMoveLbl.implicitWidth + 14
                                        color: modelData.bgColor || "#a8a878"

                                        Label {
                                            id: memberMoveLbl
                                            anchors.centerIn: parent
                                            text: modelData.name + " ✕"
                                            font.pixelSize: 9
                                            color: "#171717"
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: 200
                                            ToolTip.text: "[" + (modelData.moveType || "Normal") + "] " + (modelData.classLabel || "Move") + " · " + (modelData.method || "") +
                                                          "\nPower: " + modelData.power + " | Accuracy: " + modelData.accuracy +
                                                          "\n" + (modelData.description || "") +
                                                          "\n\nClick to remove"
                                            onClicked: popup.removeMoveFromActiveMember(index)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: popup.teamWeaknesses.length > 0
                        spacing: 2

                        Kirigami.Heading {
                            text: "Team Weaknesses (2×+)"
                            level: 3
                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: popup.teamWeaknesses
                                delegate: Rectangle {
                                    required property var modelData
                                    radius: 4
                                    height: 20
                                    width: weakLbl.implicitWidth + 10
                                    color: modelData.color

                                    Label {
                                        id: weakLbl
                                        anchors.centerIn: parent
                                        text: modelData.name + " (" + modelData.count + ")"
                                        color: modelData.textColor
                                        font.bold: true
                                        font.pixelSize: 9
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        ToolTip.visible: containsMouse
                                        ToolTip.delay: 200
                                        ToolTip.text: modelData.pokemonList
                                    }
                                }
                            }
                        }
                    }

                    // --- TEAM OFFENSIVE COVERAGE SUMMARY ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: popup.teamOffensiveCoverage.length > 0
                        spacing: 2

                        Kirigami.Heading {
                            text: "Offensive Coverage (Super Effective)"
                            level: 3
                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: popup.teamOffensiveCoverage
                                delegate: Rectangle {
                                    required property var modelData
                                    radius: 4
                                    height: 20
                                    width: covLbl.implicitWidth + 10
                                    color: modelData.color

                                    Label {
                                        id: covLbl
                                        anchors.centerIn: parent
                                        text: modelData.name + " (" + modelData.count + ")"
                                        color: modelData.textColor
                                        font.bold: true
                                        font.pixelSize: 9
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        ToolTip.visible: containsMouse
                                        ToolTip.delay: 200
                                        ToolTip.text: "Super Effective Sources:\n" + modelData.sourcesList
                                    }
                                }
                            }
                        }
                    }

                }
            }
        }
    }
}
