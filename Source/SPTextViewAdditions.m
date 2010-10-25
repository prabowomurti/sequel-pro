//
//  $Id$
//
//  SPTextViewAdditions.m
//  sequel-pro
//
//  Created by Hans-Jörg Bibiko on April 05, 2009
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//  More info at <http://code.google.com/p/sequel-pro/>

@implementation NSTextView (SPTextViewAdditions)

/*
 * Returns the range of the current word.
 *   finds: [| := caret]  |word  wo|rd  word|
 * If | is in between whitespaces nothing will be selected.
 */
- (NSRange)getRangeForCurrentWord
{
	NSRange curRange = [self selectedRange];
	
	if (curRange.length)
        return curRange;
	
	NSUInteger curLocation = curRange.location;

	[self moveWordLeft:self];
	[self moveWordRightAndModifySelection:self];
	
	NSUInteger newStartRange = [self selectedRange].location;
	NSUInteger newEndRange = newStartRange + [self selectedRange].length;
	
	// if current location does not intersect with found range
	// then caret is at the begin of a word -> change strategy
	if(curLocation < newStartRange || curLocation > newEndRange)
	{
		[self setSelectedRange:curRange];
		[self moveWordRight:self];
		[self moveWordLeftAndModifySelection:self];
		newStartRange = [self selectedRange].location;
		newEndRange = newStartRange + [self selectedRange].length;
	}
	
	// how many space in front of the selection
	NSInteger bias = [self selectedRange].length - [[[[self string] substringWithRange:[self selectedRange]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length];
	[self setSelectedRange:NSMakeRange([self selectedRange].location+bias, [self selectedRange].length-bias)];
	newStartRange += bias;
	newEndRange -= bias;

	// is caret inside the selection still?
	if(curLocation < newStartRange || curLocation > newEndRange 
		|| [[[self string] substringWithRange:[self selectedRange]] rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound)
		[self setSelectedRange:curRange];
	
	NSRange wordRange = [self selectedRange];
	
	[self setSelectedRange:curRange];
	
	return(wordRange);
}

/*
 * Select current word.
 *   finds: [| := caret]  |word  wo|rd  word|
 * If | is in between whitespaces nothing will be selected.
 */
- (IBAction)selectCurrentWord:(id)sender
{
	[self setSelectedRange:[self getRangeForCurrentWord]];
}

/*
 * Select current line.
 */
- (IBAction)selectCurrentLine:(id)sender
{
	NSRange lineRange = [[self string] lineRangeForRange:[self selectedRange]];
	if(lineRange.location != NSNotFound && lineRange.length)
		[self setSelectedRange:lineRange];
	else
		NSBeep();
}

/*
 *
 */
- (IBAction)selectEnclosingBrackets:(id)sender
{
	NSUInteger caretPosition = [self selectedRange].location;
	NSUInteger stringLength = [[self string] length];
	unichar co, cc;
	
	if(caretPosition == 0 || caretPosition >= stringLength) return;

	NSInteger pcnt = 0;
	NSInteger bcnt = 0;
	NSInteger scnt = 0;

	NSInteger i;

	// look for the first non-balanced closing bracket
	for(i=caretPosition; i<stringLength; i++) {
		switch([[self string] characterAtIndex:i]) {
			case ')': 
			if(!pcnt) {
				co='(';cc=')';
				i=stringLength;
			}
			pcnt++; break;
			case '(': pcnt--; break;
			case ']': 
			if(!bcnt) {
				co='[';cc=']';
				i=stringLength;
			}
			bcnt++; break;
			case '[': bcnt--; break;
			case '}': 
			if(!scnt) {
				co='{';cc='}';
				i=stringLength;
			}
			scnt++; break;
			case '{': scnt--; break;
		}
	}
	
	NSInteger start = -1;
	NSInteger end = -1;
	NSInteger bracketCounter = 0;

	if([[self string] characterAtIndex:caretPosition] == cc)
		bracketCounter--;
	if([[self string] characterAtIndex:caretPosition] == co)
		bracketCounter++;

	for(i=caretPosition; i>=0; i--) {
		if([[self string] characterAtIndex:i] == co) {
			if(!bracketCounter) {
				start = i;
				break;
			}
			bracketCounter--;
		}
		if([[self string] characterAtIndex:i] == cc) {
			bracketCounter++;
		}
	}
	if(start < 0 ) return;

	bracketCounter = 0;
	for(i=caretPosition; i<stringLength; i++) {
		if([[self string] characterAtIndex:i] == co) {
			bracketCounter++;
		}
		if([[self string] characterAtIndex:i] == cc) {
			if(!bracketCounter) {
				end = i+1;
				break;
			}
			bracketCounter--;
		}
	}
	if(end < 0 || bracketCounter || end-start < 1) return;
	
	[self setSelectedRange:NSMakeRange(start, end-start)];
	
}

/*
 * Change selection or current word to upper case and preserves the selection.
 */
- (IBAction)doSelectionUpperCase:(id)sender
{
	NSRange curRange = [self selectedRange];
	NSRange selRange = (curRange.length) ? curRange : [self getRangeForCurrentWord];
	[self setSelectedRange:selRange];
	[self insertText:[[[self string] substringWithRange:selRange] uppercaseString]];
	[self setSelectedRange:curRange];
}

/*
 * Change selection or current word to lower case and preserves the selection.
 */
- (IBAction)doSelectionLowerCase:(id)sender
{
	NSRange curRange = [self selectedRange];
	NSRange selRange = (curRange.length) ? curRange : [self getRangeForCurrentWord];
	[self setSelectedRange:selRange];
	[self insertText:[[[self string] substringWithRange:selRange] lowercaseString]];
	[self setSelectedRange:curRange];
}

/*
 * Change selection or current word to title case and preserves the selection.
 */
- (IBAction)doSelectionTitleCase:(id)sender
{
	NSRange curRange = [self selectedRange];
	NSRange selRange = (curRange.length) ? curRange : [self getRangeForCurrentWord];
	[self setSelectedRange:selRange];
	[self insertText:[[[self string] substringWithRange:selRange] capitalizedString]];
	[self setSelectedRange:curRange];
}

/*
 * Change selection or current word according to Unicode's NFD and preserves the selection.
 */
- (IBAction)doDecomposedStringWithCanonicalMapping:(id)sender
{
	NSRange curRange = [self selectedRange];
	NSRange selRange = (curRange.length) ? curRange : [self getRangeForCurrentWord];
	[self setSelectedRange:selRange];
	NSString* convString = [[[self string] substringWithRange:selRange] decomposedStringWithCanonicalMapping];
	[self insertText:convString];
	
	// correct range for combining characters
	if(curRange.length)
		[self setSelectedRange:NSMakeRange(selRange.location, [convString length])];
	else
	// if no selection place the caret at the end of the current word
	{
		NSRange newRange = [self getRangeForCurrentWord];
		[self setSelectedRange:NSMakeRange(newRange.location + newRange.length, 0)];
	}
}

/*
 * Change selection or current word according to Unicode's NFKD and preserves the selection.
 */
- (IBAction)doDecomposedStringWithCompatibilityMapping:(id)sender
{
	NSRange curRange = [self selectedRange];
	NSRange selRange = (curRange.length) ? curRange : [self getRangeForCurrentWord];
	[self setSelectedRange:selRange];
	NSString* convString = [[[self string] substringWithRange:selRange] decomposedStringWithCompatibilityMapping];
	[self insertText:convString];
	
	// correct range for combining characters
	if(curRange.length)
		[self setSelectedRange:NSMakeRange(selRange.location, [convString length])];
	else
	// if no selection place the caret at the end of the current word
	{
		NSRange newRange = [self getRangeForCurrentWord];
		[self setSelectedRange:NSMakeRange(newRange.location + newRange.length, 0)];
	}
}

/*
 * Change selection or current word according to Unicode's NFC and preserves the selection.
 */
- (IBAction)doPrecomposedStringWithCanonicalMapping:(id)sender
{
	NSRange curRange = [self selectedRange];
	NSRange selRange = (curRange.length) ? curRange : [self getRangeForCurrentWord];
	[self setSelectedRange:selRange];
	NSString* convString = [[[self string] substringWithRange:selRange] precomposedStringWithCanonicalMapping];
	[self insertText:convString];
	
	// correct range for combining characters
	if(curRange.length)
		[self setSelectedRange:NSMakeRange(selRange.location, [convString length])];
	else
	// if no selection place the caret at the end of the current word
	{
		NSRange newRange = [self getRangeForCurrentWord];
		[self setSelectedRange:NSMakeRange(newRange.location + newRange.length, 0)];
	}
}

- (IBAction)doRemoveDiacritics:(id)sender
{

	NSRange curRange = [self selectedRange];
	NSRange selRange = (curRange.length) ? curRange : [self getRangeForCurrentWord];
	[self setSelectedRange:selRange];
	NSString* convString = [[[self string] substringWithRange:selRange] decomposedStringWithCanonicalMapping];
	NSArray* chars;
	chars = [convString componentsSeparatedByCharactersInSet:[NSCharacterSet nonBaseCharacterSet]];
	NSString* cleanString = [chars componentsJoinedByString:@""];
	[self insertText:cleanString];
	if(curRange.length)
		[self setSelectedRange:NSMakeRange(selRange.location, [cleanString length])];
	else
	// if no selection place the caret at the end of the current word
	{
		NSRange newRange = [self getRangeForCurrentWord];
		[self setSelectedRange:NSMakeRange(newRange.location + newRange.length, 0)];
	}
	
}

/*
 * Change selection or current word according to Unicode's NFKC to title case and preserves the selection.
 */
- (IBAction)doPrecomposedStringWithCompatibilityMapping:(id)sender
{
	NSRange curRange = [self selectedRange];
	NSRange selRange = (curRange.length) ? curRange : [self getRangeForCurrentWord];
	[self setSelectedRange:selRange];
	NSString* convString = [[[self string] substringWithRange:selRange] precomposedStringWithCompatibilityMapping];
	[self insertText:convString];
	
	// correct range for combining characters
	if(curRange.length)
		[self setSelectedRange:NSMakeRange(selRange.location, [convString length])];
	else
	// if no selection place the caret at the end of the current word
	{
		NSRange newRange = [self getRangeForCurrentWord];
		[self setSelectedRange:NSMakeRange(newRange.location + newRange.length, 0)];
	}
}


/*
 * Transpose adjacent characters, or if a selection is given reverse the selected characters.
 * If the caret is at the absolute end of the text field it transpose the two last charaters.
 * If the caret is at the absolute beginnng of the text field do nothing.
 * TODO: not yet combining-diacritics-safe
 */
- (IBAction)doTranspose:(id)sender
{
	NSRange curRange = [self selectedRange];
	NSRange workingRange = curRange;
	
	if(!curRange.length)
		@try // caret is in between two chars
		{
			if(curRange.location+1 > [[self string] length])
			{
				// caret is at the end of a text field
				// transpose last two characters
				[self moveLeftAndModifySelection:self];
				[self moveLeftAndModifySelection:self];
				workingRange = [self selectedRange];
			}
			else if(curRange.location == 0)
			{
				// caret is at the beginning of the text field
				// do nothing
				workingRange.length = 0;
			}
			else
			{
				// caret is in between two characters
				// reverse adjacent characters 
				NSRange twoCharRange = NSMakeRange(curRange.location-1, 2);
				[self setSelectedRange:twoCharRange];
				workingRange = twoCharRange;
			}
		}
		@catch(id ae)
		{ workingRange.length = 0; }

	
	
	// reverse string : TODO not yet combining diacritics safe!
	NSUInteger len = workingRange.length;
	if (len > 1)
	{
		NSMutableString *reversedStr = [NSMutableString stringWithCapacity:len];
		while (len > 0)
			[reversedStr appendString:
				[NSString stringWithFormat:@"%C", [[self string] characterAtIndex:--len+workingRange.location]]];

		[self insertText:reversedStr];
		[self setSelectedRange:curRange];
	}
}

/**
 * Inserts the preference's NULL value set by the user
 */
- (IBAction)insertNULLvalue:(id)sender
{

	id prefs = [NSUserDefaults standardUserDefaults];
	if([self respondsToSelector:@selector(insertText:)])
		if([prefs objectForKey:SPNullValue] && [[prefs objectForKey:SPNullValue] length])
			[self insertText:[prefs objectForKey:SPNullValue]];
		else
			[self insertText:@"NULL"];

}

/*
 * Increase the textView's font size by 1
 */
- (void)makeTextSizeLarger
{
	NSFont *aFont = [self font];
	BOOL editableStatus = [self isEditable];
	[self setEditable:YES];
	[self setFont:[[NSFontManager sharedFontManager] convertFont:aFont toSize:[aFont pointSize]+1]];
	[self setEditable:editableStatus];
}

/*
 * Decrease the textView's font size by 1 but not smaller than 4pt
 */
- (void)makeTextSizeSmaller
{
	NSFont *aFont = [self font];
	NSInteger newSize = ([aFont pointSize]-1 < 4) ? [aFont pointSize] : [aFont pointSize]-1;
	BOOL editableStatus = [self isEditable];
	[self setEditable:YES];
	[self setFont:[[NSFontManager sharedFontManager] convertFont:aFont toSize:newSize]];
	[self setEditable:editableStatus];
}


#pragma mark -
#pragma mark multi-touch trackpad support

/*
 * Trackpad two-finger zooming gesture for in/decreasing the font size
 */
- (void) magnifyWithEvent:(NSEvent *)anEvent
{

	//Avoid font resizing for NSTextViews in SPCopyTable or NSTableView
	if([[[[self delegate] class] description] isEqualToString:@"SPCopyTable"] 
		|| [[[[self delegate] class] description] isEqualToString:@"NSTableView"]) return;

	if([anEvent deltaZ]>5.0)
		[self makeTextSizeLarger];
	else if([anEvent deltaZ]<-5.0)
		[self makeTextSizeSmaller];
}

@end
