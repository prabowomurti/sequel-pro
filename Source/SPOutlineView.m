//
//  $Id$
//
//  SPOutlineView.m
//  sequel-pro
//
//  Created by Mark Townsend on Aug 25, 2009
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

#import "SPOutlineView.h"

@implementation SPOutlineView

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)keyDown:(NSEvent *)theEvent
{
	if ([self numberOfSelectedRows] == 1 && ([theEvent keyCode] == 36 || [theEvent keyCode] == 76)) {
		
		[self editColumn:0 row:[self selectedRow] withEvent:nil select:YES];
	}
	else {
		[super keyDown:theEvent];
	}
}

/**
 * Right-click at row will select that row before ordering out the contextual menu
 * if not more than one row is selected.
 */
- (NSMenu *)menuForEvent:(NSEvent *)event
{	
	// If more than one row is selected only return the default contextual menu
	if ([self numberOfSelectedRows] > 1) return [self menu];
	
	// Right-click at a row will select that row before ordering out the context menu
	NSInteger row = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
	
	if ((row >= 0) && (row < [self numberOfRows])) {
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		[[self window] makeFirstResponder:self];
	}
	
	return [self menu];
}

/**
 * To prevent right-clicking in a column's 'group' heading, ask the delegate if we support selecting it
 * as this normally doesn't apply to left-clicks. If we do support selecting this row, simply pass on the event.
 */
- (void)rightMouseDown:(NSEvent *)event
{
	if ([[self delegate] respondsToSelector:@selector(outlineView:shouldSelectItem:)]) {
		if ([[self delegate] outlineView:self shouldSelectItem:[self itemAtRow:[self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]]]]) {
			[super rightMouseDown:event];
		}
	}
	else {
		[super rightMouseDown:event];
	}
}

@end
