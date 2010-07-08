//
//  TableDocument.h
//  sequel-pro
//
//  Created by lorenz textor (lorenz@textor.ch) on Wed May 01 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
//  
//  Forked by Abhi Beckert (abhibeckert.com) 2008-04-04
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

#import "TableContent.h"
#import "TableDocument.h"
#import "TablesList.h"
#import "CMImageView.h"
#import "SPDataCellFormatter.h"
#import "SPTableData.h"

@implementation TableContent

- (id)init
{
	if (![super init])
		return nil;
	
	fullResult = [[NSMutableArray alloc] init];
	filteredResult = [[NSMutableArray alloc] init];
	oldRow = [[NSMutableDictionary alloc] init];
	selectedTable = nil;
	sortField = nil;
	areShowingAllRows = false;
	
	return self;
}

- (void)awakeFromNib
{
}

/*
 Loads aTable, retrieving column information and updating the tableViewColumns before
 reloading table data into the fullResults array and redrawing the table.
 */
- (void)loadTable:(NSString *)aTable
{
	int			i;
	NSNumber	*colWidth;
	NSArray		*theColumns, *columnNames;
	NSDictionary *columnDefinition;
	NSTableColumn	*theCol;
	NSString	*query;
	CMMCPResult	*queryResult;
	BOOL		preserveCurrentView = [aTable isEqualToString:selectedTable];
	NSString	*preservedFilterField = nil, *preservedFilterComparison, *preservedFilterValue;

	// Clear the selection, and abort the reload if the user is still editing a row
	[tableContentView deselectAll:self];
	if ( isEditingRow )
		return;

	// Store the newly selected table name
	selectedTable = aTable;

	// Reset table key store for use in argumentForRow:
	if ( keys )
		keys = nil;

	// Restore the table content view to the top left
	[tableContentView scrollRowToVisible:0];
	[tableContentView scrollColumnToVisible:0];

	// Remove existing columns from the table
	theColumns = [tableContentView tableColumns];
	while ([theColumns count]) {
		[tableContentView removeTableColumn:[theColumns objectAtIndex:0]];
	}

	// If no table has been supplied, reset the view to a blank table and disabled elements
	if ( [aTable isEqualToString:@""] || !aTable )
	{

		// Empty the stored data arrays
		[fullResult removeAllObjects];
		[filteredResult removeAllObjects];
		[tableContentView reloadData];
		areShowingAllRows = YES;
		[countText setStringValue:@""];

		// Empty and disable filter options
		[fieldField setEnabled:NO];
		[fieldField removeAllItems];
		[fieldField addItemWithTitle:NSLocalizedString(@"field", @"popup menuitem for field (showing only if disabled)")];
		[compareField setEnabled:NO];
		[compareField removeAllItems];
		[compareField addItemWithTitle:NSLocalizedString(@"is", @"popup menuitem for field IS value")];
		[argumentField setEnabled:NO];
		[argumentField setStringValue:@""];
		[filterButton setEnabled:NO];

		// Empty and disable the limit field
		[limitRowsField setStringValue:@""];
		[limitRowsText setStringValue:NSLocalizedString(@"No limit", @"text showing that the result isn't limited")];
		[limitRowsField setEnabled:NO];
		[limitRowsButton setEnabled:NO];
		[limitRowsStepper setEnabled:NO];

		// Disable table action buttons
		[addButton setEnabled:NO];
		[copyButton setEnabled:NO];
		[removeButton setEnabled:NO];

		return;
	}

	// Post a notification that a query will be performed
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:self];

	// Retrieve the field names and types for this table from the data cache.  This is used when requesting all data as part
	// of the fieldListForQuery method, and also to decide whether or not to preserve the current filter/sort settings.
	theColumns = [tableDataInstance columns];
	columnNames = [tableDataInstance columnNames];

	// Retrieve the number of rows in the table and initially mark all as being visible.
	numRows = [self getNumberOfRows];
	areShowingAllRows = YES;
	
	// Add the new columns to the table
	for ( i = 0 ; i < [theColumns count] ; i++ ) {
		columnDefinition = [theColumns objectAtIndex:i];

		// Set up the column
		theCol = [[NSTableColumn alloc] initWithIdentifier:[columnDefinition objectForKey:@"name"]];
		[[theCol headerCell] setStringValue:[columnDefinition objectForKey:@"name"]];
		[theCol setEditable:YES];
		
		// Set up the data cell depending on the column type
		NSComboBoxCell *dataCell;
		if ([[columnDefinition objectForKey:@"typegrouping"] isEqualToString:@"enum"]) {
			dataCell = [[[NSComboBoxCell alloc] initTextCell:@""] autorelease];
			[dataCell setButtonBordered:NO];
			[dataCell setBezeled:NO];
			[dataCell setDrawsBackground:NO];
			[dataCell setCompletes:YES];
			[dataCell setControlSize:NSSmallControlSize];
			[dataCell addItemWithObjectValue:@"NULL"];
			[dataCell addItemsWithObjectValues:[columnDefinition objectForKey:@"values"]];
		} else {
			dataCell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
		}
		[dataCell setEditable:YES];

		// Set the line break mode and an NSFormatter subclass which truncates long strings for display
		[dataCell setLineBreakMode:NSLineBreakByTruncatingTail];
		[dataCell setFormatter:[[SPDataCellFormatter new] autorelease]];

		// Set the data cell font according to the preferences
		if ( [prefs boolForKey:@"useMonospacedFonts"] ) {
			[dataCell setFont:[NSFont fontWithName:@"Monaco" size:10]];
		} else {
			[dataCell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		}

		// Assign the data cell
		[theCol setDataCell:dataCell];
		
		// Set the width of this column to saved value if exists
		colWidth = [[[[prefs objectForKey:@"tableColumnWidths"] objectForKey:[NSString stringWithFormat:@"%@@%@", [tableDocumentInstance database], [tableDocumentInstance host]]] objectForKey:[tablesListInstance tableName]] objectForKey:[columnDefinition objectForKey:@"name"]];
		if ( colWidth ) {
			[theCol setWidth:[colWidth floatValue]];
		}
		
		// Add the column to the table
		[tableContentView addTableColumn:theCol];
		[theCol release];
	}

	// If the table has been reloaded and the previously selected sort column is still present, reselect it. 
	if (preserveCurrentView && [columnNames containsObject:sortField]) {
		theCol = [tableContentView tableColumnWithIdentifier:sortField];
		[tableContentView setHighlightedTableColumn:theCol];
		if ( isDesc ) {
			[tableContentView setIndicatorImage:[NSImage imageNamed:@"NSDescendingSortIndicator"] inTableColumn:theCol];
		} else {
			[tableContentView setIndicatorImage:[NSImage imageNamed:@"NSAscendingSortIndicator"] inTableColumn:theCol];
		}
	
	// Otherwise, clear sorting
	} else {
		sortField = nil;
		isDesc = NO;
	}

	// Preserve the stored filter settings if appropriate
	if (preserveCurrentView && [fieldField isEnabled]) {
		preservedFilterField = [NSString stringWithString:[[fieldField selectedItem] title]];
		preservedFilterComparison = [NSString stringWithString:[[compareField selectedItem] title]];
		preservedFilterValue = [NSString stringWithString:[argumentField stringValue]];
	}

	// Enable and initialize filter fields (with tags for position of menu item and field position)
	[fieldField setEnabled:YES];
	[fieldField removeAllItems];
	[fieldField addItemsWithTitles:columnNames];
	for ( i = 0 ; i < [fieldField numberOfItems] ; i++ ) {
		[[fieldField itemAtIndex:i] setTag:i];
	}
	[compareField setEnabled:YES];
	[self setCompareTypes:self];
	[argumentField setEnabled:YES];
	[argumentField setStringValue:@""];
	[filterButton setEnabled:YES];
	
	// Restore preserved filter settings if appropriate and valid
	if (preserveCurrentView && preservedFilterField != nil && [fieldField itemWithTitle:preservedFilterField]) {
		[fieldField selectItemWithTitle:preservedFilterField];
		[self setCompareTypes:self];
	}
	if (preserveCurrentView && preservedFilterField != nil
		&& [fieldField itemWithTitle:preservedFilterField]
		&& [compareField itemWithTitle:preservedFilterComparison]) {
		[compareField selectItemWithTitle:preservedFilterComparison];
		[argumentField setStringValue:preservedFilterValue];
		areShowingAllRows = NO;
	}

	// Enable or disable the limit fields according to preference setting
	if ( [prefs boolForKey:@"limitRows"] ) {

		// Attempt to preserve the limit value if it's still valid
		if (!preserveCurrentView || [limitRowsField intValue] < 1 || [limitRowsField intValue] >= numRows) {	
			[limitRowsField setStringValue:@"1"];
		}
		[limitRowsField setEnabled:YES];
		[limitRowsButton setEnabled:YES];
		[limitRowsStepper setEnabled:YES];
		[limitRowsText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Limited to %d rows starting with row", @"text showing the number of rows the result is limited to"),
									   [prefs integerForKey:@"limitRowsValue"]]];
		if ([prefs integerForKey:@"limitRowsValue"] < numRows)
			areShowingAllRows = NO;
	} else {
		[limitRowsField setEnabled:NO];
		[limitRowsButton setEnabled:NO];
		[limitRowsStepper setEnabled:NO];
		[limitRowsField setStringValue:@""];
		[limitRowsText setStringValue:NSLocalizedString(@"No limit", @"text showing that the result isn't limited")];
	}

	// Enable the table buttons
	[addButton setEnabled:YES];
	[copyButton setEnabled:YES];
	[removeButton setEnabled:YES];

	// Perform the data query and store the result as an array containing a dictionary per result row
	query = [NSString stringWithFormat:@"SELECT %@ FROM `%@`", [self fieldListForQuery], selectedTable];
	if ( sortField ) {
		query = [NSString stringWithFormat:@"%@ ORDER BY `%@`", query, sortField];
		if ( isDesc )
			query = [query stringByAppendingString:@" DESC"];
	}
	if ( [prefs boolForKey:@"limitRows"] ) {
		if ( [limitRowsField intValue] <= 0 ) {
			[limitRowsField setStringValue:@"1"];
		}
		query = [query stringByAppendingString:
					[NSString stringWithFormat:@" LIMIT %d,%d",
						[limitRowsField intValue]-1, [prefs integerForKey:@"limitRowsValue"]]];
	}
	queryResult = [mySQLConnection queryString:query];
	if ( queryResult == nil ) {
		NSLog(@"Loading table data for %@ failed, query string was: %@", aTable, query);
		return;
	}
	[fullResult setArray:[self fetchResultAsArray:queryResult]];

	// Apply any filtering and update the row count
	if ( !areShowingAllRows ) {
		[self filterTable:self];
		[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows of %d selected", @"text showing how many rows are in the filtered result"), [filteredResult count], numRows]];
	} else {
		[filteredResult setArray:fullResult];
		[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows in table", @"text showing how many rows are in the result"), numRows]];
	}

	// Reload the table data.
	[tableContentView reloadData];
	
	// Post the notification that the query is finished
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:self];
}


