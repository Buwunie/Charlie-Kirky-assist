local botPlayEnabled    = true
local botPlayRating     = 'Sick!'
local showText          = false
local bigAssistEnabled  = false
local bigAssistRating   = 'Sick!'
local holdKeyEnabled    = false
local holdKeyRating     = 'Sick!'
local easyDoubleEnabled = false
local easyDoubleRating  = 'Sick!'
local noMissesEnabled   = false
local fakeKeyboardEnabled = false
local fakeKeyboardColor  = 'White'
local fakeKeyboardSize   = 0.75
local fakeKeyboardScroll = 'Downscroll'
local creditsEnabled     = false
local creditsTimer = 0
local creditsFadeStarted = false
local hitboxMultiplier  = 1.5
local glowDuration = 0.15
local chordTolerance = 10
local ratingPool = {'Sick!', 'Good', 'Bad', 'Shit!'}
local directionNames = {'left', 'down', 'up', 'right'}
local delayForRating = {}
local toggleKey = 'F2'
local randomChoices = {}
local lastHumanHitTime = {[0] = -math.huge, [1] = -math.huge, [2] = -math.huge, [3] = -math.huge}
local KB_NATIVE_W, KB_NATIVE_H = 343, 247
local KB_NATIVE_KEY = 96
local KB_MARGIN = 24
local KB_OFFSETS = {
	[0] = {x = 19,  y = 137},
	[1] = {x = 123, y = 137},
	[2] = {x = 123, y = 14},
	[3] = {x = 228, y = 137},
}
local kbAngles = {[0] = 270, [1] = 180, [2] = 0, [3] = 90}
local kbX, kbY, kbKeyPixelSize = 0, 0, KB_NATIVE_KEY
local kbFacePos = {}
local keyFlashDuration = 0.15
local keyFlashTimers = {[0] = 0, [1] = 0, [2] = 0, [3] = 0}
local function recalcFakeKeyboardLayout()
	local scale = fakeKeyboardSize
	local frameW, frameH = KB_NATIVE_W * scale, KB_NATIVE_H * scale
	kbX = 1280 - frameW - KB_MARGIN
	if fakeKeyboardScroll == 'Upscroll' then
		kbY = 720 - frameH - KB_MARGIN
	else
		kbY = KB_MARGIN
	end
	kbKeyPixelSize = KB_NATIVE_KEY * scale
	for dir = 0, 3 do
		kbFacePos[dir] = {
			x = kbX + KB_OFFSETS[dir].x * scale,
			y = kbY + KB_OFFSETS[dir].y * scale,
		}
	end
	return frameW, frameH
end
local function applyHitboxSize(multiplier)
	for i = 0, 2 do
		local base = getProperty('ratingsData[' .. i .. '].hitWindow')
		if base ~= nil then
			setProperty('ratingsData[' .. i .. '].hitWindow', base * multiplier)
		end
	end
	local baseZone = getPropertyFromClass('backend.Conductor', 'safeZoneOffset')
	if baseZone ~= nil then
		setPropertyFromClass('backend.Conductor', 'safeZoneOffset', baseZone * multiplier)
	end
end
local function forceHitInLane(direction, rating, requireCanBeHit)
	local songPos = getSongPosition()
	local totalNotes = getProperty('notes.length')
	if totalNotes == nil or totalNotes <= 0 then return false end
	local bestIndex, earliestTime = nil, nil
	for i = 0, totalNotes - 1 do
		pcall(function()
			local mustPress = getPropertyFromGroup('notes', i, 'mustPress')
			local noteDir     = getPropertyFromGroup('notes', i, 'noteData')
			if mustPress == true and noteDir == direction then
				local wasHit    = getPropertyFromGroup('notes', i, 'wasGoodHit')
				local canBeHit  = getPropertyFromGroup('notes', i, 'canBeHit')
				local ignored   = getPropertyFromGroup('notes', i, 'ignoreNote')
				local blocked   = getPropertyFromGroup('notes', i, 'blockHit')
				local isSustain = getPropertyFromGroup('notes', i, 'isSustainNote')
				local okToHit = wasHit ~= true and ignored ~= true and blocked ~= true and isSustain ~= true
				if requireCanBeHit then okToHit = okToHit and canBeHit == true end
				if okToHit then
					local strumTime = getPropertyFromGroup('notes', i, 'strumTime')
					if strumTime ~= nil and (earliestTime == nil or strumTime < earliestTime) then
						earliestTime = strumTime
						bestIndex = i
					end
				end
			end
		end)
	end
	if bestIndex == nil then return false end
	local targetRating = rating
	if targetRating == 'Random' then
		targetRating = ratingPool[getRandomInt(1, 4)]
	end
	local delay = delayForRating[targetRating] or 0
	setPropertyFromGroup('notes', bestIndex, 'strumTime', songPos - delay)
	callMethod('goodNoteHit', {instanceArg('notes.members[' .. bestIndex .. ']')})
	setPropertyFromGroup('playerStrums', direction, 'resetAnim', glowDuration)
	return true
