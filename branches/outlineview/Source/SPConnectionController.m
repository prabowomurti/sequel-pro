//
//  $Id$
//
//  SPConnectionController.m
//  sequel-pro
//
//  Created by Rowan Beentje on 28/06/2009.
//  Copyright 2009 Arboreal. All rights reserved.
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

#import "SPConnectionController.h"
#import "SPDatabaseDocument.h"
#import "SPAppController.h"
#import "SPPreferenceController.h"
#import "ImageAndTextCell.h"
#import "RegexKitLite.h"
#import "SPAlertSheets.h"
#import "SPKeychain.h"
#import "SPSSHTunnel.h"
#import "SPTableTextFieldCell.h"
#import "SPFavoritesController.h"
#import "SPFavoriteNode.h"

// Constants
static const NSString *SPRemoveNode              = @"RemoveNode";
static const NSString *SPImportFavorites         = @"ImportFavorites";
static const NSString *SPExportFavorites         = @"ExportFavorites";
static const NSString *SPExportFavoritesFilename = @"SequelProFavorites.plist";

@interface SPConnectionController (PrivateAPI)

- (BOOL)_checkHost;
- (void)_sortFavorites;
- (void)_favoriteTypeDidChange;
- (void)_reloadFavoritesViewData;
- (void)_restoreConnectionInterface;
- (void)_mySQLConnectionEstablished;
- (void)_selectNode:(SPTreeNode *)node;
- (void)_initiateMySQLConnectionInBackground;

- (NSNumber *)_createNewFavoriteID;
- (SPTreeNode *)_favoriteNodeForFavoriteID:(NSInteger)favoriteID;

- (void)_updateFavoritePasswordsFromField:(NSControl *)control;

@end

@implementation SPConnectionController

@synthesize delegate;
@synthesize type;
@synthesize name;
@synthesize host;
@synthesize user;
@synthesize password;
@synthesize database;
@synthesize socket;
@synthesize port;
@synthesize useSSL;
@synthesize sslKeyFileLocationEnabled;
@synthesize sslKeyFileLocation;
@synthesize sslCertificateFileLocationEnabled;
@synthesize sslCertificateFileLocation;
@synthesize sslCACertFileLocationEnabled;
@synthesize sslCACertFileLocation;
@synthesize sshHost;
@synthesize sshUser;
@synthesize sshPassword;
@synthesize sshKeyLocationEnabled;
@synthesize sshKeyLocation;
@synthesize sshPort;

@synthesize connectionKeychainItemName;
@synthesize connectionKeychainItemAccount;
@synthesize connectionSSHKeychainItemName;
@synthesize connectionSSHKeychainItemAccount;

@synthesize isConnecting;

#pragma mark -

/**
 * Initialise the connection controller, linking it to the
 * parent document and setting up the parent window.
 */