/*
 * Reloads the current table data, performing a new SQL query.  Now attempts to preserve sort order, filters, and viewport.
 */
- (IBAction)reloadTable:(id)sender
{
	// Store the current viewport location
	NSRect viewRect = [tableContentView visibleRect];

	// Clear the table data column cache
	[tableDataInstance resetColumnData];

	[self loadTable:selectedTable];
	
	// Restore the viewport
	[tableContentView scrollRectToVisible:viewRect];
}


/*
 * Reload the table values without reconfiguring the tableView (with filter and limit if set)
 */
- (IBAction)reloadTableValues:(id)sender
{
	NSString *queryString;
	CMMCPResult *queryResult;
	
	//query started
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:self];
	
	//enable or disable limit fields
	if ( [prefs boolForKey:@"limitRows"] ) {
		[limitRowsField setEnabled:YES];
		[limitRowsButton setEnabled:YES];
		[limitRowsStepper setEnabled:YES];
		[limitRowsText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Limited to %d rows starting with row", @"text showing the number of rows the result is limited to"),
									   [prefs integerForKey:@"limitRowsValue"]]];
	} else {
		[limitRowsField setEnabled:NO];
		[limitRowsButton setEnabled:NO];
		[limitRowsStepper setEnabled:NO];
		[limitRowsText setStringValue:NSLocalizedString(@"No limit", @"text showing that the result isn't limited")];
		[limitRowsField setStringValue:@""];
	}
	
	//	queryString = [@"SELECT * FROM " stringByAppendingString:selectedTable];
	queryString = [NSString stringWithFormat:@"SELECT %@ FROM `%@`", [self fieldListForQuery], selectedTable];
	if ( sortField ) {
		queryString = [NSString stringWithFormat:@"%@ ORDER BY `%@`", queryString, sortField];
		//		queryString = [queryString stringByAppendingString:[NSString stringWithFormat:@" ORDER BY `%@`", sortField]];
		if ( isDesc )
			queryString = [queryString stringByAppendingString:@" DESC"];
	}
	if ( [prefs boolForKey:@"limitRows"] ) {
		if ( [limitRowsField intValue] <= 0 ) {
			[limitRowsField setStringValue:@"1"];
		}
		queryString = [queryString stringByAppendingString:
					   [NSString stringWithFormat:@" LIMIT %d,%d",
						[limitRowsField intValue]-1, [prefs integerForKey:@"limitRowsValue"]]];
		[limitRowsField selectText:self];
	}
	queryResult = [mySQLConnection queryString:queryString];
	//	[fullResult setArray:[[self fetchResultAsArray:queryResult] retain]];
	[fullResult setArray:[self fetchResultAsArray:queryResult]];
	numRows = [self getNumberOfRows];
	if ( !areShowingAllRows ) {
		[self filterTable:self];
		[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows of %d selected", @"text showing how many rows are in the filtered result"), [filteredResult count], numRows]];
	} else {
		[filteredResult setArray:fullResult];
		[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows in table", @"text showing how many rows are in the result"), numRows]];
	}
	[tableContentView reloadData];
	
	//query finished
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:self];
}


/*
 * Filter the table with arguments given by the user
 */
- (IBAction)filterTable:(id)sender
{
	CMMCPResult *theResult;
	int tag = [[compareField selectedItem] tag];
	NSString *compareOperator = @"";
	NSMutableString *argument = [[NSMutableString alloc] initWithString:[argumentField stringValue]];
	NSString *queryString;
	int i;

	// Update negative limits
	if ( [limitRowsField intValue] <= 0 ) {
		[limitRowsField setStringValue:@"1"];
	}
	
	// If the filter field is empty, the limit field is at 1, and the selected filter is not looking
	// for NULLs or NOT NULLs, then don't allow filtering.
	if (([argument length] == 0) && (![[[compareField selectedItem] title] hasSuffix:@"NULL"]) && (![prefs boolForKey:@"limitRows"] || [limitRowsField intValue] == 1)) {
		[argument release];
		[self showAll:sender];
		return;
	}
	
	// Query started
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:self];
	
	BOOL doQuote = YES;
	BOOL ignoreArgument = NO;

	// Start building the query string
	queryString = [NSString stringWithFormat:@"SELECT %@ FROM `%@`", [self fieldListForQuery], selectedTable];			

	// Add filter if appropriate
	if (([argument length] > 0) || [[[compareField selectedItem] title] hasSuffix:@"NULL"]) {
		if (![compareType isEqualToString:@""]) {
			if ([compareType isEqualToString:@"string"]) {
				// String comparision
				switch (tag) {
					case 0:
						compareOperator = @"LIKE";
						break;
					case 1:
						compareOperator = @"NOT LIKE";
						break;
					case 2:
						compareOperator = @"LIKE";
						[argument setString:[[@"%" stringByAppendingString:argument] stringByAppendingString:@"%"]];
						break;
					case 3:
						compareOperator = @"NOT LIKE";
						[argument setString:[[@"%" stringByAppendingString:argument] stringByAppendingString:@"%"]];
						break;
					case 4:
						compareOperator = @"IN";
						doQuote = NO;
						[argument setString:[[@"('" stringByAppendingString:argument] stringByAppendingString:@"')"]];
						break;
					case 5:
						compareOperator = @"IS NULL";
						doQuote = NO;
						ignoreArgument = YES;
						break;
					case 6:
						compareOperator = @"IS NOT NULL";
						doQuote = NO;
						ignoreArgument = YES;
						break;
				}
			} else if ( [compareType isEqualToString:@"number"] ) {
				//number comparision
				switch ( tag ) {
					case 0:
						compareOperator = @"=";
						break;
					case 1:
						compareOperator = @"!=";
						break;
					case 2:
						compareOperator = @">";
						break;
					case 3:
						compareOperator = @"<";
						break;
					case 4:
						compareOperator = @">=";
						break;
					case 5:
						compareOperator = @"<=";
						break;
					case 6:
						compareOperator = @"IN";
						doQuote = NO;
						[argument setString:[[@"(" stringByAppendingString:argument] stringByAppendingString:@")"]];
						break;
					case 7:
						compareOperator = @"IS NULL";
						doQuote = NO;
						ignoreArgument = YES;
						break;
					case 8:
						compareOperator = @"IS NOT NULL";
						doQuote = NO;
						ignoreArgument = YES;
						break;
				}
			} else if ( [compareType isEqualToString:@"date"] ) {
				//date comparision
				switch ( tag ) {
					case 0:
						compareOperator = @"=";
						break;
					case 1:
						compareOperator = @"!=";
						break;
					case 2:
						compareOperator = @">";
						break;
					case 3:
						compareOperator = @"<";
						break;
					case 4:
						compareOperator = @">=";
						break;
					case 5:
						compareOperator = @"<=";
						break;
					case 6:
						compareOperator = @"IS NULL";
						doQuote = NO;
						ignoreArgument = YES;
						break;
					case 7:
						compareOperator = @"IS NOT NULL";
						doQuote = NO;
						ignoreArgument = YES;
						break;
				}
			} else {
				doQuote = NO;
				ignoreArgument = YES;
				NSLog(@"ERROR: unknown compare type %@", compareType);
			}
			
			if (doQuote) {
				//escape special characters
				for ( i = 0 ; i < [argument length] ; i++ ) {
					if ( [argument characterAtIndex:i] == '\\' ) {
						[argument insertString:@"\\" atIndex:i];
						i++;
					}
				}
				[argument setString:[mySQLConnection prepareString:argument]];
				queryString = [NSString stringWithFormat:@"%@ WHERE `%@` %@ \"%@\"",
								queryString, [fieldField titleOfSelectedItem], compareOperator, argument];			
			} else {
				queryString = [NSString stringWithFormat:@"%@ WHERE `%@` %@ %@",
								queryString, [fieldField titleOfSelectedItem],
								compareOperator, (ignoreArgument) ? @"" : argument];
			}
		}
	}

	// Add sorting details if appropriate
	if ( sortField ) {
		queryString = [NSString stringWithFormat:@"%@ ORDER BY `%@`", queryString, sortField];
		if ( isDesc )
			queryString = [queryString stringByAppendingString:@" DESC"];
	}

	// LIMIT if appropriate
	if ( [prefs boolForKey:@"limitRows"] ) {
		queryString = [NSString stringWithFormat:@"%@ LIMIT %d,%d", queryString,
						[limitRowsField intValue]-1, [prefs integerForKey:@"limitRowsValue"]];
	}

	theResult = [mySQLConnection queryString:queryString];
	[filteredResult setArray:[self fetchResultAsArray:theResult]];
	
	[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows of %d selected", @"text showing how many rows are in the filtered result"), [filteredResult count], numRows]];
	
	// Reset the table view
	[tableContentView scrollPoint:NSMakePoint(0.0, 0.0)];
	[tableContentView reloadData];
	areShowingAllRows = NO;
	
	//query finished
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:self];
	[argument release];
}

