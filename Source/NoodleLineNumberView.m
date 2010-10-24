//
//  NoodleLineNumberView.m
//  Line View Test
//
//  Created by Paul Kim on 9/28/08.
//  Copyright (c) 2008 Noodlesoft, LLC. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//

// This version of the NoodleLineNumberView for Sequel Pro removes marker
// functionality and adds selection by clicking on the ruler.

#import "NoodleLineNumberView.h"

#include <tgmath.h>

#define DEFAULT_THICKNESS	22.0
#define RULER_MARGIN		5.0

@interface NoodleLineNumberView (Private)

- (NSMutableArray *)lineIndices;
- (void)invalidateLineIndices;
- (void)calculateLines;
- (NSDictionary *)textAttributes;

@end

@implementation NoodleLineNumberView

- (id)initWithScrollView:(NSScrollView *)aScrollView
{
	if ((self = [super initWithScrollView:aScrollView orientation:NSVerticalRuler]) != nil)
	{
		[self setClientView:[aScrollView documentView]];
		lineIndices = nil;
	}

	return self;
}

- (void)awakeFromNib
{
	[self setClientView:[[self scrollView] documentView]];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	if (lineIndices) [lineIndices release];
	[font release];

	[super dealloc];
}

- (void)setFont:(NSFont *)aFont
{
	if (font != aFont)
	{
		[font autorelease];
		font = [aFont retain];
	}
}

- (NSFont *)font
{
	if (font == nil)
	{
		return [NSFont labelFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]];
	}
    return font;
}

- (void)setTextColor:(NSColor *)color
{
	if (textColor != color)
	{
		[textColor autorelease];
		textColor  = [color retain];
	}
}

- (NSColor *)textColor
{
	if (textColor == nil)
	{
		return [NSColor colorWithCalibratedWhite:0.42 alpha:1.0];
	}
	return textColor;
}

- (void)setAlternateTextColor:(NSColor *)color
{
	if (alternateTextColor != color)
	{
		[alternateTextColor autorelease];
		alternateTextColor = [color retain];
	}
}

- (NSColor *)alternateTextColor
{
	if (alternateTextColor == nil)
	{
		return [NSColor whiteColor];
	}
	return alternateTextColor;
}

- (void)setBackgroundColor:(NSColor *)color
{
	if (backgroundColor != color)
	{
		[backgroundColor autorelease];
		backgroundColor = [color retain];
	}
}

- (NSColor *)backgroundColor
{
	return backgroundColor;
}

- (void)setClientView:(NSView *)aView
{
	id oldClientView;

	oldClientView = [self clientView];

	if ((oldClientView != aView) && [oldClientView isKindOfClass:[NSTextView class]])
	{
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextStorageDidProcessEditingNotification object:[(NSTextView *)oldClientView textStorage]];
	}
	[super setClientView:aView];
	if ((aView != nil) && [aView isKindOfClass:[NSTextView class]])
	{
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textDidChange:) name:NSTextStorageDidProcessEditingNotification object:[(NSTextView *)aView textStorage]];

		[self invalidateLineIndices];
	}
}

- (NSMutableArray *)lineIndices
{
	if (lineIndices == nil)
	{
		[self calculateLines];
	}
	return lineIndices;
}

- (void)invalidateLineIndices
{
	if (lineIndices) [lineIndices release], lineIndices = nil;
}

- (void)textDidChange:(NSNotification *)notification
{
	// Invalidate the line indices. They will be recalculated and recached on demand.
	[self invalidateLineIndices];

	[self setNeedsDisplay:YES];
}

