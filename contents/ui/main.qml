import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
        color: Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.largeSpacing
        border.color: "#111111"
        border.width: 2
        clip: true

        property string pokemonName: ""
        property string pokemonId: ""
        property string spriteUrl: ""
        property string shinyUrl: ""
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

        Component.onCompleted: {
            loadPokemon("pikachu")
            loadSpeciesNames()
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
            return "https://img.pokemondb.net/sprites/home/normal/" + name + ".png"
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

        function loadPokemon(input) {
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
                stats = pokemon.stats.map(function (entry) {
                    return {
                        name: titleCase(entry.stat.name.replace("special-", "sp. ")),
                        base: entry.base_stat,
                        ev: entry.effort
                    }
                })
                let evTotal = 0
                for (let i = 0; i < stats.length; ++i) {
                    evTotal += stats[i].ev
                }
                totalEvYield = evTotal
                
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

                for (let m = 0; m < pokemon.moves.length; ++m) {
                    let entry = pokemon.moves[m]
                    let moveName = titleCase(entry.move.name)
                    
                    for (let d = 0; d < entry.version_group_details.length; ++d) {
                        let detail = entry.version_group_details[d]
                        let versionName = detail.version_group.name
                        let genName = versionToGenMap[versionName]

                        if (genName) {
                            let exists = false
                            for (let k = 0; k < tempCategorized[genName].length; ++k) {
                                if (tempCategorized[genName][k].name === moveName) {
                                    exists = true
                                    break
                                }
                            }
                            
                            if (!exists) {
                                let methodRaw = detail.move_learn_method.name
                                let method = titleCase(methodRaw)
                                let bgColor = methodRaw === "level-up" ? "#d4edda" : (methodRaw === "machine" ? "#fff3cd" : "#d1ecf1")
                                let borderColor = methodRaw === "level-up" ? "#c3e6cb" : (methodRaw === "machine" ? "#ffeeba" : "#bee5eb")
                                
                                tempCategorized[genName].push({
                                    name: moveName,
                                    method: method,
                                    level: detail.level_learned_at,
                                    bgColor: bgColor,
                                    borderColor: borderColor
                                })
                            }
                        }
                    }
                }

                let gens = []
                for (let i = 1; i <= 9; ++i) {
                    let g = "Gen " + i
                    if (tempCategorized[g].length > 0) {
                        tempCategorized[g].sort(function(a, b) {
                            return a.name.localeCompare(b.name)
                        })
                        gens.push(g)
                    }
                }
                
                categorizedMoves = tempCategorized
                availableGenerations = gens
                if (gens.length > 0) {
                    selectGeneration(gens[gens.length - 1])
                }

                const speciesName = pokemon.species.name
                const fileName = speciesName
                spriteUrl = "https://img.pokemondb.net/sprites/home/normal/" + fileName + ".png"
                shinyUrl = "https://img.pokemondb.net/sprites/home/shiny/" + fileName + ".png"
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

        function requirementText(requirement) {
            const parts = []
            if (requirement.level)
                parts.push("Lv. " + requirement.level)
            if (requirement.item)
                parts.push(titleCase(requirement.item))
            if (requirement.heldItem)
                parts.push("Hold " + titleCase(requirement.heldItem))
            if (requirement.happiness)
                parts.push("Friendship " + requirement.happiness)
            if (requirement.affection)
                parts.push("Affection " + requirement.affection)
            if (requirement.beauty)
                parts.push("Beauty " + requirement.beauty)
            if (requirement.gender)
                parts.push(requirement.gender === 1 ? "Female" : "Male")
            if (requirement.timeOfDay)
                parts.push(titleCase(requirement.timeOfDay))
            if (requirement.location)
                parts.push(titleCase(requirement.location))
            if (requirement.knownMove)
                parts.push(titleCase(requirement.knownMove))
            if (requirement.knownMoveType)
                parts.push(titleCase(requirement.knownMoveType) + " move")
            if (requirement.partySpecies)
                parts.push("Party: " + titleCase(requirement.partySpecies))
            if (requirement.partyType)
                parts.push(titleCase(requirement.partyType) + " in party")
            if (requirement.tradeSpecies)
                parts.push("Trade for " + titleCase(requirement.tradeSpecies))
            if (requirement.relativeStats !== null) {
                const statRelation = ["Attack < Defense", "Attack = Defense", "Attack > Defense"]
                parts.push(statRelation[requirement.relativeStats + 1])
            }
            if (requirement.rain)
                parts.push("Rain")
            if (requirement.multiplayer)
                parts.push("Multiplayer")
            if (requirement.upsideDown)
                parts.push("Turn upside down")
            if (requirement.trigger === "trade" && !requirement.item && !requirement.heldItem)
                parts.push("Trade")
            else if (requirement.trigger === "use-item" && !requirement.item)
                parts.push("Use an item")
            else if (requirement.trigger === "level-up" && !requirement.level)
                parts.push("Level up")
            return parts.join(" · ")
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
            return requirementText(first)
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
                            text: "PlasmaDex"
                            level: 2
                            Layout.fillWidth: true
                            color: "#ffffff"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            text: "pikachu"
                            leftPadding: 38
                            placeholderText: "Search Name or #ID…"
                            focus: true
                            palette.text: "#171717"
                            palette.placeholderText: "#666666"
                            palette.base: "#ffffff"
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
                    color: "#111111"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#ffffff"

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
                            color: "#ffffff"
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
                                        color: "#171717"
                                    }
                                    Label {
                                        text: popup.pokemonId
                                        color: "#555555"
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
                                    Image {
                                        width: 48
                                        height: 48
                                        source: popup.spriteUrl
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
                                    }
                                }
                                Column {
                                    spacing: 0
                                    Image {
                                        width: 48
                                        height: 48
                                        source: popup.shinyUrl
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
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
                                    color: "#171717"
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
                                    color: "#555555"
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
                                color: "#171717"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: popup.heightText
                                    Layout.fillWidth: true
                                    color: "#171717"
                                }
                                Label {
                                    text: popup.weightText
                                    color: "#555555"
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
                                    color: "#171717"
                                }
                                Label {
                                    text: "EV yield " + popup.totalEvYield
                                    color: "#555555"
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Label {
                                    text: ""
                                    Layout.preferredWidth: 36
                                }
                                Label {
                                    text: "BASE"
                                    Layout.fillWidth: true
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: "#555555"
                                }
                                Label {
                                    text: "EV"
                                    Layout.preferredWidth: 32
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: "#555555"
                                }
                                Label {
                                    text: "IV"
                                    Layout.preferredWidth: 38
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: "#555555"
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
                                        Layout.preferredWidth: 36
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        color: "#171717"
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: 20
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: "#e5e5e5"
                                        }
                                        Rectangle {
                                            width: parent.width * modelData.base / 255
                                            height: parent.height
                                            radius: height / 2
                                            color: "#78a9e6"
                                            opacity: 0.8
                                        }
                                        Label {
                                            anchors.fill: parent
                                            text: modelData.base
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            font.bold: true
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            color: "#171717"
                                        }
                                    }
                                    Item {
                                        Layout.preferredWidth: 32
                                        implicitHeight: 20
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: "#e5e5e5"
                                        }
                                        Rectangle {
                                            width: modelData.ev ? Math.max(parent.width * modelData.ev / 3, 14) : 0
                                            height: parent.height
                                            radius: height / 2
                                            color: "#a6ce83"
                                            opacity: 0.8
                                        }
                                        Label {
                                            anchors.fill: parent
                                            text: "+" + modelData.ev
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            font.bold: true
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            color: "#171717"
                                        }
                                    }
                                    Item {
                                        Layout.preferredWidth: 38
                                        implicitHeight: 20
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: "#e5e5e5"
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: "#c5a5d8"
                                        }
                                        Label {
                                            anchors.fill: parent
                                            text: "0–31"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            font.bold: true
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            color: "#171717"
                                        }
                                    }
                                }
                            }

                            Label {
                                text: "EV is gained by defeating this Pokémon. IVs are individual values: each stat can range from 0 to 31."
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: "#555555"
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }

                            Kirigami.Separator {
                                Layout.fillWidth: true
                                color: "#777777"
                            }

                            Kirigami.Heading {
                                text: "Evolution"
                                level: 2
                                color: "#171717"
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
                                                    color: "#555555"
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
                                                    color: "#555555"
                                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            Column {
                                                width: 56
                                                spacing: 0
                                                Image {
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
                                                    color: "#171717"
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Kirigami.Separator {
                                Layout.fillWidth: true
                                color: "#777777"
                            }
                            
                            Kirigami.Heading {
                                text: "Moves"
                                level: 2
                                color: "#171717"
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
                                        color: isSelected ? "#e53935" : "#eeeeee"
                                        border.color: isSelected ? "#b71c1c" : "#cccccc"
                                        border.width: 1

                                        Label {
                                            id: genPillLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: parent.isSelected ? "#ffffff" : "#171717"
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
                                        border.color: modelData.borderColor
                                        border.width: 1

                                        Label {
                                            id: moveLabel
                                            anchors.centerIn: parent
                                            text: modelData.name
                                            color: "#171717"
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: 200
                                            ToolTip.text: (modelData.method === "Level Up" ? "Level " + modelData.level : modelData.method)
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