/**
 * reload tableView with all results shown (no new mysql-query, it uses simply the fullResult array)
 */
- (IBAction)showAll:(id)sender
{
	[filteredResult setArray:fullResult];
	[tableContentView reloadData];
	areShowingAllRows = YES;
	
	[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows in table", @"text showing how many rows are in the result"), numRows]];
}

/**
 * Enables or disables the filter input field based on the selected filter type.
 */
- (IBAction)toggleFilterField:(id)sender
{
	// If the user is filtering for NULLs then disabled the filter field, otherwise enable it.
	[argumentField setEnabled:(![[[compareField selectedItem] title] hasSuffix:@"NULL"])];
}


#pragma mark Edit methods

/*
 * Adds an empty row to the table-array and goes into edit mode
 */
- (IBAction)addRow:(id)sender
{
	NSArray *columns;
	NSMutableDictionary *column, *newRow = [NSMutableDictionary dictionary];
	int i;

	if ( ![self selectionShouldChangeInTableView:nil] )
		return;

	columns = [[NSArray alloc] initWithArray:[tableDataInstance columns]];
	for ( i = 0 ; i < [columns count] ; i++ ) {
		column = [columns objectAtIndex:i];
		if ([column objectForKey:@"default"] == nil) {
			[newRow setObject:[prefs stringForKey:@"nullValue"] forKey:[column objectForKey:@"name"]];
		} else {
			[newRow setObject:[column objectForKey:@"default"] forKey:[column objectForKey:@"name"]];
		}
	}
	[filteredResult addObject:newRow];
	[columns release];

	isEditingRow = YES;
	isEditingNewRow = YES;
	[tableContentView reloadData];
	[tableContentView selectRow:[tableContentView numberOfRows]-1 byExtendingSelection:NO];
	if ( [multipleLineEditingButton state] == NSOffState )
		[tableContentView editColumn:0 row:[tableContentView numberOfRows]-1 withEvent:nil select:YES];
}

- (IBAction)copyRow:(id)sender
/*
 copies a row of the table-array and goes into edit mode
 */
{
	NSMutableDictionary *tempRow;
	CMMCPResult *queryResult;
	NSDictionary *row;
	int i;
	
	if ( ![self selectionShouldChangeInTableView:nil] )
		return;
	if ( [tableContentView numberOfSelectedRows] < 1 )
		return;
	if ( [tableContentView numberOfSelectedRows] > 1 ) {
		NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, NSLocalizedString(@"You can only copy single rows.", @"message of panel when trying to copy multiple rows"));
		return;
	}
	
	//copy row
	tempRow = [NSMutableDictionary dictionaryWithDictionary:[filteredResult objectAtIndex:[tableContentView selectedRow]]];
	[filteredResult insertObject:tempRow atIndex:[tableContentView selectedRow]+1];
	isEditingRow = YES;
	isEditingNewRow = YES;
	//set autoincrement fields to NULL
	queryResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM `%@`", selectedTable]];
	if ([queryResult numOfRows]) [queryResult dataSeek:0];
	for ( i = 0 ; i < [queryResult numOfRows] ; i++ ) {
		row = [queryResult fetchRowAsDictionary];
		if ( [[row objectForKey:@"Extra"] isEqualToString:@"auto_increment"] ) {
			[tempRow setObject:[prefs stringForKey:@"nullValue"] forKey:[row objectForKey:@"Field"]];
		}
	}
	//select row and go in edit mode
	[tableContentView reloadData];
	[tableContentView selectRow:[tableContentView selectedRow]+1 byExtendingSelection:NO];
	if ( [multipleLineEditingButton state] == NSOffState )
		[tableContentView editColumn:0 row:[tableContentView selectedRow] withEvent:nil select:YES];
}

- (IBAction)removeRow:(id)sender
/*
 asks user if he really wants to delete the selected rows
 */
{
	if ( ![self selectionShouldChangeInTableView:nil] )
		return;
	if ( ![tableContentView numberOfSelectedRows] )
		return;
	/*
	 if ( ([tableContentView numberOfSelectedRows] == [self numberOfRowsInTableView:tableContentView]) &&
	 areShowingAllRows &&
	 (![prefs boolForKey:@"limitRows"] || ([tableContentView numberOfSelectedRows] < [prefs integerForKey:@"limitRowsValue"])) ) {
	 */
	if ( ([tableContentView numberOfSelectedRows] == [tableContentView numberOfRows]) && 
		(([prefs boolForKey:@"limitRows"] && [tableContentView numberOfSelectedRows] == [self fetchNumberOfRows]) ||
		 (![prefs boolForKey:@"limitRows"] && [tableContentView numberOfSelectedRows] == [self getNumberOfRows])) ) {
		NSBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"Delete", @"delete button"), NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:),
						  nil, @"removeallrows", NSLocalizedString(@"Do you really want to delete all rows?", @"message of panel asking for confirmation for deleting all rows"));
	} else if ( [tableContentView numberOfSelectedRows] == 1 ) {
		NSBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"Delete", @"delete button"), NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:),
						  nil, @"removerow", NSLocalizedString(@"Do you really want to delete the selected row?", @"message of panel asking for confirmation for deleting the selected row"));
	} else {
		NSBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"Delete", @"delete button"), NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:),
						  nil, @"removerow",
						  [NSString stringWithFormat:NSLocalizedString(@"Do you really want to delete the selected %d rows?", @"message of panel asking for confirmation for deleting the selected rows"), [tableContentView numberOfSelectedRows]]);
	}
}


//editSheet methods
- (IBAction)closeEditSheet:(id)sender
{
	[NSApp stopModalWithCode:[sender tag]];
}

- (IBAction)openEditSheet:(id)sender
/*
 loads a file into the editSheet
 */
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	
	if ( [panel runModal] == NSOKButton ) {
		NSString *fileName = [panel filename];
		
		// free old data
		if ( editData != nil ) {
			[editData release];
		}
		
		// load new data/images
		editData = [[NSData alloc] initWithContentsOfFile:fileName];
		NSImage *image = [[[NSImage alloc] initByReferencingFile:fileName] autorelease];
		NSString *contents = [[NSString stringWithContentsOfFile:fileName] autorelease];
		
		// set the image preview, string contents and hex representation
		[editImage setImage:image];
		[editTextView setString:contents];
		[hexTextView setString:[self dataToHex:editData]];
	}
}

- (IBAction)saveEditSheet:(id)sender
/*
 saves a file containing the content of the editSheet
 */
{
	NSSavePanel *panel = [NSSavePanel savePanel];
	
	if ( [panel runModal] == NSOKButton ) {
		NSString *fileName = [panel filename];
		NSString *data;
		
		if ( [editData isKindOfClass:[NSData class]] ) {
			data = editData;
		} else {
			data = [editData description];
		}
		[editData writeToFile:fileName atomically:YES encoding:[CMMCPConnection encodingForMySQLEncoding:[(NSString *)[tableDocumentInstance encoding] UTF8String]] error:NULL];
	}
}

- (IBAction)dropImage:(id)sender
/*
 invoked when user drag&drops image on imageView
 */
{
	// load new data/images
	if (nil != editData)
	{
		[editData release];
	}
	editData = [[[NSData alloc] initWithContentsOfFile:[sender draggedFilePath]] retain];
	NSString *contents = [NSString stringWithContentsOfFile:[sender draggedFilePath]];
	
	// set the string contents and hex representation
	[editTextView setString:contents];
	[hexTextView setString:[self dataToHex:editData]];
}

- (void)textDidChange:(NSNotification *)notification
/*
 invoked when the user changes the string in the editSheet
 */
{
	// clear the image and hex (since i doubt someone can "type" a gif)
	[editImage setImage:nil];
	[hexTextView setString:@""];
	
	// free old data
	if ( editData != nil ) {
		[editData release];
	}
	
	// set edit data to text
	editData = [[editTextView string] retain];
}

