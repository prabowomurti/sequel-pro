//
//  $Id$
//
//  SPQueryFavoriteManager.h
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on Aug 23, 2009
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
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

@class BWAnchoredButtonBar, SPTextView, SPDatabaseDocument;

@interface NSObject (SPQueryFavoriteManagerDelegate)

- (void)queryFavoritesHaveBeenUpdated:(id)manager;

@end

@interface SPQueryFavoriteManager : NSWindowController 
{
	NSUserDefaults *prefs;
	
	NSURL *delegatesFileURL;
	SPDatabaseDocument *tableDocumentInstance;
	IBOutlet NSPopUpButton *encodingPopUp;
	IBOutlet NSTableView *favoritesTableView;
	IBOutlet NSTextField *favoriteNameTextField;
	IBOutlet NSTextField *favoriteTabTriggerTextField;
	IBOutlet SPTextView  *favoriteQueryTextView;
	IBOutlet NSButton *removeButton;
	IBOutlet BWAnchoredButtonBar *splitViewButtonBar;

	IBOutlet NSArrayController *favoritesArrayController;

	NSMutableArray *favorites;

	BOOL isTableCellEditing;
}

- (id)initWithDelegate:(id)managerDelegate;

// Accessors
- (NSMutableArray *)queryFavoritesForFileURL:(NSURL *)fileURL;
- (id)customQueryInstance;

// IBAction methods
- (IBAction)addQueryFavorite:(id)sender;
- (IBAction)removeQueryFavorite:(id)sender;
- (IBAction)removeAllQueryFavorites:(id)sender;
- (IBAction)duplicateQueryFavorite:(id)sender;
- (IBAction)saveFavoriteToFile:(id)sender;
- (IBAction)exportFavorites:(id)sender;
- (IBAction)importFavoritesByAdding:(id)sender;
- (IBAction)importFavoritesByReplacing:(id)sender;
- (IBAction)closeQueryManagerSheet:(id)sender;
- (IBAction)insertPlaceholder:(id)sender;
- (IBAction)showHelp:(id)sender;

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo;
- (void)importPanelDidEnd:(NSOpenPanel *)panel returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo;
- (void)savePanelDidEnd:(NSSavePanel *)panel returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo;

@end
