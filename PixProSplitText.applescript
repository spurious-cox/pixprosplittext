-- PixProSplitText — split one text layer into any number of columns or rows
--
-- Named PixProTextColumns until 2026-09-20, when rows were added and the old
-- name only described half of what it does.
--
-- Rewritten 2026-09-20. The original split a text layer in two by counting
-- LINEFEEDS, which only worked on text that had been typed with line breaks in
-- the right places: a wrapped paragraph has none, so one column got everything.
-- It also edited the original layer in place, so the text you started with was
-- gone, and it bound to the name "Pixelmator Pro" at compile time, which since
-- the Creator Studio rebrand can be the wrong app.
--
-- Now: the text is divided by LENGTH at word boundaries, so the columns come
-- out about the same size whatever the text looks like; the original is kept,
-- hidden, and the columns are new layers named <original>_1 … <original>_n.
-- The whole set — the columns and the hidden original — is gathered into one
-- group named after the original layer.
--
-- The columns share the original's styling, because each is a duplicate of it,
-- and are laid out to FIT THE DOCUMENT: a text layer can hang off the side of
-- the canvas, and columns inheriting that would be unusable. Their height is
-- left alone, so long text still runs off the bottom.
--
-- Hidden text layers are ignored throughout. A hidden layer is one the user has
-- put aside — often the original from an earlier run of this very script.

property scriptVersion : "8.5.4"
property kPixIDs : {"com.apple.pixelmator", "com.pixelmatorteam.pixelmator.x"}
-- Set by pixTarget() before anything talks to Pixelmator.
property pixApp : ""
-- Share of each piece's pitch left empty, so neighbors do not touch.
property kGutterFraction : 0.08
-- More than this many pieces of one block of text is a mistake, not a wish.
property kMaxPieces : 20
-- A layer must span at least this share of the document's width before it can
-- be divided into rows. Shape is no guide: a column out of a three-way split
-- is wider than it is tall, and still far too narrow to cut into rows.
property kRowMinWidthFraction : 0.5
-- Where the header sits, and how much room is left under it, in points.
property kTopMargin : 24
property kHeaderGap : 16

on pixTarget()
	set rawPaths to {}
	try
		set psOut to do shell script "/bin/ps -Axo args= | /usr/bin/grep '/Contents/MacOS/Pixelmator' | /usr/bin/grep -v grep | /usr/bin/sed 's|/Contents/MacOS/.*||' | /usr/bin/sort -u"
		-- `do shell script` separates lines with RETURN, not linefeed. Split on
		-- the wrong one and every path arrives glued into a single string.
		set AppleScript's text item delimiters to return
		set rawPaths to text items of psOut
		set AppleScript's text item delimiters to ""
	end try
	
	-- Keep only genuine Pixelmator Pro builds, identified by the bundle id in
	-- each app's OWN Info.plist. Nothing here depends on what the app is
	-- called or where it lives, so this works on any Mac: renamed bundles,
	-- App Store or Setapp copies, apps in ~/Applications, all fine. It also
	-- excludes the classic Pixelmator (com.pixelmatorteam.pixelmator), whose
	-- dictionary is different and which would fail halfway through.
	set candidates to {}
	repeat with rp in rawPaths
		set p to rp as text
		if p is not "" then
			try
				set theID to do shell script "/usr/bin/defaults read " & quoted form of (p & "/Contents/Info") & " CFBundleIdentifier"
				if theID is in kPixIDs then set end of candidates to p
			end try
		end if
	end repeat
	if candidates is {} then return ""
	
	-- Which of them, if any, is frontmost. The frontmost process's pid maps
	-- back to its bundle path through ps.
	set frontPath to ""
	try
		-- Bounded: asking System Events which app is frontmost needs Automation
		-- permission, and on a first run that call sits there waiting for a
		-- consent prompt. If the prompt does not appear — and for a freshly
		-- built applet it may not — the app hangs with no window and nothing
		-- to click. Five seconds, then carry on: the frontmost check only
		-- orders the candidates, it does not find them.
		with timeout of 5 seconds
			tell application "System Events"
				set fpid to unix id of (first application process whose frontmost is true)
			end tell
		end timeout
		set frontPath to do shell script "/bin/ps -p " & fpid & " -o args= | /usr/bin/sed 's|/Contents/MacOS/.*||'"
	end try
	
	set ordered to {}
	repeat with c in candidates
		set cc to c as text
		if cc is equal to frontPath then set end of ordered to cc
	end repeat
	repeat with c in candidates
		set cc to c as text
		if cc is not equal to frontPath then set end of ordered to cc
	end repeat
	
	repeat with c in ordered
		set cc to c as text
		try
			using terms from application "Pixelmator Pro Creator Studio"
				tell application cc
					if (count of documents) > 0 then return cc
				end tell
			end using terms from
		end try
	end repeat
	return item 1 of ordered