- (NSUInteger)lineNumberForLocation:(CGFloat)location
{
	NSUInteger		line, count, index, rectCount, i;
	NSRectArray		rects;
	NSRect			visibleRect;
	NSLayoutManager	*layoutManager;
	NSTextContainer	*container;
	NSRange			nullRange;
	NSMutableArray	*lines;
	id				view;
		
	view = [self clientView];
	visibleRect = [[[self scrollView] contentView] bounds];
	
	lines = [self lineIndices];

	location += NSMinY(visibleRect);
	
	if ([view isKindOfClass:[NSTextView class]])
	{
		nullRange = NSMakeRange(NSNotFound, 0);
		layoutManager = [view layoutManager];
		container = [view textContainer];
		count = [lines count];
		
		for (line = 0; line < count; line++)
		{
			index = [NSArrayObjectAtIndex(lines, line) unsignedIntegerValue];
			
			rects = [layoutManager rectArrayForCharacterRange:NSMakeRange(index, 0)
								 withinSelectedCharacterRange:nullRange
											  inTextContainer:container
													rectCount:&rectCount];
			
			for (i = 0; i < rectCount; i++)
			{
				if ((location >= NSMinY(rects[i])) && (location < NSMaxY(rects[i])))
				{
					return line + 1;
				}
			}
		}	
	}
	return NSNotFound;
}

- (void)calculateLines
{
	id view;

	view = [self clientView];

	if ([view isKindOfClass:[NSTextView class]])
	{
		NSUInteger index, numberOfLines, stringLength, lineEnd, contentEnd;
		NSString *text;
		CGFloat oldThickness, newThickness;

		text = [view string];
		stringLength = [text length];
		// Switch off line numbering if text larger than 6MB
		// for performance reasons.
		// TODO improve performance maybe via threading
		if(stringLength>6000000)
			return;
		if (lineIndices) [lineIndices release];
		lineIndices = [[NSMutableArray alloc] init];

		index = 0;
		numberOfLines = 0;

		do
		{
			[lineIndices addObject:[NSNumber numberWithUnsignedInteger:index]];

			index = NSMaxRange([text lineRangeForRange:NSMakeRange(index, 0)]);
			numberOfLines++;
		}
		while (index < stringLength);

		// Check if text ends with a new line.
		[text getLineStart:NULL end:&lineEnd contentsEnd:&contentEnd forRange:NSMakeRange([[lineIndices lastObject] unsignedIntegerValue], 0)];
		if (contentEnd < lineEnd)
		{
			[lineIndices addObject:[NSNumber numberWithUnsignedInteger:index]];
		}

		oldThickness = [self ruleThickness];
		newThickness = [self requiredThickness];
		if (fabs(oldThickness - newThickness) > 1)
		{
			NSInvocation			*invocation;

			// Not a good idea to resize the view during calculations (which can happen during
			// display). Do a delayed perform (using NSInvocation since arg is a float).
			invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(setRuleThickness:)]];
			[invocation setSelector:@selector(setRuleThickness:)];
			[invocation setTarget:self];
			[invocation setArgument:&newThickness atIndex:2];

			[invocation performSelector:@selector(invoke) withObject:nil afterDelay:0.0];
		}
	}
}

- (NSUInteger)lineNumberForCharacterIndex:(NSUInteger)index inText:(NSString *)text
{
    NSUInteger			left, right, mid, lineStart;
	NSMutableArray		*lines;

	lines = [self lineIndices];
	
    // Binary search
    left = 0;
    right = [lines count];

    while ((right - left) > 1)
    {
        mid = (right + left) / 2;
        lineStart = [NSArrayObjectAtIndex(lines, mid) unsignedIntegerValue];
        
        if (index < lineStart)
        {
            right = mid;
        }
        else if (index > lineStart)
        {
            left = mid;
        }
        else
        {
            return mid;
        }
    }
    return left;
}

- (NSDictionary *)textAttributes
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [self font], NSFontAttributeName, 
            [self textColor], NSForegroundColorAttributeName,
            nil];
}