- (NSString *)dataToHex:(NSData *)data
/*
 returns the hex representation of the given data
 */
{
	unsigned i;
	unsigned totalLength = [data length];
	int bytesPerLine = 16;
	NSMutableString *retVal = [NSMutableString string];
	unsigned char *nodisplay = "\t\n\r\f";
	
	// get the length of the longest location
	int longest = [(NSString *)[NSString stringWithFormat:@"%X", totalLength - ( totalLength % bytesPerLine )] length];
	
	for ( i = 0; i < totalLength; i += bytesPerLine ) {
		int j;
		NSMutableString *hex = [[NSMutableString alloc] initWithCapacity:(3 * bytesPerLine - 1)];
		NSMutableString *location = [[NSMutableString alloc] initWithCapacity:(longest + 2)];
		NSMutableString *chars = [[NSMutableString alloc] init];
		unsigned char *buffer;
		int buffLength = bytesPerLine;
		
		// add hex value of location
		[location appendString:[NSString stringWithFormat:@"%X", i]];
		
		// pad it
		while( longest > [location length] ) {
			[location insertString:@"0" atIndex:0];
		}
		
		// get the chars from the NSData obj
		if ( i + buffLength >= totalLength ) {
			buffLength = totalLength - i;
		}
		buffer = (unsigned char*) malloc( sizeof( unsigned char ) * buffLength );
		NSRange range = { i, buffLength };
		[data getBytes:buffer range:range];
		
		// build the hex string
		for ( j = 0; j < buffLength; j++ ) {
			unsigned char byte = *(buffer + j);
			if ( byte < 16 ) {
				[hex appendString:@"0"];
			}
			[hex appendString:[NSString stringWithFormat:@"%X", byte]];
			[hex appendString:@" "];
			
			// if the char is undisplayable, replace it with "."
			unsigned char current;
			int count = 0;
			while ( ( current = *(nodisplay + count++) ) > 0 ) {
				if ( current == byte ) {
					*(buffer + j) = '.';
					break;
				}
			}
		}
		
		// add padding to missing hex values.
		for ( j = 0; j < bytesPerLine - buffLength; j++ ) {
			[hex appendString:@"   "];
		}
		
		// remove extra ghost characters
		[chars appendString:[NSString stringWithCString:buffer]];
		if ( [chars length] > bytesPerLine ) {
			[chars deleteCharactersInRange:NSMakeRange( bytesPerLine, [chars length] - bytesPerLine )];
		}
		
		// build line
		[retVal appendString:location];
		[retVal appendString:@"  "];
		[retVal appendString:hex];
		[retVal appendString:@" "];
		[retVal appendString:chars];
		[retVal appendString:@"\n"];
		
		// clean up
		[hex release];
		[chars release];
		[location release];
		free( buffer );
	}
	
	return retVal;
}

//getter methods
- (NSArray *)currentResult
/*
 returns the current result (as shown in table content view) as array, the first object containing the field names as array, the following objects containing the rows as array
 */
{
	NSArray *tableColumns;
	NSEnumerator *enumerator;
	id tableColumn;
	NSMutableArray *currentResult = [NSMutableArray array];
	NSMutableArray *tempRow = [NSMutableArray array];
	int i;
	
	//load table if not already done
	if ( ![tablesListInstance contentLoaded] ) {
		[self loadTable:[tablesListInstance tableName]];
	}
	
	tableColumns = [tableContentView tableColumns];
	enumerator = [tableColumns objectEnumerator];
	
	//set field names as first line
	while ( (tableColumn = [enumerator nextObject]) ) {
		[tempRow addObject:[[tableColumn headerCell] stringValue]];
	}
	[currentResult addObject:[NSArray arrayWithArray:tempRow]];
	
	//add rows
	for ( i = 0 ; i < [self numberOfRowsInTableView:nil] ; i++) {
		[tempRow removeAllObjects];
		enumerator = [tableColumns objectEnumerator];
		while ( (tableColumn = [enumerator nextObject]) ) {
			[tempRow addObject:[self tableView:nil objectValueForTableColumn:tableColumn row:i]];
		}
		[currentResult addObject:[NSArray arrayWithArray:tempRow]];
	}
	return currentResult;
}


