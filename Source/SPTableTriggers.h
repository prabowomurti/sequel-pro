//
//  $Id$
//
//  SPTableTriggers.h
//  sequel-pro
//
//  Created by Marius Ursache
//  Copyright (c) 2010 Marius Ursache. All rights reserved.
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

@interface SPTableTriggers : NSObject 
{
	IBOutlet id tableDocumentInstance;
	IBOutlet id tablesListInstance;
	IBOutlet id tableDataInstance;
	
	IBOutlet id tableList;
	
	IBOutlet NSButton      *addTriggerButton;
	IBOutlet NSButton      *removeTriggerButton;	
	IBOutlet NSButton      *refreshTriggersButton;
	IBOutlet NSTableView   *triggersTableView;
	IBOutlet NSPanel       *addTriggerPanel;
	IBOutlet NSTextField   *labelTextField;
	
	IBOutlet NSTextField   *triggerNameTextField;
	IBOutlet NSPopUpButton *triggerActionTimePopUpButton;
	IBOutlet NSPopUpButton *triggerEventPopUpButton;
	IBOutlet NSTextView    *triggerStatementTextView;
	
	IBOutlet NSBox         *addTriggerTableBox;
	IBOutlet NSButton      *confirmAddTriggerButton;
	
	MCPConnection *connection;
	
	NSMutableArray *triggerData;
	
	BOOL isEdit;
	
	NSString *editTriggerName;
	NSString *editTriggerEvent;
	NSString *editTriggerTableName;
	NSString *editTriggerStatement;
	NSString *editTriggerActionTime;
}

@property (readwrite, assign) MCPConnection *connection;

- (void)loadTriggers;

// IB action methods
- (IBAction)addTrigger:(id)sender;
- (IBAction)editTrigger:(id)sender;
- (IBAction)removeTrigger:(id)sender;
- (IBAction)closeTriggerSheet:(id)sender;
- (IBAction)confirmAddTrigger:(id)sender;
- (IBAction)refreshTriggers:(id)sender;

// Task interaction
- (void)startDocumentTaskForTab:(NSNotification *)notification;
- (void)endDocumentTaskForTab:(NSNotification *)notification;

// Other
- (NSArray *)triggerDataForPrinting;

@end
