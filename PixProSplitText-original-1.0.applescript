-- The original PixProTextColumns, as it was before the 2026-09-20 rewrite.
-- Recovered by decompiling the .scpt, which the rewrite replaced in place.
-- Kept for reference only; PixProTextColumns.applescript is the live source.

tell application "Pixelmator Pro Creator Studio"
	tell the front document
		set sel_lays to selected layers
		if ((count of sel_lays) = 1) then
			repeat with layerid from 1 to (count of sel_lays)
				set thisLayer to item layerid in sel_lays
				try
					set multiLineString to text content of thisLayer
				on error
					display dialog "This isn't a text layer. Can't divide into columns"
				end try
				set linesList to my splitTextIntoLines(multiLineString)
				
				#Count the number of lines
				set lineCount to count of linesList
				set midpoint to lineCount div 2
				
				#First half
				set firstHalfLines to items 1 thru midpoint of linesList
				set firstHalfString to my joinLines(firstHalfLines)
				#Second half
				set secondHalfLines to items (midpoint + 1) thru lineCount of linesList
				set secondHalfString to my joinLines(secondHalfLines)
				
				# Width of thisLayer
				set newwidth to ((width of thisLayer) div 2)
				
				tell thisLayer to set text content to firstHalfString
				tell thisLayer to set width to newwidth
				duplicate thisLayer
				
				set newLayer to current layer
				tell newLayer to set text content to secondHalfString
				set {firstXloc, firstYloc} to position of newLayer
				tell newLayer to set position to {firstXloc + newwidth, firstYloc}
			end repeat
		else
			display dialog "Too many selected layers. Choose 1"
		end if
	end tell
end tell
return "Done Splitting"

-- Function to split text into lines
on splitTextIntoLines(theText)
	set {saveTID, AppleScript's text item delimiters} to {AppleScript's text item delimiters, linefeed}
	set theLines to text items of theText
	set AppleScript's text item delimiters to saveTID
	return theLines
end splitTextIntoLines

-- Function to join lines into a single string
on joinLines(theLines)
	set {saveTID, AppleScript's text item delimiters} to {AppleScript's text item delimiters, linefeed}
	set joinedString to theLines as string
	set AppleScript's text item delimiters to saveTID
	return joinedString
end joinLines