//additional methods
- (void)setConnection:(CMMCPConnection *)theConnection
/*
 sets the connection (received from TableDocument) and makes things that have to be done only once 
 */
{
	mySQLConnection = theConnection;
	
	[tableContentView setVerticalMotionCanBeginDrag:NO];
	
	prefs = [[NSUserDefaults standardUserDefaults] retain];
	if ( [prefs boolForKey:@"useMonospacedFonts"] ) {
		[argumentField setFont:[NSFont fontWithName:@"Monaco" size:10]];
		[limitRowsField setFont:[NSFont fontWithName:@"Monaco" size:[NSFont smallSystemFontSize]]];
		[editTextView setFont:[NSFont fontWithName:@"Monaco" size:[NSFont smallSystemFontSize]]];
	} else {
		[editTextView setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[limitRowsField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		[argumentField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	}
	[hexTextView setFont:[NSFont fontWithName:@"Monaco" size:[NSFont smallSystemFontSize]]];
	[limitRowsStepper setEnabled:NO];
	if ( [prefs boolForKey:@"limitRows"] ) {
		[limitRowsText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Limited to %d rows starting with row", @"text showing the number of rows the result is limited to"),
									   [prefs integerForKey:@"limitRowsValue"]]];
	} else {
		[limitRowsText setStringValue:NSLocalizedString(@"No limit", @"text showing that the result isn't limited")];
		[limitRowsField setStringValue:@""];
	}
}

/**
 * Sets the compare types for the filter and the appropriate formatter for the textField
 */
- (IBAction)setCompareTypes:(id)sender
{
	NSArray *stringTypes  = [NSArray arrayWithObjects:NSLocalizedString(@"is", @"popup menuitem for field IS value"), NSLocalizedString(@"is not", @"popup menuitem for field IS NOT value"), NSLocalizedString(@"contains", @"popup menuitem for field CONTAINS value"), NSLocalizedString(@"contains not", @"popup menuitem for field CONTAINS NOT value"), @"IN", nil];
	NSArray *numberTypes  = [NSArray arrayWithObjects:@"=", @"≠", @">", @"<", @"≥", @"≤", @"IN", nil];
	NSArray *dateTypes    = [NSArray arrayWithObjects:NSLocalizedString(@"is", @"popup menuitem for field IS value"), NSLocalizedString(@"is not", @"popup menuitem for field IS NOT value"), NSLocalizedString(@"older than", @"popup menuitem for field OLDER THAN value"), NSLocalizedString(@"younger than", @"popup menuitem for field YOUNGER THAN value"), NSLocalizedString(@"older than or equal to", @"popup menuitem for field OLDER THAN OR EQUAL TO value"), NSLocalizedString(@"younger than or equal to", @"popup menuitem for field YOUNGER THAN OR EQUAL TO value"), nil];
	NSString *fieldTypeGrouping   = [NSString stringWithString:[[tableDataInstance columnWithName:[[fieldField selectedItem] title]] objectForKey:@"typegrouping"]];
	
	int i;
	
	[compareField removeAllItems];
	
	if ( [fieldTypeGrouping isEqualToString:@"date"] ) {
		[compareField addItemsWithTitles:dateTypes];
		compareType = @"date";
		/*
		 if ([fieldType isEqualToString:@"timestamp"]) {
		 [argumentField setFormatter:[[NSDateFormatter alloc]
		 initWithDateFormat:@"%Y-%m-%d %H:%M:%S" allowNaturalLanguage:YES]];
		 }
		 if ([fieldType isEqualToString:@"datetime"]) {
		 [argumentField setFormatter:[[NSDateFormatter alloc] initWithDateFormat:@"%Y-%m-%d %H:%M:%S" allowNaturalLanguage:YES]];
		 }
		 if ([fieldType isEqualToString:@"date"]) {
		 [argumentField setFormatter:[[NSDateFormatter alloc] initWithDateFormat:@"%Y-%m-%d" allowNaturalLanguage:YES]];
		 }
		 if ([fieldType isEqualToString:@"time"]) {
		 [argumentField setFormatter:[[NSDateFormatter alloc] initWithDateFormat:@"%H:%M:%S" allowNaturalLanguage:YES]];
		 }
		 if ([fieldType isEqualToString:@"year"]) {
		 [argumentField setFormatter:[[NSDateFormatter alloc] initWithDateFormat:@"%Y" allowNaturalLanguage:YES]];
		 }
		 */

	// TODO: A bug in the framework previously meant enum fields had to be treated as string fields for the purposes
	// of comparison - this can now be split out to support additional comparison fucntionality if desired.
	} else if ([fieldTypeGrouping isEqualToString:@"string"] || [fieldTypeGrouping isEqualToString:@"binary"]
			|| [fieldTypeGrouping isEqualToString:@"textdata"] || [fieldTypeGrouping isEqualToString:@"blobdata"]
			|| [fieldTypeGrouping isEqualToString:@"enum"]) {
		[compareField addItemsWithTitles:stringTypes];
		compareType = @"string";
		//		[argumentField setFormatter:nil];
	} else if ([fieldTypeGrouping isEqualToString:@"bit"] || [fieldTypeGrouping isEqualToString:@"integer"]
				|| [fieldTypeGrouping isEqualToString:@"float"]) {
		[compareField addItemsWithTitles:numberTypes];
		compareType = @"number";
		//		[argumentField setFormatter:numberFormatter];
	} else  {
		NSLog(@"ERROR: unknown type for comparision: %@, in %@", [[tableDataInstance columnWithName:[[fieldField selectedItem] title]] objectForKey:@"type"], fieldTypeGrouping);
	}
	
	// Add IS NULL and IS NOT NULL as they should always be available
	[compareField addItemWithTitle:@"IS NULL"];
	[compareField addItemWithTitle:@"IS NOT NULL"];
	
	for ( i = 0 ; i < [compareField numberOfItems] ; i++ ) {
		[[compareField itemAtIndex:i] setTag:i];
	}

	// Update the argumentField enabled state
	[self toggleFilterField:self];

	// set focus on argumentField
	[argumentField selectText:self];
}

- (IBAction)stepLimitRows:(id)sender
/*
 steps the start row up or down (+/- limitRowsValue)
 */
{
	if ( [limitRowsStepper intValue] > 0 ) {
		[limitRowsField setIntValue:[limitRowsField intValue]+[prefs integerForKey:@"limitRowsValue"]];
	} else {
		if ( ([limitRowsField intValue]-[prefs integerForKey:@"limitRowsValue"]) < 1 ) {
			[limitRowsField setIntValue:1];
		} else {
			[limitRowsField setIntValue:[limitRowsField intValue]-[prefs integerForKey:@"limitRowsValue"]];
		}
	}
	[limitRowsStepper setIntValue:0];
}

/*
 * Fetches the result as an array with a dictionary for each row in it
 */
- (NSArray *)fetchResultAsArray:(CMMCPResult *)theResult
{
	NSArray *columns;
	NSString *columnTypeGrouping;
	NSMutableArray *columnsBlobStatus, *tempResult = [NSMutableArray array];
	NSDictionary *tempRow;
	NSMutableDictionary *modifiedRow = [NSMutableDictionary dictionary];
	NSEnumerator *enumerator;
	id key;
	int i, j;
	BOOL columnIsBlobOrText;

	columns = [tableDataInstance columns];
	columnsBlobStatus = [[NSMutableArray alloc] init];
	for ( i = 0 ; i < [columns count]; i++ ) {
		columnTypeGrouping = [[columns objectAtIndex:i] objectForKey:@"typegrouping"];
		columnIsBlobOrText = ([columnTypeGrouping isEqualToString:@"textdata"] || [columnTypeGrouping isEqualToString:@"blobdata"]);
		[columnsBlobStatus addObject:[NSNumber numberWithBool:columnIsBlobOrText]];
	}

	if ([theResult numOfRows]) [theResult dataSeek:0];
	for ( i = 0 ; i < [theResult numOfRows] ; i++ ) {
		tempRow = [theResult fetchRowAsDictionary];
		enumerator = [tempRow keyEnumerator];

		while ( key = [enumerator nextObject] ) {
			if ( [[tempRow objectForKey:key] isMemberOfClass:[NSNull class]] ) {
				[modifiedRow setObject:[prefs stringForKey:@"nullValue"] forKey:key];
			} else {
				[modifiedRow setObject:[tempRow objectForKey:key] forKey:key];
			}
		}

		// Add values for hidden blob and text fields if appropriate
		if ( [prefs boolForKey:@"dontShowBlob"] ) {
			for ( j = 0 ; j < [columns count] ; j++ ) {
				if ( [[columnsBlobStatus objectAtIndex:j] boolValue] ) {
					[modifiedRow setObject:NSLocalizedString(@"- blob or text -", @"value shown for hidden blob and text fields") forKey:[[columns objectAtIndex:j] objectForKey:@"name"]];
				}
			}
		}

		[tempResult addObject:[NSMutableDictionary dictionaryWithDictionary:modifiedRow]];
	}

	[columnsBlobStatus release];

	return tempResult;
}


/*
 * Tries to write a new row to the database.
 * Returns YES if row is written to database, otherwise NO; also returns YES if no row
 * is being edited and nothing has to be written to the database.
 */
- (BOOL)addRowToDB
{
	int rowIndex = [tableContentView selectedRow];
	NSArray *theColumns, *columnNames;
	NSMutableArray *fieldValues = [[NSMutableArray alloc] init];
	NSMutableString *queryString;
	NSString *query;
	CMMCPResult *queryResult;
	id rowObject;
	NSMutableString *rowValue = [NSMutableString string];
	NSString *currentTime = [[NSDate date] descriptionWithCalendarFormat:@"%H:%M:%S" timeZone:nil locale:nil];
	int i;
	
	if ( !isEditingRow || rowIndex == -1) {
		[fieldValues release];
		return YES;
	}

	// Retrieve the field names and types for this table from the data cache.  This is used when requesting all data as part
	// of the fieldListForQuery method, and also to decide whether or not to preserve the current filter/sort settings.
	theColumns = [tableDataInstance columns];
	columnNames = [tableDataInstance columnNames];
	
	// Get the field values
	for ( i = 0 ; i < [columnNames count] ; i++ ) {
		rowObject = [[filteredResult objectAtIndex:rowIndex] objectForKey:[columnNames objectAtIndex:i]];

		// Convert the object to a string (here we can add special treatment for date-, number- and data-fields)
		if ( [[rowObject description] isEqualToString:[prefs stringForKey:@"nullValue"]]
				|| ([rowObject isMemberOfClass:[NSString class]] && [[rowObject description] isEqualToString:@""]) ) {

			//NULL when user entered the nullValue string defined in the prefs or when a number field isn't set
			//	problem: when a number isn't set, sequel-pro enters 0
			//	-> second if argument isn't necessary!
			[rowValue setString:@"NULL"];
		} else {

			// I don't believe any of these class matches are ever met at present.
			if ( [rowObject isKindOfClass:[NSCalendarDate class]] ) {
				[rowValue setString:[NSString stringWithFormat:@"'%@'", [mySQLConnection prepareString:[rowObject description]]]];
			} else if ( [rowObject isKindOfClass:[NSNumber class]] ) {
				[rowValue setString:[rowObject stringValue]];
			} else if ( [rowObject isKindOfClass:[NSData class]] ) {
				[rowValue setString:[NSString stringWithFormat:@"X'%@'", [mySQLConnection prepareBinaryData:rowObject]]];
			} else {
				if ( [[rowObject description] isEqualToString:@"CURRENT_TIMESTAMP"] ) {
					[rowValue setString:@"CURRENT_TIMESTAMP"];
				} else {
					[rowValue setString:[NSString stringWithFormat:@"'%@'", [mySQLConnection prepareString:[rowObject description]]]];
				}
			}
		}
		[fieldValues addObject:[NSString stringWithString:rowValue]];
	}
	
	// Use INSERT syntax when creating new rows
	if ( isEditingNewRow ) {
		queryString = [NSString stringWithFormat:@"INSERT INTO `%@` (`%@`) VALUES (%@)",
					   selectedTable, [columnNames componentsJoinedByString:@"`,`"], [fieldValues componentsJoinedByString:@","]];

	// Use UPDATE syntax otherwise
	} else {
		queryString = [NSMutableString stringWithFormat:@"UPDATE `%@` SET ", selectedTable];
		for ( i = 0 ; i < [columnNames count] ; i++ ) {
			if ( i > 0 ) {
				[queryString appendString:@", "];
			}
			[queryString appendString:[NSString stringWithFormat:@"`%@`=%@",
									   [columnNames objectAtIndex:i], [fieldValues objectAtIndex:i]]];
		}
		[queryString appendString:[NSString stringWithFormat:@" WHERE %@", [self argumentForRow:-2]]];
	}
	[mySQLConnection queryString:queryString];
	[fieldValues release];
	
	// If no rows have been changed, show error if appropriate.	
	if ( ![mySQLConnection affectedRows] ) {
		if ( [prefs boolForKey:@"showError"] ) {
			NSBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
							  NSLocalizedString(@"The row was not written to the MySQL database. You probably haven't changed anything.\nReload the table to be sure that the row exists and use a primary key for your table.\n(This error can be turned off in the preferences.)", @"message of panel when no rows have been affected after writing to the db"));
		} else {
			NSBeep();
		}
		[filteredResult replaceObjectAtIndex:rowIndex withObject:[NSMutableDictionary dictionaryWithDictionary:oldRow]];
		isEditingRow = NO;
		isEditingNewRow = NO;
		[tableDocumentInstance showErrorInConsole:[NSString stringWithFormat:NSLocalizedString(@"/* WARNING %@ No rows have been affected */\n", @"warning shown in the console when no rows have been affected after writing to the db"), currentTime]];
		return YES;

	// On success...
	} else if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
		isEditingRow = NO;

		// New row created successfully
		if ( isEditingNewRow ) {
			if ( [prefs boolForKey:@"reloadAfterAdding"] ) {
				[self reloadTableValues:self];
				[tableContentView deselectAll:self];
			} else {

				// Set the insertId for fields with auto_increment
				for ( i = 0; i < [theColumns count] ; i++ ) {
					if ([[theColumns objectAtIndex:i] objectForKey:@"autoincrement"]) {
						[[filteredResult objectAtIndex:rowIndex] setObject:[NSNumber numberWithLong:[mySQLConnection insertId]]
																	forKey:[columnNames objectAtIndex:i]];
					}
				}
				[fullResult addObject:[filteredResult objectAtIndex:rowIndex]];
			}
			isEditingNewRow = NO;

		// Existing row edited successfully
		} else {
			if ( [prefs boolForKey:@"reloadAfterEditing"] ) {
				[self reloadTableValues:self];
				[tableContentView deselectAll:self];

			// TODO: this probably needs looking at... it's reloading it all itself?
			} else {
				query = [NSString stringWithFormat:@"SELECT %@ FROM `%@`", [self fieldListForQuery], selectedTable];
				if ( sortField ) {
					query = [NSString stringWithFormat:@"%@ ORDER BY `%@`", query, sortField];
					if ( isDesc )
						query = [query stringByAppendingString:@" DESC"];
				}
				if ( [prefs boolForKey:@"limitRows"] ) {
					if ( [limitRowsField intValue] <= 0 ) {
						[limitRowsField setStringValue:@"1"];
					}
					query = [query stringByAppendingString:
							 [NSString stringWithFormat:@" LIMIT %d,%d",
							  [limitRowsField intValue]-1, [prefs integerForKey:@"limitRowsValue"]]];
				}
				queryResult = [mySQLConnection queryString:query];
				[fullResult setArray:[self fetchResultAsArray:queryResult]];
			}
		}
		return YES;

	// Report errors which have occurred
	} else {
		NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:), nil, @"addrow",
						  [NSString stringWithFormat:NSLocalizedString(@"Couldn't write row.\nMySQL said: %@", @"message of panel when error while adding row to db"), [mySQLConnection getLastErrorMessage]]);
		return NO;
	}
}