end
local function processHeldLane(direction)
	local songPos = getSongPosition()
	local totalNotes = getProperty('notes.length')
	if totalNotes == nil or totalNotes <= 0 then return end
	local delay = delayForRating[holdKeyRating] or 0
	for i = 0, totalNotes - 1 do
		local success, err = pcall(function()
			local mustPress = getPropertyFromGroup('notes', i, 'mustPress')
			local noteDir     = getPropertyFromGroup('notes', i, 'noteData')
			if mustPress == true and noteDir == direction then
				local wasHit  = getPropertyFromGroup('notes', i, 'wasGoodHit')
				local ignored = getPropertyFromGroup('notes', i, 'ignoreNote')
				local blocked = getPropertyFromGroup('notes', i, 'blockHit')
				if wasHit ~= true and ignored ~= true and blocked ~= true then
					local strumTime = getPropertyFromGroup('notes', i, 'strumTime')
					if strumTime ~= nil and songPos >= (strumTime + delay) then
						callMethod('goodNoteHit', {instanceArg('notes.members[' .. i .. ']')})
						setPropertyFromGroup('playerStrums', direction, 'resetAnim', glowDuration)
					end
				end
			end
		end)
	end
end
local function findAnchorTime(direction)
	local totalNotes = getProperty('notes.length')
	if totalNotes == nil or totalNotes <= 0 then return nil end
	local anchorTime = nil
	for i = 0, totalNotes - 1 do
		pcall(function()
			local mustPress = getPropertyFromGroup('notes', i, 'mustPress')
			local noteDir     = getPropertyFromGroup('notes', i, 'noteData')
			if mustPress == true and noteDir == direction then
				local wasHit   = getPropertyFromGroup('notes', i, 'wasGoodHit')
				local canBeHit = getPropertyFromGroup('notes', i, 'canBeHit')
				if wasHit ~= true and canBeHit == true then
					local strumTime = getPropertyFromGroup('notes', i, 'strumTime')
					if strumTime ~= nil and (anchorTime == nil or strumTime < anchorTime) then
						anchorTime = strumTime
					end
				end
			end
		end)
	end
	return anchorTime
end
local function findAnchorTime(direction)
	local totalNotes = getProperty('notes.length')
	if totalNotes == nil or totalNotes <= 0 then return nil end
	local anchorTime = nil
	for i = 0, totalNotes - 1 do
		pcall(function()
			local mustPress = getPropertyFromGroup('notes', i, 'mustPress')
			local noteDir     = getPropertyFromGroup('notes', i, 'noteData')
			if mustPress == true and noteDir == direction then
				local wasHit   = getPropertyFromGroup('notes', i, 'wasGoodHit')
				local canBeHit = getPropertyFromGroup('notes', i, 'canBeHit')
				if wasHit ~= true and canBeHit == true then
					local strumTime = getPropertyFromGroup('notes', i, 'strumTime')
					if strumTime ~= nil and (anchorTime == nil or strumTime < anchorTime) then
						anchorTime = strumTime
					end
				end
			end
		end)
	end
	return anchorTime