end pixTarget

on dialogTitle()
	return "PixProSplitText v" & scriptVersion
end dialogTitle

-- EVERY dialog goes through these three handlers, and none of them may be
-- called from inside a `tell application` block.
--
-- A `display dialog` or `choose from list` written inside a tell-Pixelmator
-- block is presented BY PIXELMATOR. If that copy of Pixelmator is not
-- frontmost — and more than one build can be installed, one of them idling on
-- another Space — the dialog opens somewhere the user never sees, and the
-- script simply hangs with nothing on screen. Called with `my` from top level,
-- the dialog belongs to this applet, and activating first puts it in front.
on bringForward()
	try
		tell me to activate
	end try
end bringForward

on askChoice(promptText, itemList, okName)
	my bringForward()
	return choose from list itemList with title my dialogTitle() with prompt promptText default items {item 1 of itemList} OK button name okName cancel button name "Cancel"
end askChoice

on askText(promptText, defaultText, okName)
	my bringForward()
	set reply to display dialog promptText default answer defaultText buttons {"Cancel", okName} default button okName cancel button "Cancel" with title my dialogTitle()
	return text returned of reply
end askText

on askCountAndDirection(promptText, defaultText)
	-- One dialog does both jobs: the field holds how many, and which button
	-- was pressed says whether they run across or down. A separate dialog for
	-- the direction would be one more thing to click for no more information.
	my bringForward()
	set reply to display dialog promptText default answer defaultText buttons {"Cancel", "Rows", "Columns"} default button "Columns" cancel button "Cancel" with title my dialogTitle()
	return {text returned of reply, button returned of reply}
end askCountAndDirection

on alertUser(msg)
	my bringForward()
	display dialog msg buttons {"OK"} default button "OK" with title my dialogTitle()
end alertUser

-- Divide text into `colCount` pieces of roughly equal length, breaking only
-- between words. Paragraph breaks are kept where they fall.
--
-- Splitting by length rather than by line is the whole point of the rewrite:
-- a wrapped paragraph contains no line breaks at all, and the old split by
-- linefeed put all of it in one column.
on splitBalanced(theText, colCount)
	set theText to my normalizeBreaks(theText)
	set total to count of characters of theText
	if total is 0 then return {}
	
	set AppleScript's text item delimiters to linefeed
	set paras to text items of theText
	set AppleScript's text item delimiters to ""
	
	set target to total / colCount
	set columns to {}
	set current to ""
	set placed to 0
	
	repeat with pIndex from 1 to count of paras
		set para to item pIndex of paras
		set AppleScript's text item delimiters to space
		set words_ to text items of para
		set AppleScript's text item delimiters to ""
		
		set firstWordOfPara to true
		repeat with w in words_
			set theWord to w as text
			-- An empty item is a run of spaces or a blank line; keeping it
			-- would drift the spacing, and dropping it costs nothing.
			if theWord is not "" then
				if current is "" then
					set current to theWord
				else if firstWordOfPara then
					set current to current & linefeed & theWord
				else
					set current to current & space & theWord
				end if
				set firstWordOfPara to false
				
				-- Close this column once it has its share, as long as there
				-- is still text and still columns left to fill.
				if (count of columns) < (colCount - 1) then
					set placedSoFar to placed + (count of characters of current)
					if placedSoFar ≥ (target * ((count of columns) + 1)) then
						set end of columns to current
						set placed to placed + (count of characters of current)
						set current to ""
						set firstWordOfPara to true
					end if
				end if
			end if
		end repeat
		-- A paragraph boundary: the next word starts a new line, unless the
		-- column was just closed.
		if current is not "" then set firstWordOfPara to true
	end repeat
	
	if current is not "" then set end of columns to current
	-- Fewer words than columns: the empty ones are still made, so the layer
	-- names run 1..n as promised and nothing silently goes missing.
	repeat while (count of columns) < colCount
		set end of columns to ""
	end repeat
	return columns