- (CGFloat)requiredThickness
{
	NSUInteger lineCount = [[self lineIndices] count];
	if(lineCount < 10)
		return ceil(MAX(DEFAULT_THICKNESS, [[NSString stringWithString:@"8"] sizeWithAttributes:[self textAttributes]].width + RULER_MARGIN * 2));
	else if(lineCount < 100)
		return ceil(MAX(DEFAULT_THICKNESS, [[NSString stringWithString:@"88"] sizeWithAttributes:[self textAttributes]].width + RULER_MARGIN * 2));
	else if(lineCount < 1000)
		return ceil(MAX(DEFAULT_THICKNESS, [[NSString stringWithString:@"888"] sizeWithAttributes:[self textAttributes]].width + RULER_MARGIN * 2));
	else if(lineCount < 10000)
		return ceil(MAX(DEFAULT_THICKNESS, [[NSString stringWithString:@"8888"] sizeWithAttributes:[self textAttributes]].width + RULER_MARGIN * 2));
	else if(lineCount < 100000)
		return ceil(MAX(DEFAULT_THICKNESS, [[NSString stringWithString:@"88888"] sizeWithAttributes:[self textAttributes]].width + RULER_MARGIN * 2));
	else if(lineCount < 1000000)
		return ceil(MAX(DEFAULT_THICKNESS, [[NSString stringWithString:@"888888"] sizeWithAttributes:[self textAttributes]].width + RULER_MARGIN * 2));
	else if(lineCount < 10000000)
		return ceil(MAX(DEFAULT_THICKNESS, [[NSString stringWithString:@"8888888"] sizeWithAttributes:[self textAttributes]].width + RULER_MARGIN * 2));
	else if(lineCount < 100000000)
		return ceil(MAX(DEFAULT_THICKNESS, [[NSString stringWithString:@"88888888"] sizeWithAttributes:[self textAttributes]].width + RULER_MARGIN * 2));
	else
		return 100;
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)aRect
{
    id			view;
	NSRect		bounds;

	bounds = [self bounds];

	if (backgroundColor != nil)
	{
		[backgroundColor set];
		NSRectFill(bounds);
		
		[[NSColor colorWithCalibratedWhite:0.58 alpha:1.0] set];
		[NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(bounds) - 0/5, NSMinY(bounds)) toPoint:NSMakePoint(NSMaxX(bounds) - 0.5, NSMaxY(bounds))];
	}
	
    view = [self clientView];
	
    if ([view isKindOfClass:[NSTextView class]])
    {
        NSLayoutManager			*layoutManager;
        NSTextContainer			*container;
        NSRect					visibleRect;
        NSRange					range, glyphRange, nullRange;
        NSString				*text, *labelText;
        NSUInteger				rectCount, index, line, count;
        NSRectArray				rects;
        CGFloat					ypos, yinset;
        NSDictionary			*textAttributes, *currentTextAttributes;
        NSSize					stringSize;
		NSMutableArray			*lines;

        layoutManager = [view layoutManager];
        container = [view textContainer];
        text = [view string];
        nullRange = NSMakeRange(NSNotFound, 0);
		
		yinset = [view textContainerInset].height;        
        visibleRect = [[[self scrollView] contentView] bounds];

        textAttributes = [self textAttributes];
		
		lines = [self lineIndices];

        // Find the characters that are currently visible
        glyphRange = [layoutManager glyphRangeForBoundingRect:visibleRect inTextContainer:container];
        range = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
        
        // Fudge the range a tad in case there is an extra new line at end.
        // It doesn't show up in the glyphs so would not be accounted for.
        range.length++;
        
        count = [lines count];
        
        for (line = [self lineNumberForCharacterIndex:range.location inText:text]; line < count; line++)
        {
            index = [NSArrayObjectAtIndex(lines, line) unsignedIntegerValue];
            
            if (NSLocationInRange(index, range))
            {
                rects = [layoutManager rectArrayForCharacterRange:NSMakeRange(index, 0)
                                     withinSelectedCharacterRange:nullRange
                                                  inTextContainer:container
                                                        rectCount:&rectCount];
				
                if (rectCount > 0)
                {
                    // Note that the ruler view is only as tall as the visible
                    // portion. Need to compensate for the clipview's coordinates.
                    ypos = yinset + NSMinY(rects[0]) - NSMinY(visibleRect);

                    // Line numbers are internally stored starting at 0
                    labelText = [NSString stringWithFormat:@"%lu", (unsigned long)(line + 1)];
                    
                    stringSize = [labelText sizeWithAttributes:textAttributes];

					currentTextAttributes = textAttributes;
					
                    // Draw string flush right, centered vertically within the line
                    [labelText drawInRect:
                       NSMakeRect(NSWidth(bounds) - stringSize.width - RULER_MARGIN,
                                  ypos + (NSHeight(rects[0]) - stringSize.height) / 2.0,
                                  NSWidth(bounds) - RULER_MARGIN * 2.0, NSHeight(rects[0]))
                           withAttributes:currentTextAttributes];
                }
            }
			if (index > NSMaxRange(range))
			{
				break;
			}
        }
    }
}

