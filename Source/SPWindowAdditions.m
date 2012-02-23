//
//  $Id$
//
//  SPWindowAdditions.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on Dec 10, 2008
//  Copyright (c) 2008 Stuart Connolly. All rights reserved.
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

#import "SPWindowAdditions.h"
#import "SPDatabaseDocument.h"
#import "SPWindowController.h"

@implementation NSWindow (SPWindowAdditions)

/**
 * Returns the height of the currently visible toolbar.
 */
- (CGFloat)toolbarHeight
{
	NSRect windowFrame;
	CGFloat toolbarHeight = 0.0f;

	if ([self toolbar] && [[self toolbar] isVisible]) {
		windowFrame   = [NSWindow contentRectForFrameRect:[self frame] styleMask:[self styleMask]];
		toolbarHeight = NSHeight(windowFrame) - NSHeight([[self contentView] frame]);
	}

	return toolbarHeight;
}

/**
 * Resizes this window to the size of the supplied view.
 */
- (void)resizeForContentView:(NSView *)view titleBarVisible:(BOOL)visible
{
	NSSize viewSize = [view frame].size;
	NSRect frame    = [self frame];

	if (viewSize.height < [self contentMinSize].height) {
		viewSize.height = [self contentMinSize].height;
	}

	CGFloat newHeight = (viewSize.height + [self toolbarHeight]);

	// If the title bar is visible add 22 pixels to new height of window.
	if (visible) newHeight += 22;

	frame.origin.y += frame.size.height - newHeight;

	frame.size.height = newHeight;
	frame.size.width  = viewSize.width; 

	[self setFrame:frame display:YES animate:YES];
}

/**
 * Three finger multi-touch right/left swipe event to go back/forward in table history.
 */
- (void)swipeWithEvent:(NSEvent *)anEvent
{

	if(![[self delegate] isKindOfClass:[SPWindowController class]] || ![[[self delegate] documents] count]) return;

	id frontDoc = [[self delegate] selectedTableDocument];

	if( frontDoc && [frontDoc isKindOfClass:[SPDatabaseDocument class]]
		&& [frontDoc valueForKeyPath:@"spHistoryControllerInstance"]
		&& ![frontDoc isWorking])
	{
		if([anEvent deltaX] == -1.0f)
			[[frontDoc valueForKeyPath:@"spHistoryControllerInstance"] valueForKey:@"goForwardInHistory"];
		else if([anEvent deltaX] == 1.0f)
			[[frontDoc valueForKeyPath:@"spHistoryControllerInstance"] valueForKey:@"goBackInHistory"];
	}
}


@end