/*
 * Returns the WHERE argument to identify a row.
 * If "row" is -2, it uses the oldRow.
 * Uses the primary key if available, otherwise uses all fields as argument and sets LIMIT to 1
 */
- (NSString *)argumentForRow:(int)row
{
	CMMCPResult *theResult;
	NSDictionary *theRow;
	id tempValue;
	NSMutableString *value = [NSMutableString string];
	NSMutableString *argument = [NSMutableString string];
	NSString *columnType;
	NSArray *columnNames;
	int i,j;
	
	if ( row == -1 )
		return @"";
	
	// Retrieve the field names for this table from the data cache.  This is used when requesting all data as part
	// of the fieldListForQuery method, and also to decide whether or not to preserve the current filter/sort settings.
	columnNames = [tableDataInstance columnNames];

	// Get the primary key if there is one
	if ( !keys ) {
		setLimit = NO;
		keys = [[NSMutableArray alloc] init];
		theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM `%@`", selectedTable]];
		if ([theResult numOfRows]) [theResult dataSeek:0];
		for ( i = 0 ; i < [theResult numOfRows] ; i++ ) {
			theRow = [theResult fetchRowAsDictionary];
			if ( [[theRow objectForKey:@"Key"] isEqualToString:@"PRI"] ) {
				[keys addObject:[theRow objectForKey:@"Field"]];
			}
		}
	}
	
	// If there is no primary key, all the fields are used in the argument.
	if ( ![keys count] ) {
		[keys setArray:columnNames];
		setLimit = YES;

		// When the option to not show blob or text options is set, we have a problem - we don't have
		// the right values to use in the WHERE statement.  Throw an error if this is the case.
		if ( [prefs boolForKey:@"dontShowBlob"] && [self tableContainsBlobOrTextColumns] ) {
			NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
							  NSLocalizedString(@"You can't hide blob and text fields when working with tables without index.", @"message of panel when trying to edit tables without index and with hidden blob/text fields"));
			[keys removeAllObjects];
			[tableContentView deselectAll:self];
			return @"";
		}
	}

	// Walk through the keys list constructing the argument list
	for ( i = 0 ; i < [keys count] ; i++ ) {
		if ( i )
			[argument appendString:@" AND "];

		// Use the selected row if appropriate
		if ( row >= 0 ) {
			tempValue = [[filteredResult objectAtIndex:row] objectForKey:[keys objectAtIndex:i]];

		// Otherwise use the oldRow
		} else {
			tempValue = [oldRow objectForKey:[keys objectAtIndex:i]];
		}

		if ( [tempValue isKindOfClass:[NSData class]] ) {
			NSString *tmpString = [[NSString alloc] initWithData:tempValue encoding:[mySQLConnection encoding]];
			[value setString:[NSString stringWithString:tmpString]];
			[tmpString release];
		} else {
			[value setString:[tempValue description]];
		}

		if ( [value isEqualToString:[prefs stringForKey:@"nullValue"]] ) {
			[argument appendString:[NSString stringWithFormat:@"`%@` IS NULL", [keys objectAtIndex:i]]];
		} else {

			// Escape special characters (in WHERE statement!)
			for ( j = 0 ; j < [value length] ; j++ ) {
				if ( [value characterAtIndex:j] == '\\' ) {
					[value insertString:@"\\" atIndex:j];
					j++;
				}
			}
			[value setString:[mySQLConnection prepareString:value]];
			for ( j = 0 ; j < [value length] ; j++ ) {
				if ( [value characterAtIndex:j] == '%' ||
					[value characterAtIndex:j] == '_' ) {
					[value insertString:@"\\" atIndex:j];
					j++;
				}
			}
			[value setString:[NSString stringWithFormat:@"'%@'", value]];

			columnType = [[tableDataInstance columnWithName:[keys objectAtIndex:i]] objectForKey:@"typegrouping"];
			if ( [columnType isEqualToString:@"integer"] || [columnType isEqualToString:@"float"] ) {
				[argument appendString:[NSString stringWithFormat:@"`%@` = %@", [keys objectAtIndex:i], value]];
			} else {
				[argument appendString:[NSString stringWithFormat:@"`%@` LIKE %@", [keys objectAtIndex:i], value]];
			}
		}
	}
	if ( setLimit )
		[argument appendString:@" LIMIT 1"];
	return argument;
}


/*
 * Returns YES if the table contains any columns which are of any of the blob or text types,
 * NO otherwise.
 */
- (BOOL)tableContainsBlobOrTextColumns
{
	int i;
	NSArray *tableColumns = [tableDataInstance tableColumns];
	NSString *columnTypeGrouping;

	for ( i = 0 ; i < [tableColumns count]; i++ ) {
		columnTypeGrouping = [[tableColumns objectAtIndex:i] objectForKey:@"typegrouping"];
		if ([columnTypeGrouping isEqualToString:@"textdata"] || [columnTypeGrouping isEqualToString:@"blobdata"]) {
			return YES;
		}
	}

	return NO;
}

/*
 * Returns a string controlling which fields to retrieve for a query.  Returns * (all fields) if the preferences
 * option dontShowBlob isn't set; otherwise, returns a comma-separated list of all non-blob/text fields.
 */
- (NSString *)fieldListForQuery
{
	int i;
	NSMutableArray *fields = [NSMutableArray array];
	NSArray *columns = [tableDataInstance columns];
	NSArray *columnNames = [tableDataInstance columnNames];
	NSString *columnTypeGrouping;
	
	if ( [prefs boolForKey:@"dontShowBlob"] ) {
		for ( i = 0 ; i < [columnNames count] ; i++ ) {
			columnTypeGrouping = [[columns objectAtIndex:i] objectForKey:@"typegrouping"];
			if (![columnTypeGrouping isEqualToString:@"textdata"] && ![columnTypeGrouping isEqualToString:@"blobdata"]) {
				[fields addObject:[columnNames objectAtIndex:i]];
			}
		}

		// Always select at least one field - the first if there are no non-blob fields.
		if ( [fields count] == 0 ) {
			return [NSString stringWithFormat:@"`%@`", [columnNames objectAtIndex:0]];
		} else {
			return [NSString stringWithFormat:@"`%@`", [fields componentsJoinedByString:@"`,`"]];
		}
	} else {
		return @"*";
	}
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(NSString *)contextInfo
/*
 if contextInfo == addrow: remain in edit-mode if user hits OK, otherwise cancel editing
 if contextInfo == removerow: removes row if user hits OK
 */
{
	NSEnumerator *enumerator = [tableContentView selectedRowEnumerator];
	NSNumber *index;
	NSMutableArray *tempArray = [NSMutableArray array];
	NSMutableArray *tempResult = [NSMutableArray array];
	NSString *queryString;
	CMMCPResult *queryResult;
	int i, errors;
	
	[sheet orderOut:self];
	
	if ( [contextInfo isEqualToString:@"addrow"] ) {
		if ( returnCode == NSAlertDefaultReturn ) {
			//problem: reenter edit mode doesn't function
			[tableContentView editColumn:0 row:[tableContentView selectedRow] withEvent:nil select:YES];
		} else {
			if ( !isEditingNewRow ) {
				[filteredResult replaceObjectAtIndex:[tableContentView selectedRow]
										  withObject:[NSMutableDictionary dictionaryWithDictionary:oldRow]];
				isEditingRow = NO;
			} else {
				[filteredResult removeObjectAtIndex:[tableContentView selectedRow]];
				isEditingRow = NO;
				isEditingNewRow = NO;
			}
		}
		[tableContentView reloadData];
	} else if ( [contextInfo isEqualToString:@"removeallrows"] ) {
		if ( returnCode == NSAlertDefaultReturn ) {
			/*
			 if ( ([tableContentView numberOfSelectedRows] == [self numberOfRowsInTableView:tableContentView]) &&
			 areShowingAllRows &&
			 ([tableContentView numberOfSelectedRows] < [prefs integerForKey:@"limitRowsValue"]) ) {
			 */
			[mySQLConnection queryString:[NSString stringWithFormat:@"DELETE FROM `%@`", selectedTable]];
			if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
				[self reloadTable:self];
			} else {
				NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
								  [NSString stringWithFormat:NSLocalizedString(@"Couldn't remove rows.\nMySQL said: %@", @"message of panel when field cannot be removed"),
								   [mySQLConnection getLastErrorMessage]]);
			}
		}
	} else if ( [contextInfo isEqualToString:@"removerow"] ) {
		if ( returnCode == NSAlertDefaultReturn ) {
			errors = 0;
			
			while ( (index = [enumerator nextObject]) ) {
				[mySQLConnection queryString:[NSString stringWithFormat:@"DELETE FROM `%@` WHERE %@",
											  selectedTable, [self argumentForRow:[index intValue]]]];
				if ( ![mySQLConnection affectedRows] ) {
					//no rows deleted
					errors++;
				} else if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
					//rows deleted with success
					[tempArray addObject:index];
				} else {
					//error in mysql-query
					errors++;
				}
			}
			
			if ( errors ) {
				NSBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, [NSString stringWithFormat:NSLocalizedString(@"%d rows have not been removed. Reload the table to be sure that the rows exist and use a primary key for your table.", @"message of panel when not all selected fields have been deleted"), errors]);
			}
			
			//do deleting (after enumerating)
			if ( [prefs boolForKey:@"reloadAfterRemoving"] ) {
				[self reloadTableValues:self];
			} else {
				for ( i = 0 ; i < [filteredResult count] ; i++ ) {
					if ( ![tempArray containsObject:[NSNumber numberWithInt:i]] )
						[tempResult addObject:[filteredResult objectAtIndex:i]];
				}
				[filteredResult setArray:tempResult];
				numRows = [self getNumberOfRows];
				if ( !areShowingAllRows ) {
					//					queryString = [@"SELECT * FROM " stringByAppendingString:selectedTable];
					queryString = [NSString stringWithFormat:@"SELECT %@ FROM `%@`", [self fieldListForQuery], selectedTable];
					if ( sortField ) {
						//						queryString = [queryString stringByAppendingString:[NSString stringWithFormat:@" ORDER BY `%@`", sortField]];
						queryString = [NSString stringWithFormat:@"%@ ORDER BY `%@`", queryString, sortField];
						if ( isDesc )
							queryString = [queryString stringByAppendingString:@" DESC"];
					}
					if ( [prefs boolForKey:@"limitRows"] ) {
						if ( [limitRowsField intValue] <= 0 ) {
							[limitRowsField setStringValue:@"1"];
						}
						queryString = [queryString stringByAppendingString:
									   [NSString stringWithFormat:@" LIMIT %d,%d",
										[limitRowsField intValue]-1, [prefs integerForKey:@"limitRowsValue"]]];
					}
					queryResult = [mySQLConnection queryString:queryString];
					//						[fullResult setArray:[[self fetchResultAsArray:queryResult] retain]];
					[fullResult setArray:[self fetchResultAsArray:queryResult]];
					[tableContentView reloadData];
					[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows of %d selected", @"text showing how many rows are in the filtered result"),
											   [filteredResult count], numRows]];
				} else {
					[fullResult setArray:filteredResult];
					[tableContentView reloadData];
					[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows in table", @"text showing how many rows are in the result"), numRows]];
				}
			}
			[tableContentView deselectAll:self];
		}
	}
}