end splitBalanced

on normalizeBreaks(theText)
	set AppleScript's text item delimiters to (ASCII character 13) & (ASCII character 10)
	set parts to text items of theText
	set AppleScript's text item delimiters to linefeed
	set theText to parts as text
	set AppleScript's text item delimiters to return
	set parts to text items of theText
	set AppleScript's text item delimiters to linefeed
	set theText to parts as text
	set AppleScript's text item delimiters to ""
	return theText
end normalizeBreaks

on uniqueEntry(layerName, wordCount, takenEntries)
	-- What one row of the chooser reads as. Two layers can share a name, and
	-- the list hands back only the string that was clicked, so each row has to
	-- be different from every other.
	set shown to layerName & "  —  " & wordCount & " words"
	set n to 1
	repeat while shown is in takenEntries
		set n to n + 1
		set shown to layerName & "  (" & n & ")  —  " & wordCount & " words"
	end repeat
	return shown
end uniqueEntry

on wordsAndBreaks(theText)
	-- The text as a list of words, plus a matching list saying which of them
	-- starts a new paragraph. Splitting has to happen between words, and the
	-- paragraph breaks have to survive being reassembled into columns.
	set theText to my normalizeBreaks(theText)
	set AppleScript's text item delimiters to linefeed
	set paras to text items of theText
	set AppleScript's text item delimiters to ""
	set wordList to {}
	set breakList to {}
	repeat with pIndex from 1 to count of paras
		set AppleScript's text item delimiters to space
		set words_ to text items of (item pIndex of paras)
		set AppleScript's text item delimiters to ""
		set firstOfPara to true
		repeat with w in words_
			set theWord to w as text
			if theWord is not "" then
				set end of wordList to theWord
				set end of breakList to (firstOfPara and (pIndex > 1))
				set firstOfPara to false
			end if
		end repeat
	end repeat
	return {wordList, breakList}
end wordsAndBreaks

on assemble(wordList, breakList, fromIdx, toIdx)
	if toIdx < fromIdx then return ""
	set out to item fromIdx of wordList
	repeat with k from (fromIdx + 1) to toIdx
		if item k of breakList then
			set out to out & linefeed & (item k of wordList)
		else
			set out to out & space & (item k of wordList)
		end if
	end repeat
	return out
end assemble

on freeName(base, takenNames)
	-- Layer names are not unique in Pixelmator, and two layers with the same
	-- name are indistinguishable in any list the user is shown.
	set candidate to base
	set n to 1
	repeat while candidate is in takenNames
		set n to n + 1
		set candidate to base & " (" & n & ")"
	end repeat
	return candidate
end freeName