- (id)initWithDocument:(SPDatabaseDocument *)document
{
	if (self = [super init]) {
		
		// Weak reference
		dbDocument = document;
		
		databaseConnectionSuperview = [dbDocument databaseView];
		databaseConnectionView = [dbDocument valueForKey:@"contentViewSplitter"];
		
		// Keychain references
		connectionKeychainItemName = nil;
		connectionKeychainItemAccount = nil;
		connectionSSHKeychainItemName = nil;
		connectionSSHKeychainItemAccount = nil;
		
		sshTunnel = nil;
		mySQLConnection = nil;
		isConnecting = NO;
		cancellingConnection = NO;
		mySQLConnectionCancelled = NO;
		
		favoriteNameFieldWasTouched = YES;
		
		// Load the connection nib, keeping references to the top-level objects for later release
		nibObjectsToRelease = [[NSMutableArray alloc] init];
		NSArray *connectionViewTopLevelObjects = nil;
		NSNib *nibLoader = [[NSNib alloc] initWithNibNamed:@"ConnectionView" bundle:[NSBundle mainBundle]];
		
		[nibLoader instantiateNibWithOwner:self topLevelObjects:&connectionViewTopLevelObjects];
		[nibObjectsToRelease addObjectsFromArray:connectionViewTopLevelObjects];
		[nibLoader release];
		
		// Hide the main view and position and display the connection view
		[databaseConnectionView setHidden:YES];
		[connectionView setFrame:[databaseConnectionView frame]];
		[databaseConnectionSuperview addSubview:connectionView];		
		[connectionSplitView setPosition:[[dbDocument valueForKey:@"dbTablesTableView"] frame].size.width-6 ofDividerAtIndex:0];
		[connectionSplitViewButtonBar setSplitViewDelegate:self];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scrollViewFrameChanged:) name:NSViewFrameDidChangeNotification object:nil];
		
		// Generic folder image for use in the outline view's groups
		folderImage = [[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericFolderIcon)] retain];
		
		[folderImage setSize:NSMakeSize(16, 16)];
		
		// Set up a keychain instance and preferences reference, and create the initial favorites list
		keychain = [[SPKeychain alloc] init];
		prefs = [[NSUserDefaults standardUserDefaults] retain];
				
		// Create a reference to the favorites controller, forcing the data to be loaded from disk and the
		// tree constructor.
		favoritesController = [SPFavoritesController sharedFavoritesController];
		
		// Tree reference
		favoritesRoot = [favoritesController favoritesTree];
		
		// Update the UI
		[self _reloadFavoritesViewData];

        // Set sort items
        currentSortItem = [prefs integerForKey:SPFavoritesSortedBy];
        reverseFavoritesSort = [prefs boolForKey:SPFavoritesSortedInReverse];
        
		// Register double click action for the favorites outline view (double click favorite to connect)
		[favoritesOutlineView setTarget:self];
		[favoritesOutlineView setDoubleAction:@selector(nodeDoubleClicked:)];
        [favoritesOutlineView registerForDraggedTypes:[NSArray arrayWithObject:SPFavoritesPasteboardDragType]];
        [favoritesOutlineView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

		// Registered to be notified of changes to connection information
		[self addObserver:self forKeyPath:SPFavoriteNameKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteHostKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteUserKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteDatabaseKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSocketKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoritePortKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteUseSSLKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSHHostKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSHUserKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSHPortKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSHKeyLocationEnabledKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSHKeyLocationKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSLKeyFileLocationEnabledKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSLKeyFileLocationKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSLCertificateFileLocationEnabledKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSLCertificateFileLocationKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSLCACertFileLocationEnabledKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		[self addObserver:self forKeyPath:SPFavoriteSSLCACertFileLocationKey options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
		
		// Sort the favourites to match prefs and select the appropriate row - if a valid sort option is selected
		// TODO: Fix me, sorting currently does not work in the new outline view
		//if (currentSortItem > -1) [self _sortFavorites];
					
		SPTreeNode *favorite = [self _favoriteNodeForFavoriteID:[prefs integerForKey:([prefs boolForKey:SPSelectLastFavoriteUsed]) ? SPLastFavoriteID : SPDefaultFavorite]];
						
		if (favorite && [favorite representedObject]) {
													
			NSNumber *typeNumber = [[[favorite representedObject] nodeFavorite] objectForKey:SPFavoriteTypeKey];
			
			previousType = (typeNumber) ? [typeNumber integerValue] : SPTCPIPConnection;
						
		    [self _selectNode:favorite];
		 
			[self resizeTabViewToConnectionType:[[[[favorite representedObject] nodeFavorite] objectForKey:SPFavoriteTypeKey] integerValue] animating:NO];
			
			[favoritesOutlineView scrollRowToVisible:[favoritesOutlineView selectedRow]];
		} 
		else {
			previousType = SPTCPIPConnection;
			
			[self resizeTabViewToConnectionType:SPTCPIPConnection animating:NO];
		}
	}
	
	return self;
}

#pragma mark -
#pragma mark Connection processes

/**
 * Starts the connection process; invoked when user hits the connect button
 * or double-clicks on a favourite.
 * Error-checks fields as required, and triggers connection of MySQL or any
 * connection proxies in use.
 */
- (IBAction)initiateConnection:(id)sender
{	
	// Ensure that host is not empty if this is a TCP/IP or SSH connection
	if (([self type] == SPTCPIPConnection || [self type] == SPSSHTunnelConnection) && ![[self host] length]) {
		SPBeginAlertSheet(NSLocalizedString(@"Insufficient connection details", @"insufficient details message"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [dbDocument parentWindow], self, nil, nil, NSLocalizedString(@"Insufficient details provided to establish a connection. Please enter at least the hostname.", @"insufficient details informative message"));		
		return;
	}
	
	// If SSH is enabled, ensure that the SSH host is not nil
	if ([self type] == SPSSHTunnelConnection && ![[self sshHost] length]) {
		SPBeginAlertSheet(NSLocalizedString(@"Insufficient connection details", @"insufficient details message"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [dbDocument parentWindow], self, nil, nil, NSLocalizedString(@"Insufficient details provided to establish a connection. Please enter the hostname for the SSH Tunnel, or disable the SSH Tunnel.", @"insufficient SSH tunnel details informative message"));
		return;
	}

	// If an SSH key has been provided, verify it exists
	if ([self type] == SPSSHTunnelConnection && sshKeyLocationEnabled && sshKeyLocation) {
		if (![[NSFileManager defaultManager] fileExistsAtPath:[sshKeyLocation stringByExpandingTildeInPath]]) {
			[self setSshKeyLocationEnabled:NSOffState];
			SPBeginAlertSheet(NSLocalizedString(@"SSH Key not found", @"SSH key check error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [dbDocument parentWindow], self, nil, nil, NSLocalizedString(@"A SSH key location was specified, but no file was found in the specified location.  Please re-select the key and try again.", @"SSH key not found message"));
			return;
		}
	}

	// Ensure that a socket connection is not inadvertently used
	if (![self _checkHost]) return;

	// If SSL keys have been supplied, verify they exist
	if (([self type] == SPTCPIPConnection || [self type] == SPSocketConnection) && [self useSSL]) {
		if (sslKeyFileLocationEnabled && sslKeyFileLocation
			&& ![[NSFileManager defaultManager] fileExistsAtPath:[sslKeyFileLocation stringByExpandingTildeInPath]])
		{
			[self setSslKeyFileLocationEnabled:NSOffState];
			[self setSslKeyFileLocation:nil];
			SPBeginAlertSheet(NSLocalizedString(@"SSL Key File not found", @"SSL key file check error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [dbDocument parentWindow], self, nil, nil, NSLocalizedString(@"A SSL key file location was specified, but no file was found in the specified location.  Please re-select the key file and try again.", @"SSL key file not found message"));
			return;
		}
		if (sslCertificateFileLocationEnabled && sslCertificateFileLocation
			&& ![[NSFileManager defaultManager] fileExistsAtPath:[sslCertificateFileLocation stringByExpandingTildeInPath]])
		{
			[self setSslCertificateFileLocationEnabled:NSOffState];
			[self setSslCertificateFileLocation:nil];
			SPBeginAlertSheet(NSLocalizedString(@"SSL Certificate File not found", @"SSL certificate file check error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [dbDocument parentWindow], self, nil, nil, NSLocalizedString(@"A SSL certificate location was specified, but no file was found in the specified location.  Please re-select the certificate and try again.", @"SSL certificate file not found message"));
			return;
		}
		if (sslCACertFileLocationEnabled && sslCACertFileLocation
			&& ![[NSFileManager defaultManager] fileExistsAtPath:[sslCACertFileLocation stringByExpandingTildeInPath]])
		{
			[self setSslCACertFileLocationEnabled:NSOffState];
			[self setSslCACertFileLocation:nil];
			SPBeginAlertSheet(NSLocalizedString(@"SSL Certificate Authority File not found", @"SSL certificate authority file check error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [dbDocument parentWindow], self, nil, nil, NSLocalizedString(@"A SSL Certificate Authority certificate location was specified, but no file was found in the specified location.  Please re-select the Certificate Authority certificate and try again.", @"SSL CA certificate file not found message"));
			return;
		}
	}

	// Basic details have validated - start the connection process animating
	isConnecting = YES;
	cancellingConnection = NO;
	
	[addToFavoritesButton setHidden:YES];
	[addToFavoritesButton display];
	[helpButton setHidden:YES];
	[helpButton display];
	[connectButton setEnabled:NO];
	[connectButton display];
	[progressIndicator startAnimation:self];
	[progressIndicator display];
	[progressIndicatorText setHidden:NO];
	[progressIndicatorText display];
	
	// Start the current tab's progress indicator
	[dbDocument setIsProcessing:YES];

	// If the password(s) are marked as having been originally sourced from a keychain, check whether they
	// have been changed or not; if not, leave the mark in place and remove the password from the field
	// for increased security.
	if (connectionKeychainItemName) {
		if ([[keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount] isEqualToString:[self password]]) {
			[self setPassword:[[NSString string] stringByPaddingToLength:[[self password] length] withString:@"sp" startingAtIndex:0]];
			[[standardPasswordField undoManager] removeAllActionsWithTarget:standardPasswordField];
			[[socketPasswordField undoManager] removeAllActionsWithTarget:socketPasswordField];
			[[sshPasswordField undoManager] removeAllActionsWithTarget:sshPasswordField];
		} 
		else {
			[connectionKeychainItemName release], connectionKeychainItemName = nil;
			[connectionKeychainItemAccount release], connectionKeychainItemAccount = nil;
		}
	}
	
	if (connectionSSHKeychainItemName) {
		if ([[keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount] isEqualToString:[self sshPassword]]) {
			[self setSshPassword:[[NSString string] stringByPaddingToLength:[[self sshPassword] length] withString:@"sp" startingAtIndex:0]];
			[[sshSSHPasswordField undoManager] removeAllActionsWithTarget:sshSSHPasswordField];
		} else {
			[connectionSSHKeychainItemName release], connectionSSHKeychainItemName = nil;
			[connectionSSHKeychainItemAccount release], connectionSSHKeychainItemAccount = nil;
		}
	}
	
	// Inform the delegate that we are starting the connection process
	if (delegate && [delegate respondsToSelector:@selector(connectionControllerInitiatingConnection:)]) {
		[delegate connectionControllerInitiatingConnection:self];
	}
	
	// Trim whitespace and newlines from the host field before attempting to connect
	[self setHost:[[self host] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	
	// Initiate the SSH connection process for tunnels
	if ([self type] == SPSSHTunnelConnection) {
		[self performSelector:@selector(initiateSSHTunnelConnection) withObject:nil afterDelay:0.0];
		return;
	}
	
	// ...or start the MySQL connection process directly	
	[self performSelector:@selector(initiateMySQLConnection) withObject:nil afterDelay:0.0];
}

/**
 * Cancels (or rather marks) the current connection is to be cancelled once established.
 *
 * Note, that once called this method does not mark the connection attempt to be immediately cancelled as
 * there is no reliable way to actually cancel connection attempts via the MySQL client libs. Once the
 * connection is established it will be immediately killed.
 */
- (IBAction)cancelMySQLConnection:(id)sender
{
	[connectButton setEnabled:NO];
	
	[progressIndicatorText setStringValue:NSLocalizedString(@"Cancelling...", @"cancelling task status message")];
	[progressIndicatorText display];
	
	mySQLConnectionCancelled = YES;
}

#pragma mark -
#pragma mark Interface interaction

/**
 * Registered in initWithDocument: to be the double click action of the favorites outline view.
 */
- (IBAction)nodeDoubleClicked:(id)sender
{
	SPTreeNode *node = [self selectedFavoriteNode];
	
	// Only proceed to initiate a connection if a leaf node (i.e. a favorite and not a group) was double clicked.
	if (![node isGroup]) {
		[self initiateConnection:self];
	}
	// Otherwise start editing the group item's name
	else {
		[favoritesOutlineView editColumn:0 row:[favoritesOutlineView selectedRow] withEvent:nil select:YES];
	}
}

/**
 * Opens the SSH/SSL key selection window, ready to select a key file.
 */
- (IBAction)chooseKeyLocation:(id)sender
{
	[favoritesOutlineView deselectAll:self];
	NSString *directoryPath = nil;
	NSString *filePath = nil;
	NSArray *permittedFileTypes = nil;
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];

	// Switch details by sender.
	// First, SSH keys:
	if (sender == sshSSHKeyButton) {

		// If the custom key location is currently disabled - after the button
		// action - leave it disabled and return without showing the sheet.
		if (!sshKeyLocationEnabled) {
			return;
		}

		// Otherwise open a panel at the last or default location
		if (sshKeyLocation && [sshKeyLocation length]) {
			filePath = [sshKeyLocation lastPathComponent];
			directoryPath = [sshKeyLocation stringByDeletingLastPathComponent];
		}

		permittedFileTypes = [NSArray arrayWithObjects:@"pem", @"", nil];
		[openPanel setAccessoryView:sshKeyLocationHelp];

	// SSL key file location:
	} else if (sender == standardSSLKeyFileButton || sender == socketSSLKeyFileButton) {
		if ([sender state] == NSOffState) {
			[self setSslKeyFileLocation:nil];
			return;
		}
		permittedFileTypes = [NSArray arrayWithObjects:@"pem", @"key", @"", nil];
		[openPanel setAccessoryView:sslKeyFileLocationHelp];
		
	// SSL certificate file location:
	} else if (sender == standardSSLCertificateButton || sender == socketSSLCertificateButton) {
		if ([sender state] == NSOffState) {
			[self setSslCertificateFileLocation:nil];
			return;
		}
		permittedFileTypes = [NSArray arrayWithObjects:@"pem", @"cert", @"", nil];
		[openPanel setAccessoryView:sslCertificateLocationHelp];
		
	// SSL CA certificate file location:
	} else if (sender == standardSSLCACertButton || sender == socketSSLCACertButton) {
		if ([sender state] == NSOffState) {
			[self setSslCACertFileLocation:nil];
			return;
		}
		permittedFileTypes = [NSArray arrayWithObjects:@"pem", @"cert", @"", nil];
		[openPanel setAccessoryView:sslCACertLocationHelp];
	}

	[openPanel beginSheetForDirectory:directoryPath
								 file:filePath
								types:permittedFileTypes
					   modalForWindow:[dbDocument parentWindow]
						modalDelegate:self
					   didEndSelector:@selector(chooseKeyLocationSheetDidEnd:returnCode:contextInfo:)
						  contextInfo:sender];
}

/**
 * Show connection help webpage.
 */
- (IBAction)showHelp:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:SPLOCALIZEDURL_CONNECTIONHELP]];
}

/**
 * Resize parts of the interface to reflect SSL status.
 */
- (IBAction)updateSSLInterface:(id)sender
{
	[self resizeTabViewToConnectionType:[self type] animating:YES];
}

#pragma mark -
#pragma mark Connection details interaction and display

/**
 * Control tab view resizing based on the supplied connection type,
 * with an option defining whether it should be animated or not.
 */
- (void)resizeTabViewToConnectionType:(NSUInteger)theType animating:(BOOL)animate
{
	NSRect frameRect, targetResizeRect;
	NSInteger additionalFormHeight = 55;

	frameRect = [connectionResizeContainer frame];

	switch (theType) {
		case SPTCPIPConnection:
			targetResizeRect = [standardConnectionFormContainer frame];
			if ([self useSSL]) additionalFormHeight += [standardConnectionSSLDetailsContainer frame].size.height;
			break;
		case SPSocketConnection:
			targetResizeRect = [socketConnectionFormContainer frame];
			if ([self useSSL]) additionalFormHeight += [socketConnectionSSLDetailsContainer frame].size.height;
			break;
		case SPSSHTunnelConnection:
			targetResizeRect = [sshConnectionFormContainer frame];
			break;
	} 

	frameRect.size.height = targetResizeRect.size.height + additionalFormHeight;

	if (animate) {
		[[connectionResizeContainer animator] setFrame:frameRect];
	} 
	else {
		[connectionResizeContainer setFrame:frameRect];	
	}
}

#pragma mark -
#pragma mark Favorites interaction

/**
 * Sorts the favorites table view based on the selected sort by item.
 */
- (void)sortFavorites:(id)sender
{	
    previousSortItem = currentSortItem;
	currentSortItem  = [[sender menu] indexOfItem:sender];
	
	[prefs setInteger:currentSortItem forKey:SPFavoritesSortedBy];
	
	// Perform sorting
	[self _sortFavorites];
	
	if (previousSortItem > -1) [[[sender menu] itemAtIndex:previousSortItem] setState:NSOffState];
	
	[[[sender menu] itemAtIndex:currentSortItem] setState:NSOnState];
}

/**
 * Reverses the favorites table view sorting based on the selected criteria.
 */
- (void)reverseSortFavorites:(id)sender
{
    reverseFavoritesSort = (![sender state]);
    
	[prefs setBool:reverseFavoritesSort forKey:SPFavoritesSortedInReverse];
	
	// Perform re-sorting
	[self _sortFavorites];
	
	[sender setState:reverseFavoritesSort]; 
}

/**
 * Sets fields for the chosen favorite.
 */
- (void)updateFavoriteSelection:(id)sender
{
	automaticFavoriteSelection = YES;

	// Clear the keychain referral items as appropriate
	if (connectionKeychainItemName) [connectionKeychainItemName release], connectionKeychainItemName = nil;
	if (connectionKeychainItemAccount) [connectionKeychainItemAccount release], connectionKeychainItemAccount = nil;
	if (connectionSSHKeychainItemName) [connectionSSHKeychainItemName release], connectionSSHKeychainItemName = nil;
	if (connectionSSHKeychainItemAccount) [connectionSSHKeychainItemAccount release], connectionSSHKeychainItemAccount = nil;
	
	SPTreeNode *node = [self selectedFavoriteNode];
	
	// Update key-value properties from the selected favourite, using empty strings where not found
	NSDictionary *fav = [[node representedObject] nodeFavorite];
	
	// Keep a copy of the favorite as it currently stands
	if (currentFavorite) [currentFavorite release], currentFavorite = nil;
	
	currentFavorite = [[node representedObject] copy];
	
	[connectionResizeContainer setHidden:NO];
	
	// Standard details
	[self setType:([fav objectForKey:SPFavoriteTypeKey] ? [[fav objectForKey:SPFavoriteTypeKey] integerValue] : SPTCPIPConnection)];
	[self setName:([fav objectForKey:SPFavoriteNameKey] ? [fav objectForKey:SPFavoriteNameKey] : @"")];
	[self setHost:([fav objectForKey:SPFavoriteHostKey] ? [fav objectForKey:SPFavoriteHostKey] : @"")];
	[self setSocket:([fav objectForKey:SPFavoriteSocketKey] ? [fav objectForKey:SPFavoriteSocketKey] : @"")];
	[self setUser:([fav objectForKey:SPFavoriteUserKey] ? [fav objectForKey:SPFavoriteUserKey] : @"")];
	[self setPort:([fav objectForKey:SPFavoritePortKey] ? [fav objectForKey:SPFavoritePortKey] : @"")];
	[self setDatabase:([fav objectForKey:SPFavoriteDatabaseKey] ? [fav objectForKey:SPFavoriteDatabaseKey] : @"")];
	
	// SSL details
	[self setUseSSL:([fav objectForKey:SPFavoriteUseSSLKey] ? [[fav objectForKey:SPFavoriteUseSSLKey] intValue] : NSOffState)];
	[self setSslKeyFileLocationEnabled:([fav objectForKey:SPFavoriteSSLKeyFileLocationEnabledKey] ? [[fav objectForKey:SPFavoriteSSLKeyFileLocationEnabledKey] intValue] : NSOffState)];
	[self setSslKeyFileLocation:([fav objectForKey:SPFavoriteSSLKeyFileLocationKey] ? [fav objectForKey:SPFavoriteSSLKeyFileLocationKey] : @"")];
	[self setSslCertificateFileLocationEnabled:([fav objectForKey:SPFavoriteSSLCertificateFileLocationEnabledKey] ? [[fav objectForKey:SPFavoriteSSLCertificateFileLocationEnabledKey] intValue] : NSOffState)];
	[self setSslCertificateFileLocation:([fav objectForKey:SPFavoriteSSLCertificateFileLocationKey] ? [fav objectForKey:SPFavoriteSSLCertificateFileLocationKey] : @"")];
	[self setSslCACertFileLocationEnabled:([fav objectForKey:SPFavoriteSSLCACertFileLocationEnabledKey] ? [[fav objectForKey:SPFavoriteSSLCACertFileLocationEnabledKey] intValue] : NSOffState)];
	[self setSslCACertFileLocation:([fav objectForKey:SPFavoriteSSLCACertFileLocationKey] ? [fav objectForKey:SPFavoriteSSLCACertFileLocationKey] : @"")];
	
	// SSH details
	[self setSshHost:([fav objectForKey:SPFavoriteSSHHostKey] ? [fav objectForKey:SPFavoriteSSHHostKey] : @"")];
	[self setSshUser:([fav objectForKey:SPFavoriteSSHUserKey] ? [fav objectForKey:SPFavoriteSSHUserKey] : @"")];
	[self setSshKeyLocationEnabled:([fav objectForKey:SPFavoriteSSHKeyLocationEnabledKey] ? [[fav objectForKey:SPFavoriteSSHKeyLocationEnabledKey] intValue] : NSOffState)];
	[self setSshKeyLocation:([fav objectForKey:SPFavoriteSSHKeyLocationKey] ? [fav objectForKey:SPFavoriteSSHKeyLocationKey] : @"")];
	[self setSshPort:([fav objectForKey:SPFavoriteSSHPortKey] ? [fav objectForKey:SPFavoriteSSHPortKey] : @"")];
	
	// Trigger an interface update
	[self resizeTabViewToConnectionType:[self type] animating:YES];
	
	// Check whether the password exists in the keychain, and if so add it; also record the
	// keychain details so we can pass around only those details if the password doesn't change
	connectionKeychainItemName = [[keychain nameForFavoriteName:[self valueForKeyPath:@"selectedFavorite.name"] id:[self valueForKeyPath:@"selectedFavorite.id"]] retain];
	connectionKeychainItemAccount = [[keychain accountForUser:[self valueForKeyPath:@"selectedFavorite.user"] host:(([self type] == SPSocketConnection)?@"localhost":[self valueForKeyPath:@"selectedFavorite.host"]) database:[self valueForKeyPath:@"selectedFavorite.database"]] retain];
	
	[self setPassword:[keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount]];
	
	if (![[self password] length]) {
		[self setPassword:nil];
		[connectionKeychainItemName release], connectionKeychainItemName = nil;
		[connectionKeychainItemAccount release], connectionKeychainItemAccount = nil;
	}
	
	// And the same for the SSH password
	connectionSSHKeychainItemName = [[keychain nameForSSHForFavoriteName:[self valueForKeyPath:@"selectedFavorite.name"] id:[self valueForKeyPath:@"selectedFavorite.id"]] retain];
	connectionSSHKeychainItemAccount = [[keychain accountForSSHUser:[self valueForKeyPath:@"selectedFavorite.sshUser"] sshHost:[self valueForKeyPath:@"selectedFavorite.sshHost"]] retain];
	
	[self setSshPassword:[keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount]];
	
	if (![[self sshPassword] length]) {
		[self setSshPassword:nil];
		[connectionSSHKeychainItemName release], connectionSSHKeychainItemName = nil;
		[connectionSSHKeychainItemAccount release], connectionSSHKeychainItemAccount = nil;
	}
	
	[prefs setInteger:([favoritesOutlineView selectedRow] - 1) forKey:SPLastFavoriteID];
	
	// Set first responder to password field if it is empty
	switch ([self type]) 
	{
		case SPTCPIPConnection:
			if (![[standardPasswordField stringValue] length]) [[dbDocument parentWindow] makeFirstResponder:standardPasswordField];
			break;
		case SPSocketConnection:
			if (![[socketPasswordField stringValue] length]) [[dbDocument parentWindow] makeFirstResponder:socketPasswordField];
			break;
		case SPSSHTunnelConnection:
			if (![[sshPasswordField stringValue] length]) [[dbDocument parentWindow] makeFirstResponder:sshPasswordField];
			break;
	}
}

/**
 * Returns the selected favorite data dictionary or nil if nothing is selected.
 */
- (NSMutableDictionary *)selectedFavorite
{
	SPTreeNode *node = [self selectedFavoriteNode];
	
	return (![node isGroup]) ? [[node representedObject] nodeFavorite] : nil;
}

/**
 * Returns the selected favorite node or nil if nothing is selected.
 */
- (SPTreeNode *)selectedFavoriteNode
{
	NSArray *nodes = [self selectedFavoriteNodes];
	
	return ([nodes count]) ? (SPTreeNode *)[[self selectedFavoriteNodes] objectAtIndex:0] : nil;
}

/**
 * Returns an array of selected favorite nodes.
 */
- (NSArray *)selectedFavoriteNodes
{
	NSMutableArray *nodes = [NSMutableArray array];
	NSIndexSet *indexes = [favoritesOutlineView selectedRowIndexes];

	NSUInteger currentIndex = [indexes firstIndex];
	
	while (currentIndex != NSNotFound)
	{
		[nodes addObject:[favoritesOutlineView itemAtRow:currentIndex]];
		
		currentIndex = [indexes indexGreaterThanIndex:currentIndex];
	}
	
	return nodes;
}

/**
 * Adds a new connection favorite.
 */
- (IBAction)addFavorite:(id)sender
{
	NSNumber *favoriteID = [self _createNewFavoriteID];
	
	NSArray *objects = [NSArray arrayWithObjects:NSLocalizedString(@"New Favorite", @"new favorite name"), 
						[NSNumber numberWithInteger:0], @"", @"", @"", @"", 
						[NSNumber numberWithInt:NSOffState], 
						[NSNumber numberWithInt:NSOffState], 
						[NSNumber numberWithInt:NSOffState], 
						[NSNumber numberWithInt:NSOffState], @"", @"", @"", 
						[NSNumber numberWithInt:NSOffState], @"", @"", favoriteID, nil];
	
	NSArray *keys = [NSArray arrayWithObjects:
					 SPFavoriteNameKey, 
					 SPFavoriteTypeKey, 
					 SPFavoriteHostKey, 
					 SPFavoriteSocketKey, 
					 SPFavoriteUserKey, 
					 SPFavoritePortKey, 
					 SPFavoriteUseSSLKey, 
					 SPFavoriteSSLKeyFileLocationEnabledKey,
					 SPFavoriteSSLCertificateFileLocationEnabledKey, 
					 SPFavoriteSSLCACertFileLocationEnabledKey, 
					 SPFavoriteDatabaseKey, 
					 SPFavoriteSSHHostKey, 
					 SPFavoriteSSHUserKey, 
					 SPFavoriteSSHKeyLocationEnabledKey, 
					 SPFavoriteSSHKeyLocationKey, 
					 SPFavoriteSSHPortKey, 
					 SPFavoriteIDKey,
					 nil];
	
    // Create default favorite
    NSMutableDictionary *favorite = [NSMutableDictionary dictionaryWithObjects:objects forKeys:keys];
				
	SPTreeNode *selectedNode = [self selectedFavoriteNode];
	
	SPTreeNode *parent = ([selectedNode isGroup]) ? selectedNode : [selectedNode parentNode];
	
	SPTreeNode *node = [favoritesController addFavoriteNodeWithData:favorite asChildOfNode:parent];
	
	[self _reloadFavoritesViewData];
    [self _selectNode:node];
	
    [[[[NSApp delegate] preferenceController] generalPreferencePane] updateDefaultFavoritePopup];
	
	favoriteNameFieldWasTouched = NO;
		
	[favoritesOutlineView editColumn:0 row:[favoritesOutlineView selectedRow] withEvent:nil select:YES];
}

/**
 * Adds the current details as a new connection favorite, selects it, and scrolls the selected
 * row to be visible.
 */
- (IBAction)addFavoriteUsingCurrentDetails:(id)sender
{
	NSString *thePassword, *theSSHPassword;
	NSNumber *favoriteid = [self _createNewFavoriteID];
	NSString *favoriteName = [[self name] length] ? [self name] : [NSString stringWithFormat:@"%@@%@", ([self user] && [[self user] length])?[self user] : @"anonymous", (([self type] == SPSocketConnection) ? @"localhost" : [self host])];
	
	if (![[self name] length] && [self database] && ![[self database] isEqualToString:@""]) {
		favoriteName = [NSString stringWithFormat:@"%@ %@", [self database], favoriteName];
	}
	
	// Ensure that host is not empty if this is a TCP/IP or SSH connection
	if (([self type] == SPTCPIPConnection || [self type] == SPSSHTunnelConnection) && ![[self host] length]) {
		NSRunAlertPanel(NSLocalizedString(@"Insufficient connection details", @"insufficient details message"), NSLocalizedString(@"Insufficient details provided to establish a connection. Please provide at least a host.", @"insufficient details informative message"), NSLocalizedString(@"OK", @"OK button"), nil, nil);
		return;
	}
	
	// If SSH is enabled, ensure that the SSH host is not nil
	if ([self type] == SPSSHTunnelConnection && ![[self sshHost] length]) {
		NSRunAlertPanel(NSLocalizedString(@"Insufficient connection details", @"insufficient details message"), NSLocalizedString(@"Please enter the hostname for the SSH Tunnel, or disable the SSH Tunnel.", @"message of panel when ssh details are incomplete"), NSLocalizedString(@"OK", @"OK button"), nil, nil);
		return;
	}

	// Ensure that a socket connection is not inadvertently used
	if (![self _checkHost]) return;
	
	// Construct the favorite details - cannot use only dictionaryWithObjectsAndKeys for possible nil values.
	NSMutableDictionary *newFavorite = [NSMutableDictionary dictionaryWithObjectsAndKeys:
										[NSNumber numberWithInteger:[self type]], SPFavoriteTypeKey,
										favoriteName, SPFavoriteNameKey,
										favoriteid, SPFavoriteIDKey,
										nil];
	
	// Standard details
	if ([self host])     [newFavorite setObject:[self host] forKey:SPFavoriteHostKey];
	if ([self socket])   [newFavorite setObject:[self socket] forKey:SPFavoriteSocketKey];
	if ([self user])     [newFavorite setObject:[self user] forKey:SPFavoriteUserKey];
	if ([self port])     [newFavorite setObject:[self port] forKey:SPFavoritePortKey];
	if ([self database]) [newFavorite setObject:[self database] forKey:SPFavoriteDatabaseKey];
	
	// SSL details
	if ([self useSSL]) [newFavorite setObject:[NSNumber numberWithInt:[self useSSL]] forKey:SPFavoriteUseSSLKey];
	[newFavorite setObject:[NSNumber numberWithInt:[self sslKeyFileLocationEnabled]] forKey:SPFavoriteSSLKeyFileLocationEnabledKey];
	if ([self sslKeyFileLocation]) [newFavorite setObject:[self sslKeyFileLocation] forKey:SPFavoriteSSLKeyFileLocationKey];
	[newFavorite setObject:[NSNumber numberWithInt:[self sslCertificateFileLocationEnabled]] forKey:SPFavoriteSSLCertificateFileLocationEnabledKey];
	if ([self sslCertificateFileLocation]) [newFavorite setObject:[self sslCertificateFileLocation] forKey:SPFavoriteSSLCertificateFileLocationKey];
	[newFavorite setObject:[NSNumber numberWithInt:[self sslCACertFileLocationEnabled]] forKey:SPFavoriteSSLCACertFileLocationEnabledKey];
	if ([self sslCACertFileLocation]) [newFavorite setObject:[self sslCACertFileLocation] forKey:SPFavoriteSSLCACertFileLocationKey];
	
	// SSH details
	if ([self sshHost]) [newFavorite setObject:[self sshHost] forKey:SPFavoriteSSHHostKey];
	if ([self sshUser]) [newFavorite setObject:[self sshUser] forKey:SPFavoriteSSHUserKey];
	if ([self sshPort]) [newFavorite setObject:[self sshPort] forKey:SPFavoriteSSHPortKey];
	[newFavorite setObject:[NSNumber numberWithInt:[self sshKeyLocationEnabled]] forKey:SPFavoriteSSHKeyLocationEnabledKey];
	if ([self sshKeyLocation]) [newFavorite setObject:[self sshKeyLocation] forKey:SPFavoriteSSHKeyLocationKey];

	// Add the password to keychain as appropriate
	thePassword = [self password];
	
	if (mySQLConnection && connectionKeychainItemName) {
		thePassword = [keychain getPasswordForName:connectionKeychainItemName account:connectionKeychainItemAccount];
	}
	
	if (thePassword && (![thePassword isEqualToString:@""])) {
		[keychain addPassword:thePassword
					  forName:[keychain nameForFavoriteName:favoriteName id:[NSString stringWithFormat:@"%lld", [favoriteid longLongValue]]]
					  account:[keychain accountForUser:[self user] host:(([self type] == SPSocketConnection) ? @"localhost" : [self host]) database:[self database]]];
	}

	// Add the SSH password to keychain as appropriate
	theSSHPassword = [self sshPassword];
	
	if (mySQLConnection && connectionSSHKeychainItemName) {
		theSSHPassword = [keychain getPasswordForName:connectionSSHKeychainItemName account:connectionSSHKeychainItemAccount];
	}
	
	if (theSSHPassword && (![theSSHPassword isEqualToString:@""])) {
		[keychain addPassword:theSSHPassword
					  forName:[keychain nameForSSHForFavoriteName:favoriteName id:[NSString stringWithFormat:@"%lld", [favoriteid longLongValue]]]
					  account:[keychain accountForSSHUser:[self sshUser] sshHost:[self sshHost]]];
	}
	
	SPTreeNode *node = [favoritesController addFavoriteNodeWithData:newFavorite asChildOfNode:nil];
	
	[self _reloadFavoritesViewData];
	[self _selectNode:node];

	// Update the favorites popup button in the preferences
	[[[[NSApp delegate] preferenceController] generalPreferencePane] updateDefaultFavoritePopup];
}

/**
 * Adds a new group node to the favorites tree with a default name. Once added it is selected for editing.
 */
- (IBAction)addGroup:(id)sender
{
	SPTreeNode *selectedNode = [self selectedFavoriteNode];
	
	SPTreeNode *parent = ([selectedNode isGroup]) ? selectedNode : [selectedNode parentNode];
	
	SPTreeNode *node = [favoritesController addGroupNodeWithName:NSLocalizedString(@"New Folder", @"new folder placeholder name") asChildOfNode:parent];
	
	[self _reloadFavoritesViewData];
	[self _selectNode:node];
	
	[favoritesOutlineView editColumn:0 row:[favoritesOutlineView selectedRow] withEvent:nil select:YES];
}

/**
 * Removes the selected node.
 */
- (IBAction)removeNode:(id)sender
{
	if ([favoritesOutlineView numberOfSelectedRows] == 1) {
		
		SPTreeNode *node = [self selectedFavoriteNode];
		
		NSString *message = @"";
		NSString *informativeMessage = @"";
		
		if (![node isGroup]) {
			message            = [NSString stringWithFormat:NSLocalizedString(@"Delete favorite '%@'?", @"delete database message"), [[[node representedObject] nodeFavorite] objectForKey:SPFavoriteNameKey]];
			informativeMessage = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the favorite '%@'? This operation cannot be undone.", @"delete database informative message"), [[[node representedObject] nodeFavorite] objectForKey:SPFavoriteNameKey]];
		}
		else {
			message            = [NSString stringWithFormat:NSLocalizedString(@"Delete group '%@'?", @"delete database message"), [[node representedObject] nodeName]];
			informativeMessage = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the group '%@'? All favorites within this group will also be deleted. This operation cannot be undone.", @"delete database informative message"), [[node representedObject] nodeName]];
		}
		
		NSAlert *alert = [NSAlert alertWithMessageText:message
										 defaultButton:NSLocalizedString(@"Delete", @"delete button") 
									   alternateButton:NSLocalizedString(@"Cancel", @"cancel button") 
										   otherButton:nil 
							 informativeTextWithFormat:informativeMessage];
		
		NSArray *buttons = [alert buttons];
		
		// Change the alert's cancel button to have the key equivalent of return
		[[buttons objectAtIndex:0] setKeyEquivalent:@"d"];
		[[buttons objectAtIndex:0] setKeyEquivalentModifierMask:NSCommandKeyMask];
		[[buttons objectAtIndex:1] setKeyEquivalent:@"\r"];
		
		[alert setAlertStyle:NSCriticalAlertStyle];
		
		[alert beginSheetModalForWindow:[dbDocument parentWindow] 
						  modalDelegate:self 
						 didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) 
							contextInfo:SPRemoveNode];
	}
}

/**
 * Duplicates the selected connection favorite.
 */
- (IBAction)duplicateFavorite:(id)sender
{
	if ([favoritesOutlineView numberOfSelectedRows] == 1) {
		
		NSMutableDictionary *favorite = [NSMutableDictionary dictionaryWithDictionary:[self selectedFavorite]];
		
		NSNumber *favoriteID = [self _createNewFavoriteID];
		
		NSInteger duplicatedFavoriteType = [[favorite objectForKey:SPFavoriteTypeKey] integerValue];
		
		// Update the unique ID
		[favorite setObject:favoriteID forKey:SPFavoriteIDKey];
		
		// Alter the name for clarity
		[favorite setObject:[NSString stringWithFormat:NSLocalizedString(@"%@ Copy", @"Initial favourite name after duplicating a previous favourite"), [favorite objectForKey:SPFavoriteNameKey]] forKey:SPFavoriteNameKey];
		
		// Create new keychain items if appropriate
		if (password && [password length]) {
			NSString *keychainName        = [keychain nameForFavoriteName:[favorite objectForKey:SPFavoriteNameKey] id:[favorite objectForKey:SPFavoriteIDKey]];
			NSString *keychainAccount     = [keychain accountForUser:[favorite objectForKey:SPFavoriteUserKey] host:((duplicatedFavoriteType == SPSocketConnection) ? @"localhost" : [favorite objectForKey:SPFavoriteHostKey]) database:[favorite objectForKey:SPFavoriteDatabaseKey]];
			NSString *favoritePassword    = [keychain getPasswordForName:keychainName account:keychainAccount];
			
			keychainName = [keychain nameForFavoriteName:[favorite objectForKey:SPFavoriteNameKey] id:[favorite objectForKey:SPFavoriteIDKey]];
			
			[keychain addPassword:favoritePassword forName:keychainName account:keychainAccount];
			
			favoritePassword = nil;
		}
		
		if (sshPassword && [sshPassword length]) {
			NSString *keychainSSHName     = [keychain nameForSSHForFavoriteName:[favorite objectForKey:SPFavoriteNameKey] id:[favorite objectForKey:SPFavoriteIDKey]];
			NSString *keychainSSHAccount  = [keychain accountForSSHUser:[favorite objectForKey:SPFavoriteSSHUserKey] sshHost:[favorite objectForKey:SPFavoriteSSHHostKey]];
			NSString *favoriteSSHPassword = [keychain getPasswordForName:keychainSSHName account:keychainSSHAccount];
			
			keychainSSHName = [keychain nameForSSHForFavoriteName:[favorite objectForKey:SPFavoriteNameKey] id:[favorite objectForKey:SPFavoriteIDKey]];
			
			[keychain addPassword:favoriteSSHPassword forName:keychainSSHName account:keychainSSHAccount];
		
			favoriteSSHPassword = nil;
		}
		
		SPTreeNode *selectedNode = [self selectedFavoriteNode];
		
		SPTreeNode *parent = ([selectedNode isGroup]) ? selectedNode : [selectedNode parentNode];
		
		SPTreeNode *node = [favoritesController addFavoriteNodeWithData:favorite asChildOfNode:parent];
		
		[self _reloadFavoritesViewData];
		[self _selectNode:node];
		
		[[(SPPreferenceController *)[[NSApp delegate] preferenceController] generalPreferencePane] updateDefaultFavoritePopup];
	}
}

/**
 * Switches the selected favorite/group to editing mode so it can be renamed.
 */
- (IBAction)renameFavorite:(id)sender
{
	if ([favoritesOutlineView numberOfSelectedRows] == 1) {
		[favoritesOutlineView editColumn:0 row:[favoritesOutlineView selectedRow] withEvent:nil select:YES];
	}
}

/**
 * Marks the selected favorite as the default.
 */
- (IBAction)makeSelectedFavoriteDefault:(id)sender
{
	NSInteger favoriteID = [[[self selectedFavorite] objectForKey:SPFavoriteIDKey] integerValue];
	
	[prefs setInteger:favoriteID forKey:SPDefaultFavorite];
}
	
#pragma mark -
#pragma mark Import/export favorites

/**
 * Displays an open panel, allowing the user to import their favorites.
 */
- (IBAction)importFavorites:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	
	[openPanel beginSheetForDirectory:nil
								 file:nil
								types:nil
					   modalForWindow:[dbDocument parentWindow]
						modalDelegate:self
					   didEndSelector:@selector(importExportFavoritesSheetDidEnd:returnCode:contextInfo:)
						  contextInfo:SPImportFavorites];
}

/**
 * Displays a save panel, allowing the user to export their favorites.
 */
- (IBAction)exportFavorites:(id)sender
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	
	[savePanel beginSheetForDirectory:nil
								 file:SPExportFavoritesFilename
					   modalForWindow:[dbDocument parentWindow]
						modalDelegate:self
					   didEndSelector:@selector(importExportFavoritesSheetDidEnd:returnCode:contextInfo:)
						  contextInfo:SPExportFavorites];
}

#pragma mark -
#pragma mark Key Value Observing

/**
 * This method is called as part of Key Value Observing.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{	
	id oldObject = [change objectForKey:NSKeyValueChangeOldKey];
	id newObject = [change objectForKey:NSKeyValueChangeNewKey];
		
	if (oldObject != newObject) {
		NSMutableDictionary *favorite = [self selectedFavorite];

		[favorite setObject:(newObject) ? newObject : @"" forKey:keyPath];
			
		// Save the new data to disk
		[favoritesController saveFavorites];
		
		[self _reloadFavoritesViewData];
	}
}

#pragma mark -
#pragma mark Sheet methods

/**
 * Called when the user dismisses the remove node sheet.
 */
- (void)sheetDidEnd:(id)sheet returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo
{	
	// Remove the current favorite/group
	if ([contextInfo isEqualToString:SPRemoveNode]) {
		if (returnCode == NSAlertDefaultReturn) {
			
			NSDictionary *favorite = [self selectedFavorite];
			
			// Get selected favorite's details
			NSString *favoriteName     = [favorite objectForKey:SPFavoriteNameKey];
			NSString *favoriteUser     = [favorite objectForKey:SPFavoriteUserKey];
			NSString *favoriteHost     = [favorite objectForKey:SPFavoriteHostKey];
			NSString *favoriteDatabase = [favorite objectForKey:SPFavoriteDatabaseKey];
			NSString *favoriteSSHUser  = [favorite objectForKey:SPFavoriteSSHUserKey];
			NSString *favoriteSSHHost  = [favorite objectForKey:SPFavoriteSSHHostKey];
			NSString *favoriteID       = [favorite objectForKey:SPFavoriteIDKey];
			
			NSInteger favoriteType     = [[favorite objectForKey:SPFavoriteTypeKey] integerValue];
			
			// Remove passwords from the Keychain
			[keychain deletePasswordForName:[keychain nameForFavoriteName:favoriteName id:favoriteID]
									account:[keychain accountForUser:favoriteUser host:((type == SPSocketConnection) ? @"localhost" : favoriteHost) database:favoriteDatabase]];
			[keychain deletePasswordForName:[keychain nameForSSHForFavoriteName:favoriteName id:favoriteID]
									account:[keychain accountForSSHUser:favoriteSSHUser sshHost:favoriteSSHHost]];
			
			// Reset last used favorite
			if ([[favorite objectForKey:SPFavoriteIDKey] integerValue] == [prefs integerForKey:SPLastFavoriteID]) {
				[prefs setInteger:0	forKey:SPLastFavoriteID];
			}
			
			// Reset default favorite
			if ([[favorite objectForKey:SPFavoriteIDKey] integerValue] == [prefs integerForKey:SPDefaultFavorite]) {
				[prefs setInteger:[prefs integerForKey:SPLastFavoriteID] forKey:SPDefaultFavorite];
			}
			
			[favoritesController removeFavoriteNode:[self selectedFavoriteNode]];
			
			[self _reloadFavoritesViewData];
			
			[[(SPPreferenceController *)[[NSApp delegate] preferenceController] generalPreferencePane] updateDefaultFavoritePopup];
		}
	}	
}

/**
 * Called after closing the SSH/SSL key selection sheet.
 */
- (void)chooseKeyLocationSheetDidEnd:(NSOpenPanel *)openPanel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	NSString *abbreviatedFileName = [[openPanel filename] stringByAbbreviatingWithTildeInPath];
	
	// SSH key file selection
	if (contextInfo == sshSSHKeyButton) {
		if (returnCode == NSCancelButton) {
			[self setSshKeyLocationEnabled:NSOffState];
			return;
		}
		
		[self setSshKeyLocation:abbreviatedFileName];
	} 
	// SSL key file selection
	else if (contextInfo == standardSSLKeyFileButton || contextInfo == socketSSLKeyFileButton) {
		if (returnCode == NSCancelButton) {
			[self setSslKeyFileLocationEnabled:NSOffState];
			[self setSslKeyFileLocation:nil];
			return;
		}
		
		[self setSslKeyFileLocation:abbreviatedFileName];
	}
	// SSL certificate file selection
	else if (contextInfo == standardSSLCertificateButton || contextInfo == socketSSLCertificateButton) {
		if (returnCode == NSCancelButton) {
			[self setSslCertificateFileLocationEnabled:NSOffState];
			[self setSslCertificateFileLocation:nil];
			return;
		}
		
		[self setSslCertificateFileLocation:abbreviatedFileName];
	} 
	// SSL CA certificate file selection
	else if (contextInfo == standardSSLCACertButton || contextInfo == socketSSLCACertButton) {
		if (returnCode == NSCancelButton) {
			[self setSslCACertFileLocationEnabled:NSOffState];
			[self setSslCACertFileLocation:nil];
			return;
		}
		
		[self setSslCACertFileLocation:abbreviatedFileName];
	}
}

/**
 * Called when the user dismisses either the import of export favorites panels.
 */
- (void)importExportFavoritesSheetDidEnd:(NSOpenPanel *)openPanel returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo
{
	
}

/**
 * Alert sheet callback method - invoked when the error sheet is closed.
 */
- (void)localhostErrorSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{	
	if (returnCode == NSAlertAlternateReturn) {
		[self setType:SPSocketConnection];
		[self setHost:@""];
	} 
	else {
		[self setHost:@"127.0.0.1"];
	}
}

#pragma mark -
#pragma mark Private API

/**
 * Check the host field and ensure it isn't set to 'localhost' for non-socket connections.
 */
- (BOOL)_checkHost
{
	if ([self type] != SPSocketConnection && [[self host] isEqualToString:@"localhost"]) {
		SPBeginAlertSheet(NSLocalizedString(@"You have entered 'localhost' for a non-socket connection", @"title of error when using 'localhost' for a network connection"),
						  NSLocalizedString(@"Use 127.0.0.1", @"Use 127.0.0.1 button"),	// Main button
						  NSLocalizedString(@"Connect via socket", @"Connect via socket button"),	// Alternate button
						  nil,	// Other button
						  [dbDocument parentWindow],	// Window to attach to
						  self,	// Modal delegate
						  @selector(localhostErrorSheetDidEnd:returnCode:contextInfo:),	// Did end selector
						  nil,	// Contextual info for selectors
						  NSLocalizedString(@"To MySQL, 'localhost' is a special host and means that a socket connection should be used.\n\nDid you mean to use a socket connection, or to connect to the local machine via a port?  If you meant to connect via a port, '127.0.0.1' should be used instead of 'localhost'.", @"message of error when using 'localhost' for a network connection"));
		return NO;
	}
	
	return YES;
}

/**
 * Sorts the connection favorites based on the selected criteria.
 */
- (void)_sortFavorites
{
    NSString *sortKey = SPFavoriteNameKey;
	
	switch (currentSortItem)
	{
		case SPFavoritesSortNameItem:
			sortKey = SPFavoriteNameKey;
			break;
		case SPFavoritesSortHostItem:
			sortKey = SPFavoriteHostKey;
			break;
		case SPFavoritesSortTypeItem:
			sortKey = SPFavoriteTypeKey;
			break;
	}
	
	NSSortDescriptor *sortDescriptor = nil;
	
	if (currentSortItem == SPFavoritesSortTypeItem) {
		sortDescriptor = [[[NSSortDescriptor alloc] initWithKey:sortKey ascending:(!reverseFavoritesSort)] autorelease];
	}
	else {
		sortDescriptor = [[[NSSortDescriptor alloc] initWithKey:sortKey ascending:(!reverseFavoritesSort) selector:@selector(caseInsensitiveCompare:)] autorelease];
	}
	    
	// TODO: Perform actual sorting here
	
	[self _reloadFavoritesViewData];
}

/**
 * Updates the favorite's host when the type changes.
 */
- (void)_favoriteTypeDidChange
{
	// TODO: Handle changing favorite connection types
	
	/*NSDictionary *favorite = [[[self selectedFavoriteNode] representedObject] nodeFavorite];
	
	// If either socket or host is localhost, clear.
	if ((selectedTabView != SPSocketConnection) && [[favorite objectForKey:SPFavoriteHostKey] isEqualToString:@"localhost"]) {
		[self setHost:@""];
	}
	
	// Update the name for newly added favorites if not already touched by the user, by trigger a KVO update
	if (!favoriteNameFieldWasTouched) {
		[self setName:[NSString stringWithFormat:@"%@@%@", 
					   ([favorite objectForKey:SPFavoriteUserKey]) ? [favorite objectForKey:SPFavoriteUserKey] : @"", 
						((previousType == SPSocketConnection) ? @"localhost" :
						(([favorite objectForKey:SPFavoriteHostKey]) ? [favorite valueForKeyPath:SPFavoriteHostKey] : @""))
					   ]];
	}
	
	// Request a password refresh to keep keychain references in synch with the favorites
	[self _updateFavoritePasswordsFromField:nil];*/
}

/**
 * Convenience method for rebuilding the connection favorites tree, reloading the outline view, expanding the
 * items and scrolling to the selected item.
 */
- (void)_reloadFavoritesViewData
{	
	[favoritesOutlineView reloadData];
	[favoritesOutlineView expandItem:[[favoritesRoot childNodes] objectAtIndex:0] expandChildren:YES];
	[favoritesOutlineView scrollRowToVisible:[favoritesOutlineView selectedRow]];
}

/**
 * Restores the connection interface to its original state.
 */
- (void)_restoreConnectionInterface
{
	// Must be performed on the main thread
	if (![NSThread isMainThread]) return [[self onMainThread] _restoreConnectionInterface];
	
	// Reset the window title
	[[dbDocument parentWindow] setTitle:[dbDocument displayName]];
	
	// Stop the current tab's progress indicator
	[dbDocument setIsProcessing:NO];
	
	// Reset the UI
	[addToFavoritesButton setHidden:NO];
	[addToFavoritesButton display];
	[helpButton setHidden:NO];
	[helpButton display];
	[connectButton setTitle:NSLocalizedString(@"Connect", @"connect button")];
	[connectButton setEnabled:YES];
	[connectButton display];
	[progressIndicator stopAnimation:self];
	[progressIndicator display];
	[progressIndicatorText setHidden:YES];
	[progressIndicatorText display];
	
	// Re-enable favorites table view
	[favoritesOutlineView setEnabled:YES];
	[favoritesOutlineView display];
	
	mySQLConnectionCancelled = NO;
	
	// Revert the connect button back to its original selector
	[connectButton setAction:@selector(initiateConnection:)];
}

/**
 * Selected the supplied node in the favorites outline view.
 */
- (void)_selectNode:(SPTreeNode *)node
{
	[favoritesOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[favoritesOutlineView rowForItem:node]] byExtendingSelection:NO];
	[favoritesOutlineView scrollRowToVisible:[favoritesOutlineView selectedRow]];
}

/**
 * Called on the main thread once the MySQL connection is established on the background thread. Either the
 * connection was cancelled or it was successful. 
 */
- (void)_mySQLConnectionEstablished
{	
	isConnecting = NO;
	
	// If the user hit cancel during the connection attempt, kill the connection once 
	// established and reset the UI.
	if (mySQLConnectionCancelled) {		
		if ([mySQLConnection isConnected]) {
			[mySQLConnection disconnect];
			[mySQLConnection release], mySQLConnection = nil;
		}
		
		// Kill the SSH connection if present
		[self cancelConnection];
		
		[self _restoreConnectionInterface];
		
		return;
	}
	
	[progressIndicatorText setStringValue:NSLocalizedString(@"Connected", @"connection established message")];
	[progressIndicatorText display];
	
	// Stop the current tab's progress indicator
	[dbDocument setIsProcessing:NO];
	
	// Successful connection!
	[connectButton setEnabled:NO];
	[connectButton display];
	[progressIndicator stopAnimation:self];
	[progressIndicatorText setHidden:YES];
	[addToFavoritesButton setHidden:NO];

	// If SSL was enabled, check it was established correctly
	if (useSSL && ([self type] == SPTCPIPConnection || [self type] == SPSocketConnection)) {
		if (![mySQLConnection isConnectedViaSSL]) {
			SPBeginAlertSheet(NSLocalizedString(@"SSL connection not established", @"SSL requested but not used title"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [dbDocument parentWindow], nil, nil, nil, NSLocalizedString(@"You requested that the connection should be established using SSL, but MySQL made the connection without SSL.\n\nThis may be because the server does not support SSL connections, or has SSL disabled; or insufficient details were supplied to establish an SSL connection.\n\nThis connection is not encrypted.", @"SSL connection requested but not established error detail"));
		} 
		else {
			[dbDocument setStatusIconToImageWithName:@"titlebarlock"]; 
		}
	}

	// Re-enable favorites table view
	[favoritesOutlineView setEnabled:YES];
	[favoritesOutlineView display];
	
	// Release the tunnel if set - will now be retained by the connection
	if (sshTunnel) [sshTunnel release], sshTunnel = nil;
	
	// Pass the connection to the document and clean up the interface
	[self addConnectionToDocument];
}

/**
 * Initiates the core of the MySQL connection process on a background thread.
 */
- (void)_initiateMySQLConnectionInBackground
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
	// Initialise to socket if appropriate.
	if ([self type] == SPSocketConnection) {
		mySQLConnection = [[MCPConnection alloc] initToSocket:[self socket] withLogin:[self user]];
		
		// Otherwise, initialise to host, using tunnel if appropriate
	} else {
		if ([self type] == SPSSHTunnelConnection) {
			mySQLConnection = [[MCPConnection alloc] initToHost:@"127.0.0.1"
													  withLogin:[self user]
													  usingPort:[sshTunnel localPort]];
			[mySQLConnection setConnectionProxy:sshTunnel];
		} else {
			mySQLConnection = [[MCPConnection alloc] initToHost:[self host]
													  withLogin:[self user]
													  usingPort:([[self port] length] ? [[self port] integerValue] : 3306)];
		}
	}
	
	// Only set the password if there is no Keychain item set. The connection will ask the delegate for passwords in the Keychain.	
	if (!connectionKeychainItemName && [self password]) {
		[mySQLConnection setPassword:[self password]];
	}

	// Enable SSL if set
	if ([self useSSL]) {
		[mySQLConnection setSSL:YES
			usingKeyFilePath:[self sslKeyFileLocationEnabled] ? [self sslKeyFileLocation] : nil
			certificatePath:[self sslCertificateFileLocationEnabled] ? [self sslCertificateFileLocation] : nil
			certificateAuthorityCertificatePath:[self sslCACertFileLocationEnabled] ? [self sslCACertFileLocation] : nil];
	}
	

	// Connection delegate must be set before actual connection attempt is made
	[mySQLConnection setDelegate:dbDocument];

	// Set whether or not we should enable delegate logging according to the prefs
	[mySQLConnection setDelegateQueryLogging:[prefs boolForKey:SPConsoleEnableLogging]];
	
	// Set options from preferences
	[mySQLConnection setConnectionTimeout:[[prefs objectForKey:SPConnectionTimeoutValue] integerValue]];
	[mySQLConnection setUseKeepAlive:[[prefs objectForKey:SPUseKeepAlive] boolValue]];
	[mySQLConnection setKeepAliveInterval:[[prefs objectForKey:SPKeepAliveInterval] doubleValue]];
	
	// Connect
	[mySQLConnection connect];
	
	if (![mySQLConnection isConnected]) {
		if (sshTunnel) {
			
			// If an SSH tunnel is running, temporarily block to allow the tunnel to register changes in state
			[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
			
			// If the state is connection refused, attempt the MySQL connection again with the host using the hostfield value.
			if ([sshTunnel state] == PROXY_STATE_FORWARDING_FAILED) {
				if ([sshTunnel localPortFallback]) {
					[mySQLConnection setPort:[sshTunnel localPortFallback]];
					[mySQLConnection connect];
					if (![mySQLConnection isConnected]) {
						[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
					}
				}
			}
		}
		
		if (![mySQLConnection isConnected]) {
			NSString *errorMessage = @"";
			if (sshTunnel && [sshTunnel state] == PROXY_STATE_FORWARDING_FAILED) {
				errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Unable to connect to host %@ because the port connection via SSH was refused.\n\nPlease ensure that your MySQL host is set up to allow TCP/IP connections (no --skip-networking) and is configured to allow connections from the host you are tunnelling via.\n\nYou may also want to check the port is correct and that you have the necessary privileges.\n\nChecking the error detail will show the SSH debug log which may provide more details.\n\nMySQL said: %@", @"message of panel when SSH port forwarding failed"), [self host], [mySQLConnection getLastErrorMessage]];
				[[self onMainThread] failConnectionWithTitle:NSLocalizedString(@"SSH port forwarding failed", @"title when ssh tunnel port forwarding failed") errorMessage:errorMessage detail:[sshTunnel debugMessages]];
			} else if ([mySQLConnection getLastErrorID] == 1045) { // "Access denied" error
				errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Unable to connect to host %@ because access was denied.\n\nDouble-check your username and password and ensure that access from your current location is permitted.\n\nMySQL said: %@", @"message of panel when connection to host failed due to access denied error"), [self host], [mySQLConnection getLastErrorMessage]];
				[[self onMainThread] failConnectionWithTitle:NSLocalizedString(@"Access denied!", @"connection failed due to access denied title") errorMessage:errorMessage detail:nil];
			} else if ([self type] == SPSocketConnection && (![self socket] || ![[self socket] length]) && ![mySQLConnection findSocketPath]) {
				errorMessage = [NSString stringWithFormat:NSLocalizedString(@"The socket file could not be found in any common location. Please supply the correct socket location.\n\nMySQL said: %@", @"message of panel when connection to socket failed because optional socket could not be found"), [mySQLConnection getLastErrorMessage]];
				[[self onMainThread] failConnectionWithTitle:NSLocalizedString(@"Socket not found!", @"socket not found title") errorMessage:errorMessage detail:nil];
			} else if ([self type] == SPSocketConnection) {
				errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Unable to connect via the socket, or the request timed out.\n\nDouble-check that the socket path is correct and that you have the necessary privileges, and that the server is running.\n\nMySQL said: %@", @"message of panel when connection to host failed"), [mySQLConnection getLastErrorMessage]];
				[[self onMainThread] failConnectionWithTitle:NSLocalizedString(@"Socket connection failed!", @"socket connection failed title") errorMessage:errorMessage detail:nil];
			} else {
				errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Unable to connect to host %@, or the request timed out.\n\nBe sure that the address is correct and that you have the necessary privileges, or try increasing the connection timeout (currently %ld seconds).\n\nMySQL said: %@", @"message of panel when connection to host failed"), [self host], (long)[[prefs objectForKey:SPConnectionTimeoutValue] integerValue], [mySQLConnection getLastErrorMessage]];
				[[self onMainThread] failConnectionWithTitle:NSLocalizedString(@"Connection failed!", @"connection failed title") errorMessage:errorMessage detail:nil];
			}
			
			// Tidy up
			isConnecting = NO;
			
			if (sshTunnel) [sshTunnel release], sshTunnel = nil;
			
			[mySQLConnection release], mySQLConnection = nil;
			[self _restoreConnectionInterface];
			[pool release];
			
			return;
		}
	}
	
	if ([self database] && ![[self database] isEqualToString:@""]) {
		if (![mySQLConnection selectDB:[self database]]) {
			[[self onMainThread] failConnectionWithTitle:NSLocalizedString(@"Could not select database", @"message when database selection failed") errorMessage:[NSString stringWithFormat:NSLocalizedString(@"Connected to host, but unable to connect to database %@.\n\nBe sure that the database exists and that you have the necessary privileges.\n\nMySQL said: %@", @"message of panel when connection to db failed"), [self database], [mySQLConnection getLastErrorMessage]] detail:nil];
			
			// Tidy up
			isConnecting = NO;
			
			if (sshTunnel) [sshTunnel release], sshTunnel = nil;
			
			[mySQLConnection release], mySQLConnection = nil;
			[self _restoreConnectionInterface];
			[pool release];
			
			return;
		}
	}
	
	// Connection established
	[self performSelectorOnMainThread:@selector(_mySQLConnectionEstablished) withObject:nil waitUntilDone:NO];
		
	[pool release];
}

/**
 * Creates a new favorite ID based on the UNIX epoch time.
 */
- (NSNumber *)_createNewFavoriteID
{
	return [NSNumber numberWithInteger:[[NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]] hash]];
}

/**
 * Returns the favorite node for the conection favorite with the supplied ID.
 */
- (SPTreeNode *)_favoriteNodeForFavoriteID:(NSInteger)favoriteID
{	
	SPTreeNode *node = nil;
	
	if (!favoritesRoot) return;
		
	for (node in [favoritesRoot allChildLeafs]) 
	{						
		if ([[[[node representedObject] nodeFavorite] objectForKey:SPFavoriteIDKey] integerValue] == favoriteID) {
			return node;
		} 
	}
}

/**
 * Check all fields used in the keychain names against the old values for that
 * favorite, and update the keychain names to match if necessary.
 * If an (optional) recognised password field is supplied, that field is assumed
 * to have changed and is used to supply the new value.
 */
- (void)_updateFavoritePasswordsFromField:(NSControl *)control
{
	if (!currentFavorite) return;
	
	NSDictionary *oldFavorite = [currentFavorite nodeFavorite];
	NSDictionary *newFavorite = [[[self selectedFavoriteNode] representedObject] nodeFavorite];
	
	NSString *passwordValue;
	NSString *oldKeychainName, *newKeychainName;
	NSString *oldKeychainAccount, *newKeychainAccount;
	NSString *oldHostnameForPassword = ([[oldFavorite objectForKey:SPFavoriteTypeKey] integerValue] == SPSocketConnection) ? @"localhost" : [oldFavorite objectForKey:SPFavoriteHostKey];
	NSString *newHostnameForPassword = ([[newFavorite objectForKey:SPFavoriteTypeKey] integerValue] == SPSocketConnection) ? @"localhost" : [newFavorite objectForKey:SPFavoriteHostKey];
	
	// SQL passwords are indexed by name, host, user and database.  If any of these
	// have changed, or a standard password field has, alter the keychain item to match.
	if (![[oldFavorite objectForKey:SPFavoriteNameKey] isEqualToString:[newFavorite objectForKey:SPFavoriteNameKey]] ||
		![oldHostnameForPassword isEqualToString:newHostnameForPassword] ||
		![[oldFavorite objectForKey:SPFavoriteUserKey] isEqualToString:[newFavorite objectForKey:SPFavoriteUserKey]] ||
		![[oldFavorite objectForKey:SPFavoriteDatabaseKey] isEqualToString:[newFavorite objectForKey:SPFavoriteDatabaseKey]] ||
		control == standardPasswordField || control == socketPasswordField || control == sshPasswordField)
	{
		// Determine the correct password field to read the password from, defaulting to standard
		if (control == socketPasswordField) {
			passwordValue = [socketPasswordField stringValue];
		} 
		else if (control == sshPasswordField) {
			passwordValue = [sshPasswordField stringValue];
		} 
		else {
			passwordValue = [standardPasswordField stringValue];
		}
		
		// Get the old keychain name and account strings
		oldKeychainName = [keychain nameForFavoriteName:[oldFavorite objectForKey:SPFavoriteNameKey] id:[newFavorite objectForKey:SPFavoriteIDKey]];
		oldKeychainAccount = [keychain accountForUser:[oldFavorite objectForKey:SPFavoriteUserKey] host:oldHostnameForPassword database:[oldFavorite objectForKey:SPFavoriteDatabaseKey]];
		
		// Delete the old keychain item
		[keychain deletePasswordForName:oldKeychainName account:oldKeychainAccount];
		
		// Set up the new keychain name and account strings
		newKeychainName = [keychain nameForFavoriteName:[newFavorite objectForKey:SPFavoriteNameKey] id:[newFavorite objectForKey:SPFavoriteIDKey]];
		newKeychainAccount = [keychain accountForUser:[newFavorite objectForKey:SPFavoriteUserKey] host:newHostnameForPassword database:[newFavorite objectForKey:SPFavoriteDatabaseKey]];
		
		// Add the new keychain item if the password field has a value
		if ([passwordValue length]) {
			[keychain addPassword:passwordValue forName:newKeychainName account:newKeychainAccount];
		}
		
		// Synch password changes
		[standardPasswordField setStringValue:passwordValue];
		[socketPasswordField setStringValue:passwordValue];
		[sshPasswordField setStringValue:passwordValue];
		
		passwordValue = @"";
	}
	
	// If SSH account/password details have changed, update the keychain to match
	if (![[oldFavorite objectForKey:SPFavoriteNameKey] isEqualToString:[newFavorite objectForKey:SPFavoriteNameKey]] ||
		![[oldFavorite objectForKey:SPFavoriteSSHHostKey] isEqualToString:[newFavorite objectForKey:SPFavoriteSSHHostKey]] ||
		![[oldFavorite objectForKey:SPFavoriteSSHUserKey] isEqualToString:[newFavorite objectForKey:SPFavoriteSSHUserKey]] ||
		control == sshSSHPasswordField) 
	{
		// Get the old keychain name and account strings
		oldKeychainName = [keychain nameForSSHForFavoriteName:[oldFavorite objectForKey:SPFavoriteNameKey] id:[newFavorite objectForKey:SPFavoriteIDKey]];
		oldKeychainAccount = [keychain accountForSSHUser:[oldFavorite objectForKey:SPFavoriteSSHUserKey] sshHost:[oldFavorite objectForKey:SPFavoriteSSHHostKey]];
		
		// Delete the old keychain item
		[keychain deletePasswordForName:oldKeychainName account:oldKeychainAccount];
		
		// Set up the new keychain name and account strings
		newKeychainName = [keychain nameForSSHForFavoriteName:[newFavorite objectForKey:SPFavoriteNameKey] id:[newFavorite objectForKey:SPFavoriteIDKey]];
		newKeychainAccount = [keychain accountForSSHUser:[newFavorite objectForKey:SPFavoriteSSHUserKey] sshHost:[newFavorite objectForKey:SPFavoriteSSHHostKey]];
		
		// Add the new keychain item if the password field has a value
		if ([[sshPasswordField stringValue] length]) {
			[keychain addPassword:[sshPasswordField stringValue] forName:newKeychainName account:newKeychainAccount];
		}
	}
	
	// Update the current favorite
	if (currentFavorite) [currentFavorite release], currentFavorite = nil;
	
	if ([[favoritesOutlineView selectedRowIndexes] count]) {
		currentFavorite = [[[self selectedFavoriteNode] representedObject] copy];
	}
}

#pragma mark -

- (void)dealloc
{
    [keychain release];
    [prefs release];
	
	[folderImage release], folderImage = nil;
	
	for (id retainedObject in nibObjectsToRelease) [retainedObject release];
	
	[nibObjectsToRelease release];
	
	if (mySQLConnection) [mySQLConnection release];
	if (sshTunnel) [sshTunnel setConnectionStateChangeSelector:nil delegate:nil], [sshTunnel disconnect], [sshTunnel release];
	if (connectionKeychainItemName) [connectionKeychainItemName release];
	if (connectionKeychainItemAccount) [connectionKeychainItemAccount release];
	if (connectionSSHKeychainItemName) [connectionSSHKeychainItemName release];
	if (connectionSSHKeychainItemAccount) [connectionSSHKeychainItemAccount release];
	if (currentFavorite) [currentFavorite release], currentFavorite = nil;
    
    [super dealloc];
}

@end