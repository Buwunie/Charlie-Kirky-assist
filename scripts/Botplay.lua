--[[
    ================================================
     SA Bot Play v2 - Script de Auto Play
     Friday Night Funkin' (Psych Engine)
    ================================================

    Estrutura de pastas (tem que ficar exatamente assim
    dentro de mods/):

      SA-Bot-Play/
        pack.json             <- faz o mod carregar sempre
        data/
          settings.json       <- as configurações do mod
        scripts/
          SA Bot Play v2.lua  <- este arquivo

    Configurações (Menu > Mods > engrenagem do mod):
    - Bot Play: liga/desliga o auto play
    - Rating do Bot: Sick! / Good / Bad / Shit! / Random
    - Mostrar aviso na tela: mostra "Botplay: ON"

    F2 liga/desliga o bot na hora, sem sair da música.

    Assim que a música começa, este script escreve uma
    linha no console de debug do jogo (tecla padrão do
    Psych pra abrir o console: NUMPAD 1 ou o botão de
    bug no canto). Se essa linha não aparecer, o mod
    não está sendo carregado (confira o passo a passo
    de instalação).
]]

------------------------------------------------
-- Janelas de tempo padrão do Psych Engine (ms),
-- usadas pra calcular o atraso de cada rating.
-- Se você mudou a "Sensibilidade de Julgamento" nas
-- opções do jogo, pode ajustar esses valores aqui.
------------------------------------------------
local janelaSick = 45
local janelaGood = 90
local janelaBad  = 135
local janelaShit = janelaBad + 10 -- fica seguro abaixo do limite de "tooLate" (~166ms)

local atrasoPorRating = {
	['Sick!'] = 0,
	['Good']  = (janelaSick + janelaGood) / 2,
	['Bad']   = (janelaGood + janelaBad) / 2,
	['Shit!'] = janelaShit,
}
local opcoesDeRating = {'Sick!', 'Good', 'Bad', 'Shit!'} -- usadas no modo "Random"
local duracaoDoGlow = 0.15 -- segundos que a seta fica brilhando depois do acerto

------------------------------------------------
-- Valores padrão (só são usados se, por algum
-- motivo, não der pra ler as Configurações do Mod)
------------------------------------------------
local botAtivo   = true
local botRating  = 'Sick!'
local mostrarTxt = false
------------------------------------------------

local teclaAlternar = 'F2'
local escolhasAleatorias = {} -- memória do rating sorteado por nota, no modo "Random"
local avisouErro = false      -- pra só avisar de erro uma vez, sem spammar a tela

function onCreate()
	local valor

	valor = getModSetting('botplay_enabled')
	if valor ~= nil then botAtivo = valor end

	valor = getModSetting('botplay_rating')
	if valor ~= nil then botRating = valor end

	valor = getModSetting('botplay_show_text')
	if valor ~= nil then mostrarTxt = valor end

	if mostrarTxt then
		makeLuaText('avisoBot', 'Botplay: ON', 0, 5, 5)
		setTextSize('avisoBot', 28)
		setTextColor('avisoBot', 'yellow')
		setTextBorder('avisoBot', 2, 'black', 'outline')
		addLuaText('avisoBot')
		setProperty('avisoBot.visible', botAtivo)
	end

	if mostrarTxt then
		debugPrint('[SA Bot Play v2] Carregado! Bot=' .. tostring(botAtivo) .. ' Rating=' .. tostring(botRating), 'yellow')
	end
end

function onUpdate(elapsed)
	if keyboardJustPressed(teclaAlternar) then
		botAtivo = not botAtivo
		if mostrarTxt then
			setProperty('avisoBot.visible', botAtivo)
		end
	end

	if not botAtivo then return end

	local songPos = getSongPosition()
	local totalNotas = getProperty('notes.length')
	if totalNotas == nil or totalNotas <= 0 then return end

	for i = 0, totalNotas - 1 do
		local sucesso, erro = pcall(function()
			local ehDoJogador = getPropertyFromGroup('notes', i, 'mustPress')
			if ehDoJogador == true then
				local jaFoiAcertada = getPropertyFromGroup('notes', i, 'wasGoodHit')
				local ignorada       = getPropertyFromGroup('notes', i, 'ignoreNote')
				local bloqueada      = getPropertyFromGroup('notes', i, 'blockHit')

				if jaFoiAcertada ~= true and ignorada ~= true and bloqueada ~= true then
					local tempoDaNota = getPropertyFromGroup('notes', i, 'strumTime')
					local direcao     = getPropertyFromGroup('notes', i, 'noteData')

					local ratingAlvo = botRating
					if ratingAlvo == 'Random' then
						local chave = tostring(tempoDaNota) .. ':' .. tostring(direcao)
						if escolhasAleatorias[chave] == nil then
							escolhasAleatorias[chave] = opcoesDeRating[getRandomInt(1, 4)]
						end
						ratingAlvo = escolhasAleatorias[chave]
					end

					local atraso = atrasoPorRating[ratingAlvo] or 0
					if tempoDaNota ~= nil and songPos >= (tempoDaNota + atraso) then
						callMethod('goodNoteHit', {instanceArg('notes.members[' .. i .. ']')})
						-- sem isso, a seta fica brilhando pra sempre: como o bot nao
						-- "solta" a tecla de verdade, o jogo nunca manda ela voltar
						-- pro normal sozinho, entao a gente força o reset aqui.
						if direcao ~= nil then
							setPropertyFromGroup('playerStrums', direcao, 'resetAnim', duracaoDoGlow)
						end
					end
				end
			end
		end)

		if not sucesso and not avisouErro then
			avisouErro = true
			debugPrint('[SA Bot Play v2] Erro no loop: ' .. tostring(erro), 'red')
		end
	end
end

function onDestroy()
	if mostrarTxt then
		removeLuaText('avisoBot')
	end
end