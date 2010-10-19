//
//  $Id$
//
//  SPTableInfo.m
//  sequel-pro
//
//  Created by Ben Perry on Jun 6, 2008
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

#import "SPTableInfo.h"
#import "ImageAndTextCell.h"
#import "SPDatabaseDocument.h"
#import "SPTablesList.h"
#import "SPTableData.h"
#import "SPStringAdditions.h"

@interface SPTableInfo (PrivateAPI)

- (NSString *)_getUserDefinedDateStringFromMySQLDate:(NSString *)mysqlDate;

@end

@implementation SPTableInfo

- (id)init
{
	if ((self = [super init])) {
		info = [[NSMutableArray alloc] init];
	}

	return self;
}

- (void)awakeFromNib
{
	[[NSNotificationCenter defaultCenter] addObserver:self
		selector:@selector(tableChanged:)
		name:SPTableChangedNotification
		object:tableDocumentInstance];

	[info addObject:NSLocalizedString(@"TABLE INFORMATION", @"header for table info pane")];
	[infoTable reloadData];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[info release];

	[super dealloc];
}

/**
 * Notification to indicate the table has changed and that the table info requires
 * reloading for display.  This is called on table changes, and also (with a nil argument)
 * during certain refresh operations to trigger a data update.
 * This function is not thread-safe.
 */
- (void)tableChanged:(NSNotification *)notification
{
	NSDictionary *tableStatus;
	NSNumberFormatter *numberFormatter = [[[NSNumberFormatter alloc] init] autorelease];
	[numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];

	[info removeAllObjects];

	if ([[tableListInstance tableName] isEqualToString:@""]) {
		[info addObject:NSLocalizedString(@"INFORMATION", @"header for blank info pane")];
		[info addObject:NSLocalizedString(@"multiple selection", @"multiple selection")];
		[infoTable reloadData];
		return;
	}

	// Get TABLE information
	if ([tableListInstance tableType] == SPTableTypeTable) {

		[info addObject:NSLocalizedString(@"TABLE INFORMATION", @"header for table info pane")];

		if ([tableListInstance tableName]) {

			// Retrieve the table status information via the data cache
			tableStatus = [tableDataInstance statusValues];

			// Check for errors
			if (![tableStatus count]) {
				[info addObject:NSLocalizedString(@"error occurred", @"error occurred")];
				return;
			}

			// Check for 'Create_time' == NULL
			if (![[tableStatus objectForKey:@"Create_time"] isNSNull]) {

				// Add the creation date to the infoTable
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"created: %@", @"created: %@"), [self _getUserDefinedDateStringFromMySQLDate:[tableStatus objectForKey:@"Create_time"]]]];
			}

			// Check for 'Update_time' == NULL - InnoDB tables don't have an update time
			if (![[tableStatus objectForKey:@"Update_time"] isNSNull]) {

				// Add the update date to the infoTable
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"updated: %@", @"updated: %@"), [self _getUserDefinedDateStringFromMySQLDate:[tableStatus objectForKey:@"Update_time"]]]];
			}

			// Check for 'Rows' == NULL - information_schema database doesn't report row count for it's tables
			if (![[tableStatus objectForKey:@"Rows"] isNSNull]) {
				[info addObject:[NSString stringWithFormat:[[tableStatus objectForKey:@"RowsCountAccurate"] boolValue] ? NSLocalizedString(@"rows: %@", @"rows: %@") : NSLocalizedString(@"rows: ~%@", @"rows: ~%@"),
					[numberFormatter stringFromNumber:[NSNumber numberWithLongLong:[[tableStatus objectForKey:@"Rows"] longLongValue]]]]];
			}

			[info addObject:[NSString stringWithFormat:NSLocalizedString(@"size: %@", @"size: %@"), [NSString stringForByteSize:[[tableStatus objectForKey:@"Data_length"] longLongValue]]]];
			[info addObject:[NSString stringWithFormat:NSLocalizedString(@"encoding: %@", @"encoding: %@"), [tableDataInstance tableEncoding]]];

			if (![[tableStatus objectForKey:@"Auto_increment"] isNSNull]) {
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"auto_increment: %@", @"auto_increment: %@"),
					[numberFormatter stringFromNumber:[NSNumber numberWithLongLong:[[tableStatus objectForKey:@"Auto_increment"] longLongValue]]]]];
			}

		}
	}

	// Get PROC/FUNC information
	else if ([tableListInstance tableType] == SPTableTypeProc || [tableListInstance tableType] == SPTableTypeFunc) {

		if ([tableListInstance tableType] == SPTableTypeProc)
			[info addObject:NSLocalizedString(@"PROCEDURE INFORMATION", @"header for procedure info pane")];
		else
			[info addObject:NSLocalizedString(@"FUNCTION INFORMATION", @"header for function info pane")];

		if ([tableListInstance tableName]) {

			// Retrieve the table status information via the data cache
			tableStatus = [tableDataInstance statusValues];

			// Check for errors
			if (![tableStatus count]) {
				[info addObject:NSLocalizedString(@"error occurred", @"error occurred")];
				return;
			}

			// Check for 'CREATED' == NULL
			if (![[tableStatus objectForKey:@"CREATED"] isNSNull]) {

				// Add the creation date to the infoTable
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"created: %@", @"created: %@"), [self _getUserDefinedDateStringFromMySQLDate:[tableStatus objectForKey:@"CREATED"]]]];
			}

			// Check for 'LAST_ALTERED'
			if (![[tableStatus objectForKey:@"LAST_ALTERED"] isNSNull]) {

				// Add the update date to the infoTable
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"updated: %@", @"updated: %@"), [self _getUserDefinedDateStringFromMySQLDate:[tableStatus objectForKey:@"LAST_ALTERED"]]]];
			}

			// Check for 'SQL ACCESS' and deterministic
			if (![[tableStatus objectForKey:@"SQL_DATA_ACCESS"] isNSNull] && ![[tableStatus objectForKey:@"IS_DETERMINISTIC"] isNSNull]) {
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"data access: %@ (%@)", @"data access: %@ (%@)"), [tableStatus objectForKey:@"SQL_DATA_ACCESS"], ([[tableStatus objectForKey:@"IS_DETERMINISTIC"] isEqualToString:@"YES"]) ? @"deterministic" : @"non-deterministic"]];
			}

			// Check for 'DTD_IDENTIFIER' for FUNCTIONS only
			if ([tableListInstance tableType] == SPTableTypeFunc) {
				if (![[tableStatus objectForKey:@"DTD_IDENTIFIER"] isNSNull]) {
					[info addObject:[NSString stringWithFormat:NSLocalizedString(@"return type: %@", @"return type: %@"), [tableStatus objectForKey:@"DTD_IDENTIFIER"]]];
				}
			}

			// Check for 'SECURITY_TYPE'
			if (![[tableStatus objectForKey:@"SECURITY_TYPE"] isNSNull]) {
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"execution privilege: %@", @"execution privilege: %@"), [tableStatus objectForKey:@"SECURITY_TYPE"]]];
			}

			// Check for 'DEFINER'
			if (![[tableStatus objectForKey:@"DEFINER"] isNSNull]) {
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"definer: %@", @"definer: %@"), [tableStatus objectForKey:@"DEFINER"]]];
			}

		}
	}
	// Get VIEW information
	else if ([tableListInstance tableType] == SPTableTypeView) {

		[info addObject:NSLocalizedString(@"VIEW INFORMATION", @"header for view info pane")];

		if ([tableListInstance tableName]) {

			// Retrieve the table status information via the data cache
			tableStatus = [tableDataInstance statusValues];

			// Check for errors
			if (![tableStatus count]) {
				[info addObject:NSLocalizedString(@"error occurred", @"error occurred")];
				return;
			}

			// Check for 'CREATED' == NULL
			if (![[tableStatus objectForKey:@"DEFINER"] isNSNull]) {

				// Add the creation date to the infoTable
				[info addObject:[NSString stringWithFormat:NSLocalizedString(@"definer: %@", @"definer: %@"), [tableStatus objectForKey:@"DEFINER"]]];

				// Check for 'SECURITY_TYPE'
				if (![[tableStatus objectForKey:@"SECURITY_TYPE"] isNSNull]) {
					[info addObject:[NSString stringWithFormat:NSLocalizedString(@"execution privilege: %@", @"execution privilege: %@"), [tableStatus objectForKey:@"SECURITY_TYPE"]]];
				}

				// Check for 'IS_UPDATABLE'
				if (![[tableStatus objectForKey:@"IS_UPDATABLE"] isNSNull]) {
					[info addObject:[NSString stringWithFormat:NSLocalizedString(@"is updatable: %@", @"is updatable: %@"), [tableStatus objectForKey:@"IS_UPDATABLE"]]];
				}

				// Check for 'CHECK_OPTION'
				if (![[tableStatus objectForKey:@"CHECK_OPTION"] isNSNull]) {
					[info addObject:[NSString stringWithFormat:NSLocalizedString(@"check option: %@", @"check option: %@"), [tableStatus objectForKey:@"CHECK_OPTION"]]];
				}

				// Check for 'CHARACTER_SET_CLIENT'
				if (![[tableStatus objectForKey:@"CHARACTER_SET_CLIENT"] isNSNull]) {
					[info addObject:[NSString stringWithFormat:NSLocalizedString(@"character set client: %@", @"character set client: %@"), [tableStatus objectForKey:@"CHARACTER_SET_CLIENT"]]];
				}

				// Check for 'COLLATION_CONNECTION'
				if (![[tableStatus objectForKey:@"COLLATION_CONNECTION"] isNSNull]) {
					[info addObject:[NSString stringWithFormat:NSLocalizedString(@"collation connection: %@", @"collation connection: %@"), [tableStatus objectForKey:@"COLLATION_CONNECTION"]]];
				}

			}
		}

	}

	[infoTable reloadData];

}

