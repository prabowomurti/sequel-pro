//
//  $Id: SPUserManager.h 856 2009-06-12 05:31:39Z mltownsend $
//
//  SPUserManager.h
//  sequel-pro
//
//  Created by Mark Townsend on Jan 01, 2009
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

@class SPServerSupport, SPMySQLConnection, BWAnchoredButtonBar;

@interface SPUserManager : NSWindowController
{	
	NSPersistentStoreCoordinator *persistentStoreCoordinator;
    NSManagedObjectModel *managedObjectModel;
    NSManagedObjectContext *managedObjectContext;
	NSDictionary *privColumnToGrantMap;
	
	BOOL isInitializing;
	
	SPMySQLConnection *mySqlConnection;
	SPServerSupport *serverSupport;
	
	IBOutlet NSOutlineView *outlineView;
	IBOutlet NSTabView *tabView;
	IBOutlet NSTreeController *treeController;
	IBOutlet NSMutableDictionary *privsSupportedByServer;
	
	IBOutlet NSArrayController *schemaController;
	IBOutlet NSArrayController *grantedController;
	IBOutlet NSArrayController *availableController;
	
	IBOutlet NSTableView *schemasTableView;
	IBOutlet NSTableView *grantedTableView;
	IBOutlet NSTableView *availableTableView;
	IBOutlet NSButton *addSchemaPrivButton;
	IBOutlet NSButton *removeSchemaPrivButton;
	
	IBOutlet NSTextField *maxUpdatesTextField;
	IBOutlet NSTextField *maxConnectionsTextField;
	IBOutlet NSTextField *maxQuestionsTextField;
	
    IBOutlet NSTextField *userNameTextField;

	IBOutlet NSWindow *errorsSheet;
	IBOutlet NSTextView *errorsTextView;

	IBOutlet BWAnchoredButtonBar *splitViewButtonBar;

	NSMutableArray *schemas;
	NSMutableArray *grantedSchemaPrivs;
	NSMutableArray *availablePrivs;
	
	NSArray *treeSortDescriptors;
	NSSortDescriptor *treeSortDescriptor;

	BOOL isSaving;
	NSMutableString *errorsString;
}

@property (nonatomic, retain) SPMySQLConnection *mySqlConnection;
@property (nonatomic, retain) SPServerSupport *serverSupport;
@property (nonatomic, retain) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, retain, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, retain) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, retain) NSMutableDictionary *privsSupportedByServer;

@property (nonatomic, retain) NSArray *treeSortDescriptors;
@property (nonatomic, retain) NSMutableArray *schemas;
@property (nonatomic, retain) NSMutableArray *grantedSchemaPrivs;
@property (nonatomic, retain) NSMutableArray *availablePrivs;

// Add/Remove users
- (IBAction)addUser:(id)sender;
- (IBAction)removeUser:(id)sender;
- (IBAction)addHost:(id)sender;
- (void)editNewHost;
- (IBAction)removeHost:(id)sender;

// General
- (IBAction)doCancel:(id)sender;
- (IBAction)doApply:(id)sender;
- (IBAction)checkAllPrivileges:(id)sender;
- (IBAction)uncheckAllPrivileges:(id)sender;
- (IBAction)closeErrorsSheet:(id)sender;
- (IBAction)doubleClickSchemaPriv:(id)sender;

// Schema Privieges
- (IBAction)addSchemaPriv:(id)sender;
- (IBAction)removeSchemaPriv:(id)sender;

// Refresh
- (IBAction)refresh:(id)sender;

// Core Data notifications
- (void)contextDidSave:(NSNotification *)notification;
- (BOOL)insertUsers:(NSArray *)insertedUsers;
- (BOOL)deleteUsers:(NSArray *)deletedUsers;
- (BOOL)updateUsers:(NSArray *)updatedUsers;
- (BOOL)updateResourcesForUser:(NSManagedObject *)user;
- (BOOL)grantPrivilegesToUser:(NSManagedObject *)user;
- (BOOL)grantDbPrivilegesWithPrivilege:(NSManagedObject *)user;

@end