on run
	set pixApp to pixTarget()
	if pixApp is "" then
		my alertUser("Pixelmator Pro is not running. Open Pixelmator Pro and a document with a text layer, then try again.")
		return
	end if
	
	using terms from application "Pixelmator Pro Creator Studio"
		tell application pixApp
			if (count of documents) is 0 then
				my alertUser("No document is open in Pixelmator Pro.")
				return
			end if
			
			tell front document
				-- Text layers can live inside groups, to any depth, so the
				-- document is walked rather than just its top level. Each
				-- layer is remembered together with the CONTAINER that holds
				-- it: `text layer id X` only resolves within its own parent,
				-- and duplicating, naming and grouping all have to happen
				-- there too. A layer's position is in document coordinates
				-- either way, so the layout needs no translation.
				set docRef to it
				set allIds to {}
				set allNames to {}
				set allVisible to {}
				set allWords to {}
				set allContainers to {}
				set pending to {docRef}
				repeat while (count of pending) > 0
					set thisContainer to item 1 of pending
					if (count of pending) > 1 then
						set pending to items 2 thru -1 of pending
					else
						set pending to {}
					end if
					repeat with L in (layers of thisContainer)
						if class of L is text layer then
							set end of allIds to (id of L)
							set end of allNames to (name of L)
							set end of allVisible to (visible of L)
							set theCount to 0
							try
								set theCount to count of words of (text content of L as text)
							end try
							set end of allWords to theCount
							set end of allContainers to thisContainer
						else if class of L is group layer then
							set end of pending to (contents of L)
						end if
					end repeat
				end repeat

				-- A selected text layer is the obvious subject; only ask when
				-- there is nothing to go on.
				set sourceId to ""
				set srcContainer to docRef
				try
					repeat with L in (selected layers)
						if (class of L is text layer) and (visible of L) then
							set sourceId to (id of L)
							exit repeat
						end if
					end repeat
				end try

				if sourceId is not "" then
					repeat with k from 1 to count of allIds
						if item k of allIds is sourceId then
							set srcContainer to item k of allContainers
							exit repeat
						end if
					end repeat
				else
					-- Both lists are gathered in one pass: if nothing is
					-- visible, a hidden layer can still be the one the user
					-- means, and offering to show it beats refusing.
					set candidateIds to {}
					set candidateNames to {}
					set candidateContainers to {}
					set hiddenIds to {}
					set hiddenNames to {}
					set hiddenContainers to {}
					repeat with k from 1 to count of allIds
						if item k of allVisible then
							set end of candidateNames to my uniqueEntry(item k of allNames, item k of allWords, candidateNames)
							set end of candidateIds to (item k of allIds)
							set end of candidateContainers to (item k of allContainers)
						else
							set end of hiddenNames to my uniqueEntry(item k of allNames, item k of allWords, hiddenNames)
							set end of hiddenIds to (item k of allIds)
							set end of hiddenContainers to (item k of allContainers)
						end if
					end repeat

					if candidateIds is {} and hiddenIds is {} then
						my alertUser("This document has no text layer to split.")
						return
					end if

					if candidateIds is {} then
						-- Every text layer is hidden, which is usually the
						-- original from an earlier run of this script.
						set choice to my askChoice("Every text layer in this document is hidden. Choose one to show and split.", hiddenNames, "Show and Split")
						if choice is false then return
						set wanted to item 1 of choice
						repeat with k from 1 to count of hiddenNames
							if item k of hiddenNames is wanted then
								set sourceId to (item k of hiddenIds)
								set srcContainer to (item k of hiddenContainers)
								set visible of (text layer id sourceId of srcContainer) to true
								exit repeat
							end if
						end repeat
					else
						set choice to my askChoice("Which text layer should be split?", candidateNames, "Choose")
						if choice is false then return
						set wanted to item 1 of choice
						repeat with k from 1 to count of candidateNames
							if item k of candidateNames is wanted then
								set sourceId to (item k of candidateIds)
								set srcContainer to (item k of candidateContainers)
								exit repeat
							end if
						end repeat
					end if
				end if

				set theLayer to text layer id sourceId of srcContainer

				-- Renaming belongs with choosing, but `choose from list` has
				-- no text field, so it is its own dialog. It is offered on
				-- both paths: a layer that was already selected is just as
				-- likely to be called "Text" as one picked from the list.
				-- Leaving the name alone is the default, and the columns and
				-- their group are named from whatever is confirmed here.
				set newName to my askText("Name for this layer. The pieces will be named after it.", (name of theLayer), "Continue")
				if newName is not "" and newName is not (name of theLayer) then
					set name of theLayer to newName
				end if

				set sourceName to name of theLayer
				set sourceText to text content of theLayer as text
				if sourceText is "" then
					my alertUser("“" & sourceName & "” has no text in it.")
					return
				end if
				
				set {answer, direction} to my askCountAndDirection("Split “" & sourceName & "” into how many pieces?" & return & return & "Columns run across the page, rows run down it.", "2")
				set isRows to (direction is "Rows")
				-- A column is taller than it is wide, and slicing one into
				-- rows gives stubs a few words each. Splitting a wide row into
				-- columns is the useful direction and stays allowed.
				set srcShapeWidth to width of theLayer
				if srcShapeWidth < 0 then set srcShapeWidth to -srcShapeWidth
				-- Width against the document decides this, not the layer's
				-- proportions.
				set rowMinWidth to width * kRowMinWidthFraction
				if isRows and (srcShapeWidth < rowMinWidth) then
					my alertUser("“" & sourceName & "” is " & (srcShapeWidth as integer) & " points wide, and rows need at least " & (rowMinWidth as integer) & " — half the width of the document. Split it into columns instead.")
					return
				end if
				if isRows then
					set unitWord to "rows"
					set unitOne to "row"
				else
					set unitWord to "columns"
					set unitOne to "column"
				end if
				try
					set colCount to answer as integer
				on error
					my alertUser("“" & answer & "” is not a number.")
					return
				end try
				if colCount < 2 then
					my alertUser("Two " & unitWord & " is the fewest there is.")
					return
				end if
				if colCount > kMaxPieces then
					my alertUser("That is more " & unitWord & " than this makes sense for — " & kMaxPieces & " is the most.")
					return
				end if
				
				-- Columns are filled by MEASURED HEIGHT, not by character
				-- count. Counting characters puts the break at an arbitrary
				-- word, which leaves the last line of a column holding one or
				-- two words with the rest of the line empty. Filling each
				-- column until the next word would not fit breaks at a line
				-- instead, so every column but the last is full to the bottom.
				set {wordList, breakList} to my wordsAndBreaks(sourceText)
				set wordTotal to count of wordList
				if wordTotal is 0 then
					my alertUser("“" & sourceName & "” has no words to split.")
					return
				end if
				
				-- A flipped layer reports a NEGATIVE width, and laying out from
				-- one would run the columns off the canvas backwards.
				set srcWidth to width of theLayer
				if srcWidth < 0 then set srcWidth to -srcWidth
				set {x0, y0} to position of theLayer
				
				-- Fit the canvas. The source may be wider than the document or
				-- hang off its left edge — columns that inherited that would
				-- be unreachable. Height is deliberately not clamped: long
				-- text is expected to run past the bottom.
				-- Bare `width` inside a tell-document block is the DOCUMENT's
				-- width; `width of front document` fails here, because the
				-- reference resolves inside the document it is already in.
				set docWidth to width
				set span to srcWidth
				if span > docWidth then set span to docWidth
				if x0 < 0 then set x0 to 0
				if (x0 + span) > docWidth then set x0 to docWidth - span
				if x0 < 0 then set x0 to 0
				if y0 < 0 then set y0 to 0

				-- The pieces stay inside the source's own box. Splitting a row
				-- that an earlier run produced has to work within THAT row —
				-- filling the page instead laid the new columns straight over
				-- the rows underneath it.
				set srcHeight to height of theLayer
				if srcHeight < 0 then set srcHeight to -srcHeight
				
				
				-- A header across the top, carrying the layer's name, and the
				-- whole block moved up under it. The header is a duplicate of
				-- the source, so it is in the same font as the text it labels.
				set beforeIds to {}
				repeat with L in (layers of srcContainer)
					set end of beforeIds to (id of L)
				end repeat
				duplicate (text layer id sourceId of srcContainer)
				set headerLayer to missing value
				repeat 40 times
					repeat with L in (layers of srcContainer)
						if (id of L) is not in beforeIds then
							set headerLayer to contents of L
							exit repeat
						end if
					end repeat
					if headerLayer is not missing value then exit repeat
					delay 0.1
				end repeat
				if headerLayer is missing value then
					my alertUser("Pixelmator Pro did not make the header layer.")
					return
				end if
				set takenNames to {}
				repeat with L in (layers of srcContainer)
					set end of takenNames to (name of L)
				end repeat
				set headerName to my freeName(sourceName & "_header", takenNames)
				set name of headerLayer to headerName
				-- Content first: a text layer resizes itself to whatever it
				-- holds, so a width set before the text is replaced is thrown
				-- away — the header came out as wide as its own word and the
				-- centering had nothing to centre within.
				set text content of headerLayer to sourceName
				set width of headerLayer to span
				set horizontal alignment of headerLayer to center
				-- Position LAST: changing the text moves the layer, so a
				-- position set beforehand does not survive.
				set headerId to (id of headerLayer)

				-- The header sits directly above the block it labels, not at
				-- the top of the page: a row halfway down the document has to
				-- keep its own place, or the pieces land on top of whatever is
				-- already there. The block only moves down when there is no
				-- room above it for the header.
				set headerHeight to height of headerLayer
				set headerY to y0 - headerHeight - kHeaderGap
				if headerY < kTopMargin then
					set headerY to kTopMargin
					set y0 to headerY + headerHeight + kHeaderGap
					set position of (text layer id sourceId of srcContainer) to {x0, y0}
				end if
				set position of headerLayer to {x0, headerY}

				-- How tall a piece may be before the next word is pushed to
				-- the one after it: the source's own depth, and never more
				-- than what is left of the canvas. Bare `height` is the
				-- DOCUMENT's height.
				set availHeight to srcHeight
				if availHeight > (height - y0) then set availHeight to height - y0
				if availHeight < 1 then set availHeight to height - y0

				-- One axis is the pitch the pieces step along, the other is
				-- the space each of them fills. Columns step across the page
				-- and fill it to the bottom; rows step down it, each with a
				-- share of the height, and every one as wide as the block.
				if isRows then
					set pitch to availHeight / colCount
					set pieceWidth to span
					set pieceLimit to pitch * (1 - kGutterFraction)
				else
					set pitch to span / colCount
					set pieceWidth to pitch * (1 - kGutterFraction)
					set pieceLimit to availHeight
				end if

				set wordIdx to 1
				set lastOverflows to false
				set newIds to {}
				repeat with i from 1 to colCount
					-- Which layers exist before the copy is made. `duplicate`
					-- returns nothing, and `current layer` is whatever was
					-- selected — often not the new copy at all — so the copy
					-- is identified as the id that was not there before.
					set beforeIds to {}
					repeat with L in (layers of srcContainer)
						set end of beforeIds to (id of L)
					end repeat
					
					duplicate (text layer id sourceId of srcContainer)
					
					set newLayer to missing value
					repeat 40 times
						repeat with L in (layers of srcContainer)
							if (id of L) is not in beforeIds then
								set newLayer to contents of L
								exit repeat
							end if
						end repeat
						if newLayer is not missing value then exit repeat
						-- The copy appears a moment after the command returns.
						delay 0.1
					end repeat
					if newLayer is missing value then
						my alertUser("Pixelmator Pro did not make column " & i & ".")
						return
					end if
					
					set takenNames to {}
					repeat with L in (layers of srcContainer)
						set end of takenNames to (name of L)
					end repeat
					set name of newLayer to my freeName(sourceName & "_" & i, takenNames)
					-- Width first: how much text fits depends on how it wraps,
					-- which depends on the width. Position comes after the
					-- text is settled, because every change of content moves
					-- the layer — set first, the pieces landed hundreds of
					-- points down the canvas.
					set width of newLayer to pieceWidth

					-- Every piece gets the SAME NUMBER OF LINES. Sharing by
					-- height alone leaves each piece a little under its share
					-- and the shortfall lands on the last one — a column two
					-- lines longer than its neighbours, hanging over whatever
					-- is below. Lines are all the same height, so the share is
					-- snapped to a whole number of them.
					if i is 1 then
						-- A layer's height is not its lines times a line: there
						-- is padding above and below that does not repeat. One
						-- line measured alone therefore reads as TALLER than
						-- each line actually adds, the share came out a line
						-- too generous, and the early pieces took a line each
						-- that the last one then went without — 9, 9 and 6
						-- where 8, 8 and 8 was right. Measuring one line and
						-- two gives the padding and the per-line step apart.
						set text content of newLayer to (item 1 of wordList)
						set oneLineHeight to height of newLayer
						set twoLineWords to 1
						set twoLineHeight to oneLineHeight
						repeat with k from 2 to wordTotal
							set text content of newLayer to my assemble(wordList, breakList, 1, k)
							if (height of newLayer) > oneLineHeight then
								set twoLineWords to k
								set twoLineHeight to height of newLayer
								exit repeat
							end if
						end repeat
						if twoLineWords is 1 then
							-- Everything fits on one line; nothing to divide.
							set lineStep to oneLineHeight
							set linePad to 0
						else
							set lineStep to twoLineHeight - oneLineHeight
							set linePad to oneLineHeight - lineStep
						end if

						set text content of newLayer to my assemble(wordList, breakList, 1, wordTotal)
						set wholeHeight to height of newLayer
						set totalLines to round ((wholeHeight - linePad) / lineStep)
						if totalLines < colCount then set totalLines to colCount
						-- Lines rarely divide evenly. Rounding every piece UP
						-- spends the spare lines early and starves the last:
						-- 22 lines in 3 went 8, 8, 6. Giving the remainder one
						-- line at a time makes it 8, 7, 7 — no two pieces more
						-- than a line apart, which is as even as lines allow.
						set baseLines to totalLines div colCount
						set extraLines to totalLines mod colCount
					end if

					-- Each piece is told its own share.
					set linesPer to baseLines
					if i ≤ extraLines then set linesPer to linesPer + 1
					-- Half a line of slack, so a rounding error cannot cost a
					-- piece its last line.
					set pieceLimit to linePad + (linesPer * lineStep) + (lineStep / 2)

					if wordIdx > wordTotal then
						set text content of newLayer to ""
					else if i is colCount then
						-- The last piece takes whatever is left. It may be
						-- shorter than the others, and it may run past the
						-- bottom of the canvas; both are expected.
						set text content of newLayer to my assemble(wordList, breakList, wordIdx, wordTotal)
						set wordIdx to wordTotal + 1
					else
						-- The most words that still fit, found by halving
						-- rather than by adding one word at a time: a page of
						-- text would otherwise cost hundreds of round trips
						-- to Pixelmator.
						set lo to 1
						set hi to wordTotal - wordIdx + 1
						set best to 1
						repeat while lo ≤ hi
							set mid to (lo + hi) div 2
							set text content of newLayer to my assemble(wordList, breakList, wordIdx, wordIdx + mid - 1)
							if (height of newLayer) ≤ pieceLimit then
								set best to mid
								set lo to mid + 1
							else
								set hi to mid - 1
							end if
						end repeat
						set text content of newLayer to my assemble(wordList, breakList, wordIdx, wordIdx + best - 1)
						set wordIdx to wordIdx + best
					end if
					if isRows then
						set position of newLayer to {x0, y0 + ((i - 1) * pitch)}
					else
						set position of newLayer to {x0 + ((i - 1) * pitch), y0}
					end if
					set end of newIds to (id of newLayer)
					-- Worth saying at the end: with too few pieces for the
					-- amount of text, the last one runs off the canvas.
					if i is colCount then
						-- Read the point into a variable first: indexing the
						-- result of `position of` inline fails to coerce.
						set lastPos to position of newLayer
						set lastOverflows to (((item 2 of lastPos) + (height of newLayer)) > height)
					end if
				end repeat
				
				-- The original is kept, out of the way: the columns sit on top
				-- of where it was, and deleting it would throw away the only
				-- copy of the text as it was written.
				set visible of (text layer id sourceId of srcContainer) to false
				
				-- Gather the columns and the original into one group. Each
				-- copy is inserted directly above its source, so the run is
				-- already contiguous — which `make group from` requires.
				try
					-- Built from the ids of the layers themselves. Index
					-- arithmetic looks simpler and is wrong: a copy is not
					-- reliably inserted above its source, so counting from the
					-- original swept up whatever happened to sit beside it —
					-- in one run, an unrelated image layer and a hidden layer
					-- of the same name, while the columns stayed outside.
					-- The header stays OUT of the group: it labels the block
					-- from outside it, so it can be moved, restyled or deleted
					-- without opening the group.
					set refs to {}
					repeat with cid in newIds
						set end of refs to (text layer id (cid as text) of srcContainer)
					end repeat
					set end of refs to (text layer id sourceId of srcContainer)
					set theGroup to make group from refs
					set takenNames to {}
					repeat with L in (layers of srcContainer)
						if (id of L) is not (id of theGroup) then set end of takenNames to (name of L)
					end repeat
					set name of theGroup to my freeName(sourceName, takenNames)
					set groupName to name of theGroup
				on error errText
					-- Grouping is tidying, not the job. Losing it is worth
					-- saying, but the columns themselves are already made.
					set groupName to ""
				end try
			end tell
		end tell
	end using terms from
	
	set overflowNote to ""
	if lastOverflows then set overflowNote to " The last " & unitOne & " runs past the bottom of the canvas — there is more text than " & colCount & " " & unitWord & " hold at this size."
	if groupName is "" then
		my alertUser("Made " & colCount & " " & unitWord & " from “" & sourceName & "”, and hid the original. They could not be put in a group — they are loose in the Layers list." & overflowNote)
	else
		my alertUser("Made " & colCount & " " & unitWord & " from “" & sourceName & "” in the group “" & groupName & "”, with the original hidden alongside them. The header is outside the group." & overflowNote)
	end if
end run