#pragma mark -
#pragma mark TableView datasource methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [info count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	return [info objectAtIndex:rowIndex];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	return (row == 0 ? 25 : [tableView rowHeight]);
}


- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
	// row 1 and 6 should be editable - ie be able to rename the table and change the auto_increment value.
	return NO;//(rowIndex == 1 || rowIndex == 6 );
}

- (BOOL)tableView:(NSTableView *)aTableView isGroupRow:(NSInteger)row
{
	// This makes the top row (TABLE INFORMATION) have the diff styling
	return (row == 0);
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ((rowIndex > 0) && [[aTableColumn identifier] isEqualToString:@"info"]) {
		[(ImageAndTextCell*)aCell setImage:[NSImage imageNamed:@"table-property"]];
		[(ImageAndTextCell*)aCell setIndentationLevel:1];
		[(ImageAndTextCell*)aCell setDrawsBackground:NO];
	} else {
		[(ImageAndTextCell*)aCell setImage:nil];
		[(ImageAndTextCell*)aCell setIndentationLevel:0];
	}
}

@end

@implementation SPTableInfo (PrivateAPI)

- (NSString *)_getUserDefinedDateStringFromMySQLDate:(NSString *)mysqlDate
{
	// Setup our data formatter
	NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];

	[dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];

	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterNoStyle];

	// Convert our string date from the result to an NSDate.
	NSDate *updateDate = [NSDate dateWithNaturalLanguageString:mysqlDate];

	return [dateFormatter stringFromDate:updateDate];
}

@end