- (int)getNumberOfRows
/*
 returns the number of rows in the selected table
 queries the number from mysql if enabled in prefs and result is limited, otherwise just return the fullResult count
 */
{
	if ( [prefs boolForKey:@"limitRows"] && [prefs boolForKey:@"fetchRowCount"] ) {
		numRows = [self fetchNumberOfRows];
	} else {
		numRows = [fullResult count];
	}
	return numRows;
}

- (int)fetchNumberOfRows
/*
 fetches the number of rows in the selected table using a "SELECT COUNT(*)" query and return it
 */
{
	return [[[[mySQLConnection queryString:[NSString stringWithFormat:@"SELECT COUNT(*) FROM `%@`", selectedTable]] fetchRowAsArray] objectAtIndex:0] intValue];
}


//tableView datasource methods
- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [filteredResult count];
}

- (id)tableView:(CMCopyTable *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
			row:(int)rowIndex
{
	id theRow, theValue;

	theRow = [filteredResult objectAtIndex:rowIndex];
	theValue = [theRow objectForKey:[aTableColumn identifier]];

	// Convert data objects to their string representation in the current encoding.
	if ( [theValue isKindOfClass:[NSData class]] ) {
		NSString *dataRepresentation = [[NSString alloc] initWithData:theValue encoding:[mySQLConnection encoding]];
		theValue = [NSString stringWithString:dataRepresentation];
		[dataRepresentation release];
	}
	
	return theValue;
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
			  row:(int)rowIndex
{
	if ( !isEditingRow ) {
		[oldRow setDictionary:[filteredResult objectAtIndex:rowIndex]];
		isEditingRow = YES;
	}
	if ( anObject ) {
		[[filteredResult objectAtIndex:rowIndex] setObject:anObject forKey:[aTableColumn identifier]];
	} else {
		[[filteredResult objectAtIndex:rowIndex] setObject:@"" forKey:[aTableColumn identifier]];
	}
}

#pragma mark -
#pragma mark tableView delegate methods

- (void)tableView:(NSTableView*)tableView didClickTableColumn:(NSTableColumn *)tableColumn
/*
 sorts the tableView by the clicked column
 if clicked twice, order is descending
 */
{
	NSString *queryString;
	CMMCPResult *queryResult;
	
	if ( [selectedTable isEqualToString:@""] || !selectedTable )
		return;
	if ( ![self selectionShouldChangeInTableView:nil] )
		return;
	
	//query started
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:self];
		
	//sets order descending if a header is clicked twice
	if ( [[tableColumn identifier] isEqualTo:sortField] ) {
		if ( isDesc ) {
			isDesc = NO;
		} else {
			isDesc = YES;
		}
	} else {
		isDesc = NO;
		[tableContentView setIndicatorImage:nil inTableColumn:[tableContentView tableColumnWithIdentifier:sortField]];
	}
	sortField = [tableColumn identifier];
	
	//make queryString and perform query
	queryString = [NSString stringWithFormat:@"SELECT %@ FROM `%@` ORDER BY `%@`", [self fieldListForQuery],
				   selectedTable, sortField];
	if ( isDesc )
		queryString = [queryString stringByAppendingString:@" DESC"];
	if ( [prefs boolForKey:@"limitRows"] ) {
		if ( [limitRowsField intValue] <= 0 ) {
			[limitRowsField setStringValue:@"1"];
		}
		queryString = [queryString stringByAppendingString:
					   [NSString stringWithFormat:@" LIMIT %d,%d",
						[limitRowsField intValue]-1, [prefs integerForKey:@"limitRowsValue"]]];
	}
	queryResult = [mySQLConnection queryString:queryString];
	
	//	[fullResult setArray:[[self fetchResultAsArray:queryResult] retain]];
	[fullResult setArray:[self fetchResultAsArray:queryResult]];
	
	if ( ![[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
		NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
						  [NSString stringWithFormat:NSLocalizedString(@"Couldn't sort table. MySQL said: %@", @"message of panel when sorting of table failed"), [mySQLConnection getLastErrorMessage]]);
		return;
	}
	
	//sets highlight and indicatorImage
	[tableContentView setHighlightedTableColumn:tableColumn];
	if ( isDesc ) {
		[tableContentView setIndicatorImage:[NSImage imageNamed:@"NSDescendingSortIndicator"] inTableColumn:tableColumn];
	} else {
		[tableContentView setIndicatorImage:[NSImage imageNamed:@"NSAscendingSortIndicator"] inTableColumn:tableColumn];
	}
	
	//query finished
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:self];
	
	//if filter is activated filters the result, otherwise shows fullResult
	if ( !areShowingAllRows ) {
		[self filterTable:self];
	} else {
		[filteredResult setArray:fullResult];
		[tableContentView reloadData];
	}
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	/*
	 int row = [tableContentView editedRow];
	 int column = [tableContentView editedColumn];
	 NSTableColumn *tableColumn;
	 NSCell *cell;
	 
	 if ( row != -1 ) {
	 tableColumn = [[tableContentView tableColumns] objectAtIndex:column]; 
	 cell = [tableColumn dataCellForRow:row]; 
	 [cell endEditing:[tableContentView currentEditor]]; 
	 }
	 */
	//end editing (otherwise problems when user hits reload button)
	[tableWindow endEditingFor:nil];
	
	return [self addRowToDB];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	// Check our notification object is our table content view
	if ([aNotification object] != tableContentView)
		return;
	
	if ( [tableContentView numberOfSelectedRows] > 0 ) {
		[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d of %d rows selected", @"Text showing how many rows are selected"), [tableContentView numberOfSelectedRows], [tableContentView numberOfRows]]];
	} else {
		[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows", @"Text showing how many rows are in the result"), [tableContentView numberOfRows]]];
	}
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification
{
	// Check our notification object is our table content view
	if ([aNotification object] != tableContentView)
		return;
	
	if ( [tableContentView numberOfSelectedRows] > 0 ) {
		[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d of %d rows selected", @"Text showing how many rows are selected"), [tableContentView numberOfSelectedRows], [tableContentView numberOfRows]]];
	} else {
		[countText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"%d rows", @"Text showing how many rows are in the result"), [tableContentView numberOfRows]]];
	}
}


- (void)tableViewColumnDidResize:(NSNotification *)aNotification
/*
 saves the new column size in the preferences
 */
{
	// sometimes the column has no identifier. I can't figure out what is causing it, so we just skip over this item
	if (![[[aNotification userInfo] objectForKey:@"NSTableColumn"] identifier])
		return;
	
	NSMutableDictionary *tableColumnWidths;
	NSString *database = [NSString stringWithFormat:@"%@@%@", [tableDocumentInstance database], [tableDocumentInstance host]];
	NSString *table = [tablesListInstance tableName];
	
	// get tableColumnWidths object
	if ( [prefs objectForKey:@"tableColumnWidths"] != nil ) {
		tableColumnWidths = [NSMutableDictionary dictionaryWithDictionary:[prefs objectForKey:@"tableColumnWidths"]];
	} else {
		tableColumnWidths = [NSMutableDictionary dictionary];
	}
	// get database object
	if  ( [tableColumnWidths objectForKey:database] == nil ) {
		[tableColumnWidths setObject:[NSMutableDictionary dictionary] forKey:database];
	} else {
		[tableColumnWidths setObject:[[tableColumnWidths objectForKey:database] mutableCopy] forKey:database];
	}
	// get table object
	if  ( [[tableColumnWidths objectForKey:database] objectForKey:table] == nil ) {
		[[tableColumnWidths objectForKey:database] setObject:[NSMutableDictionary dictionary] forKey:table];
	} else {
		[[tableColumnWidths objectForKey:database] setObject:[[[tableColumnWidths objectForKey:database] objectForKey:table] mutableCopy] forKey:table];
	}
	// save column size
	[[[tableColumnWidths objectForKey:database] objectForKey:table] setObject:[NSNumber numberWithFloat:[[[aNotification userInfo] objectForKey:@"NSTableColumn"] width]] forKey:[[[aNotification userInfo] objectForKey:@"NSTableColumn"] identifier]];
	[prefs setObject:tableColumnWidths forKey:@"tableColumnWidths"];
}

/*
 * Confirm whether to allow editing of a row.  Returns YES by default, unless the multipleLineEditingButton is in
 * the ON state, or for blob or text fields - in those cases opens a sheet for editing instead and returns NO.
 */
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	int code;
	NSString *columnTypeGrouping, *query;
	NSEnumerator *enumerator;
	NSDictionary *tempRow;
	NSMutableDictionary *modifiedRow = [NSMutableDictionary dictionary];
	id key, theValue;
	CMMCPResult *tempResult;
	BOOL columnIsBlobOrText = NO;
	
	// If not isEditingRow and the preference value for not showing blobs is set, check whether the row contains any blobs.
	if ( [prefs boolForKey:@"dontShowBlob"] && !isEditingRow ) {

		// If the table does contain blob or text fields, load the values ready for editing.
		if ( [self tableContainsBlobOrTextColumns] ) {
			query = [NSString stringWithFormat:@"SELECT * FROM `%@` WHERE %@",
					 selectedTable, [self argumentForRow:[tableContentView selectedRow]]];
			tempResult = [mySQLConnection queryString:query];
			if ( ![tempResult numOfRows] ) {
				NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
								  NSLocalizedString(@"Couldn't load the row. Reload the table to be sure that the row exists and use a primary key for your table.", @"message of panel when loading of row failed"));
				return NO;
			}
			tempRow = [tempResult fetchRowAsDictionary];
			enumerator = [tempRow keyEnumerator];
			while ( key = [enumerator nextObject] ) {
				if ( [[tempRow objectForKey:key] isMemberOfClass:[NSNull class]] ) {
					[modifiedRow setObject:[prefs stringForKey:@"nullValue"] forKey:key];
				} else {
					[modifiedRow setObject:[tempRow objectForKey:key] forKey:key];
				}
			}
			[filteredResult replaceObjectAtIndex:rowIndex withObject:[NSMutableDictionary dictionaryWithDictionary:modifiedRow]];
			[tableContentView reloadData];
		}
	}
	
	// If the selected column is a blob/text type, force sheet editing.
	columnTypeGrouping = [[tableDataInstance columnWithName:[aTableColumn identifier]] objectForKey:@"typegrouping"];
	if ([columnTypeGrouping isEqualToString:@"textdata"] || [columnTypeGrouping isEqualToString:@"blobdata"]) {
		columnIsBlobOrText = YES;
	}

	// Open the sheet if the multipleLineEditingButton is enabled or the column was a blob or a text.
	if ( [multipleLineEditingButton state] == NSOnState || columnIsBlobOrText ) {
		theValue = [[filteredResult objectAtIndex:rowIndex] objectForKey:[aTableColumn identifier]];
		NSImage *image = nil;
		editData = [theValue retain];
		
		if ( [theValue isKindOfClass:[NSData class]] ) {
			image = [[NSImage alloc] initWithData:theValue];
			[hexTextView setString:[self dataToHex:theValue]];
			theValue = [[NSString alloc] initWithData:theValue encoding:[mySQLConnection encoding]];
		} else {
			[hexTextView setString:@""];
			theValue = [theValue description];
		}

		[editImage setImage:image];
		[editTextView setString:theValue];
		[editTextView setSelectedRange:NSMakeRange(0,[[editTextView string] length])];

		[NSApp beginSheet:editSheet modalForWindow:tableWindow modalDelegate:self didEndSelector:nil contextInfo:nil];
		code = [NSApp runModalForWindow:editSheet];

		[NSApp endSheet:editSheet];
		[editSheet orderOut:nil];

		if ( code ) {
			if ( !isEditingRow ) {
				[oldRow setDictionary:[filteredResult objectAtIndex:rowIndex]];
				isEditingRow = YES;
			}
			
			[[filteredResult objectAtIndex:rowIndex] setObject:[editData copy] forKey:[aTableColumn identifier]];
			
			// Clean up
			[editImage setImage:nil];
			[editTextView setString:@""];
			[hexTextView setString:@""];
			if ( editData ) {
				[editData release];
			}
		}
		return NO;
	} else {
		return YES;
	}
}

- (BOOL)tableView:(NSTableView *)tableView writeRows:(NSArray*)rows 
	 toPasteboard:(NSPasteboard*)pboard
/*
 enable drag from tableview
 */
{	
	if ( tableView == tableContentView )
	{
		NSString *tmp = [tableContentView draggedRowsAsTabString:rows];
		
		if ( nil != tmp )
		{
			[pboard declareTypes:[NSArray arrayWithObjects: NSTabularTextPboardType, 
								  NSStringPboardType, nil]
						   owner:nil];
			
			[pboard setString:tmp forType:NSStringPboardType];
			[pboard setString:tmp forType:NSTabularTextPboardType];
			return YES;
		}
	}
	return NO;
}

#pragma mark -

/*
 * Trap the enter and escape keys, overriding default behaviour and continuing/ending editing,
 * only within the current row.
 */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	NSString *fieldType;
	int row, column, i;
	
	row = [tableContentView editedRow];
	column = [tableContentView editedColumn];

	// Trap enter and tab keys
	if (  [textView methodForSelector:command] == [textView methodForSelector:@selector(insertNewline:)] ||
		[textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)] )
	{
		[[control window] makeFirstResponder:control];

		// Save the current line if it's the last field in the table
		if ( column == ( [tableContentView numberOfColumns] - 1 ) ) {
			[self addRowToDB];
		} else {

			// Check if next column is a blob column, and skip to the next non-blob column
			i = 1;
			while (
				(fieldType = [[tableDataInstance columnWithName:[[[tableContentView tableColumns] objectAtIndex:column+i] identifier]] objectForKey:@"typegrouping"])
				&& ([fieldType isEqualToString:@"textdata"] || [fieldType isEqualToString:@"blobdata"])
			) {
				i++;

				// If there are no columns after the latest blob or text column, save the current line.
				if ( (column+i) >= [tableContentView numberOfColumns] ) {
					[self addRowToDB];
					return TRUE;
				}
			}

			// Edit the column after the blob column
			[tableContentView editColumn:column+i row:row withEvent:nil select:YES];
		}
		return TRUE;
	}
	
	// Trap the escape key
	else if (  [[control window] methodForSelector:command] == [[control window] methodForSelector:@selector(_cancelKey:)] ||
			 [textView methodForSelector:command] == [textView methodForSelector:@selector(complete:)] )
	{

		// Abort editing
		[control abortEditing];
		if ( isEditingRow && !isEditingNewRow ) {
			isEditingRow = NO;
			[filteredResult replaceObjectAtIndex:row withObject:[NSMutableDictionary dictionaryWithDictionary:oldRow]];
		} else if ( isEditingNewRow ) {
			isEditingRow = NO;
			isEditingNewRow = NO;
			[filteredResult removeObjectAtIndex:row];
			[tableContentView reloadData];
		}
		return TRUE;
	}
	else
	{
		return FALSE;
	}
}


//textView delegate methods
- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
/*
 traps enter and return key and closes editSheet instead of inserting a linebreak when user hits return
 */
{
	if ( aTextView == editTextView ) {
		if ( [aTextView methodForSelector:aSelector] == [aTextView methodForSelector:@selector(insertNewline:)] &&
			[[[NSApp currentEvent] characters] isEqualToString:@"\003"] )
		{
			[NSApp stopModalWithCode:1];
			return YES;
		} else {
			return NO;
		}
	}
	return NO;
}


//last but not least

- (void)dealloc
{
	//	NSLog(@"TableContent dealloc");
	
	[editData release];
	[fullResult release];
	[filteredResult release];
	[keys release];
	[oldRow release];
	[compareType release];
	[sortField release];
	[prefs release];
	
	[super dealloc];
}

@end