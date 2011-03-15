//
//  $Id$
//
//  SPConnectionController.h
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

#import <MCPKit/MCPKit.h>

#import "SPConnectionControllerDelegateProtocol.h"
#import "SPFavoritesOutlineView.h"

@class SPDatabaseDocument, SPKeychain, SPSSHTunnel, BWAnchoredButtonBar, SPFavoriteNode;

@interface NSObject (BWAnchoredButtonBar)

- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(NSInteger)dividerIndex;

@end

@interface SPFlippedView : NSView

- (BOOL)isFlipped;

@end

@interface SPConnectionController : NSObject 
{
	id <SPConnectionControllerDelegateProtocol, NSObject> delegate;
	
	SPDatabaseDocument *tableDocument;
	NSView *databaseConnectionSuperview;
	NSSplitView *databaseConnectionView;
	SPKeychain *keychain;
	NSUserDefaults *prefs;
	NSMutableArray *favorites;
	SPSSHTunnel *sshTunnel;
	MCPConnection *mySQLConnection;
	BOOL automaticFavoriteSelection;
	BOOL cancellingConnection;
	BOOL isConnecting;

	NSInteger previousType;
	NSInteger type;
	NSString *name;
	NSString *host;
	NSString *user;
	NSString *password;
	NSString *database;
	NSString *socket;
	NSString *port;
	int useSSL;
	int sslKeyFileLocationEnabled;
	NSString *sslKeyFileLocation;
	int sslCertificateFileLocationEnabled;
	NSString *sslCertificateFileLocation;
	int sslCACertFileLocationEnabled;
	NSString *sslCACertFileLocation;
	NSString *sshHost;
	NSString *sshUser;
	NSString *sshPassword;
	int sshKeyLocationEnabled;
	NSString *sshKeyLocation;
	NSString *sshPort;
	@private NSString *favoritesPBoardType;

	NSString *connectionKeychainID;
	NSString *connectionKeychainItemName;
	NSString *connectionKeychainItemAccount;
	NSString *connectionSSHKeychainItemName;
	NSString *connectionSSHKeychainItemAccount;

	NSMutableArray *nibObjectsToRelease;

	IBOutlet NSView *connectionView;
	IBOutlet NSSplitView *connectionSplitView;
	IBOutlet NSScrollView *connectionDetailsScrollView;
	IBOutlet BWAnchoredButtonBar *connectionSplitViewButtonBar;
	IBOutlet SPFavoritesOutlineView *favoritesTable;

	IBOutlet NSWindow *errorDetailWindow;
	IBOutlet NSTextView *errorDetailText;

	IBOutlet NSView *connectionResizeContainer;
	IBOutlet NSView *standardConnectionFormContainer;
	IBOutlet NSView *standardConnectionSSLDetailsContainer;
	IBOutlet NSView *socketConnectionFormContainer;
	IBOutlet NSView *socketConnectionSSLDetailsContainer;
	IBOutlet NSView *sshConnectionFormContainer;
	IBOutlet NSView *sshKeyLocationHelp;
	IBOutlet NSView *sslKeyFileLocationHelp;
	IBOutlet NSView *sslCertificateLocationHelp;
	IBOutlet NSView *sslCACertLocationHelp;

	IBOutlet NSTextField *standardSQLHostField;
	IBOutlet NSTextField *sshSQLHostField;
	IBOutlet NSSecureTextField *standardPasswordField;
	IBOutlet NSSecureTextField *socketPasswordField;
	IBOutlet NSSecureTextField *sshPasswordField;
	IBOutlet NSSecureTextField *sshSSHPasswordField;
	IBOutlet NSButton *sshSSHKeyButton;
	IBOutlet NSButton *standardSSLKeyFileButton;
	IBOutlet NSButton *standardSSLCertificateButton;
	IBOutlet NSButton *standardSSLCACertButton;
	IBOutlet NSButton *socketSSLKeyFileButton;
	IBOutlet NSButton *socketSSLCertificateButton;
	IBOutlet NSButton *socketSSLCACertButton;

	IBOutlet NSButton *addToFavoritesButton;
	IBOutlet NSButton *connectButton;
	IBOutlet NSButton *helpButton;
	IBOutlet NSProgressIndicator *progressIndicator;
	IBOutlet NSTextField *progressIndicatorText;
    IBOutlet NSMenuItem *favoritesSortByMenuItem;
	
    BOOL reverseFavoritesSort;
	BOOL mySQLConnectionCancelled;
	
    SPFavoritesSortItem previousSortItem, currentSortItem;
	
	SPFavoriteNode *favoritesRoot;
}

@property (readwrite, assign) id <SPConnectionControllerDelegateProtocol> delegate;
@property (readwrite, assign) NSInteger type;
@property (readwrite, retain) NSString *name;
@property (readwrite, retain) NSString *host;
@property (readwrite, retain) NSString *user;
@property (readwrite, retain) NSString *password;
@property (readwrite, retain) NSString *database;
@property (readwrite, retain) NSString *socket;
@property (readwrite, retain) NSString *port;
@property (readwrite, assign) int useSSL;
@property (readwrite, assign) int sslKeyFileLocationEnabled;
@property (readwrite, retain) NSString *sslKeyFileLocation;
@property (readwrite, assign) int sslCertificateFileLocationEnabled;
@property (readwrite, retain) NSString *sslCertificateFileLocation;
@property (readwrite, assign) int sslCACertFileLocationEnabled;
@property (readwrite, retain) NSString *sslCACertFileLocation;
@property (readwrite, retain) NSString *sshHost;
@property (readwrite, retain) NSString *sshUser;
@property (readwrite, retain) NSString *sshPassword;
@property (readwrite, assign) int sshKeyLocationEnabled;
@property (readwrite, retain) NSString *sshKeyLocation;
@property (readwrite, retain) NSString *sshPort;

@property (readwrite, retain) NSString *connectionKeychainItemName;
@property (readwrite, retain) NSString *connectionKeychainItemAccount;
@property (readwrite, retain) NSString *connectionSSHKeychainItemName;
@property (readwrite, retain) NSString *connectionSSHKeychainItemAccount;

@property (readonly, assign) BOOL isConnecting;
@property (readonly, assign) NSString *favoritesPBoardType;

- (id)initWithDocument:(SPDatabaseDocument *)theTableDocument;

// Connection processes
- (IBAction)initiateConnection:(id)sender;
- (IBAction)cancelMySQLConnection:(id)sender;
- (void)initiateSSHTunnelConnection;
- (void)sshTunnelCallback:(SPSSHTunnel *)theTunnel;
- (void)initiateMySQLConnection;
- (void)cancelConnection;
- (void)failConnectionWithTitle:(NSString *)theTitle errorMessage:(NSString *)theErrorMessage detail:(NSString *)errorDetail;
- (void)addConnectionToDocument;

// Interface interaction
- (IBAction)chooseKeyLocation:(id)sender;
- (IBAction)editFavorites:(id)sender;
- (IBAction)showHelp:(id)sender;
- (IBAction)updateSSLInterface:(id)sender;
- (void)resizeTabViewToConnectionType:(NSUInteger)theType animating:(BOOL)animate;
- (IBAction)sortFavorites:(id)sender;
- (IBAction)reverseSortFavorites:(id)sender;

// Connection details interaction
- (BOOL)checkHost;

// Favorites interaction
- (void)updateFavorites;
- (void)updateFavoriteSelection:(id)sender;
- (id)selectedFavorite;
- (IBAction)addFavorite:(id)sender;

- (void)scrollViewFrameChanged:(NSNotification *)aNotification;

@end