- (void)mouseDown:(NSEvent *)theEvent
{
	NSPoint					location;
	NSUInteger				line;
	NSTextView				*view;
	
    if (![[self clientView] isKindOfClass:[NSTextView class]]) return;
	view = (NSTextView *)[self clientView];
	
	location = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	line = [self lineNumberForLocation:location.y];
	dragSelectionStartLine = line;
	
	if (line != NSNotFound)
	{
		NSUInteger selectionStart, selectionEnd;
		NSMutableArray *lines = [self lineIndices];

		selectionStart = [[lines objectAtIndex:(line - 1)] unsignedIntegerValue];
		if (line < [lines count]) {
			selectionEnd = [[lines objectAtIndex:line] unsignedIntegerValue];
		} else {
			selectionEnd = [[view string] length];
		}
		[view setSelectedRange:NSMakeRange(selectionStart, selectionEnd - selectionStart)];
	}
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	NSPoint					location;
	NSUInteger				line, startLine, endLine;
	NSTextView				*view;
	
    if (![[self clientView] isKindOfClass:[NSTextView class]] || dragSelectionStartLine == NSNotFound) return;
	view = (NSTextView *)[self clientView];
	
	location = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	line = [self lineNumberForLocation:location.y];

	if (line != NSNotFound)
	{
		NSUInteger selectionStart, selectionEnd;
		NSMutableArray *lines = [self lineIndices];
		if (line >= dragSelectionStartLine) {
			startLine = dragSelectionStartLine;
			endLine = line;
		} else {
			startLine = line;
			endLine = dragSelectionStartLine;
		}

		selectionStart = [[lines objectAtIndex:(startLine - 1)] unsignedIntegerValue];
		if (endLine < [lines count]) {
			selectionEnd = [[lines objectAtIndex:endLine] unsignedIntegerValue];
		} else {
			selectionEnd = [[view string] length];
		}
		[view setSelectedRange:NSMakeRange(selectionStart, selectionEnd - selectionStart)];
	}
	
	[view autoscroll:theEvent];
}

#pragma mark NSCoding methods

#define NOODLE_FONT_CODING_KEY				@"font"
#define NOODLE_TEXT_COLOR_CODING_KEY		@"textColor"
#define NOODLE_ALT_TEXT_COLOR_CODING_KEY	@"alternateTextColor"
#define NOODLE_BACKGROUND_COLOR_CODING_KEY	@"backgroundColor"

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder]) != nil)
	{
		if ([decoder allowsKeyedCoding])
		{
			font = [[decoder decodeObjectForKey:NOODLE_FONT_CODING_KEY] retain];
			textColor = [[decoder decodeObjectForKey:NOODLE_TEXT_COLOR_CODING_KEY] retain];
			alternateTextColor = [[decoder decodeObjectForKey:NOODLE_ALT_TEXT_COLOR_CODING_KEY] retain];
			backgroundColor = [[decoder decodeObjectForKey:NOODLE_BACKGROUND_COLOR_CODING_KEY] retain];
		}
		else
		{
			font = [[decoder decodeObject] retain];
			textColor = [[decoder decodeObject] retain];
			alternateTextColor = [[decoder decodeObject] retain];
			backgroundColor = [[decoder decodeObject] retain];
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[super encodeWithCoder:encoder];
	
	if ([encoder allowsKeyedCoding])
	{
		[encoder encodeObject:font forKey:NOODLE_FONT_CODING_KEY];
		[encoder encodeObject:textColor forKey:NOODLE_TEXT_COLOR_CODING_KEY];
		[encoder encodeObject:alternateTextColor forKey:NOODLE_ALT_TEXT_COLOR_CODING_KEY];
		[encoder encodeObject:backgroundColor forKey:NOODLE_BACKGROUND_COLOR_CODING_KEY];
	}
	else
	{
		[encoder encodeObject:font];
		[encoder encodeObject:textColor];
		[encoder encodeObject:alternateTextColor];
		[encoder encodeObject:backgroundColor];
	}
}

@end
