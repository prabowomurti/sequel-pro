//
//  $Id$
//
//  SPHistoryController.h
//  sequel-pro
//
//  Created by Rowan Beentje on July 23, 2009
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

@class SPDatabaseDocument, SPTableContent, SPTablesList;

@interface SPHistoryController : NSObject 
{
	IBOutlet SPDatabaseDocument *theDocument;
	IBOutlet NSSegmentedControl *historyControl;

	SPTableContent *tableContentInstance;
	SPTablesList *tablesListInstance;
	NSMutableArray *history;
	NSMutableDictionary *tableContentStates;
	NSUInteger historyPosition;
	BOOL modifyingState;
	BOOL toolbarItemVisible;
}

@property (readonly) NSUInteger historyPosition;
@property (readonly) NSMutableArray *history;
@property (readwrite, assign) BOOL modifyingState;

// Interface interaction
- (void) updateToolbarItem;
- (void)goBackInHistory;
- (void)goForwardInHistory;
- (IBAction) historyControlClicked:(NSSegmentedControl *)theControl;
- (NSUInteger) currentlySelectedView;
- (void) setupInterface;

// Adding or updating history entries
- (void) updateHistoryEntries;

// Loading history entries
- (void) loadEntryAtPosition:(NSUInteger)position;
- (void) loadEntryTaskWithPosition:(NSNumber *)positionNumber;
- (void) abortEntryLoadWithPool:(NSAutoreleasePool *)pool;
- (void) loadEntryFromMenuItem:(id)theMenuItem;

// Restoring view states
- (void) restoreViewStates;

// History entry details and description
- (NSMenuItem *) menuEntryForHistoryEntryAtIndex:(NSInteger)theIndex;
- (NSString *) nameForHistoryEntryDetails:(NSDictionary *)theEntry;

@end
