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

        Component.onCompleted: {
            initTeamDatabase()
            loadPokemon("charmander")
            loadSpeciesNames()
        }

        function getDatabase() {
            return LocalStorage.openDatabaseSync("PlasmaDexTeamsDB", "1.0", "Persistent Pokemon Teams", 1000000)
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

        function calculateTeamAnalysis() {
            if (!currentTeam || currentTeam.length === 0) {
                teamWeaknesses = []
                teamOffensiveCoverage = []
                return
            }

            const allTypes = [
                "normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
                "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"
            ]

            let weaknessMap = {}
            for (let t = 0; t < allTypes.length; ++t) weaknessMap[allTypes[t]] = []

            let offensiveTypesCovered = {} // type -> list of moves hitting it super effectively
            for (let t = 0; t < allTypes.length; ++t) offensiveTypesCovered[allTypes[t]] = []

            let membersProcessed = 0
            for (let i = 0; i < currentTeam.length; ++i) {
                const member = currentTeam[i]
                const memberTypes = member.types || []

                // 1. Calculate Defenses / Weaknesses
                if (memberTypes.length > 0) {
                    let memberMults = {}
                    for (let t = 0; t < allTypes.length; ++t) memberMults[allTypes[t]] = 1

                    let typesRemaining = memberTypes.length
                    for (let mt = 0; mt < memberTypes.length; ++mt) {
                        const tName = memberTypes[mt].toLowerCase()
                        const xhr = new XMLHttpRequest()
                        xhr.open("GET", "https://pokeapi.co/api/v2/type/" + tName)
                        xhr.setRequestHeader("Accept", "application/json")
                        xhr.onreadystatechange = function() {
                            if (xhr.readyState !== XMLHttpRequest.DONE) return
                            if (xhr.status >= 200 && xhr.status < 300) {
                                try {
                                    const data = JSON.parse(xhr.responseText)
                                    const rel = data.damage_relations
                                    const doubleFrom = rel.double_damage_from || []
                                    const halfFrom = rel.half_damage_from || []
                                    const noFrom = rel.no_damage_from || []

                                    for (let d = 0; d < doubleFrom.length; ++d) memberMults[doubleFrom[d].name] *= 2
                                    for (let h = 0; h < halfFrom.length; ++h) memberMults[halfFrom[h].name] *= 0.5
                                    for (let n = 0; n < noFrom.length; ++n) memberMults[noFrom[n].name] *= 0
                                } catch (e) {}
                            }
                            typesRemaining--
                            if (typesRemaining === 0) {
                                for (let t = 0; t < allTypes.length; ++t) {
                                    if (memberMults[allTypes[t]] > 1) {
                                        weaknessMap[allTypes[t]].push(member.name + " (" + memberMults[allTypes[t]] + "×)")
                                    }
                                }
                                checkMemberDone()
                            }
                        }
                        xhr.send()
                    }
                } else {
                    checkMemberDone()
                }

                // 2. Calculate Offensive Move Types Coverage
                const memberMoves = member.moves || []
                for (let m = 0; m < memberMoves.length; ++m) {
                    const moveName = memberMoves[m].name.toLowerCase().replace(/\s+/g, "-")
                    const mxhr = new XMLHttpRequest()
                    mxhr.open("GET", "https://pokeapi.co/api/v2/move/" + moveName)
                    mxhr.setRequestHeader("Accept", "application/json")
                    mxhr.onreadystatechange = function() {
                        if (mxhr.readyState !== XMLHttpRequest.DONE) return
                        if (mxhr.status >= 200 && mxhr.status < 300) {
                            try {
                                const moveData = JSON.parse(mxhr.responseText)
                                if (moveData.type && moveData.type.name) {
                                    const moveType = moveData.type.name
                                    // Fetch type efficacy for this move type to see what it hits super effectively
                                    const txhr = new XMLHttpRequest()
                                    txhr.open("GET", "https://pokeapi.co/api/v2/type/" + moveType)
                                    txhr.setRequestHeader("Accept", "application/json")
                                    txhr.onreadystatechange = function() {
                                        if (txhr.readyState !== XMLHttpRequest.DONE) return
                                        if (txhr.status >= 200 && txhr.status < 300) {
                                            try {
                                                const typeData = JSON.parse(txhr.responseText)
                                                const doubleTo = typeData.damage_relations.double_damage_to || []
                                                for (let dt = 0; dt < doubleTo.length; ++dt) {
                                                    const targetType = doubleTo[dt].name
                                                    if (offensiveTypesCovered[targetType]) {
                                                        const entryStr = member.name + " (" + memberMoves[m].name + ")"
                                                        if (offensiveTypesCovered[targetType].indexOf(entryStr) < 0) {
                                                            offensiveTypesCovered[targetType].push(entryStr)
                                                        }
                                                    }
                                                }
                                                updateOffensiveCoverageView(offensiveTypesCovered)
                                            } catch (e) {}
                                        }
                                    }
                                    txhr.send()
                                }
                            } catch (e) {}
                        }
                    }
                    mxhr.send()
                }
            }

            function checkMemberDone() {
                membersProcessed++
                if (membersProcessed === currentTeam.length) {
                    finalizeWeaknesses(weaknessMap)
                }
            }
        }

        function finalizeWeaknesses(map) {
            let res = []
            for (let type in map) {
                if (map[type].length > 0) {
                    res.push({
                        name: titleCase(type),
                        count: map[type].length,
                        pokemonList: map[type].join(", "),
                        color: typeColor(type),
                        textColor: typeTextColor(type)
                    })
                }
            }
            res.sort(function(a, b) { return b.count - a.count })
            teamWeaknesses = res
        }

        function updateOffensiveCoverageView(map) {
            let res = []
            for (let type in map) {
                if (map[type].length > 0) {
                    res.push({
                        name: titleCase(type),
                        count: map[type].length,
                        movesList: map[type].join(", "),
                        color: typeColor(type),
                        textColor: typeTextColor(type)
                    })
                }
            }
            res.sort(function(a, b) { return b.count - a.count })
            teamOffensiveCoverage = res
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
                method: moveObj.method
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

        property string suggestionError: ""

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

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: popup.isDarkMode ? "#181818" : "#ffffff"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing

                    ScrollView {
                        id: bodyScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        visible: popup.pokemonName.length > 0
                        ScrollBar.horizontal: ScrollBar {
                            policy: ScrollBar.AlwaysOff
                        }
                        ScrollBar.vertical: ScrollBar {
                            parent: bodyScroll
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            policy: ScrollBar.AlwaysOn
                            interactive: true
                        }
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

                                Column {
                                    spacing: 0
                                    AnimatedImage {
                                        width: 56
                                        height: 56
                                        source: popup.animatedUrl
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        playing: true
                                    }
                                }
                                Column {
                                    spacing: 0
                                    AnimatedImage {
                                        width: 48
                                        height: 48
                                        source: popup.animatedShinyUrl
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        playing: true
                                    }
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
                                Label {
                                    text: "Damage taken; neutral types omitted."
                                    color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
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

                            Kirigami.Separator {
                                Layout.fillWidth: true
                            }

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
                                Label {
                                    text: ""
                                    Layout.preferredWidth: 48
                                }
                                Label {
                                    text: "BASE"
                                    Layout.fillWidth: true
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                                }
                                Label {
                                    text: "EV"
                                    Layout.preferredWidth: 32
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                                }
                                Label {
                                    text: "IV"
                                    Layout.preferredWidth: 38
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                                }
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

                            Label {
                                text: "EV is gained by defeating this Pokémon. IVs are individual values: each stat can range from 0 to 31."
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }

                            Kirigami.Separator {
                                Layout.fillWidth: true
                                color: popup.isDarkMode ? "#333333" : "#777777"
                            }

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
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Image {
                                                    visible: modelData.requirements.length > 0
                                                        && (modelData.requirements[0].item.length > 0
                                                            || modelData.requirements[0].heldItem.length > 0)
                                                    source: (visible
                                                        ? "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/"
                                                            + (modelData.requirements[0].item || modelData.requirements[0].heldItem) + ".png"
                                                        : "")
                                                    sourceSize.width: 18
                                                    sourceSize.height: 18
                                                    width: visible ? 18 : 0
                                                    height: visible ? 18 : 0
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    cache: true
                                                }
                                                Label {
                                                    text: popup.shortRequirement(modelData.requirements)
                                                    width: Math.min(implicitWidth, 46)
                                                    elide: Text.ElideRight
                                                    color: popup.isDarkMode ? "#aaaaaa" : "#555555"
                                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            Item {
                                                width: 56
                                                height: 60
                                                Column {
                                                    id: evoCol
                                                    width: 56
                                                    spacing: 0
                                                    Image {
                                                        id: evoImg
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 44
                                                        height: 44
                                                        source: modelData.spriteUrl
                                                        fillMode: Image.PreserveAspectFit
                                                        asynchronous: true
                                                        cache: true
                                                        onStatusChanged: {
                                                            if (status === Image.Error)
                                                                source = modelData.fallbackSpriteUrl
                                                        }
                                                    }
                                                    Label {
                                                        width: parent.width
                                                        text: popup.titleCase(modelData.name)
                                                        horizontalAlignment: Text.AlignHCenter
                                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                                        font.bold: modelData.name === popup.pokemonName.toLowerCase()
                                                        elide: Text.ElideRight
                                                        color: popup.isDarkMode ? "#ffffff" : "#171717"
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: 200
                                                    ToolTip.text: "Load " + popup.titleCase(modelData.name)
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

                            Kirigami.Separator {
                                Layout.fillWidth: true
                                color: popup.isDarkMode ? "#333333" : "#777777"
                            }
                            
                            RowLayout {
                                Layout.fillWidth: true
                                Kirigami.Heading {
                                    text: "Moves"
                                    level: 2
                                    Layout.fillWidth: true
                                    color: popup.isDarkMode ? "#ffffff" : "#171717"
                                }
                                Label {
                                    visible: popup.selectedMemberIndex >= 0
                                        && popup.selectedMemberIndex < popup.currentTeam.length
                                        && popup.currentTeam[popup.selectedMemberIndex].name.toLowerCase() === popup.pokemonName.toLowerCase()
                                    text: "Click move → " + popup.pokemonName + " (Slot " + (popup.selectedMemberIndex + 1) + ")"
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
                                        height: genPillLabel.implicitHeight + 6
                                        width: genPillLabel.implicitWidth + 10
                                        color: isSelected ? "#e53935" : (popup.isDarkMode ? "#2d2d2d" : "#eeeeee")
                                        border.color: isSelected ? "#b71c1c" : (popup.isDarkMode ? "#444444" : "#cccccc")
                                        border.width: 1

                                        Label {
                                            id: genPillLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: parent.isSelected ? "#ffffff" : (popup.isDarkMode ? "#ffffff" : "#171717")
                                            font.bold: parent.isSelected
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
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
                                spacing: Kirigami.Units.smallSpacing
                                
                                Repeater {
                                    model: popup.learnableMoves
                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: 4
                                        height: moveLabel.implicitHeight + 8
                                        width: moveLabel.implicitWidth + 12
                                        color: modelData.bgColor
                                        border.color: popup.isDarkMode ? "#444444" : "#222222"
                                        border.width: 1

                                        Label {
                                            id: moveLabel
                                            anchors.centerIn: parent
                                            text: modelData.displayText
                                            color: "#171717"
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: 200
                                            ToolTip.text: modelData.classLabel + " · " + modelData.method + 
                                                          "\nPower: " + modelData.power + " | Accuracy: " + modelData.accuracy + 
                                                          "\n" + modelData.description +
                                                          ((popup.selectedMemberIndex >= 0
                                                            && popup.selectedMemberIndex < popup.currentTeam.length
                                                            && popup.currentTeam[popup.selectedMemberIndex].name.toLowerCase() === popup.pokemonName.toLowerCase())
                                                            ? "\n\nClick to add to " + popup.currentTeam[popup.selectedMemberIndex].name + " (Slot " + (popup.selectedMemberIndex + 1) + ")"
                                                            : "\n\n(Select this Pokémon in your team below to assign moves)")
                                            onClicked: popup.addMoveToActiveMember(modelData)
                                        }
                                    }
                                }
                            }

                            // --- SLEEK AUTO-SAVING TEAM BUILDER ---
                            Kirigami.Separator {
                                Layout.fillWidth: true
                                color: popup.isDarkMode ? "#333333" : "#777777"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Kirigami.Heading {
                                    text: "Teams"
                                    level: 2
                                    Layout.fillWidth: true
                                    color: popup.isDarkMode ? "#ffffff" : "#171717"
                                }

                                Rectangle {
                                    visible: popup.currentTeam.length < 6 && popup.pokemonName.length > 0
                                    radius: 4
                                    height: 22
                                    width: addBtnLbl.implicitWidth + 12
                                    color: "#e53935"

                                    Label {
                                        id: addBtnLbl
                                        anchors.centerIn: parent
                                        text: "+ Add " + popup.pokemonName
                                        color: "#ffffff"
                                        font.bold: true
                                        font.pixelSize: 10
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: popup.addPokemonToTeam()
                                    }
                                }
                            }

                            // 3 Team Slot Pills (Auto-loads & Auto-saves)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: [1, 2, 3]
                                    delegate: Rectangle {
                                        required property int modelData
                                        readonly property bool isCurrentSlot: popup.activeTeamSlot === modelData
                                        Layout.fillWidth: true
                                        height: 24
                                        radius: 4
                                        color: isCurrentSlot ? "#e53935" : (popup.isDarkMode ? "#2d2d2d" : "#eeeeee")
                                        border.color: isCurrentSlot ? "#b71c1c" : (popup.isDarkMode ? "#444444" : "#cccccc")
                                        border.width: 1

                                        Label {
                                            anchors.centerIn: parent
                                            text: "Team " + modelData
                                            color: parent.isCurrentSlot ? "#ffffff" : (popup.isDarkMode ? "#ffffff" : "#171717")
                                            font.bold: parent.isCurrentSlot
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: popup.loadTeamSlot(modelData)
                                        }
                                    }
                                }
                            }

                            // 6-Slot Visual Party Grid (3x2)
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                rowSpacing: 6
                                columnSpacing: 6

                                Repeater {
                                    model: 6
                                    delegate: Rectangle {
                                        id: slotCard
                                        required property int index
                                        readonly property bool hasMember: index < popup.currentTeam.length
                                        readonly property var member: hasMember ? popup.currentTeam[index] : null
                                        readonly property bool isSelected: index === popup.selectedMemberIndex
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 64
                                        radius: 6
                                        color: hasMember
                                            ? (popup.isDarkMode ? "#242424" : "#f7f7f7")
                                            : (popup.isDarkMode ? "#1c1c1c" : "#fafafa")
                                        border.color: isSelected
                                            ? "#e53935"
                                            : (popup.isDarkMode ? "#3a3a3a" : "#dddddd")
                                        border.width: isSelected ? 2 : 1

                                        // Empty Slot View
                                        Label {
                                            visible: !slotCard.hasMember
                                            anchors.centerIn: parent
                                            text: "+"
                                            font.pixelSize: 20
                                            font.bold: true
                                            color: popup.isDarkMode ? "#555555" : "#bbbbbb"
                                        }

                                        // Occupied Slot View
                                        Column {
                                            visible: slotCard.hasMember
                                            anchors.centerIn: parent
                                            spacing: 1

                                            Image {
                                                id: memberSpriteImg
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 40
                                                height: 40
                                                source: slotCard.member
                                                    ? (slotCard.member.sprite && slotCard.member.sprite.length > 0
                                                        ? slotCard.member.sprite
                                                        : popup.spriteForName(slotCard.member.name))
                                                    : ""
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                cache: true
                                                onStatusChanged: {
                                                    if (status === Image.Error && slotCard.member) {
                                                        const fallback = slotCard.member.fallbackSprite || popup.spriteForName(slotCard.member.name)
                                                        if (source != fallback) {
                                                            source = fallback
                                                        }
                                                    }
                                                }
                                            }

                                            Label {
                                                width: 54
                                                text: slotCard.member ? slotCard.member.name : ""
                                                horizontalAlignment: Text.AlignHCenter
                                                font.pixelSize: 9
                                                font.bold: slotCard.isSelected
                                                elide: Text.ElideRight
                                                color: popup.isDarkMode ? "#ffffff" : "#171717"
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: 200
                                            ToolTip.text: slotCard.hasMember
                                                ? (slotCard.member.name + (slotCard.member.item ? " @ " + slotCard.member.item : "") + "\n(" + (slotCard.member.moves ? slotCard.member.moves.length : 0) + "/4 moves)\nClick to load & edit")
                                                : ("Add " + popup.pokemonName + " to slot " + (slotCard.index + 1))
                                            onClicked: {
                                                if (slotCard.hasMember) {
                                                    popup.selectedMemberIndex = slotCard.index
                                                    if (popup.pokemonName.toLowerCase() !== slotCard.member.name.toLowerCase()) {
                                                        searchField.text = slotCard.member.name
                                                        popup.searchEdited = false
                                                        popup.loadPokemon(slotCard.member.name, slotCard.index)
                                                    }
                                                } else {
                                                    popup.addPokemonToTeam()
                                                }
                                            }
                                        }

                                        // Quick Remove "✕" Badge
                                        Rectangle {
                                            visible: slotCard.hasMember
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.margins: 3
                                            width: 14
                                            height: 14
                                            radius: 7
                                            color: popup.isDarkMode ? "#3a3a3a" : "#e0e0e0"

                                            Label {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                font.pixelSize: 8
                                                font.bold: true
                                                color: popup.isDarkMode ? "#ffffff" : "#171717"
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: popup.removePokemonFromTeam(slotCard.index)
                                            }
                                        }
                                    }
                                }
                            }

                            // Active Team Member's Held Item & Moves
                            Rectangle {
                                visible: popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length
                                Layout.fillWidth: true
                                implicitHeight: memberDetailsCol.implicitHeight + 12
                                radius: 6
                                color: popup.isDarkMode ? "#222222" : "#f5f5f5"
                                border.color: popup.isDarkMode ? "#383838" : "#dddddd"
                                border.width: 1

                                ColumnLayout {
                                    id: memberDetailsCol
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label {
                                            text: (popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length)
                                                ? popup.currentTeam[popup.selectedMemberIndex].name
                                                : ""
                                            font.bold: true
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            color: popup.isDarkMode ? "#ffffff" : "#171717"
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Held Item Input Field
                                        TextField {
                                            id: itemField
                                            Layout.preferredWidth: 110
                                            Layout.preferredHeight: 24
                                            placeholderText: "Held Item…"
                                            font.pixelSize: 10
                                            text: (popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length)
                                                ? (popup.currentTeam[popup.selectedMemberIndex].item || "")
                                                : ""
                                            palette.text: popup.isDarkMode ? "#ffffff" : "#171717"
                                            palette.placeholderText: popup.isDarkMode ? "#888888" : "#777777"
                                            palette.base: popup.isDarkMode ? "#2d2d2d" : "#ffffff"
                                            onTextChanged: {
                                                if (popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length) {
                                                    popup.updateActiveMemberItem(text)
                                                }
                                            }
                                        }
                                    }

                                    Label {
                                        visible: popup.selectedMemberIndex >= 0
                                            && popup.selectedMemberIndex < popup.currentTeam.length
                                            && popup.currentTeam[popup.selectedMemberIndex].moves.length === 0
                                        text: "Click any move pill above to assign it."
                                        font.pixelSize: 10
                                        color: popup.isDarkMode ? "#aaaaaa" : "#666666"
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        Repeater {
                                            model: (popup.selectedMemberIndex >= 0 && popup.selectedMemberIndex < popup.currentTeam.length)
                                                ? popup.currentTeam[popup.selectedMemberIndex].moves
                                                : []
                                            delegate: Rectangle {
                                                required property var modelData
                                                required property int index
                                                radius: 4
                                                height: assignedMoveLbl.implicitHeight + 8
                                                width: assignedMoveLbl.implicitWidth + 12
                                                color: modelData.bgColor || "#a8a878"
                                                border.color: "#222222"
                                                border.width: 1

                                                Label {
                                                    id: assignedMoveLbl
                                                    anchors.centerIn: parent
                                                    text: modelData.name + " · " + modelData.power + "/" + modelData.accuracy + " ✕"
                                                    color: "#171717"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: 200
                                                    ToolTip.text: (modelData.classLabel || "Move") + " · " + (modelData.method || "") +
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

                            // --- TEAM TYPE WEAKNESS SUMMARY ---
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: popup.teamWeaknesses.length > 0
                                spacing: 4

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
                                            height: weakLbl.implicitHeight + 6
                                            width: weakLbl.implicitWidth + 10
                                            color: modelData.color
                                            border.color: "#222222"
                                            border.width: 1

                                            Label {
                                                id: weakLbl
                                                anchors.centerIn: parent
                                                text: modelData.name + " (" + modelData.count + ")"
                                                color: modelData.textColor
                                                font.bold: true
                                                font.pixelSize: 10
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                ToolTip.visible: containsMouse
                                                ToolTip.delay: 200
                                                ToolTip.text: "Vulnerable Pokémon:\n" + modelData.pokemonList
                                            }
                                        }
                                    }
                                }
                            }

                            // --- TEAM OFFENSIVE COVERAGE SUMMARY ---
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: popup.teamOffensiveCoverage.length > 0
                                spacing: 4

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
                                            height: covLbl.implicitHeight + 6
                                            width: covLbl.implicitWidth + 10
                                            color: modelData.color
                                            border.color: "#222222"
                                            border.width: 1

                                            Label {
                                                id: covLbl
                                                anchors.centerIn: parent
                                                text: modelData.name + " (" + modelData.count + ")"
                                                color: modelData.textColor
                                                font.bold: true
                                                font.pixelSize: 10
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                ToolTip.visible: containsMouse
                                                ToolTip.delay: 200
                                                ToolTip.text: "Hits Super Effective via:\n" + modelData.movesList
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
    }
}