end
local function collectCandidateNotes()
	local totalNotes = getProperty('notes.length')
	if totalNotes == nil or totalNotes <= 0 then return {} end
	local list = {}
	for i = 0, totalNotes - 1 do
		pcall(function()
			local mustPress = getPropertyFromGroup('notes', i, 'mustPress')
			if mustPress == true then
				local wasHit    = getPropertyFromGroup('notes', i, 'wasGoodHit')
				local canBeHit  = getPropertyFromGroup('notes', i, 'canBeHit')
				local ignored   = getPropertyFromGroup('notes', i, 'ignoreNote')
				local blocked   = getPropertyFromGroup('notes', i, 'blockHit')
				local isSustain = getPropertyFromGroup('notes', i, 'isSustainNote')
				if wasHit ~= true and canBeHit == true and ignored ~= true
					and blocked ~= true and isSustain ~= true then
					local strumTime = getPropertyFromGroup('notes', i, 'strumTime')
					local direction  = getPropertyFromGroup('notes', i, 'noteData')
					if strumTime ~= nil then
						list[#list + 1] = {index = i, time = strumTime, dir = direction}
					end
				end
			end
		end)
	end
	table.sort(list, function(a, b) return a.time < b.time end)
	return list
end
local function hitNoteCluster(pressedDirection, anchorTime)
	local candidates = collectCandidateNotes()
	if #candidates == 0 then return end
	local anchorPos = nil
	for pos, note in ipairs(candidates) do
		if note.dir == pressedDirection and math.abs(note.time - anchorTime) <= 1 then
			anchorPos = pos
			break
		end
	end
	if anchorPos == nil then return end
	local firstPos, lastPos = anchorPos, anchorPos
	while firstPos > 1 and (candidates[firstPos].time - candidates[firstPos - 1].time) <= chordTolerance do
		firstPos = firstPos - 1
	end
	while lastPos < #candidates and (candidates[lastPos + 1].time - candidates[lastPos].time) <= chordTolerance do
		lastPos = lastPos + 1
	end
	for pos = firstPos, lastPos do
		local note = candidates[pos]
		if note.dir ~= pressedDirection or note.time ~= anchorTime then
			pcall(function()
				local wasHit = getPropertyFromGroup('notes', note.index, 'wasGoodHit')
				if wasHit ~= true then
					local targetRating = easyDoubleRating
					if targetRating == 'Random' then
						targetRating = ratingPool[getRandomInt(1, 4)]
					end
					local delay = delayForRating[targetRating] or 0
					local songPos = getSongPosition()
					setPropertyFromGroup('notes', note.index, 'strumTime', songPos - delay)
					callMethod('goodNoteHit', {instanceArg('notes.members[' .. note.index .. ']')})
					setPropertyFromGroup('playerStrums', note.dir, 'resetAnim', glowDuration)
				end
			end)
		end
	end
end
local lastKnownCombo  = 0
local lastKnownHealth = 1.0
local lastKnownScore  = 0
local function undoMiss()
	setProperty('combo', lastKnownCombo)
	setProperty('health', lastKnownHealth)
	setProperty('songScore', lastKnownScore)
	local misses = getProperty('songMisses')
	if misses ~= nil and misses > 0 then setProperty('songMisses', misses - 1) end
	local played = getProperty('totalPlayed')
	if played ~= nil and played > 0 then setProperty('totalPlayed', played - 1) end
	pcall(callMethod, 'RecalculateRating', {false, false})
end
local function idleKeyImage()
	if fakeKeyboardColor == 'Black' then
		return 'fake_key_black'
	end
	return 'fake_key_white'
end
local function createFakeKeyboard()
	local frameW, frameH = recalcFakeKeyboardLayout()
	makeLuaSprite('fakeKbFrame', 'fake_frame', kbX, kbY)
	setGraphicSize('fakeKbFrame', frameW, frameH)
	setScrollFactor('fakeKbFrame', 0, 0)
	setObjectCamera('fakeKbFrame', 'hud')
	addLuaSprite('fakeKbFrame', true)
	for dir = 0, 3 do
		local pos = kbFacePos[dir]
		local tag = 'fakeKey' .. dir
		makeLuaSprite(tag, idleKeyImage(), pos.x, pos.y)
		setGraphicSize(tag, kbKeyPixelSize, kbKeyPixelSize)
		setProperty(tag .. '.angle', kbAngles[dir])
		setScrollFactor(tag, 0, 0)
		setObjectCamera(tag, 'hud')
		addLuaSprite(tag, true)
	end
end
local function removeFakeKeyboard()
	removeLuaSprite('fakeKbFrame', true)
	for dir = 0, 3 do
		removeLuaSprite('fakeKey' .. dir, true)
	end
end
local function setFakeKeyArt(direction, imageName)
	local pos = kbFacePos[direction]
	local tag = 'fakeKey' .. direction
	makeLuaSprite(tag, imageName, pos.x, pos.y)
	setGraphicSize(tag, kbKeyPixelSize, kbKeyPixelSize)
	setProperty(tag .. '.angle', kbAngles[direction])
	setScrollFactor(tag, 0, 0)
	setObjectCamera(tag, 'hud')
	addLuaSprite(tag, true)
end
local function flashFakeKey(direction)
	if not fakeKeyboardEnabled or direction == nil then return end
	setFakeKeyArt(direction, 'fake_key_press')
	keyFlashTimers[direction] = keyFlashDuration
end
function onCreate()
	local value
	value = getModSetting('botplay_enabled')
	if value ~= nil then botPlayEnabled = value end
	value = getModSetting('botplay_rating')
	if value ~= nil then botPlayRating = value end
	value = getModSetting('botplay_show_text')
	if value ~= nil then showText = value end
	value = getModSetting('bigassist_enabled')
	if value ~= nil then bigAssistEnabled = value end
	value = getModSetting('bigassist_rating')
	if value ~= nil then bigAssistRating = value end
	value = getModSetting('holdkey_enabled')
	if value ~= nil then holdKeyEnabled = value end
	value = getModSetting('holdkey_rating')
	if value ~= nil then holdKeyRating = value end
	value = getModSetting('easydouble_enabled')
	if value ~= nil then easyDoubleEnabled = value end
	value = getModSetting('easydouble_rating')
	if value ~= nil then easyDoubleRating = value end
	value = getModSetting('nomisses_enabled')
	if value ~= nil then noMissesEnabled = value end
	value = getModSetting('fakekeyboard_enabled')
	if value ~= nil then fakeKeyboardEnabled = value end
	value = getModSetting('fakekeyboard_color')
	if value ~= nil then fakeKeyboardColor = value end
	value = getModSetting('fakekeyboard_size')
	if value ~= nil then fakeKeyboardSize = value end
	value = getModSetting('fakekeyboard_scroll')
	if value ~= nil then fakeKeyboardScroll = value end
	value = getModSetting('credits_enabled')
	if value ~= nil then creditsEnabled = value end
	value = getModSetting('hitbox_size')
	if value ~= nil then hitboxMultiplier = value end
	applyHitboxSize(hitboxMultiplier)
	local sickWindow = getProperty('ratingsData[0].hitWindow') or (45 * hitboxMultiplier)
	local goodWindow = getProperty('ratingsData[1].hitWindow') or (90 * hitboxMultiplier)
	local badWindow  = getProperty('ratingsData[2].hitWindow') or (135 * hitboxMultiplier)
	local safeZone   = getPropertyFromClass('backend.Conductor', 'safeZoneOffset') or (166 * hitboxMultiplier)
	local shitMargin = (safeZone - badWindow) / 2
	if shitMargin > 15 then shitMargin = 15 end
	if shitMargin < 3 then shitMargin = 3 end
	delayForRating = {
		['Sick!'] = 0,
		['Good']  = (sickWindow + goodWindow) / 2,
		['Bad']   = (goodWindow + badWindow) / 2,
		['Shit!'] = badWindow + shitMargin,
	}
	lastKnownCombo  = getProperty('combo') or 0
	lastKnownHealth = getProperty('health') or 1.0
	lastKnownScore  = getProperty('songScore') or 0
	if fakeKeyboardEnabled then
		createFakeKeyboard()
	end
	if creditsEnabled then
		makeLuaSprite('creditsPic', 'credits_pic', 16, 16)
		setScrollFactor('creditsPic', 0, 0)
		setObjectCamera('creditsPic', 'hud')
		addLuaSprite('creditsPic', true)
		makeLuaText('creditsLabel', '@buwunieee', 124, 16, 16 + 130 + 6)
		setTextSize('creditsLabel', 16)
		setTextColor('creditsLabel', 'white')
		setTextBorder('creditsLabel', 2, 'black', 'outline')
		setTextAlignment('creditsLabel', 'center')
		setScrollFactor('creditsLabel', 0, 0)
		setObjectCamera('creditsLabel', 'hud')
		addLuaText('creditsLabel')
	end
	if showText then
		makeLuaText('assistText', 'Botplay: ON', 0, 5, 5)
		setTextSize('assistText', 28)
		setTextColor('assistText', 'yellow')
		setTextBorder('assistText', 2, 'black', 'outline')
		addLuaText('assistText')
		setProperty('assistText.visible', botPlayEnabled)
	end
end
function onUpdate(elapsed)
	if creditsEnabled and not creditsFadeStarted then
		creditsTimer = creditsTimer + elapsed
		if creditsTimer >= 3.0 then
			creditsFadeStarted = true
			doTweenAlpha('creditsPicFade', 'creditsPic', 0, 1.0, 'linear')
			doTweenAlpha('creditsLabelFade', 'creditsLabel', 0, 1.0, 'linear')
		end
	end
	if noMissesEnabled then
		lastKnownCombo  = getProperty('combo') or lastKnownCombo
		lastKnownHealth = getProperty('health') or lastKnownHealth
		lastKnownScore  = getProperty('songScore') or lastKnownScore
	end
	if keyboardJustPressed(toggleKey) then
		botPlayEnabled = not botPlayEnabled
		if showText then
			setProperty('assistText.visible', botPlayEnabled)
		end
	end
	if botPlayEnabled then
		local songPos = getSongPosition()
		local totalNotes = getProperty('notes.length')
		if totalNotes ~= nil and totalNotes > 0 then
			for i = 0, totalNotes - 1 do
				local success, err = pcall(function()
					local mustPress = getPropertyFromGroup('notes', i, 'mustPress')
					if mustPress == true then
						local wasHit   = getPropertyFromGroup('notes', i, 'wasGoodHit')
						local ignored  = getPropertyFromGroup('notes', i, 'ignoreNote')
						local blocked  = getPropertyFromGroup('notes', i, 'blockHit')
						if wasHit ~= true and ignored ~= true and blocked ~= true then
							local strumTime = getPropertyFromGroup('notes', i, 'strumTime')
							local direction  = getPropertyFromGroup('notes', i, 'noteData')
							local targetRating = botPlayRating
							local skipAsImpossible = false
							if targetRating == 'Random' then
								local key = tostring(strumTime) .. ':' .. tostring(direction)
								if randomChoices[key] == nil then
									randomChoices[key] = ratingPool[getRandomInt(1, 4)]
								end
								targetRating = randomChoices[key]
							elseif targetRating == 'Humanized' then
								local lastHit = lastHumanHitTime[direction] or -math.huge
								local humanThreshold = 45 + getRandomInt(0, 25)
								if strumTime ~= nil and (strumTime - lastHit) < humanThreshold then
									skipAsImpossible = true
								end
								targetRating = 'Sick!'
							end
							if not skipAsImpossible then
								local delay = delayForRating[targetRating] or 0
								if strumTime ~= nil and songPos >= (strumTime + delay) then
									callMethod('goodNoteHit', {instanceArg('notes.members[' .. i .. ']')})
									if direction ~= nil then
										setPropertyFromGroup('playerStrums', direction, 'resetAnim', glowDuration)
									end
									flashFakeKey(direction)
									if botPlayRating == 'Humanized' and direction ~= nil then
										lastHumanHitTime[direction] = strumTime
									end
								end
							end
						end
					end
				end)
			end
		end
	end
	if holdKeyEnabled then
		for dir = 0, 3 do
			if keyPressed(directionNames[dir + 1]) then
				processHeldLane(dir)
			end
		end
	end
	if fakeKeyboardEnabled then
		for dir = 0, 3 do
			if keyFlashTimers[dir] > 0 then
				keyFlashTimers[dir] = keyFlashTimers[dir] - elapsed
				if keyFlashTimers[dir] <= 0 then
					keyFlashTimers[dir] = 0
					setFakeKeyArt(dir, idleKeyImage())
				end
			end
		end
	end
end
function onKeyPressPre(key)
	local anchorTime = nil
	if easyDoubleEnabled then
		anchorTime = findAnchorTime(key)
	end
	local handled = false
	if holdKeyEnabled and forceHitInLane(key, holdKeyRating, true) then
		handled = true
	elseif bigAssistEnabled and forceHitInLane(key, bigAssistRating, true) then
		handled = true
	end
	if easyDoubleEnabled and anchorTime ~= nil then
		hitNoteCluster(key, anchorTime)
	end
	if handled then return Function_Stop end
	return nil
end
function noteMiss(id, direction, noteType, isSustainNote)
	if noMissesEnabled then
		undoMiss()
	end
end
function noteMissPress(direction)
	if noMissesEnabled then
		undoMiss()
	end
end
function onDestroy()
	if showText then
		removeLuaText('assistText')
	end
	if fakeKeyboardEnabled then
		removeFakeKeyboard()
	end
	if creditsEnabled then
		removeLuaSprite('creditsPic', true)
		removeLuaText('creditsLabel')
	end
end