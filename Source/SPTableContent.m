//
//  $Id$
//
//  SPDatabaseDocument.h
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

#import "SPTableContent.h"
#import "SPDatabaseDocument.h"
#import "SPTableStructure.h"
#import "SPTableInfo.h"
#import "SPTablesList.h"
#import "SPImageView.h"
#import "SPCopyTable.h"
#import "SPDataCellFormatter.h"
#import "SPTableData.h"
#import "SPQueryController.h"
#import "SPStringAdditions.h"
#import "SPArrayAdditions.h"
#import "SPTextViewAdditions.h"
#import "SPDataAdditions.h"
#import "SPTextAndLinkCell.h"
#import "QLPreviewPanel.h"
#import "SPFieldEditorController.h"
#import "SPTooltip.h"
#import "RegexKitLite.h"
#import "SPContentFilterManager.h"
#import "SPNotLoaded.h"
#import "SPConstants.h"
#import "SPDataStorage.h"
#import "SPAlertSheets.h"
#import "SPMainThreadTrampoline.h"
#import "SPHistoryController.h"

@implementation SPTableContent

/**
 * Standard init method. Initialize various ivars.
 */
- (id)init
{
	if ((self == [super init])) {
		_mainNibLoaded = NO;
		isWorking = NO;
		pthread_mutex_init(&tableValuesLock, NULL);
		nibObjectsToRelease = [[NSMutableArray alloc] init];

		tableValues      = [[SPDataStorage alloc] init];
		tableRowsCount = 0;
		previousTableRowsCount = 0;
		dataColumns       = [[NSMutableArray alloc] init];
		oldRow            = [[NSMutableArray alloc] init];

		filterTableData   = [[NSMutableDictionary alloc] initWithCapacity:1];
		filterTableNegate = NO;
		filterTableDistinct = NO;
		lastEditedFilterTableValue = nil;
		activeFilter = 0;

		selectedTable = nil;
		sortCol       = nil;
		isDesc		  = NO;
		keys		  = nil;

		currentlyEditingRow = -1;
		contentPage = 1;

		sortColumnToRestore = nil;
		sortColumnToRestoreIsAsc = YES;
		pageToRestore = 1;
		selectionIndexToRestore = nil;
		selectionViewportToRestore = NSZeroRect;
		filterFieldToRestore = nil;
		filterComparisonToRestore = nil;
		filterValueToRestore = nil;
		firstBetweenValueToRestore = nil;
		secondBetweenValueToRestore = nil;
		tableRowsSelectable = YES;
		contentFilterManager = nil;
		isFirstChangeInView = YES;

		isFiltered = NO;
		isLimited = NO;
		isInterruptedLoad = NO;

		prefs = [NSUserDefaults standardUserDefaults];

		usedQuery = [[NSString alloc] initWithString:@""];

		tableLoadTimer = nil;

		// Init default filters for Content Browser
		contentFilters = nil;
		contentFilters = [[NSMutableDictionary alloc] init];
		numberOfDefaultFilters = [[NSMutableDictionary alloc] init];

		NSError *readError = nil;
		NSString *convError = nil;
		NSPropertyListFormat format;
		NSData *defaultFilterData = [NSData dataWithContentsOfFile:[NSBundle pathForResource:@"ContentFilters.plist" ofType:nil inDirectory:[[NSBundle mainBundle] bundlePath]]
			options:NSMappedRead error:&readError];

		[contentFilters setDictionary:[NSPropertyListSerialization propertyListFromData:defaultFilterData
				mutabilityOption:NSPropertyListMutableContainersAndLeaves format:&format errorDescription:&convError]];
		if(contentFilters == nil || readError != nil || convError != nil) {
			NSLog(@"Error while reading 'ContentFilters.plist':\n%@\n%@", [readError localizedDescription], convError);
			NSBeep();
		} else {
			[numberOfDefaultFilters setObject:[NSNumber numberWithInteger:[[contentFilters objectForKey:@"number"] count]] forKey:@"number"];
			[numberOfDefaultFilters setObject:[NSNumber numberWithInteger:[[contentFilters objectForKey:@"date"] count]] forKey:@"date"];
			[numberOfDefaultFilters setObject:[NSNumber numberWithInteger:[[contentFilters objectForKey:@"string"] count]] forKey:@"string"];
		}

		kCellEditorErrorNoMatch = NSLocalizedString(@"Field is not editable. No matching record found.\nReload table, check the encoding, or try to add\na primary key field or more fields\nin the view declaration of '%@' to identify\nfield origin unambiguously.", @"Table Content result editing error - could not identify original row");
		kCellEditorErrorNoMultiTabDb = NSLocalizedString(@"Field is not editable. Field has no or multiple table or database origin(s).",@"field is not editable due to no table/database");
		kCellEditorErrorTooManyMatches = NSLocalizedString(@"Field is not editable. Couldn't identify field origin unambiguously (%ld match%@).", @"Query result editing error - could not match row being edited uniquely");

	}

	return self;
}

/**
 * Initialise various interface controls
 */
- (void)awakeFromNib
{
	if (_mainNibLoaded) return;
	_mainNibLoaded = YES;

	// Set the table content view's vertical gridlines if required
	[tableContentView setGridStyleMask:([prefs boolForKey:SPDisplayTableViewVerticalGridlines]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];

	// Load the pagination view, keeping references to the top-level objects for later release
	NSArray *paginationViewTopLevelObjects = nil;
	NSNib *nibLoader = [[NSNib alloc] initWithNibNamed:@"ContentPaginationView" bundle:[NSBundle mainBundle]];
	if (![nibLoader instantiateNibWithOwner:self topLevelObjects:&paginationViewTopLevelObjects]) {
		NSLog(@"Content pagination nib could not be loaded; pagination will not function correctly.");
	} else {
		[nibObjectsToRelease addObjectsFromArray:paginationViewTopLevelObjects];
	}
	[nibLoader release];

	// Add the pagination view to the content area
	NSRect paginationViewFrame = [paginationView frame];
	NSRect paginationButtonFrame = [paginationButton frame];
	paginationViewHeight = paginationViewFrame.size.height;
	paginationViewFrame.origin.x = paginationButtonFrame.origin.x + paginationButtonFrame.size.width - paginationViewFrame.size.width;
	paginationViewFrame.origin.y = paginationButtonFrame.origin.y + paginationButtonFrame.size.height - 2;
	paginationViewFrame.size.height = 0;
	[paginationView setFrame:paginationViewFrame];
	[contentViewPane addSubview:paginationView];

	// Init Filter Table GUI
	[filterTableDistinctCheckbox setState:(filterTableDistinct) ? NSOnState : NSOffState];
	[filterTableNegateCheckbox setState:(filterTableNegate) ? NSOnState : NSOffState];
	[filterTableLiveSearchCheckbox setState:NSOffState];
	filterTableDefaultOperator = @"LIKE '%%%@%%'";

	// Add observers for document task activity
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDocumentTaskForTab:)
												 name:SPDocumentTaskStartNotification
											   object:tableDocumentInstance];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(endDocumentTaskForTab:)
												 name:SPDocumentTaskEndNotification
											   object:tableDocumentInstance];
}

#pragma mark -
#pragma mark Table loading methods and information

/**
 * Loads aTable, retrieving column information and updating the tableViewColumns before
 * reloading table data into the data array and redrawing the table.
 *
 * @param aTable The to be loaded table name
 *
 */
- (void)loadTable:(NSString *)aTable
{

	// Abort the reload if the user is still editing a row
	if ( isEditingRow )
		return;

	// If no table has been supplied, clear the table interface and return
	if (!aTable || [aTable isEqualToString:@""]) {
		[self performSelectorOnMainThread:@selector(setTableDetails:) withObject:nil waitUntilDone:YES];
		return;
	}

	// Attempt to retrieve the table encoding; if that fails (indicating an error occurred
	// while retrieving table data), or if the Rows variable is null, clear and return
	if (![tableDataInstance tableEncoding] || [[[tableDataInstance statusValues] objectForKey:@"Rows"] isNSNull]) {
		[self performSelectorOnMainThread:@selector(setTableDetails:) withObject:nil waitUntilDone:YES];
		return;
	}

	// Post a notification that a query will be performed
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryWillBePerformed" object:tableDocumentInstance];

	// Set up the table details for the new table, and trigger an interface update
	NSDictionary *tableDetails = [NSDictionary dictionaryWithObjectsAndKeys:
									aTable, @"name",
									[tableDataInstance columns], @"columns",
									[tableDataInstance columnNames], @"columnNames",
									[tableDataInstance getConstraints], @"constraints",
									nil];
	[self performSelectorOnMainThread:@selector(setTableDetails:) withObject:tableDetails waitUntilDone:YES];

	// Init copyTable with necessary information for copying selected rows as SQL INSERT
	[tableContentView setTableInstance:self withTableData:tableValues withColumns:dataColumns withTableName:selectedTable withConnection:mySQLConnection];

	// Trigger a data refresh
	[self loadTableValues];

	// Restore the view origin if appropriate
	if (!NSEqualRects(selectionViewportToRestore, NSZeroRect)) {

		// Scroll the viewport to the saved location
		selectionViewportToRestore.size = [tableContentView visibleRect].size;
		[tableContentView scrollRectToVisible:selectionViewportToRestore];
	}

	// Restore selection indexes if appropriate
	if (selectionIndexToRestore) {
		BOOL previousTableRowsSelectable = tableRowsSelectable;
		tableRowsSelectable = YES;
		[tableContentView selectRowIndexes:selectionIndexToRestore byExtendingSelection:NO];
		tableRowsSelectable = previousTableRowsSelectable;
	}

	// Update display if necessary
	if (!NSEqualRects(selectionViewportToRestore, NSZeroRect))
		[[tableContentView onMainThread] setNeedsDisplayInRect:selectionViewportToRestore];
	else
		[[tableContentView onMainThread] setNeedsDisplay:YES];

	// Post the notification that the query is finished
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];

	// Clear any details to restore now that they have been restored
	[self clearDetailsToRestore];
}

/**
 * Update stored table details and update the interface to match the supplied
 * table details.
 * Should be called on the main thread.
 */
- (void) setTableDetails:(NSDictionary *)tableDetails
{
	NSString *newTableName;
	NSInteger i;
	NSNumber *colWidth, *sortColumnNumberToRestore = nil;
	NSArray *columnNames;
	NSDictionary *columnDefinition;
	NSTableColumn	*theCol, *filterCol;
	BOOL enableInteraction = ![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableContent] || ![tableDocumentInstance isWorking];

	if (!tableDetails) {
		newTableName = nil;
	} else {
		newTableName = [tableDetails objectForKey:@"name"];
	}

	// Ensure the pagination view hides itself if visible, after a tiny delay for smoothness
	[self performSelector:@selector(setPaginationViewVisibility:) withObject:nil afterDelay:0.1];

	// Reset table key store for use in argumentForRow:
	if (keys) [keys release], keys = nil;

	// Reset data column store
	[dataColumns removeAllObjects];

	// Check the supplied table name.  If it matches the old one, a reload is being performed;
	// reload the data in-place to maintain table state if possible.
	if ([selectedTable isEqualToString:newTableName]) {
		previousTableRowsCount = tableRowsCount;

	// Otherwise store the newly selected table name and reset the data
	} else {
		if (selectedTable) [selectedTable release], selectedTable = nil;
		if (newTableName) selectedTable = [[NSString alloc] initWithString:newTableName];
		previousTableRowsCount = 0;
		contentPage = 1;
		[paginationPageField setStringValue:@"1"];

		// Clear the selection
		[tableContentView deselectAll:self];

		// Restore the table content view to the top left
		[tableContentView scrollRowToVisible:0];
		[tableContentView scrollColumnToVisible:0];
	}

	// If no table has been supplied, reset the view to a blank table and disabled elements.
	if (!newTableName) {
		// Remove existing columns from the table
		while ([[tableContentView tableColumns] count]) {
			[tableContentView removeTableColumn:NSArrayObjectAtIndex([tableContentView tableColumns], 0)];
		}

		// Empty the stored data arrays, including emptying the tableValues array
		// by ressignment for thread safety.
		previousTableRowsCount = 0;
		[self clearTableValues];
		[tableContentView reloadData];
		isFiltered = NO;
		isLimited = NO;
		[countText setStringValue:@""];

		// Reset sort column
		if (sortCol) [sortCol release]; sortCol = nil;
		isDesc = NO;

		// Empty and disable filter options
		[fieldField setEnabled:NO];
		[fieldField removeAllItems];
		[fieldField addItemWithTitle:NSLocalizedString(@"field", @"popup menuitem for field (showing only if disabled)")];
		[compareField setEnabled:NO];
		[compareField removeAllItems];
		[compareField addItemWithTitle:NSLocalizedString(@"is", @"popup menuitem for field IS value")];
		[argumentField setHidden:NO];
		[argumentField setEnabled:NO];
		[firstBetweenField setEnabled:NO];
		[secondBetweenField setEnabled:NO];
		[firstBetweenField setStringValue:@""];
		[secondBetweenField setStringValue:@""];
		[argumentField setStringValue:@""];
		[filterButton setEnabled:NO];

		// Hide BETWEEN operator controls
		[firstBetweenField setHidden:YES];
		[secondBetweenField setHidden:YES];
		[betweenTextField setHidden:YES];

		// Disable pagination
		[paginationPreviousButton setEnabled:NO];
		[paginationButton setEnabled:NO];
		[paginationButton setTitle:@""];
		[paginationNextButton setEnabled:NO];

		// Disable table action buttons
		[addButton setEnabled:NO];
		[copyButton setEnabled:NO];
		[removeButton setEnabled:NO];

		// Clear restoration settings
		[self clearDetailsToRestore];

		return;
	}

	// Otherwise, prepare to set up the new table - the table data instance already has table details set.

	// Remove existing columns from the table
	while ([[tableContentView tableColumns] count]) {
		[tableContentView removeTableColumn:NSArrayObjectAtIndex([tableContentView tableColumns], 0)];
	}
	// Remove existing columns from the filter table
	while ([[filterTableView tableColumns] count]) {
		[filterTableView removeTableColumn:NSArrayObjectAtIndex([filterTableView tableColumns], 0)];
	}
	// Clear filter table data
	[filterTableData removeAllObjects];
	[filterTableWhereClause setString:@""];
	activeFilter = 0;

	// Retrieve the field names and types for this table from the data cache. This is used when requesting all data as part
	// of the fieldListForQuery method, and also to decide whether or not to preserve the current filter/sort settings.
	[dataColumns addObjectsFromArray:[tableDetails objectForKey:@"columns"]];
	columnNames = [tableDetails objectForKey:@"columnNames"];

	// Retrieve the constraints, and loop through them to add up to one foreign key to each column
	NSArray *constraints = [tableDetails objectForKey:@"constraints"];

	for (NSDictionary *constraint in constraints)
	{
		NSString *firstColumn    = [[constraint objectForKey:@"columns"] objectAtIndex:0];
		NSString *firstRefColumn = [[[constraint objectForKey:@"ref_columns"] componentsSeparatedByString:@","] objectAtIndex:0];
		NSUInteger columnIndex   = [columnNames indexOfObject:firstColumn];

		if (columnIndex != NSNotFound && ![[dataColumns objectAtIndex:columnIndex] objectForKey:@"foreignkeyreference"]) {
			NSDictionary *refDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
											[constraint objectForKey:@"ref_table"], @"table",
											firstRefColumn, @"column",
											nil];
			NSMutableDictionary *rowDictionary = [NSMutableDictionary dictionaryWithDictionary:[dataColumns objectAtIndex:columnIndex]];
			[rowDictionary setObject:refDictionary forKey:@"foreignkeyreference"];
			[dataColumns replaceObjectAtIndex:columnIndex withObject:rowDictionary];
		}
	}

	NSString *nullValue = [prefs objectForKey:SPNullValue];
	NSFont *tableFont = [NSUnarchiver unarchiveObjectWithData:[prefs dataForKey:SPGlobalResultTableFont]];
	[tableContentView setRowHeight:2.0f+NSSizeToCGSize([[NSString stringWithString:@"{ǞṶḹÜ∑zgyf"] sizeWithAttributes:[NSDictionary dictionaryWithObject:tableFont forKey:NSFontAttributeName]]).height];

	// Add the new columns to the table and filterTable
	for ( i = 0 ; i < [dataColumns count] ; i++ ) {
		columnDefinition = NSArrayObjectAtIndex(dataColumns, i);

		// Set up the column
		theCol = [[NSTableColumn alloc] initWithIdentifier:[columnDefinition objectForKey:@"datacolumnindex"]];
		[[theCol headerCell] setStringValue:[columnDefinition objectForKey:@"name"]];
		[theCol setEditable:YES];

		// Set up column for filterTable 
		filterCol = [[NSTableColumn alloc] initWithIdentifier:[columnDefinition objectForKey:@"datacolumnindex"]];
		[[filterCol headerCell] setStringValue:[columnDefinition objectForKey:@"name"]];
		[filterCol setEditable:YES];
		SPTextAndLinkCell *filterDataCell = [[[SPTextAndLinkCell alloc] initTextCell:@""] autorelease];
		[filterDataCell setEditable:YES];
		[filterCol setDataCell:filterDataCell];
		[filterTableView addTableColumn:filterCol];
		[filterCol release];

		[filterTableData setObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
				[columnDefinition objectForKey:@"name"], @"name",
				[columnDefinition objectForKey:@"typegrouping"], @"typegrouping",
				[NSMutableArray arrayWithObjects:@"", @"", @"", @"", @"", @"", @"", @"", @"", @"", nil], @"filter",
				nil] forKey:[columnDefinition objectForKey:@"datacolumnindex"]];

		// Set up the data cell depending on the column type
		id dataCell;
		if ([[columnDefinition objectForKey:@"typegrouping"] isEqualToString:@"enum"]) {
			dataCell = [[[NSComboBoxCell alloc] initTextCell:@""] autorelease];
			[dataCell setButtonBordered:NO];
			[dataCell setBezeled:NO];
			[dataCell setDrawsBackground:NO];
			[dataCell setCompletes:YES];
			[dataCell setControlSize:NSSmallControlSize];
			// add prefs NULL value representation if NULL value is allowed for that field
			if([[columnDefinition objectForKey:@"null"] boolValue])
				[dataCell addItemWithObjectValue:nullValue];
			[dataCell addItemsWithObjectValues:[columnDefinition objectForKey:@"values"]];

		// Add a foreign key arrow if applicable
		} else if ([columnDefinition objectForKey:@"foreignkeyreference"]) {
			dataCell = [[[SPTextAndLinkCell alloc] initTextCell:@""] autorelease];
			[dataCell setTarget:self action:@selector(clickLinkArrow:)];

		// Otherwise instantiate a text-only cell
		} else {
			dataCell = [[[SPTextAndLinkCell alloc] initTextCell:@""] autorelease];
		}
		[dataCell setEditable:YES];

		// Set the line break mode and an NSFormatter subclass which truncates long strings for display
		[dataCell setLineBreakMode:NSLineBreakByTruncatingTail];
		[dataCell setFormatter:[[SPDataCellFormatter new] autorelease]];

		// Set field length limit if field is a varchar to match varchar length
		if ([[columnDefinition objectForKey:@"typegrouping"] isEqualToString:@"string"]
			|| [[columnDefinition objectForKey:@"typegrouping"] isEqualToString:@"bit"]) {
			[[dataCell formatter] setTextLimit:[[columnDefinition objectForKey:@"length"] integerValue]];
		}

		// Set field type for validations
		[[dataCell formatter] setFieldType:[columnDefinition objectForKey:@"type"]];

		// Set the data cell font according to the preferences
		[dataCell setFont:tableFont];

		// Assign the data cell
		[theCol setDataCell:dataCell];

		// Set the width of this column to saved value if exists
		colWidth = [[[[prefs objectForKey:SPTableColumnWidths] objectForKey:[NSString stringWithFormat:@"%@@%@", [tableDocumentInstance database], [tableDocumentInstance host]]] objectForKey:[tablesListInstance tableName]] objectForKey:[columnDefinition objectForKey:@"name"]];
		if ( colWidth ) {
			[theCol setWidth:[colWidth doubleValue]];
		}

		// Set the column to be reselected for sorting if appropriate
		if (sortColumnToRestore && [sortColumnToRestore isEqualToString:[columnDefinition objectForKey:@"name"]])
			sortColumnNumberToRestore = [columnDefinition objectForKey:@"datacolumnindex"];

		// Add the column to the table
		[tableContentView addTableColumn:theCol];
		[theCol release];
	}

	[filterTableView setDelegate:self];
	[filterTableView setDataSource:self];

	// If the table has been reloaded and the previously selected sort column is still present, reselect it.
	if (sortColumnNumberToRestore) {
		theCol = [tableContentView tableColumnWithIdentifier:sortColumnNumberToRestore];
		if (sortCol) [sortCol release];
		sortCol = [sortColumnNumberToRestore copy];
		[tableContentView setHighlightedTableColumn:theCol];
		isDesc = !sortColumnToRestoreIsAsc;
		if ( isDesc ) {
			[tableContentView setIndicatorImage:[NSImage imageNamed:@"NSDescendingSortIndicator"] inTableColumn:theCol];
		} else {
			[tableContentView setIndicatorImage:[NSImage imageNamed:@"NSAscendingSortIndicator"] inTableColumn:theCol];
		}

	// Otherwise, clear sorting
	} else {
		if (sortCol) {
			[sortCol release];
			sortCol = nil;
		}
		isDesc = NO;
	}

	// Store the current first responder so filter field doesn't steal focus
	id currentFirstResponder = [[tableDocumentInstance parentWindow] firstResponder];

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
	[filterButton setEnabled:enableInteraction];

	// Restore preserved filter settings if appropriate and valid
	if (filterFieldToRestore) {
		[fieldField selectItemWithTitle:filterFieldToRestore];
		[self setCompareTypes:self];

		if ([fieldField itemWithTitle:filterFieldToRestore]
			&& ((!filterComparisonToRestore && filterValueToRestore)
				|| [compareField itemWithTitle:filterComparisonToRestore]))
		{
			if (filterComparisonToRestore) [compareField selectItemWithTitle:filterComparisonToRestore];
			if([filterComparisonToRestore isEqualToString:@"BETWEEN"]) {
				[argumentField setHidden:YES];
				if (firstBetweenValueToRestore) [firstBetweenField setStringValue:firstBetweenValueToRestore];
				if (secondBetweenValueToRestore) [secondBetweenField setStringValue:secondBetweenValueToRestore];
			} else {
				if (filterValueToRestore) [argumentField setStringValue:filterValueToRestore];
			}
			[self toggleFilterField:self];

		}
	}

	// Restore page number if limiting is set
	if ([prefs boolForKey:SPLimitResults]) contentPage = pageToRestore;

	// Restore first responder
	[[tableDocumentInstance parentWindow] makeFirstResponder:currentFirstResponder];

	// Set the state of the table buttons
	[addButton setEnabled:(enableInteraction && [tablesListInstance tableType] == SPTableTypeTable)];
	[copyButton setEnabled:NO];
	[removeButton setEnabled:NO];

	// Reset the table store if required - basically if the table is being changed,
	// reassigning before emptying for thread safety.
	if (!previousTableRowsCount) {
		[self clearTableValues];
	}
	[filterTableView reloadData];

}

/**
 * Remove all items from the current table value store.  Do this by
 * reassigning the tableValues store and releasing the old location,
 * while setting thread safety flags.
 */
- (void) clearTableValues
{
	SPDataStorage *tableValuesTransition;

	tableValuesTransition = tableValues;
	pthread_mutex_lock(&tableValuesLock);
	tableRowsCount = 0;
	tableValues = [[SPDataStorage alloc] init];
	[tableContentView setTableData:tableValues];
	pthread_mutex_unlock(&tableValuesLock);
	[tableValuesTransition release];
}

/**
 * Reload the table data without reconfiguring the tableView,
 * using filters and limits as appropriate.
 * Will not refresh the table view itself.
 * Note that this does not empty the table array - see use of previousTableRowsCount.
 */
- (void) loadTableValues
{
	// If no table is selected, return
	if (!selectedTable) return;

	NSMutableString *queryString;
	NSString *queryStringBeforeLimit = nil;
	NSString *filterString;
	MCPStreamingResult *streamingResult;
	NSInteger rowsToLoad = [[tableDataInstance statusValueForKey:@"Rows"] integerValue];

	[countText setStringValue:NSLocalizedString(@"Loading table data...", @"Loading table data string")];

	// Notify any listeners that a query has started
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryWillBePerformed" object:tableDocumentInstance];

	// Start construction of the query string
	queryString = [NSMutableString stringWithFormat:@"SELECT %@%@ FROM %@", (activeFilter == 1 && [self tableFilterString] && [filterTableDistinctCheckbox state] == NSOnState) ? @"DISTINCT " : @"", [self fieldListForQuery], [selectedTable backtickQuotedString]];

	// Add a filter string if appropriate
	filterString = [self tableFilterString];

	if (filterString) {
		[queryString appendFormat:@" WHERE %@", filterString];
		isFiltered = YES;
	} else {
		isFiltered = NO;
	}

	// Add sorting details if appropriate
	if (sortCol) {
		[queryString appendFormat:@" ORDER BY %@", [[[dataColumns objectAtIndex:[sortCol integerValue]] objectForKey:@"name"] backtickQuotedString]];
		if (isDesc) [queryString appendString:@" DESC"];
	}

	// Check to see if a limit needs to be applied
	if ([prefs boolForKey:SPLimitResults]) {

		// Ensure the page supplied is within the appropriate limits
		if (contentPage <= 0)
			contentPage = 1;
		else if (contentPage > 1 && (contentPage - 1) * [prefs integerForKey:SPLimitResultsValue] >= maxNumRows)
			contentPage = ceil((CGFloat)maxNumRows / [prefs floatForKey:SPLimitResultsValue]);

		// If the result set is from a late page, take a copy of the string to allow resetting limit
		// if no results are found
		if (contentPage > 1) {
			queryStringBeforeLimit = [NSString stringWithString:queryString];
		}

		// Append the limit settings
		[queryString appendFormat:@" LIMIT %ld,%ld", (long)((contentPage-1)*[prefs integerForKey:SPLimitResultsValue]), (long)[prefs integerForKey:SPLimitResultsValue]];

		// Update the approximate count of the rows to load
		rowsToLoad = rowsToLoad - (contentPage-1)*[prefs integerForKey:SPLimitResultsValue];
		if (rowsToLoad > [prefs integerForKey:SPLimitResultsValue]) rowsToLoad = [prefs integerForKey:SPLimitResultsValue];
	}

	// If within a task, allow this query to be cancelled
	[tableDocumentInstance enableTaskCancellationWithTitle:NSLocalizedString(@"Stop", @"stop button") callbackObject:nil callbackFunction:NULL];

	// Perform and process the query
	[tableContentView performSelectorOnMainThread:@selector(noteNumberOfRowsChanged) withObject:nil waitUntilDone:YES];
	[self setUsedQuery:queryString];
	streamingResult = [[mySQLConnection streamingQueryString:queryString] retain];

	// Ensure the number of columns are unchanged; if the column count has changed, abort the load
	// and queue a full table reload.
	BOOL fullTableReloadRequired = NO;
	if (streamingResult && [dataColumns count] != [streamingResult numOfFields]) {
		[tableDocumentInstance disableTaskCancellation];
		[mySQLConnection cancelCurrentQuery];
		[streamingResult cancelResultLoad];
		fullTableReloadRequired = YES;
	}

	// Process the result into the data store
	if (!fullTableReloadRequired && streamingResult) {
		[self processResultIntoDataStorage:streamingResult approximateRowCount:rowsToLoad];
	}
	if (streamingResult) [streamingResult release];

	// If the result is empty, and a late page is selected, reset the page
	if (!fullTableReloadRequired && [prefs boolForKey:SPLimitResults] && queryStringBeforeLimit && !tableRowsCount && ![mySQLConnection queryCancelled]) {
		contentPage = 1;
		previousTableRowsCount = tableRowsCount;
		queryString = [NSMutableString stringWithFormat:@"%@ LIMIT 0,%ld", queryStringBeforeLimit, (long)[prefs integerForKey:SPLimitResultsValue]];
		[self setUsedQuery:queryString];
		streamingResult = [[mySQLConnection streamingQueryString:queryString] retain];
		if (streamingResult) {
			[self processResultIntoDataStorage:streamingResult approximateRowCount:[prefs integerForKey:SPLimitResultsValue]];
			[streamingResult release];
		}
	}

	if ([mySQLConnection queryCancelled] || [mySQLConnection queryErrored])
		isInterruptedLoad = YES;
	else
		isInterruptedLoad = NO;

	// End cancellation ability
	[tableDocumentInstance disableTaskCancellation];

	if ([prefs boolForKey:SPLimitResults]
		&& (contentPage > 1
			|| tableRowsCount == [prefs integerForKey:SPLimitResultsValue]))
	{
		isLimited = YES;
	} else {
		isLimited = NO;
	}

	// Update the rows count as necessary
	[self updateNumberOfRows];

	// Set the filter text
	[self updateCountText];

	// Update pagination
	[self updatePaginationState];

	// Retrieve and cache the column definitions for editing views
	if (cqColumnDefinition) [cqColumnDefinition release];
	cqColumnDefinition = [[streamingResult fetchResultFieldsStructure] retain];


	// Notify listenters that the query has finished
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];

	if ([mySQLConnection queryErrored] && ![mySQLConnection queryCancelled]) {
		if(activeFilter == 0) {
			if(filterString)
				SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
							  [NSString stringWithFormat:NSLocalizedString(@"The table data couldn't be loaded presumably due to used filter clause. \n\nMySQL said: %@", @"message of panel when loading of table failed and presumably due to used filter argument"), [mySQLConnection getLastErrorMessage]]);
			else
				SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
							  [NSString stringWithFormat:NSLocalizedString(@"The table data couldn't be loaded.\n\nMySQL said: %@", @"message of panel when loading of table failed"), [mySQLConnection getLastErrorMessage]]);
		}
		// Filter task came from filter table
		else if(activeFilter == 1){
			[filterTableWindow setTitle:[NSString stringWithFormat:@"%@ – %@", NSLocalizedString(@"Filter", @"filter table window title"), NSLocalizedString(@"WHERE clause not valid", @"WHERE clause not valid")]];
		}
	} else {
		// Trigger a full reload if required
		if (fullTableReloadRequired) [self reloadTable:self];
		[filterTableWindow setTitle:NSLocalizedString(@"Filter", @"filter table window title")];
	}
}

/**
 * Processes a supplied streaming result set, loading it into the data array.
 */
- (void)processResultIntoDataStorage:(MCPStreamingResult *)theResult approximateRowCount:(NSUInteger)targetRowCount
{
	NSArray *tempRow;
	NSUInteger i;
	NSUInteger dataColumnsCount = [dataColumns count];
	BOOL *columnBlobStatuses = malloc(dataColumnsCount * sizeof(BOOL));
	tableLoadTargetRowCount = targetRowCount;

	// Set up the table updates timer
	[[self onMainThread] initTableLoadTimer];

	// Set the column count on the data store
	[tableValues setColumnCount:dataColumnsCount];

	NSAutoreleasePool *dataLoadingPool;
	NSProgressIndicator *dataLoadingIndicator = [tableDocumentInstance valueForKey:@"queryProgressBar"];
	BOOL prefsLoadBlobsAsNeeded = [prefs boolForKey:SPLoadBlobsAsNeeded];

	// Build up an array of which columns are blobs for faster iteration
	for ( i = 0; i < dataColumnsCount ; i++ ) {
		columnBlobStatuses[i] = [tableDataInstance columnIsBlobOrText:[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"name"]];
	}

	// Set up an autorelease pool for row processing
	dataLoadingPool = [[NSAutoreleasePool alloc] init];

	// Loop through the result rows as they become available
	tableRowsCount = 0;
	while (tempRow = [theResult fetchNextRowAsArray]) {
		pthread_mutex_lock(&tableValuesLock);

		if (tableRowsCount < previousTableRowsCount) {
			SPDataStorageReplaceRow(tableValues, tableRowsCount, tempRow);
		} else {
			SPDataStorageAddRow(tableValues, tempRow);
		}

		// Alter the values for hidden blob and text fields if appropriate
		if ( prefsLoadBlobsAsNeeded ) {
			for ( i = 0 ; i < dataColumnsCount ; i++ ) {
				if (columnBlobStatuses[i]) {
					SPDataStorageReplaceObjectAtRowAndColumn(tableValues, tableRowsCount, i, [SPNotLoaded notLoaded]);
				}
			}
		}
		tableRowsCount++;

		pthread_mutex_unlock(&tableValuesLock);

		// Drain and reset the autorelease pool every ~1024 rows
		if (!(tableRowsCount % 1024)) {
			[dataLoadingPool drain];
			dataLoadingPool = [[NSAutoreleasePool alloc] init];
		}
	}

	// Clean up the interface update timer
	[[self onMainThread] clearTableLoadTimer];

	// If the final column autoresize wasn't performed, perform it
	if (tableLoadLastRowCount < 200) [[self onMainThread] autosizeColumns];

	// If the reloaded table is shorter than the previous table, remove the extra values from the storage
	if (tableRowsCount < [tableValues count]) {
		pthread_mutex_lock(&tableValuesLock);
		[tableValues removeRowsInRange:NSMakeRange(tableRowsCount, [tableValues count] - tableRowsCount)];
		pthread_mutex_unlock(&tableValuesLock);
	}

	// Ensure the table is aware of changes
	if ([NSThread isMainThread]) {
		[tableContentView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
	} else {
		[tableContentView performSelectorOnMainThread:@selector(noteNumberOfRowsChanged) withObject:nil waitUntilDone:YES];
		[tableContentView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
	}

	// Clean up the autorelease pool and reset the progress indicator
	[dataLoadingPool drain];
	[dataLoadingIndicator setIndeterminate:YES];

	free(columnBlobStatuses);
}

/**
 * Returns the query string for the current filter settings,
 * ready to be dropped into a WHERE clause, or nil if no filtering
 * is active.
 */
- (NSString *)tableFilterString
{

	// Call did come from filter table and is filter table window still open?
	if(activeFilter == 1 && [filterTableWindow isVisible]) {

		if([[[filterTableWhereClause textStorage] string] length])
			if([filterTableNegateCheckbox state] == NSOnState)
				return [NSString stringWithFormat:@"NOT (%@)", [[filterTableWhereClause textStorage] string]];
			else
				return [[filterTableWhereClause textStorage] string];
		else
			return nil;

	}

	// If the clause has the placeholder $BINARY that placeholder will be replaced
	// by BINARY if the user pressed ⇧ while invoking 'Filter' otherwise it will
	// replaced by @"".
	BOOL caseSensitive = (([[[NSApp onMainThread] currentEvent] modifierFlags]
		& (NSShiftKeyMask|NSControlKeyMask|NSAlternateKeyMask|NSCommandKeyMask)) > 0);

	NSString *filterString;

	if(contentFilters == nil) {
		NSLog(@"Fatal error while retrieving content filters. No filters found.");
		NSBeep();
		return nil;
	}

	// Current selected filter type
	if(![contentFilters objectForKey:compareType]) {
		NSLog(@"Error while retrieving filters. Filter type “%@” unknown.", compareType);
		NSBeep();
		return nil;
	}
	NSDictionary *filter = [[contentFilters objectForKey:compareType] objectAtIndex:[[compareField selectedItem] tag]];

	if(![filter objectForKey:@"NumberOfArguments"]) {
		NSLog(@"Error while retrieving filter clause. No “Clause” or/and “NumberOfArguments” key found.");
		NSBeep();
		return nil;
	}

	if(![filter objectForKey:@"Clause"] || ![[filter objectForKey:@"Clause"] length]) {

		SPBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
					  NSLocalizedString(@"Content Filter clause is empty.", @"content filter clause is empty tooltip."));

		return nil;
	}

	NSUInteger numberOfArguments = [[filter objectForKey:@"NumberOfArguments"] integerValue];

	BOOL suppressLeadingTablePlaceholder = NO;
	if([filter objectForKey:@"SuppressLeadingFieldPlaceholder"])
		suppressLeadingTablePlaceholder = YES;

	// argument if Filter requires only one argument
	NSMutableString *argument = [[NSMutableString alloc] initWithString:[argumentField stringValue]];

	// If the filter field is empty and the selected filter does not require
	// only one argument, then no filtering is required - return nil.
	if (![argument length] && numberOfArguments == 1) {
		[argument release];
		return nil;
	}

	// arguments if Filter requires two arguments
	NSMutableString *firstBetweenArgument  = [[NSMutableString alloc] initWithString:[firstBetweenField stringValue]];
	NSMutableString *secondBetweenArgument = [[NSMutableString alloc] initWithString:[secondBetweenField stringValue]];

	// If filter requires two arguments and either of the argument fields are empty
	// return nil.
	if (numberOfArguments == 2) {
		if (([firstBetweenArgument length] == 0) || ([secondBetweenArgument length] == 0)) {
			[argument release];
			[firstBetweenArgument release];
			[secondBetweenArgument release];
			return nil;
		}
	}

	// Retrieve actual WHERE clause
	NSMutableString *clause = [[NSMutableString alloc] init];
	[clause setString:[filter objectForKey:@"Clause"]];

	[clause replaceOccurrencesOfRegex:@"(?<!\\\\)\\$BINARY" withString:(caseSensitive) ? @"BINARY" : @""];
	[clause flushCachedRegexData];
	[clause replaceOccurrencesOfRegex:@"(?<!\\\\)\\$CURRENT_FIELD" withString:([fieldField titleOfSelectedItem]) ? [[fieldField titleOfSelectedItem] backtickQuotedString] : @""];
	[clause flushCachedRegexData];

	// Escape % sign for format insertion ie if number of arguments is greater than 0
	if(numberOfArguments > 0)
		[clause replaceOccurrencesOfRegex:@"%" withString:@"%%"];
	[clause flushCachedRegexData];

	// Replace placeholder ${} by %@
	NSRange matchedRange;
	NSString *re = @"(?<!\\\\)\\$\\{.*?\\}";
	if([clause isMatchedByRegex:re]) {
		while([clause isMatchedByRegex:re]) {
			matchedRange = [clause rangeOfRegex:re];
			[clause replaceCharactersInRange:matchedRange withString:@"%@"];
			[clause flushCachedRegexData];
		}
	}

	// Check number of placeholders and given 'NumberOfArguments'
	if([clause replaceOccurrencesOfString:@"%@" withString:@"%@" options:NSLiteralSearch range:NSMakeRange(0, [clause length])] != numberOfArguments) {
		NSLog(@"Error while setting filter string. “NumberOfArguments” differs from the number of arguments specified in “Clause”.");
		NSBeep();
		[argument release];
		[firstBetweenArgument release];
		[secondBetweenArgument release];
		[clause release];
		return nil;
	}

	// Construct the filter string according the required number of arguments

	if(suppressLeadingTablePlaceholder) {
		if (numberOfArguments == 2) {
			filterString = [NSString stringWithFormat:clause,
					[self escapeFilterArgument:firstBetweenArgument againstClause:clause],
					[self escapeFilterArgument:secondBetweenArgument againstClause:clause]];
		} else if (numberOfArguments == 1) {
			filterString = [NSString stringWithFormat:clause, [self escapeFilterArgument:argument againstClause:clause]];
		} else {
			filterString = [NSString stringWithString:clause];
				if(numberOfArguments > 2) {
					NSLog(@"Filter with more than 2 arguments is not yet supported.");
					NSBeep();
				}
		}
	} else {
		if (numberOfArguments == 2) {
			filterString = [NSString stringWithFormat:@"%@ %@",
				[[fieldField titleOfSelectedItem] backtickQuotedString],
				[NSString stringWithFormat:clause,
					[self escapeFilterArgument:firstBetweenArgument againstClause:clause],
					[self escapeFilterArgument:secondBetweenArgument againstClause:clause]]];
		} else if (numberOfArguments == 1) {
			filterString = [NSString stringWithFormat:@"%@ %@",
				[[fieldField titleOfSelectedItem] backtickQuotedString],
				[NSString stringWithFormat:clause, [self escapeFilterArgument:argument againstClause:clause]]];
		} else {
			filterString = [NSString stringWithFormat:@"%@ %@",
				[[fieldField titleOfSelectedItem] backtickQuotedString], clause];
				if(numberOfArguments > 2) {
					NSLog(@"Filter with more than 2 arguments is not yet supported.");
					NSBeep();
				}
		}
	}

	[argument release];
	[firstBetweenArgument release];
	[secondBetweenArgument release];
	[clause release];

	// Return the filter string
	return filterString;
}

/**
 * Esacpe argument by looking for used quoting strings in clause
 *
 * @param argument The to be used filter argument which should be be escaped
 *
 * @param clause The entire WHERE filter clause
 *
 */
- (NSString *)escapeFilterArgument:(NSString *)argument againstClause:(NSString *)clause
{

	NSMutableString *arg = [[NSMutableString alloc] init];
	[arg setString:argument];

	[arg replaceOccurrencesOfRegex:@"(\\\\)(?![nrt_%])" withString:@"\\\\\\\\\\\\\\\\"];
	[arg flushCachedRegexData];
	[arg replaceOccurrencesOfRegex:@"(\\\\)(?=[nrt])" withString:@"\\\\\\"];
	[arg flushCachedRegexData];

	// Get quote sign for escaping - this should work for 99% of all cases
	NSString *quoteSign = [clause stringByMatching:@"([\"'])[^\\1]*?%@[^\\1]*?\\1" capture:1L];
	// Esape argument
	if(quoteSign != nil && [quoteSign length] == 1) {
		[arg replaceOccurrencesOfRegex:[NSString stringWithFormat:@"(%@)", quoteSign] withString:@"\\\\$1"];
		[arg flushCachedRegexData];
	}
	// if([clause isMatchedByRegex:@"(?i)\\blike\\b.*?%(?!@)"]) {
	// 	[arg replaceOccurrencesOfRegex:@"([_%])" withString:@"\\\\$1"];
	// 	[arg flushCachedRegexData];
	// }
	return [arg autorelease];
}

/**
 * Update the table count/selection text
 */
- (void)updateCountText
{
	NSString *rowString;
	NSMutableString *countString = [NSMutableString string];
	NSNumberFormatter *numberFormatter = [[[NSNumberFormatter alloc] init] autorelease];
	[numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];

	// Set up a couple of common strings
	NSString *tableCountString = [numberFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:tableRowsCount]];
	NSString *maxRowsString = [numberFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:maxNumRows]];

	// If the result is partial due to an error or query cancellation, show a very basic count
	if (isInterruptedLoad) {
		if (tableRowsCount == 1)
			[countString appendFormat:NSLocalizedString(@"%@ row in partial load", @"text showing a single row a partially loaded result"), tableCountString];
		else
			[countString appendFormat:NSLocalizedString(@"%@ rows in partial load", @"text showing how many rows are in a partially loaded result"), tableCountString];

	// If no filter or limit is active, show just the count of rows in the table
	} else if (!isFiltered && !isLimited) {
		if (tableRowsCount == 1)
			[countString appendFormat:NSLocalizedString(@"%@ row in table", @"text showing a single row in the result"), tableCountString];
		else
			[countString appendFormat:NSLocalizedString(@"%@ rows in table", @"text showing how many rows are in the result"), tableCountString];

	// If a limit is active, display a string suggesting a limit is active
	} else if (!isFiltered && isLimited) {
		NSUInteger limitStart = (contentPage-1)*[prefs integerForKey:SPLimitResultsValue] + 1;
		[countString appendFormat:NSLocalizedString(@"Rows %@ - %@ of %@%@ from table", @"text showing how many rows are in the limited result"),  [numberFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:limitStart]], [numberFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:(limitStart+tableRowsCount-1)]], maxNumRowsIsEstimate?@"~":@"", maxRowsString];

	// If just a filter is active, show a count and an indication a filter is active
	} else if (isFiltered && !isLimited) {
		if (tableRowsCount == 1)
			[countString appendFormat:NSLocalizedString(@"%@ row of %@%@ matches filter", @"text showing how a single rows matched filter"), tableCountString, maxNumRowsIsEstimate?@"~":@"", maxRowsString];
		else
			[countString appendFormat:NSLocalizedString(@"%@ rows of %@%@ match filter", @"text showing how many rows matched filter"), tableCountString, maxNumRowsIsEstimate?@"~":@"", maxRowsString];

	// If both a filter and limit is active, display full string
	} else {
		NSUInteger limitStart = (contentPage-1)*[prefs integerForKey:SPLimitResultsValue] + 1;
		[countString appendFormat:NSLocalizedString(@"Rows %@ - %@ from filtered matches", @"text showing how many rows are in the limited filter match"), [numberFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:limitStart]], [numberFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:(limitStart+tableRowsCount-1)]]];
	}

	// If rows are selected, append selection count
	if ([tableContentView numberOfSelectedRows] > 0) {
		[countString appendString:@"; "];
		if ([tableContentView numberOfSelectedRows] == 1)
			rowString = [NSString stringWithString:NSLocalizedString(@"row", @"singular word for row")];
		else
			rowString = [NSString stringWithString:NSLocalizedString(@"rows", @"plural word for rows")];
		[countString appendFormat:NSLocalizedString(@"%@ %@ selected", @"text showing how many rows are selected"), [numberFormatter stringFromNumber:[NSNumber numberWithInteger:[tableContentView numberOfSelectedRows]]], rowString];
	}

	[[countText onMainThread] setStringValue:countString];
}

/**
 * Set up the table loading interface update timer.
 * This should be called on the main thread.
 */
- (void) initTableLoadTimer
{
	if (tableLoadTimer) [self clearTableLoadTimer];
	tableLoadInterfaceUpdateInterval = 1;
	tableLoadLastRowCount = 0;
	tableLoadTimerTicksSinceLastUpdate = 0;

	tableLoadTimer = [[NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(tableLoadUpdate:) userInfo:nil repeats:YES] retain];
}

/**
 * Invalidate and release the table loading interface update timer.
 * This should be called on the main thread.
 */
- (void) clearTableLoadTimer
{
	if (tableLoadTimer) {
		[tableLoadTimer invalidate];
		[tableLoadTimer release];
		tableLoadTimer = nil;
	}
}

/**
 * Perform table interface updates when loading tables, based on timer
 * ticks.  As data becomes available, the table should be redrawn to
 * show new rows - quickly at the start of the table, and then slightly
 * slower after some time to avoid needless updates.
 */
- (void) tableLoadUpdate:(NSTimer *)theTimer
{

	// Update the task interface as necessary
	if (!isFiltered && tableLoadTargetRowCount != NSUIntegerMax) {
		if (tableRowsCount < tableLoadTargetRowCount) {
			[tableDocumentInstance setTaskPercentage:(tableRowsCount*100/tableLoadTargetRowCount)];
		} else if (tableRowsCount >= tableLoadTargetRowCount) {
			[tableDocumentInstance setTaskPercentage:100.0];
			[tableDocumentInstance setTaskProgressToIndeterminateAfterDelay:YES];
			tableLoadTargetRowCount = NSUIntegerMax;
		}
	}

	if (tableLoadTimerTicksSinceLastUpdate < tableLoadInterfaceUpdateInterval) {
		tableLoadTimerTicksSinceLastUpdate++;
		return;
	}

	// Check whether a table update is required, based on whether new rows are
	// available to display.
	if (tableRowsCount == tableLoadLastRowCount) {
		return;
	}

	// Update the table display
	[tableContentView noteNumberOfRowsChanged];
	if (!tableLoadLastRowCount) [tableContentView setNeedsDisplay:YES];

	// Update column widths in two cases: on very first rows displayed, and once
	// more than 200 rows are present.
	if (tableLoadInterfaceUpdateInterval == 1 || (tableRowsCount >= 200 && tableLoadLastRowCount < 200)) {
		[self autosizeColumns];
	}

	tableLoadLastRowCount = tableRowsCount;

	// Determine whether to decrease the update frequency
	switch (tableLoadInterfaceUpdateInterval) {
		case 1:
			tableLoadInterfaceUpdateInterval = 10;
			break;
		case 10:
			tableLoadInterfaceUpdateInterval = 25;
			break;
	}
	tableLoadTimerTicksSinceLastUpdate = 0;
}


#pragma mark -
#pragma mark Table interface actions

/**
 * Reloads the current table data, performing a new SQL query. Now attempts to preserve sort
 * order, filters, and viewport. Performs the action in a new thread if a task is not already
 * running.
 */
- (IBAction)reloadTable:(id)sender
{
	[tableDocumentInstance startTaskWithDescription:NSLocalizedString(@"Reloading data...", @"Reloading data task description")];

	if ([NSThread isMainThread]) {
		[NSThread detachNewThreadSelector:@selector(reloadTableTask) toTarget:self withObject:nil];
	} else {
		[self reloadTableTask];
	}
}

- (void)reloadTableTask
{
	NSAutoreleasePool *reloadPool = [[NSAutoreleasePool alloc] init];

	// Check whether a save of the current row is required.
	if (![[self onMainThread] saveRowOnDeselect]) return;

	// Save view details to restore safely if possible (except viewport, which will be
	// preserved automatically, and can then be scrolled as the table loads)
	[self storeCurrentDetailsForRestoration];
	[self setViewportToRestore:NSZeroRect];

	// Clear the table data column cache and status (including counts)
	[tableDataInstance resetColumnData];
	[tableDataInstance resetStatusData];

	// Load the table's data
	[self loadTable:[tablesListInstance tableName]];

	[tableDocumentInstance endTask];

	[reloadPool drain];
}

/**
 * Filter the table with arguments given by the user.
 * Performs the action in a new thread if necessary.
 */
- (IBAction)filterTable:(id)sender
{

	if(sender == filterTableFilterButton)
		activeFilter = 1;
	else
		activeFilter = 0;

	NSString *taskString;

	if ([tableDocumentInstance isWorking]) return;
	if (![self saveRowOnDeselect]) return;
	[self setPaginationViewVisibility:FALSE];

	// Select the correct pagination value
	if (![prefs boolForKey:SPLimitResults] || [paginationPageField integerValue] <= 0)
		contentPage = 1;
	else if (([paginationPageField integerValue] - 1) * [prefs integerForKey:SPLimitResultsValue] >= maxNumRows)
		contentPage = ceil((CGFloat)maxNumRows / [prefs floatForKey:SPLimitResultsValue]);
	else
		contentPage = [paginationPageField integerValue];

	if ([self tableFilterString]) {
		taskString = NSLocalizedString(@"Filtering table...", @"Filtering table task description");
	} else if (contentPage == 1) {
		taskString = [NSString stringWithFormat:NSLocalizedString(@"Loading %@...", @"Loading table task string"), selectedTable];
	} else {
		taskString = [NSString stringWithFormat:NSLocalizedString(@"Loading page %lu...", @"Loading table page task string"), (unsigned long)contentPage];
	}

	[tableDocumentInstance startTaskWithDescription:taskString];

	if ([NSThread isMainThread]) {
		[NSThread detachNewThreadSelector:@selector(filterTableTask) toTarget:self withObject:nil];
	} else {
		[self filterTableTask];
	}
}
- (void)filterTableTask
{
	NSAutoreleasePool *filterPool = [[NSAutoreleasePool alloc] init];

	// Check whether a save of the current row is required.
	if (![[self onMainThread] saveRowOnDeselect]) return;

	// Update history
	[spHistoryControllerInstance updateHistoryEntries];

	// Reset and reload data using the new filter settings
	previousTableRowsCount = 0;
	[self clearTableValues];
	[self loadTableValues];
	[[tableContentView onMainThread] scrollPoint:NSMakePoint(0.0, 0.0)];

	[tableDocumentInstance endTask];
	[filterPool drain];
}

/**
 * Enables or disables the filter input field based on the selected filter type.
 */
- (IBAction)toggleFilterField:(id)sender
{

	// Check if user called "Edit Filter…"
	if([[compareField selectedItem] tag] == [[contentFilters objectForKey:compareType] count]) {
		[self openContentFilterManager];
		return;
	}

	// Remember last selection for "Edit filter…"
	lastSelectedContentFilterIndex = [[compareField selectedItem] tag];

	NSDictionary *filter = [[contentFilters objectForKey:compareType] objectAtIndex:lastSelectedContentFilterIndex];
	NSUInteger numOfArgs = [[filter objectForKey:@"NumberOfArguments"] integerValue];
	if (numOfArgs == 2) {
		[argumentField setHidden:YES];

		if([filter objectForKey:@"ConjunctionLabels"] && [[filter objectForKey:@"ConjunctionLabels"] count] == 1)
			[betweenTextField setStringValue:[[filter objectForKey:@"ConjunctionLabels"] objectAtIndex:0]];
		else
			[betweenTextField setStringValue:@""];

		[betweenTextField setHidden:NO];
		[firstBetweenField setHidden:NO];
		[secondBetweenField setHidden:NO];

		[firstBetweenField setEnabled:YES];
		[secondBetweenField setEnabled:YES];
		[firstBetweenField selectText:self];
	}
	else if (numOfArgs == 1){
		[argumentField setHidden:NO];
		[argumentField setEnabled:YES];
		[argumentField selectText:self];

		[betweenTextField setHidden:YES];
		[firstBetweenField setHidden:YES];
		[secondBetweenField setHidden:YES];
	}
	else {
		[argumentField setHidden:NO];
		[argumentField setEnabled:NO];

		[betweenTextField setHidden:YES];
		[firstBetweenField setHidden:YES];
		[secondBetweenField setHidden:YES];

		// Start search if no argument is required
		if(numOfArgs == 0)
			[self filterTable:self];
	}

}

- (NSString *)usedQuery
{
	return usedQuery;
}

- (void)setUsedQuery:(NSString *)query
{
	if (usedQuery) [usedQuery release];
	usedQuery = [[NSString alloc] initWithString:query];
}

#pragma mark -
#pragma mark Pagination

/**
 * Move the pagination backwards or forwards one page
 */
- (IBAction) navigatePaginationFromButton:(id)sender
{
	if (![self saveRowOnDeselect]) return;
	if (sender == paginationPreviousButton) {
		if (contentPage <= 1) return;
		[paginationPageField setIntegerValue:(contentPage - 1)];
		[self filterTable:sender];
	} else if (sender == paginationNextButton) {
		if (contentPage * [prefs integerForKey:SPLimitResultsValue] >= maxNumRows) return;
		[paginationPageField setIntegerValue:(contentPage + 1)];
		[self filterTable:sender];
	}
}

/**
 * When the Pagination button is pressed, show or hide the pagination
 * layer depending on the current state.
 */
- (IBAction) togglePagination:(id)sender
{
	if ([sender state] == NSOnState) [self setPaginationViewVisibility:YES];
	else [self setPaginationViewVisibility:NO];
}

/**
 * Show or hide the pagination layer, also changing the first responder as appropriate.
 */
- (void) setPaginationViewVisibility:(BOOL)makeVisible
{
	NSRect paginationViewFrame = [paginationView frame];

	if (makeVisible) {
		if (paginationViewFrame.size.height == paginationViewHeight) return;
		paginationViewFrame.size.height = paginationViewHeight;
		[paginationButton setState:NSOnState];
		[paginationButton setImage:[NSImage imageNamed:@"button_action"]];
		[[tableDocumentInstance parentWindow] makeFirstResponder:paginationPageField];
	} else {
		if (paginationViewFrame.size.height == 0) return;
		paginationViewFrame.size.height = 0;
		[paginationButton setState:NSOffState];
		[paginationButton setImage:[NSImage imageNamed:@"button_pagination"]];
		if ([[tableDocumentInstance parentWindow] firstResponder] == paginationPageField
			|| ([[[tableDocumentInstance parentWindow] firstResponder] respondsToSelector:@selector(superview)]
				&& [(id)[[tableDocumentInstance parentWindow] firstResponder] superview]
				&& [[(id)[[tableDocumentInstance parentWindow] firstResponder] superview] respondsToSelector:@selector(superview)]
				&& [[(id)[[tableDocumentInstance parentWindow] firstResponder] superview] superview] == paginationPageField))
		{
			[[tableDocumentInstance parentWindow] makeFirstResponder:nil];
		}
	}

	[[paginationView animator] setFrame:paginationViewFrame];
}

/**
 * Update the state of the pagination buttons and text.
 */
- (void) updatePaginationState
{
	NSUInteger maxPage = ceil((CGFloat)maxNumRows / [prefs floatForKey:SPLimitResultsValue]);
	if (isFiltered && !isLimited) {
		maxPage = contentPage;
	}
	BOOL enabledMode = ![tableDocumentInstance isWorking];

	NSNumberFormatter *numberFormatter = [[[NSNumberFormatter alloc] init] autorelease];
	[numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];

	// Set up the previous page button
	if ([prefs boolForKey:SPLimitResults] && contentPage > 1)
		[paginationPreviousButton setEnabled:enabledMode];
	else
		[paginationPreviousButton setEnabled:NO];

	// Set up the next page button
	if ([prefs boolForKey:SPLimitResults] && contentPage < maxPage)
		[paginationNextButton setEnabled:enabledMode];
	else
		[paginationNextButton setEnabled:NO];

	// As long as a table is selected (which it will be if this is called), enable pagination detail button
	[paginationButton setEnabled:enabledMode];

	// Set the values and maximums for the text field and associated pager
	[paginationPageField setStringValue:[numberFormatter stringFromNumber:[NSNumber numberWithUnsignedInteger:contentPage]]];
	[[paginationPageField formatter] setMaximum:[NSNumber numberWithUnsignedInteger:maxPage]];
	[paginationPageStepper setIntegerValue:contentPage];
	[paginationPageStepper setMaxValue:maxPage];
}

#pragma mark -
#pragma mark Edit methods

/**
 * Collect all columns for a given 'tableForColumn' table and
 * return a WHERE clause for identifying the field in quesyion.
 */
- (NSString *)argumentForRow:(NSUInteger)rowIndex ofTable:(NSString *)tableForColumn andDatabase:(NSString *)database includeBlobs:(BOOL)includeBlobs
{
	NSArray *dataRow;
	NSDictionary *theRow;
	id field;

	//Look for all columns which are coming from "tableForColumn"
	NSMutableArray *columnsForFieldTableName = [NSMutableArray array];
	for(field in cqColumnDefinition) {
		if([[field objectForKey:@"org_table"] isEqualToString:tableForColumn])
			[columnsForFieldTableName addObject:field];
	}

	// Try to identify the field bijectively
	NSMutableString *fieldIDQueryStr = [NSMutableString string];
	[fieldIDQueryStr setString:@"WHERE ("];

	// --- Build WHERE clause ---
	dataRow = [tableValues rowContentsAtIndex:rowIndex];

	// Get the primary key if there is one
	MCPResult *theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@.%@",
		[database backtickQuotedString], [tableForColumn backtickQuotedString]]];
	[theResult setReturnDataAsStrings:YES];
	if ([theResult numOfRows]) [theResult dataSeek:0];
	NSInteger i;
	for ( i = 0 ; i < [theResult numOfRows] ; i++ ) {
		theRow = [theResult fetchRowAsDictionary];
		if ( [[theRow objectForKey:@"Key"] isEqualToString:@"PRI"] ) {
			for(field in columnsForFieldTableName) {
				id aValue = [dataRow objectAtIndex:[[field objectForKey:@"datacolumnindex"] integerValue]];
				if([[field objectForKey:@"org_name"] isEqualToString:[theRow objectForKey:@"Field"]]) {
					[fieldIDQueryStr appendFormat:@"%@.%@.%@ = %@)",
						[database backtickQuotedString],
						[tableForColumn backtickQuotedString],
						[[theRow objectForKey:@"Field"] backtickQuotedString],
						[aValue description]];
					return fieldIDQueryStr;
				}
			}
		}
	}

	// If there is no primary key, all found fields belonging to the same table are used in the argument
	for(field in columnsForFieldTableName) {
		id aValue = [dataRow objectAtIndex:[[field objectForKey:@"datacolumnindex"] integerValue]];
		if ([aValue isKindOfClass:[NSNull class]] || [aValue isNSNull]) {
			[fieldIDQueryStr appendFormat:@"%@ IS NULL AND ", [[field objectForKey:@"org_name"] backtickQuotedString]];
		} else {
			if ([[field objectForKey:@"typegrouping"] isEqualToString:@"textdata"]) {
				if(includeBlobs) {
					[fieldIDQueryStr appendFormat:@"%@='%@' AND ", [[field objectForKey:@"org_name"] backtickQuotedString], [mySQLConnection prepareString:aValue]];
				}
			}
			else if ([[field objectForKey:@"typegrouping"] isEqualToString:@"blobdata"] || [[field objectForKey:@"type"] isEqualToString:@"BINARY"] || [[field objectForKey:@"type"] isEqualToString:@"VARBINARY"]) {
				if(includeBlobs) {
					[fieldIDQueryStr appendFormat:@"%@=X'%@' AND ", [[field objectForKey:@"org_name"] backtickQuotedString], [mySQLConnection prepareBinaryData:aValue]];
				}
			}
			else if ([[field objectForKey:@"typegrouping"] isEqualToString:@"bit"]) {
				[fieldIDQueryStr appendFormat:@"%@=b'%@' AND ", [[field objectForKey:@"org_name"] backtickQuotedString], [aValue description]];
			}
			else if ([[field objectForKey:@"typegrouping"] isEqualToString:@"integer"]) {
				[fieldIDQueryStr appendFormat:@"%@=%@ AND ", [[field objectForKey:@"org_name"] backtickQuotedString], [aValue description]];
			}
			else {
				[fieldIDQueryStr appendFormat:@"%@='%@' AND ", [[field objectForKey:@"org_name"] backtickQuotedString], [mySQLConnection prepareString:aValue]];
			}
		}
	}
	// Remove last " AND "
	if([fieldIDQueryStr length]>12)
		[fieldIDQueryStr replaceCharactersInRange:NSMakeRange([fieldIDQueryStr length]-5,5) withString:@")"];

	return fieldIDQueryStr;
}

/**
 * Adds an empty row to the table-array and goes into edit mode
 */
- (IBAction)addRow:(id)sender
{
	NSMutableDictionary *column;
	NSMutableArray *newRow = [NSMutableArray array];
	NSUInteger i;

	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;

	for ( i = 0 ; i < [dataColumns count] ; i++ ) {
		column = NSArrayObjectAtIndex(dataColumns, i);
		if ([column objectForKey:@"default"] == nil || [column objectForKey:@"default"] == [NSNull null]) {
			[newRow addObject:[NSNull null]];
		} else {
			[newRow addObject:[column objectForKey:@"default"]];
		}
	}
	[tableValues addRowWithContents:newRow];
	tableRowsCount++;

	[tableContentView reloadData];
	[tableContentView selectRowIndexes:[NSIndexSet indexSetWithIndex:[tableContentView numberOfRows]-1] byExtendingSelection:NO];
	[tableContentView scrollRowToVisible:[tableContentView selectedRow]];
	isEditingRow = YES;
	isEditingNewRow = YES;
	currentlyEditingRow = [tableContentView selectedRow];
	if ( [multipleLineEditingButton state] == NSOffState )
		[tableContentView editColumn:0 row:[tableContentView numberOfRows]-1 withEvent:nil select:YES];
}

/**
 * Copies a row of the table-array and goes into edit mode
 */
- (IBAction)copyRow:(id)sender
{
	NSMutableArray *tempRow;
	MCPResult *queryResult;
	NSDictionary *row;
	NSArray *dbDataRow = nil;
	NSUInteger i;

	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;

	if ( [tableContentView numberOfSelectedRows] < 1 )
		return;
	if ( [tableContentView numberOfSelectedRows] > 1 ) {
		SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil, NSLocalizedString(@"You can only copy single rows.", @"message of panel when trying to copy multiple rows"));
		return;
	}

	//copy row
	tempRow = [tableValues rowContentsAtIndex:[tableContentView selectedRow]];

	//if we don't show blobs, read data for this duplicate column from db
	if ([prefs boolForKey:SPLoadBlobsAsNeeded]) {
		// Abort if there are no indices on this table - argumentForRow will display an error.
		if (![[self argumentForRow:[tableContentView selectedRow]] length]){
			return;
		}
		//if we have indexes, use argumentForRow
		queryResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@", [selectedTable backtickQuotedString], [self argumentForRow:[tableContentView selectedRow]]]];
		dbDataRow = [queryResult fetchRowAsArray];
	}

	//set autoincrement fields to NULL
	queryResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@", [selectedTable backtickQuotedString]]];
	[queryResult setReturnDataAsStrings:YES];
	if ([queryResult numOfRows]) [queryResult dataSeek:0];
	for ( i = 0 ; i < [queryResult numOfRows] ; i++ ) {
		row = [queryResult fetchRowAsDictionary];
		if ( [[row objectForKey:@"Extra"] isEqualToString:@"auto_increment"] ) {
			[tempRow replaceObjectAtIndex:i withObject:[NSNull null]];
		} else if ( [tableDataInstance columnIsBlobOrText:[row objectForKey:@"Field"]] && [prefs boolForKey:SPLoadBlobsAsNeeded] && dbDataRow) {
			[tempRow replaceObjectAtIndex:i withObject:[dbDataRow objectAtIndex:i]];
		}
	}

	//insert the copied row
	[tableValues insertRowContents:tempRow atIndex:[tableContentView selectedRow]+1];
	tableRowsCount++;

	//select row and go in edit mode
	[tableContentView reloadData];
	[tableContentView selectRowIndexes:[NSIndexSet indexSetWithIndex:[tableContentView selectedRow]+1] byExtendingSelection:NO];
	isEditingRow = YES;
	isEditingNewRow = YES;
	currentlyEditingRow = [tableContentView selectedRow];
	if ( [multipleLineEditingButton state] == NSOffState )
		[tableContentView editColumn:0 row:[tableContentView selectedRow] withEvent:nil select:YES];
}

/**
 * Asks the user if they really want to delete the selected rows
 */
- (IBAction)removeRow:(id)sender
{
	// Check whether a save of the current row is required.
	// if (![self saveRowOnDeselect])
	//	return;

	// cancel editing (maybe this is not the ideal method -- see xcode docs for that method)
	[[tableDocumentInstance parentWindow] endEditingFor:nil];


	if (![tableContentView numberOfSelectedRows])
		return;

	NSAlert *alert = [NSAlert alertWithMessageText:@""
									 defaultButton:NSLocalizedString(@"Delete", @"delete button")
								   alternateButton:NSLocalizedString(@"Cancel", @"cancel button")
									   otherButton:nil
						 informativeTextWithFormat:@""];

	[alert setAlertStyle:NSCriticalAlertStyle];

	NSArray *buttons = [alert buttons];

	// Change the alert's cancel button to have the key equivalent of return
	[[buttons objectAtIndex:0] setKeyEquivalent:@"d"];
	[[buttons objectAtIndex:0] setKeyEquivalentModifierMask:NSCommandKeyMask];
	[[buttons objectAtIndex:1] setKeyEquivalent:@"\r"];

	[alert setShowsSuppressionButton:NO];
	[[alert suppressionButton] setState:NSOffState];

	NSString *contextInfo = @"removerow";

	if (([tableContentView numberOfSelectedRows] == [tableContentView numberOfRows]) && !isFiltered && !isLimited && !isInterruptedLoad && !isEditingNewRow) {

		contextInfo = @"removeallrows";

		// If table has PRIMARY KEY ask for resetting the auto increment after deletion if given
		if(![[tableDataInstance statusValueForKey:@"Auto_increment"] isKindOfClass:[NSNull class]]) {
			[alert setShowsSuppressionButton:YES];
			[[alert suppressionButton] setState:([prefs boolForKey:SPResetAutoIncrementAfterDeletionOfAllRows]) ? NSOnState : NSOffState];
			[[[alert suppressionButton] cell] setControlSize:NSSmallControlSize];
			[[[alert suppressionButton] cell] setFont:[NSFont systemFontOfSize:11]];
			[[alert suppressionButton] setTitle:NSLocalizedString(@"Reset AUTO_INCREMENT after deletion?", @"reset auto_increment after deletion of all rows message")];
		}

		[alert setMessageText:NSLocalizedString(@"Delete all rows?", @"delete all rows message")];
		[alert setInformativeText:NSLocalizedString(@"Are you sure you want to delete all the rows from this table? This action cannot be undone.", @"delete all rows informative message")];
	}
	else if ([tableContentView numberOfSelectedRows] == 1) {
		[alert setMessageText:NSLocalizedString(@"Delete selected row?", @"delete selected row message")];
		[alert setInformativeText:NSLocalizedString(@"Are you sure you want to delete the selected row from this table? This action cannot be undone.", @"delete selected row informative message")];
	}
	else {
		[alert setMessageText:NSLocalizedString(@"Delete rows?", @"delete rows message")];
		[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the selected %ld rows from this table? This action cannot be undone.", @"delete rows informative message"), (long)[tableContentView numberOfSelectedRows]]];
	}

	[alert beginSheetModalForWindow:[tableDocumentInstance parentWindow] modalDelegate:self didEndSelector:@selector(removeRowSheetDidEnd:returnCode:contextInfo:) contextInfo:contextInfo];
}

/**
 * Perform the requested row deletion action.
 */
- (void)removeRowSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{

	NSMutableIndexSet *selectedRows = [NSMutableIndexSet indexSet];
	NSString *wherePart;
	NSInteger i, errors;
	BOOL consoleUpdateStatus;
	BOOL reloadAfterRemovingRow = [prefs boolForKey:SPReloadAfterRemovingRow];

	// Order out current sheet to suppress overlapping of sheets
	[[alert window] orderOut:nil];

	if ( [contextInfo isEqualToString:@"removeallrows"] ) {
		if ( returnCode == NSAlertDefaultReturn ) {

			// Check if the user is currently editing a row, and revert to ensure a somewhat
			// consistent state if deletion fails.
			if (isEditingRow) [self cancelRowEditing];

			[mySQLConnection queryString:[NSString stringWithFormat:@"DELETE FROM %@", [selectedTable backtickQuotedString]]];
			if ( ![mySQLConnection queryErrored] ) {
				maxNumRows = 0;
				tableRowsCount = 0;
				maxNumRowsIsEstimate = NO;
				[self updateCountText];

				// Reset auto increment if suppression button was ticked
				if([[alert suppressionButton] state] == NSOnState) {
					[tableSourceInstance setAutoIncrementTo:@"1"];
					[prefs setBool:YES forKey:SPResetAutoIncrementAfterDeletionOfAllRows];
				} else {
					[prefs setBool:NO forKey:SPResetAutoIncrementAfterDeletionOfAllRows];
				}

				[self reloadTable:self];

			} else {
				[self performSelector:@selector(showErrorSheetWith:)
					withObject:[NSArray arrayWithObjects:NSLocalizedString(@"Error", @"error"),
						[NSString stringWithFormat:NSLocalizedString(@"Couldn't delete rows.\n\nMySQL said: %@", @"message when deleteing all rows failed"),
						   [mySQLConnection getLastErrorMessage]],
						nil]
					afterDelay:0.3];
			}
		}
	} else if ( [contextInfo isEqualToString:@"removerow"] ) {
		if ( returnCode == NSAlertDefaultReturn ) {
			[selectedRows addIndexes:[tableContentView selectedRowIndexes]];

			//check if the user is currently editing a row
			if (isEditingRow) {
				//make sure that only one row is selected. This should never happen
				if ([selectedRows count]!=1) {
					NSLog(@"Expected only one selected row, but found %d",[selectedRows count]);
				}

				// Always cancel the edit; if the user is currently editing a new row, we can just discard it;
				// if editing an old row, restore it to the original to ensure consistent state if deletion fails.
				// If editing a new row, deselect the row and return - as no table reload is required.
				if ( isEditingNewRow ) {
					[self cancelRowEditing]; // Resets isEditingNewRow!
					[tableContentView selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
					return;
				} else {
					[self cancelRowEditing];
				}
			}
			[tableContentView selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];

			NSInteger affectedRows = 0;
			errors = 0;

			// Disable updating of the Console Log window for large number of queries
			// to speed the deletion
			consoleUpdateStatus = [[SPQueryController sharedQueryController] allowConsoleUpdate];
			if([selectedRows count] > 10)
				[[SPQueryController sharedQueryController] setAllowConsoleUpdate:NO];

			NSUInteger index = [selectedRows firstIndex];

			NSArray *primaryKeyFieldNames = [tableDataInstance primaryKeyColumnNames];

			// If no PRIMARY KEY is found and numberOfSelectedRows > 3 then
			// check for uniqueness of rows via combining all column values;
			// if unique then use the all columns as 'primary keys'
			if([selectedRows count] > 3 && primaryKeyFieldNames == nil) {
				primaryKeyFieldNames = [tableDataInstance columnNames];

				NSInteger numberOfRows = 0;
				// Get the number of rows in the table
				MCPResult *r;
				r = [mySQLConnection queryString:[NSString stringWithFormat:@"SELECT COUNT(1) FROM %@", [selectedTable backtickQuotedString]]];
				if (![mySQLConnection queryErrored]) {
					NSArray *a = [r fetchRowAsArray];
					if([a count])
						numberOfRows = [[a objectAtIndex:0] integerValue];
				}
				// Check for uniqueness via LIMIT numberOfRows-1,numberOfRows for speed
				if(numberOfRows > 0) {
					[mySQLConnection queryString:[NSString stringWithFormat:@"SELECT * FROM %@ GROUP BY %@ LIMIT %ld,%ld", [selectedTable backtickQuotedString], [primaryKeyFieldNames componentsJoinedAndBacktickQuoted], (long)(numberOfRows-1), (long)numberOfRows]];
					if([mySQLConnection affectedRows] == 0)
						primaryKeyFieldNames = nil;
				} else {
					primaryKeyFieldNames = nil;
				}
			}

			if(primaryKeyFieldNames == nil) {
				// delete row by row
				while (index != NSNotFound) {

					wherePart = [NSString stringWithString:[self argumentForRow:index]];

					//argumentForRow might return empty query, in which case we shouldn't execute the partial query
					if([wherePart length]) {
						[mySQLConnection queryString:[NSString stringWithFormat:@"DELETE FROM %@ WHERE %@", [selectedTable backtickQuotedString], wherePart]];

						// Check for errors
						if ( ![mySQLConnection affectedRows] || [mySQLConnection queryErrored]) {
							// If error delete that index from selectedRows for reloading table if
							// "ReloadAfterRemovingRow" is disbaled
							if(!reloadAfterRemovingRow)
								[selectedRows removeIndex:index];
							errors++;
						} else {
							affectedRows++;
						}
					} else {
						if(!reloadAfterRemovingRow)
							[selectedRows removeIndex:index];
						errors++;
					}
					index = [selectedRows indexGreaterThanIndex:index];
				}
			} else if ([primaryKeyFieldNames count] == 1) {
				// if table has only one PRIMARY KEY
				// delete the fast way by using the PRIMARY KEY in an IN clause
				NSMutableString *deleteQuery = [NSMutableString string];

				[deleteQuery setString:[NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ IN (", [selectedTable backtickQuotedString], [NSArrayObjectAtIndex(primaryKeyFieldNames,0) backtickQuotedString]]];

				while (index != NSNotFound) {

					id keyValue = [tableValues cellDataAtRow:index column:[[[tableDataInstance columnWithName:NSArrayObjectAtIndex(primaryKeyFieldNames,0)] objectForKey:@"datacolumnindex"] integerValue]];

					if([keyValue isKindOfClass:[NSData class]])
						[deleteQuery appendFormat:@"X'%@'", [mySQLConnection prepareBinaryData:keyValue]];
					else
						[deleteQuery appendFormat:@"'%@'", [keyValue description]];

					// Split deletion query into 256k chunks
					if([deleteQuery length] > 256000) {
						[deleteQuery appendString:@")"];
						[mySQLConnection queryString:deleteQuery];
						// Remember affected rows for error checking
						affectedRows += [mySQLConnection affectedRows];
						// Reinit a new deletion query
						[deleteQuery setString:[NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ IN (", [selectedTable backtickQuotedString], [NSArrayObjectAtIndex(primaryKeyFieldNames,0) backtickQuotedString]]];
					} else {
						[deleteQuery appendString:@","];
					}

					index = [selectedRows indexGreaterThanIndex:index];
				}

				// Check if deleteQuery's maximal length was reached for the last index
				// if yes omit the empty query
				if(![deleteQuery hasSuffix:@"("]) {
					// Replace final , by ) and delete the remaining rows
					[deleteQuery setString:[NSString stringWithFormat:@"%@)", [deleteQuery substringToIndex:([deleteQuery length]-1)]]];
					[mySQLConnection queryString:deleteQuery];
					// Remember affected rows for error checking
					affectedRows += [mySQLConnection affectedRows];
				}

				errors = (affectedRows > 0) ? [selectedRows count] - affectedRows : [selectedRows count];
			} else {
				// if table has more than one PRIMARY KEY
				// delete the row by using all PRIMARY KEYs in an OR clause
				NSMutableString *deleteQuery = [NSMutableString string];

				[deleteQuery setString:[NSString stringWithFormat:@"DELETE FROM %@ WHERE ", [selectedTable backtickQuotedString]]];

				while (index != NSNotFound) {

					// Build the AND clause of PRIMARY KEYS
					[deleteQuery appendString:@"("];
					[deleteQuery appendString:[self argumentForRow:index excludingLimits:YES]];
					[deleteQuery appendString:@")"];

					// Split deletion query into 64k chunks
					if([deleteQuery length] > 64000) {
						[mySQLConnection queryString:deleteQuery];
						// Remember affected rows for error checking
						affectedRows += [mySQLConnection affectedRows];
						// Reinit a new deletion query
						[deleteQuery setString:[NSString stringWithFormat:@"DELETE FROM %@ WHERE ", [selectedTable backtickQuotedString]]];
					} else {
						[deleteQuery appendString:@" OR "];
					}

					index = [selectedRows indexGreaterThanIndex:index];
				}

				// Check if deleteQuery's maximal length was reached for the last index
				// if yes omit the empty query
				if(![deleteQuery hasSuffix:@"WHERE "]) {
					// Remove final ' OR ' and delete the remaining rows
					[deleteQuery setString:[deleteQuery substringToIndex:([deleteQuery length]-4)]];
					[mySQLConnection queryString:deleteQuery];
					// Remember affected rows for error checking
					affectedRows += [mySQLConnection affectedRows];
				}

				errors = (affectedRows > 0) ? [selectedRows count] - affectedRows : [selectedRows count];
			}

			// Restore Console Log window's updating bahaviour
			[[SPQueryController sharedQueryController] setAllowConsoleUpdate:consoleUpdateStatus];

			if (errors) {
				NSArray *message;
				//TODO: The following three messages are NOT localisable!
				if (errors < 0) {
					message = [NSArray arrayWithObjects:NSLocalizedString(@"Warning", @"warning"),
							   [NSString stringWithFormat:NSLocalizedString(@"%ld row%@ more %@ deleted! Please check the Console and inform the Sequel Pro team!", @"message of panel when more rows were deleted"), (long)(errors*-1), ((errors*-1)>1)?@"s":@"", (errors>1)?@"were":@"was"],
							   nil];
				}
				else {
					if (primaryKeyFieldNames == nil)
						message = [NSArray arrayWithObjects:NSLocalizedString(@"Warning", @"warning"),
								   [NSString stringWithFormat:NSLocalizedString(@"%ld row%@ ha%@ not been deleted. Reload the table to be sure that the rows exist and use a primary key for your table.", @"message of panel when not all selected fields have been deleted"), (long)errors, (errors>1)?@"s":@"", (errors>1)?@"ve":@"s"],
								   nil];
					else
						message = [NSArray arrayWithObjects:NSLocalizedString(@"Warning", @"warning"),
								   [NSString stringWithFormat:NSLocalizedString(@"%ld row%@ ha%@ not been deleted. Reload the table to be sure that the rows exist and check the Console for possible errors inside the primary key%@ for your table.", @"message of panel when not all selected fields have been deleted by using primary keys"), (long)errors, (errors>1)?@"s":@"", (errors>1)?@"ve":@"s", (errors>1)?@"s":@""],
								   nil];
				}

				[self performSelector:@selector(showErrorSheetWith:)
						   withObject:message
						   afterDelay:0.3];
			}

			// Refresh table content
			if ( errors || reloadAfterRemovingRow ) {
				previousTableRowsCount = tableRowsCount;
				[self loadTableValues];
			} else {
				for ( i = tableRowsCount - 1 ; i >= 0 ; i-- ) {
					if ([selectedRows containsIndex:i]) [tableValues removeRowAtIndex:i];
				}
				tableRowsCount = [tableValues count];
				[tableContentView reloadData];

				// Update the maximum number of rows and the count text
				maxNumRows -= affectedRows;
				[self updateCountText];
			}
			[tableContentView deselectAll:self];
		} else {
			// The user clicked cancel in the "sure you wanna delete" message
			// restore editing or whatever
		}

	}
}


// Accessors

/**
 * Returns the current result (as shown in table content view) as array, the first object containing the field
 * names as array, the following objects containing the rows as array.
 */
- (NSArray *)currentDataResult
{
	NSArray *tableColumns;
	NSMutableArray *currentResult = [NSMutableArray array];
	NSMutableArray *tempRow = [NSMutableArray array];
	NSUInteger i;

	// Load table if not already done
	if ( ![tablesListInstance contentLoaded] ) {
		[self loadTable:[tablesListInstance tableName]];
	}

	tableColumns = [tableContentView tableColumns];

	// Set field names as first line
	for (NSTableColumn *aTableColumn in tableColumns) {
		[tempRow addObject:[[aTableColumn headerCell] stringValue]];
	}
	[currentResult addObject:[NSArray arrayWithArray:tempRow]];

	// Add rows
	for ( i = 0 ; i < [self numberOfRowsInTableView:tableContentView] ; i++) {
		[tempRow removeAllObjects];
		for (NSTableColumn *aTableColumn in tableColumns) {
			id o = SPDataStorageObjectAtRowAndColumn(tableValues, i, [[aTableColumn identifier] integerValue]);
			if ([o isNSNull])
				[tempRow addObject:@"NULL"];
			else if ([o isSPNotLoaded])
				[tempRow addObject:NSLocalizedString(@"(not loaded)", @"value shown for hidden blob and text fields")];
			else if([o isKindOfClass:[NSString class]])
				[tempRow addObject:[o description]];
			else {
				NSImage *image = [[NSImage alloc] initWithData:o];
				if (image) {
					NSInteger imageWidth = [image size].width;
					if (imageWidth > 100) imageWidth = 100;
					[tempRow addObject:[NSString stringWithFormat:
						@"<IMG WIDTH='%ld' SRC=\"data:image/auto;base64,%@\">",
						(long)imageWidth,
						[[image TIFFRepresentationUsingCompression:NSTIFFCompressionJPEG factor:0.01] base64EncodingWithLineLength:0]]];
				} else {
					[tempRow addObject:@"&lt;BLOB&gt;"];
				}
				if(image) [image release];
			}
		}
		[currentResult addObject:[NSArray arrayWithArray:tempRow]];
	}
	return currentResult;
}

/**
 * Returns the current result (as shown in table content view) as array, the first object containing the field
 * names as array, the following objects containing the rows as array.
 */
- (NSArray *)currentResult
{
	NSArray *tableColumns;
	NSMutableArray *currentResult = [NSMutableArray array];
	NSMutableArray *tempRow = [NSMutableArray array];
	NSUInteger i;

	// Load the table if not already loaded
	if ( ![tablesListInstance contentLoaded] ) {
		[self loadTable:[tablesListInstance tableName]];
	}

	tableColumns = [tableContentView tableColumns];

	// Add the field names as the first line
	for (NSTableColumn *aTableColumn in tableColumns) {
		[tempRow addObject:[[aTableColumn headerCell] stringValue]];
	}
	[currentResult addObject:[NSArray arrayWithArray:tempRow]];

	// Add the rows
	for ( i = 0 ; i < [self numberOfRowsInTableView:tableContentView] ; i++) {
		[tempRow removeAllObjects];
		for (NSTableColumn *aTableColumn in tableColumns) {
			[tempRow addObject:[self tableView:tableContentView objectValueForTableColumn:aTableColumn row:i]];
		}
		[currentResult addObject:[NSArray arrayWithArray:tempRow]];
	}

	return currentResult;
}

// Additional methods

/**
 * Sets the connection (received from SPDatabaseDocument) and makes things that have to be done only once
 */
- (void)setConnection:(MCPConnection *)theConnection
{
	mySQLConnection = theConnection;

	[tableContentView setVerticalMotionCanBeginDrag:NO];
}

/**
 * Performs the requested action - switching to another table
 * with the appropriate filter settings - when a link arrow is
 * selected.
 */
- (void)clickLinkArrow:(SPTextAndLinkCell *)theArrowCell
{
	if ([tableDocumentInstance isWorking]) return;

	if ([theArrowCell getClickedColumn] == NSNotFound || [theArrowCell getClickedRow] == NSNotFound) return;

	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;

	// If on the main thread, fire up a thread to perform the load while keeping the modification flag
	[tableDocumentInstance startTaskWithDescription:NSLocalizedString(@"Loading reference...", @"Loading referece task string")];
	if ([NSThread isMainThread]) {
		[NSThread detachNewThreadSelector:@selector(clickLinkArrowTask:) toTarget:self withObject:theArrowCell];
	} else {
		[self clickLinkArrowTask:theArrowCell];
	}
}
- (void)clickLinkArrowTask:(SPTextAndLinkCell *)theArrowCell
{
	NSAutoreleasePool *linkPool = [[NSAutoreleasePool alloc] init];
	NSUInteger dataColumnIndex = [[[[tableContentView tableColumns] objectAtIndex:[theArrowCell getClickedColumn]] identifier] integerValue];
	BOOL tableFilterRequired = NO;

	// Ensure the clicked cell has foreign key details available
	NSDictionary *refDictionary = [[dataColumns objectAtIndex:dataColumnIndex] objectForKey:@"foreignkeyreference"];
	if (!refDictionary) {
		[linkPool release];
		return;
	}

	// Save existing scroll position and details and mark that state is being modified
	[spHistoryControllerInstance updateHistoryEntries];
	[spHistoryControllerInstance setModifyingState:YES];

	NSString *targetFilterValue = [tableValues cellDataAtRow:[theArrowCell getClickedRow] column:dataColumnIndex];

	// If the link is within the current table, apply filter settings manually
	if ([[refDictionary objectForKey:@"table"] isEqualToString:selectedTable]) {
		[fieldField selectItemWithTitle:[refDictionary objectForKey:@"column"]];
		[self setCompareTypes:self];
		if ([targetFilterValue isNSNull]) {
			[compareField selectItemWithTitle:@"IS NULL"];
		} else {
			[argumentField setStringValue:targetFilterValue];
		}
		tableFilterRequired = YES;
	} else {

		// Store the filter details to use when loading the target table
		NSDictionary *filterSettings = [NSDictionary dictionaryWithObjectsAndKeys:
											[refDictionary objectForKey:@"column"], @"filterField",
											targetFilterValue, @"filterValue",
											([targetFilterValue isNSNull]?@"IS NULL":nil), @"filterComparison",
											nil];
		[self setFiltersToRestore:filterSettings];

		// Attempt to switch to the target table
		if (![tablesListInstance selectItemWithName:[refDictionary objectForKey:@"table"]]) {
			NSBeep();
			[self setFiltersToRestore:nil];
		}
	}

	// End state and ensure a new history entry
	[spHistoryControllerInstance setModifyingState:NO];
	[spHistoryControllerInstance updateHistoryEntries];

	// End the task
	[tableDocumentInstance endTask];

	// If the same table is the target, trigger a filter task on the main thread
	if (tableFilterRequired)
		[self performSelectorOnMainThread:@selector(filterTable:) withObject:self waitUntilDone:NO];

	// Empty the loading pool and exit the thread
	[linkPool drain];
}

/**
 * Sets the compare types for the filter and the appropriate formatter for the textField
 */
- (IBAction)setCompareTypes:(id)sender
{

	if(contentFilters == nil
		|| ![contentFilters objectForKey:@"number"]
		|| ![contentFilters objectForKey:@"string"]
		|| ![contentFilters objectForKey:@"date"]) {
		NSLog(@"Error while setting filter types.");
		NSBeep();
		return;
	}


	[compareField removeAllItems];

	NSString *fieldTypeGrouping;
	if([[tableDataInstance columnWithName:[[fieldField selectedItem] title]] objectForKey:@"typegrouping"])
		fieldTypeGrouping = [NSString stringWithString:[[tableDataInstance columnWithName:[[fieldField selectedItem] title]] objectForKey:@"typegrouping"]];
	else
		return;

	if ( [fieldTypeGrouping isEqualToString:@"date"] ) {
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
	} else if ([fieldTypeGrouping isEqualToString:@"string"]   || [fieldTypeGrouping isEqualToString:@"binary"]
			|| [fieldTypeGrouping isEqualToString:@"textdata"] || [fieldTypeGrouping isEqualToString:@"blobdata"]
			|| [fieldTypeGrouping isEqualToString:@"enum"]) {

		compareType = @"string";
		// [argumentField setFormatter:nil];

	} else if ([fieldTypeGrouping isEqualToString:@"bit"] || [fieldTypeGrouping isEqualToString:@"integer"]
				|| [fieldTypeGrouping isEqualToString:@"float"]) {
		compareType = @"number";
		// [argumentField setFormatter:numberFormatter];

	} else  {
		compareType = @"";
		NSBeep();
		NSLog(@"ERROR: unknown type for comparision: %@, in %@", [[tableDataInstance columnWithName:[[fieldField selectedItem] title]] objectForKey:@"type"], fieldTypeGrouping);
	}

	// Add IS NULL and IS NOT NULL as they should always be available
	// [compareField addItemWithTitle:@"IS NULL"];
	// [compareField addItemWithTitle:@"IS NOT NULL"];

	// Remove user-defined filters first
	if([numberOfDefaultFilters objectForKey:compareType]) {
		NSUInteger cycles = [[contentFilters objectForKey:compareType] count] - [[numberOfDefaultFilters objectForKey:compareType] integerValue];
		while(cycles > 0) {
			[[contentFilters objectForKey:compareType] removeLastObject];
			cycles--;
		}
	}

	// Load global user-defined content filters
	if([prefs objectForKey:SPContentFilters]
		&& [contentFilters objectForKey:compareType]
		&& [[prefs objectForKey:SPContentFilters] objectForKey:compareType])
	{
		[[contentFilters objectForKey:compareType] addObjectsFromArray:[[prefs objectForKey:SPContentFilters] objectForKey:compareType]];
	}

	// Load doc-based user-defined content filters
	if([[SPQueryController sharedQueryController] contentFilterForFileURL:[tableDocumentInstance fileURL]]) {
		id filters = [[SPQueryController sharedQueryController] contentFilterForFileURL:[tableDocumentInstance fileURL]];
		if([filters objectForKey:compareType])
			[[contentFilters objectForKey:compareType] addObjectsFromArray:[filters objectForKey:compareType]];
	}

	// Rebuild operator popup menu
	NSUInteger i = 0;
	NSMenu *menu = [compareField menu];
	if([contentFilters objectForKey:compareType])
		for(id filter in [contentFilters objectForKey:compareType]) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:([filter objectForKey:@"MenuLabel"])?[filter objectForKey:@"MenuLabel"]:@"not specified" action:NULL keyEquivalent:@""];
			// Create the tooltip
			if([filter objectForKey:@"Tooltip"])
				[item setToolTip:[filter objectForKey:@"Tooltip"]];
			else {
				NSMutableString *tip = [[NSMutableString alloc] init];
				if([filter objectForKey:@"Clause"] && [[filter objectForKey:@"Clause"] length]) {
					[tip setString:[[filter objectForKey:@"Clause"] stringByReplacingOccurrencesOfRegex:@"(?<!\\\\)(\\$\\{.*?\\})" withString:@"[arg]"]];
					if([tip isMatchedByRegex:@"(?<!\\\\)\\$BINARY"]) {
						[tip replaceOccurrencesOfRegex:@"(?<!\\\\)\\$BINARY" withString:@""];
						[tip appendString:NSLocalizedString(@"\n\nPress ⇧ for binary search (case-sensitive).", @"\n\npress shift for binary search tooltip message")];
					}
					[tip flushCachedRegexData];
					[tip replaceOccurrencesOfRegex:@"(?<!\\\\)\\$CURRENT_FIELD" withString:[[fieldField titleOfSelectedItem] backtickQuotedString]];
					[tip flushCachedRegexData];
					[item setToolTip:tip];
					[tip release];
				} else {
					[item setToolTip:@""];
				}
			}
			[item setTag:i];
			[menu addItem:item];
			[item release];
			i++;
		}

	[menu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Edit Filters…", @"edit filter") action:NULL keyEquivalent:@""];
	[item setToolTip:NSLocalizedString(@"Edit user-defined Filters…", @"edit user-defined filter")];
	[item setTag:i];
	[menu addItem:item];
	[item release];

	// Update the argumentField enabled state
	[self performSelectorOnMainThread:@selector(toggleFilterField:) withObject:self waitUntilDone:YES];

	// set focus on argumentField
	[argumentField performSelectorOnMainThread:@selector(selectText:) withObject:self waitUntilDone:YES];

}

- (void)openContentFilterManager
{
	[compareField selectItemWithTag:lastSelectedContentFilterIndex];

	// init query favorites controller
	[prefs synchronize];
	if(contentFilterManager) [contentFilterManager release];
	contentFilterManager = [[SPContentFilterManager alloc] initWithDelegate:self forFilterType:compareType];

	// Open query favorite manager
	[NSApp beginSheet:[contentFilterManager window]
	   modalForWindow:[tableDocumentInstance parentWindow]
		modalDelegate:contentFilterManager
	   didEndSelector:nil
		  contextInfo:nil];
}

/**
 * Tries to write a new row to the database.
 * Returns YES if row is written to database, otherwise NO; also returns YES if no row
 * is being edited and nothing has to be written to the database.
 */
- (BOOL)addRowToDB
{

	if([tablesListInstance tableType] == SPTableTypeView) return;

	NSMutableString *queryString;
	id rowObject;
	NSMutableString *rowValue = [NSMutableString string];
	NSString *currentTime = [[NSDate date] descriptionWithCalendarFormat:@"%H:%M:%S" timeZone:nil locale:nil];
	BOOL prefsLoadBlobsAsNeeded = [prefs boolForKey:SPLoadBlobsAsNeeded];
	NSInteger i;

	if ( !isEditingRow || currentlyEditingRow == -1) {
		return YES;
	}

	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryWillBePerformed" object:tableDocumentInstance];

	// If editing, compare the new row to the old row and if they are identical finish editing without saving.
	if (!isEditingNewRow && [oldRow isEqualToArray:[tableValues rowContentsAtIndex:currentlyEditingRow]]) {
		isEditingRow = NO;
		currentlyEditingRow = -1;
		[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];
		return YES;
	}

	NSMutableArray *fieldValues = [[NSMutableArray alloc] init];

	// Get the field values
	for ( i = 0 ; i < [dataColumns count] ; i++ ) {
		rowObject = [tableValues cellDataAtRow:currentlyEditingRow column:i];

		// Add not loaded placeholders directly for easy comparison when added
		if (prefsLoadBlobsAsNeeded && !isEditingNewRow && [rowObject isSPNotLoaded])
		{
			[fieldValues addObject:[SPNotLoaded notLoaded]];
			continue;

		// Catch CURRENT_TIMESTAMP automatic updates - if the row is new and the cell value matches
		// the default value, or if the cell hasn't changed, update the current timestamp.
		} else if ([[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"onupdatetimestamp"] integerValue]
					&& (   (isEditingNewRow && [rowObject isEqualTo:[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"default"]])
						|| (!isEditingNewRow && [rowObject isEqualTo:NSArrayObjectAtIndex(oldRow, i)])))
		{
			[rowValue setString:@"CURRENT_TIMESTAMP"];

		// Convert the object to a string (here we can add special treatment for date-, number- and data-fields)
		} else if ( [rowObject isNSNull]
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
				if ([[rowObject description] isEqualToString:@"CURRENT_TIMESTAMP"]) {
					[rowValue setString:@"CURRENT_TIMESTAMP"];
				} else if ([[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"typegrouping"] isEqualToString:@"bit"]) {
					[rowValue setString:[NSString stringWithFormat:@"b'%@'", ((![[rowObject description] length] || [[rowObject description] isEqualToString:@"0"]) ? @"0" : [rowObject description])]];
				} else if ([[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"typegrouping"] isEqualToString:@"date"]
							&& [[rowObject description] isEqualToString:@"NOW()"]) {
					[rowValue setString:@"NOW()"];
				} else {
					[rowValue setString:[NSString stringWithFormat:@"'%@'", [mySQLConnection prepareString:[rowObject description]]]];
				}
			}
		}
		[fieldValues addObject:[NSString stringWithString:rowValue]];
	}

	// Use INSERT syntax when creating new rows - no need to do not loaded checking, as all values have been entered
	if ( isEditingNewRow ) {
		queryString = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)",
					   [selectedTable backtickQuotedString], [[tableDataInstance columnNames] componentsJoinedAndBacktickQuoted], [fieldValues componentsJoinedByString:@","]];
	// Use UPDATE syntax otherwise
	} else {
		BOOL firstCellOutput = NO;
		queryString = [NSMutableString stringWithFormat:@"UPDATE %@ SET ", [selectedTable backtickQuotedString]];
		for ( i = 0 ; i < [dataColumns count] ; i++ ) {

			// If data column loading is deferred and the value is the not loaded string, skip this cell
			if (prefsLoadBlobsAsNeeded && [[fieldValues objectAtIndex:i] isSPNotLoaded]) continue;

			if (firstCellOutput) [queryString appendString:@", "];
			else firstCellOutput = YES;

			[queryString appendFormat:@"%@ = %@",
									   [[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"name"] backtickQuotedString], [fieldValues objectAtIndex:i]];
		}
		[queryString appendFormat:@" WHERE %@", [self argumentForRow:-2]];
	}

	[mySQLConnection queryString:queryString];

	[fieldValues release];
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];

	// If no rows have been changed, show error if appropriate.
	if ( ![mySQLConnection affectedRows] && ![mySQLConnection queryErrored] ) {
		if ( [prefs boolForKey:SPShowNoAffectedRowsError] ) {
			SPBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
							  NSLocalizedString(@"The row was not written to the MySQL database. You probably haven't changed anything.\nReload the table to be sure that the row exists and use a primary key for your table.\n(This error can be turned off in the preferences.)", @"message of panel when no rows have been affected after writing to the db"));
		} else {
			NSBeep();
		}
		[tableValues replaceRowAtIndex:currentlyEditingRow withRowContents:oldRow];
		isEditingRow = NO;
		isEditingNewRow = NO;
		currentlyEditingRow = -1;
		[[SPQueryController sharedQueryController] showErrorInConsole:[NSString stringWithFormat:NSLocalizedString(@"/* WARNING %@ No rows have been affected */\n", @"warning shown in the console when no rows have been affected after writing to the db"), currentTime] connection:[tableDocumentInstance name]];
		return YES;

	// On success...
	} else if ( ![mySQLConnection queryErrored] ) {
		isEditingRow = NO;

		// New row created successfully
		if ( isEditingNewRow ) {
			if ( [prefs boolForKey:SPReloadAfterAddingRow] ) {
				[[tableDocumentInstance parentWindow] endEditingFor:nil];
				previousTableRowsCount = tableRowsCount;
				[self loadTableValues];
			} else {

				// Set the insertId for fields with auto_increment
				for ( i = 0; i < [dataColumns count] ; i++ ) {
					if ([[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"autoincrement"] integerValue]) {
						[tableValues replaceObjectInRow:currentlyEditingRow column:i withObject:[[NSNumber numberWithLong:[mySQLConnection insertId]] description]];
					}
				}
			}
			isEditingNewRow = NO;

		// Existing row edited successfully
		} else {

			// Reload table if set to - otherwise no action required.
			if ( [prefs boolForKey:SPReloadAfterEditingRow] ) {
				[[tableDocumentInstance parentWindow] endEditingFor:nil];
				previousTableRowsCount = tableRowsCount;
				[self loadTableValues];
			}
		}
		currentlyEditingRow = -1;

		return YES;

	// Report errors which have occurred
	} else {
		SPBeginAlertSheet(NSLocalizedString(@"Couldn't write row", @"Couldn't write row error"), NSLocalizedString(@"Edit row", @"Edit row button"), NSLocalizedString(@"Discard changes", @"discard changes button"), nil, [tableDocumentInstance parentWindow], self, @selector(addRowErrorSheetDidEnd:returnCode:contextInfo:), nil,
						  [NSString stringWithFormat:NSLocalizedString(@"MySQL said:\n\n%@", @"message of panel when error while adding row to db"), [mySQLConnection getLastErrorMessage]]);
		return NO;
	}
}

/**
 * Handle the user decision as a result of an addRow error.
 */
- (void) addRowErrorSheetDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	// Order out current sheet to suppress overlapping of sheets
	[[alert window] orderOut:nil];

	// Edit row selected - reselect the row, and start editing.
	if ( returnCode == NSAlertDefaultReturn ) {
		[tableContentView selectRowIndexes:[NSIndexSet indexSetWithIndex:currentlyEditingRow] byExtendingSelection:NO];
		[tableContentView performSelector:@selector(keyDown:) withObject:[NSEvent keyEventWithType:NSKeyDown location:NSMakePoint(0,0) modifierFlags:0 timestamp:0 windowNumber:[[tableDocumentInstance parentWindow] windowNumber] context:[NSGraphicsContext currentContext] characters:nil charactersIgnoringModifiers:nil isARepeat:NO keyCode:0x24] afterDelay:0.0];

	// Discard changes selected
	} else {
		[self cancelRowEditing];
	}
	[tableContentView reloadData];
}

/**
 * A method to be called whenever the table selection changes; checks whether the current
 * row is being edited, and if so attempts to save it.  Returns YES if no save was necessary
 * or the save was successful, and NO if a save was necessary and failed - in which case further
 * editing is required.  In that case this method will reselect the row in question for reediting.
 */
- (BOOL)saveRowOnDeselect
{

	if([tablesListInstance tableType] == SPTableTypeView) {
		isSavingRow = NO;
		return YES;
	}

	// Save any edits which have been made but not saved to the table yet.
	[[tableDocumentInstance parentWindow] endEditingFor:nil];

	// If no rows are currently being edited, or a save is in progress, return success at once.
	if (!isEditingRow || isSavingRow) return YES;
	isSavingRow = YES;

	// Attempt to save the row, and return YES if the save succeeded.
	if ([self addRowToDB]) {
		isSavingRow = NO;
		return YES;
	}

	// Saving failed - return failure.
	isSavingRow = NO;
	return NO;
}

/**
 * Cancel active row editing, replacing the previous row if there was one
 * and resetting state.
 * Returns whether row editing was cancelled.
 */
- (BOOL)cancelRowEditing
{
	if (!isEditingRow) return NO;
	if (isEditingNewRow) {
		tableRowsCount--;
		[tableValues removeRowAtIndex:currentlyEditingRow];
		[self updateCountText];
		isEditingNewRow = NO;
	} else {
		[tableValues replaceRowAtIndex:currentlyEditingRow withRowContents:oldRow];
	}
	isEditingRow = NO;
	currentlyEditingRow = -1;
	[tableContentView reloadData];
	[[tableDocumentInstance parentWindow] makeFirstResponder:tableContentView];
	return YES;
}

/**
 * Returns the WHERE argument to identify a row.
 * If "row" is -2, it uses the oldRow.
 * Uses the primary key if available, otherwise uses all fields as argument and sets LIMIT to 1
 */
- (NSString *)argumentForRow:(NSInteger)row
{
	return [self argumentForRow:row excludingLimits:NO];
}

/**
 * Returns the WHERE argument to identify a row.
 * If "row" is -2, it uses the oldRow value.
 * "excludeLimits" controls whether a LIMIT 1 is appended if no primary key was available to
 * uniquely identify the row.
 */
- (NSString *)argumentForRow:(NSInteger)row excludingLimits:(BOOL)excludeLimits
{
	MCPResult *theResult;
	NSDictionary *theRow;
	id tempValue;
	NSMutableString *value = [NSMutableString string];
	NSMutableString *argument = [NSMutableString string];
	NSArray *columnNames;
	NSInteger i;

	if ( row == -1 )
		return @"";

	// Retrieve the field names for this table from the data cache.  This is used when requesting all data as part
	// of the fieldListForQuery method, and also to decide whether or not to preserve the current filter/sort settings.
	columnNames = [tableDataInstance columnNames];

	// Get the primary key if there is one
	if ( !keys ) {
		setLimit = NO;
		keys = [[NSMutableArray alloc] init];
		theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@", [selectedTable backtickQuotedString]]];
		[theResult setReturnDataAsStrings:YES];
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
		if ( [prefs boolForKey:SPLoadBlobsAsNeeded] && [self tableContainsBlobOrTextColumns] ) {
			SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
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
			tempValue = [tableValues cellDataAtRow:row column:[[[tableDataInstance columnWithName:NSArrayObjectAtIndex(keys, i)] objectForKey:@"datacolumnindex"] integerValue]];

		// Otherwise use the oldRow
		}
		else {
			tempValue = [oldRow objectAtIndex:[[[tableDataInstance columnWithName:NSArrayObjectAtIndex(keys, i)] objectForKey:@"datacolumnindex"] integerValue]];
		}

		if ([tempValue isNSNull]) {
			[argument appendFormat:@"%@ IS NULL", [NSArrayObjectAtIndex(keys, i) backtickQuotedString]];
		}
		else if ([tempValue isSPNotLoaded]) {
			NSLog(@"Exceptional case: SPNotLoaded object found for method “argumentForRow:”!");
			return @"";
		}
		else {
			// If the field is of type BIT then it needs a binary prefix
			if ([[[tableDataInstance columnWithName:NSArrayObjectAtIndex(keys, i)] objectForKey:@"type"] isEqualToString:@"BIT"]) {
				[value setString:[NSString stringWithFormat:@"b'%@'", [mySQLConnection prepareString:tempValue]]];
			}
			// BLOB/TEXT data
			else if ([tempValue isKindOfClass:[NSData class]])
				[value setString:[NSString stringWithFormat:@"X'%@'", [mySQLConnection prepareBinaryData:tempValue]]];
			else
				[value setString:[NSString stringWithFormat:@"'%@'", [mySQLConnection prepareString:tempValue]]];

			[argument appendFormat:@"%@ = %@", [NSArrayObjectAtIndex(keys, i) backtickQuotedString], value];
		}
	}

	if (setLimit && !excludeLimits) [argument appendString:@" LIMIT 1"];

	return argument;
}


/**
 * Returns YES if the table contains any columns which are of any of the blob or text types,
 * NO otherwise.
 */
- (BOOL)tableContainsBlobOrTextColumns
{
	NSInteger i;

	for ( i = 0 ; i < [dataColumns count]; i++ ) {
		if ( [tableDataInstance columnIsBlobOrText:[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"name"]] ) {
			return YES;
		}
	}

	return NO;
}

/**
 * Returns a string controlling which fields to retrieve for a query.  Returns * (all fields) if the preferences
 * option dontShowBlob isn't set; otherwise, returns a comma-separated list of all non-blob/text fields.
 */
- (NSString *)fieldListForQuery
{
	NSInteger i;
	NSMutableArray *fields = [NSMutableArray array];

	if (([prefs boolForKey:SPLoadBlobsAsNeeded]) && ([dataColumns count] > 0)) {

		NSArray *columnNames = [tableDataInstance columnNames];

		for (i = 0 ; i < [columnNames count]; i++)
		{
			if (![tableDataInstance columnIsBlobOrText:[NSArrayObjectAtIndex(dataColumns, i) objectForKey:@"name"]] ) {
					[fields addObject:[NSArrayObjectAtIndex(columnNames, i) backtickQuotedString]];
			}
			else {
				// For blob/text fields, select a null placeholder so the column count is still correct
				[fields addObject:@"NULL"];
			}
		}

		return [fields componentsJoinedByString:@","];
	}
	else {
		return @"*";
	}
}

/**
 * Check if table cell is editable
 * Returns as array the minimum number of possible changes or
 * -1 if no table name can be found or multiple table origins
 * -2 for other errors
 * and the used WHERE clause to identify
 */
- (NSArray*)fieldEditStatusForRow:(NSInteger)rowIndex andColumn:(NSInteger)columnIndex
{
	NSDictionary *columnDefinition = nil;

	// Retrieve the column defintion
	for(id c in cqColumnDefinition) {
		if([[c objectForKey:@"datacolumnindex"] isEqualToNumber:columnIndex]) {
			columnDefinition = [NSDictionary dictionaryWithDictionary:c];
			break;
		}
	}

	if(!columnDefinition)
		return [NSArray arrayWithObjects:[NSNumber numberWithInteger:-2], @"", nil];

	// Resolve the original table name for current column if AS was used
	NSString *tableForColumn = [columnDefinition objectForKey:@"org_table"];

	// Get the database name which the field belongs to
	NSString *dbForColumn = [columnDefinition objectForKey:@"db"];

	// No table/database name found indicates that the field's column contains data from more than one table as for UNION
	// or the field data are not bound to any table as in SELECT 1 or if column database is unset
	if(!tableForColumn || ![tableForColumn length] || !dbForColumn || ![dbForColumn length])
		return [NSArray arrayWithObjects:[NSNumber numberWithInteger:-1], @"", nil];

	// if table and database name are given check if field can be identified unambiguously
	// first without blob data
	NSString *fieldIDQueryStr = [self argumentForRow:rowIndex ofTable:tableForColumn andDatabase:[columnDefinition objectForKey:@"db"] includeBlobs:NO];
	if(!fieldIDQueryStr)
		return [NSArray arrayWithObjects:[NSNumber numberWithInteger:-1], @"", nil];

	[tableDocumentInstance startTaskWithDescription:NSLocalizedString(@"Checking field data for editing...", @"checking field data for editing task description")];

	// Actual check whether field can be identified bijectively
	MCPResult *tempResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SELECT COUNT(1) FROM %@.%@ %@",
		[[columnDefinition objectForKey:@"db"] backtickQuotedString],
		[tableForColumn backtickQuotedString],
		fieldIDQueryStr]];

	if ([mySQLConnection queryErrored]) {
		[tableDocumentInstance endTask];
		return [NSArray arrayWithObjects:[NSNumber numberWithInteger:-1], @"", nil];
	}

	NSArray *tempRow = [tempResult fetchRowAsArray];

	if([tempRow count] && [[tempRow objectAtIndex:0] integerValue] > 1) {
		// try to identify the cell by using blob data
		fieldIDQueryStr = [self argumentForRow:rowIndex ofTable:tableForColumn andDatabase:[columnDefinition objectForKey:@"db"] includeBlobs:YES];
		if(!fieldIDQueryStr) {
			[tableDocumentInstance endTask];
			return [NSArray arrayWithObjects:[NSNumber numberWithInteger:-1], @"", nil];
		}

		tempResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SELECT COUNT(1) FROM %@.%@ %@",
			[[columnDefinition objectForKey:@"db"] backtickQuotedString],
			[tableForColumn backtickQuotedString],
			fieldIDQueryStr]];

		if ([mySQLConnection queryErrored]) {
			[tableDocumentInstance endTask];
			return [NSArray arrayWithObjects:[NSNumber numberWithInteger:-1], @"", nil];
		}

		tempRow = [tempResult fetchRowAsArray];

		if([tempRow count] && [[tempRow objectAtIndex:0] integerValue] < 1) {
			[tableDocumentInstance endTask];
			return [NSArray arrayWithObjects:[NSNumber numberWithInteger:-1], @"", nil];
		}

	}

	[tableDocumentInstance endTask];

	if(fieldIDQueryStr == nil)
		fieldIDQueryStr = @"";

	return [NSArray arrayWithObjects:[NSNumber numberWithInteger:[[tempRow objectAtIndex:0] integerValue]], fieldIDQueryStr, nil];

}

/**
 * Close an open sheet.
 */
- (void)sheetDidEnd:(id)sheet returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo
{
	[sheet orderOut:self];
}

/**
 * Show Error sheet (can be called from inside of a endSheet selector)
 * via [self performSelector:@selector(showErrorSheetWithTitle:) withObject: afterDelay:]
 */
-(void)showErrorSheetWith:(id)error
{
	// error := first object is the title , second the message, only one button OK
	SPBeginAlertSheet([error objectAtIndex:0], NSLocalizedString(@"OK", @"OK button"),
			nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
			[error objectAtIndex:1]);
}

#pragma mark -
#pragma mark Filter Table

/**
 * Clear the filter table
 */
- (IBAction)tableFilterClear:(id)sender
{

	[filterTableView abortEditing];

	if(filterTableData && [filterTableData count]) {

		// Clear filter data
		for(NSNumber *col in [filterTableData allKeys])
			[[filterTableData objectForKey:col] setObject:[NSMutableArray arrayWithObjects:@"", @"", @"", @"", @"", @"", @"", @"", @"", @"", nil] forKey:@"filter"];

		[filterTableView reloadData];
		[filterTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
		[filterTableWhereClause setString:@""];

		// Reload table
		[self filterTable:nil];

	
	}
}

/**
 * Show filter table
 */
- (IBAction)showFilterTable:(id)sender
{
	[filterTableWindow makeKeyAndOrderFront:nil];
	[filterTableWhereClause setContinuousSpellCheckingEnabled:NO];
	[filterTableWhereClause setAutoindent:NO];
	[filterTableWhereClause setAutoindentIgnoresEnter:NO];
	[filterTableWhereClause setAutopair:[prefs boolForKey:SPCustomQueryAutoPairCharacters]];
	[filterTableWhereClause setAutohelp:NO];
	[filterTableWhereClause setAutouppercaseKeywords:[prefs boolForKey:SPCustomQueryAutoUppercaseKeywords]];
	[filterTableWhereClause setCompletionWasReinvokedAutomatically:NO];
	[filterTableWhereClause insertText:@""];
	[filterTableWhereClause didChangeText];
	[[tableDocumentInstance parentWindow] makeFirstResponder:filterTableView];
}

/**
 * Set filter table's Negate
 */
- (IBAction)toggleNegateClause:(id)sender
{
	filterTableNegate = !filterTableNegate;

	// If live search is set perform filtering
	if([filterTableLiveSearchCheckbox state] == NSOnState)
		[self filterTable:filterTableFilterButton];

}

/**
 * Set filter table's Distinct
 */
- (IBAction)toggleDistinctSelect:(id)sender
{
	filterTableDistinct = !filterTableDistinct;

	// If live search is set perform filtering
	if([filterTableLiveSearchCheckbox state] == NSOnState)
		[self filterTable:filterTableFilterButton];

}

/**
 * Set filter table's default operator
 */
- (IBAction)setDefaultOperator:(id)sender
{
	NSLog(@"DEFAULT");
}

- (IBAction)swapFilterTable:(id)sender
{
	NSLog(@"SWAP");
}

/**
 * Generate WHERE clause to look for last typed pattern in all fields
 */
- (IBAction)toggleLookAllFieldsMode:(id)sender
{
	[self updateFilterTableClause:sender];

	// If live search is set perform filtering
	if([filterTableLiveSearchCheckbox state] == NSOnState)
		[self filterTable:filterTableFilterButton];

}

#pragma mark -
#pragma mark Retrieving and setting table state

/**
 * Provide a getter for the table's sort column name
 */
- (NSString *) sortColumnName
{
	if (!sortCol || !dataColumns) return nil;

	return [[dataColumns objectAtIndex:[sortCol integerValue]] objectForKey:@"name"];
}

/**
 * Provide a getter for the table current sort order
 */
- (BOOL) sortColumnIsAscending
{
	return !isDesc;
}

/**
 * Provide a getter for the table's selected rows index set
 */
- (NSIndexSet *) selectedRowIndexes
{
	return [tableContentView selectedRowIndexes];
}

/**
 * Provide a getter for the page number
 */
- (NSUInteger) pageNumber
{
	return contentPage;
}

/**
 * Provide a getter for the table's current viewport
 */
- (NSRect) viewport
{
	return [tableContentView visibleRect];
}

/**
 * Provide a getter for the table's list view width
 */
- (CGFloat) tablesListWidth
{
	return [[[[tableDocumentInstance valueForKeyPath:@"contentViewSplitter"] subviews] objectAtIndex:0] frame].size.width;
}

/**
 * Provide a getter for the current filter details
 */
- (NSDictionary *) filterSettings
{
	NSDictionary *theDictionary;

	if (![fieldField isEnabled]) return nil;

	theDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
						[self tableFilterString], @"menuLabel",
						[[fieldField selectedItem] title], @"filterField",
						[[compareField selectedItem] title], @"filterComparison",
						[NSNumber numberWithInteger:[[compareField selectedItem] tag]], @"filterComparisonTag",
						[argumentField stringValue], @"filterValue",
						[firstBetweenField stringValue], @"firstBetweenField",
						[secondBetweenField stringValue], @"secondBetweenField",
						nil];

	return theDictionary;
}

/**
 * Set the sort column and sort order to restore on next table load
 */
- (void) setSortColumnNameToRestore:(NSString *)theSortColumnName isAscending:(BOOL)isAscending
{
	if (sortColumnToRestore) [sortColumnToRestore release], sortColumnToRestore = nil;

	if (theSortColumnName) {
		sortColumnToRestore = [[NSString alloc] initWithString:theSortColumnName];
		sortColumnToRestoreIsAsc = isAscending;
	}
}

/**
 * Sets the value for the page number to use on next table load
 */
- (void) setPageToRestore:(NSUInteger)thePage
{
	pageToRestore = thePage;
}

/**
 * Set the selected row indexes to restore on next table load
 */
- (void) setSelectedRowIndexesToRestore:(NSIndexSet *)theIndexSet
{
	if (selectionIndexToRestore) [selectionIndexToRestore release], selectionIndexToRestore = nil;

	if (theIndexSet) selectionIndexToRestore = [[NSIndexSet alloc] initWithIndexSet:theIndexSet];
}

/**
 * Set the viewport to restore on next table load
 */
- (void) setViewportToRestore:(NSRect)theViewport
{
	selectionViewportToRestore = theViewport;
}

/**
 * Set the filter settings to restore (if possible) on next table load
 */
- (void) setFiltersToRestore:(NSDictionary *)filterSettings
{
	if (filterFieldToRestore) [filterFieldToRestore release], filterFieldToRestore = nil;
	if (filterComparisonToRestore) [filterComparisonToRestore release], filterComparisonToRestore = nil;
	if (filterValueToRestore) [filterValueToRestore release], filterValueToRestore = nil;
	if (firstBetweenValueToRestore) [firstBetweenValueToRestore release], firstBetweenValueToRestore = nil;
	if (secondBetweenValueToRestore) [secondBetweenValueToRestore release], secondBetweenValueToRestore = nil;

	if (filterSettings) {
		if ([filterSettings objectForKey:@"filterField"])
			filterFieldToRestore = [[NSString alloc] initWithString:[filterSettings objectForKey:@"filterField"]];
		if ([filterSettings objectForKey:@"filterComparison"]) {
			// Check if operator is BETWEEN, if so set up input fields
			if([[filterSettings objectForKey:@"filterComparison"] isEqualToString:@"BETWEEN"]) {
				[argumentField setHidden:YES];
				[betweenTextField setHidden:NO];
				[firstBetweenField setHidden:NO];
				[secondBetweenField setHidden:NO];
				[firstBetweenField setEnabled:YES];
				[secondBetweenField setEnabled:YES];
			}

			filterComparisonToRestore = [[NSString alloc] initWithString:[filterSettings objectForKey:@"filterComparison"]];
		}
		if([[filterSettings objectForKey:@"filterComparison"] isEqualToString:@"BETWEEN"]) {
			if ([filterSettings objectForKey:@"firstBetweenField"])
				firstBetweenValueToRestore = [[NSString alloc] initWithString:[filterSettings objectForKey:@"firstBetweenField"]];
			if ([filterSettings objectForKey:@"secondBetweenField"])
				secondBetweenValueToRestore = [[NSString alloc] initWithString:[filterSettings objectForKey:@"secondBetweenField"]];
		} else {
			if ([filterSettings objectForKey:@"filterValue"] && ![[filterSettings objectForKey:@"filterValue"] isNSNull])
				filterValueToRestore = [[NSString alloc] initWithString:[filterSettings objectForKey:@"filterValue"]];
		}
	}
}

/**
 * Convenience method for storing all current settings for restoration
 */
- (void) storeCurrentDetailsForRestoration
{
	[self setSortColumnNameToRestore:[self sortColumnName] isAscending:[self sortColumnIsAscending]];
	[self setPageToRestore:[self pageNumber]];
	[self setSelectedRowIndexesToRestore:[self selectedRowIndexes]];
	[self setViewportToRestore:[self viewport]];
	[self setFiltersToRestore:[self filterSettings]];
}

/**
 * Convenience method for clearing any settings to restore
 */
- (void) clearDetailsToRestore
{
	[self setSortColumnNameToRestore:nil isAscending:YES];
	[self setPageToRestore:1];
	[self setSelectedRowIndexesToRestore:nil];
	[self setViewportToRestore:NSZeroRect];
	[self setFiltersToRestore:nil];
}

#pragma mark -
#pragma mark Table drawing and editing

/**
 * Updates the number of rows in the selected table.
 * Attempts to use the fullResult count if available, also updating the
 * table data store; otherwise, uses the table data store if accurate or
 * falls back to a fetch if necessary and set in preferences.
 * The prefs option "fetch accurate row counts" is used as a last resort as
 * it can be very slow on large InnoDB tables which require a full table scan.
 */
- (void)updateNumberOfRows
{
	BOOL checkStatusCount = NO;

	// For unfiltered and non-limited tables, use the result count - and update the status count
	if (!isLimited && !isFiltered && !isInterruptedLoad) {
		maxNumRows = tableRowsCount;
		maxNumRowsIsEstimate = NO;
		[tableDataInstance setStatusValue:[NSString stringWithFormat:@"%ld", (long)maxNumRows] forKey:@"Rows"];
		[tableDataInstance setStatusValue:@"y" forKey:@"RowsCountAccurate"];
		[[tableInfoInstance onMainThread] tableChanged:nil];
		[[[tableDocumentInstance valueForKey:@"extendedTableInfoInstance"] onMainThread] loadTable:selectedTable];

	// Otherwise, if the table status value is accurate, use it
	} else if ([[tableDataInstance statusValueForKey:@"RowsCountAccurate"] boolValue]) {
		maxNumRows = [[tableDataInstance statusValueForKey:@"Rows"] integerValue];
		maxNumRowsIsEstimate = NO;
		checkStatusCount = YES;

	// Choose whether to display an estimate, or to fetch the correct row count, based on prefs
	} else if ([[prefs objectForKey:SPTableRowCountQueryLevel] integerValue] == SPRowCountFetchAlways
				|| ([[prefs objectForKey:SPTableRowCountQueryLevel] integerValue] == SPRowCountFetchIfCheap
					&& [tableDataInstance statusValueForKey:@"Data_length"]
					&& [[prefs objectForKey:SPTableRowCountCheapSizeBoundary] integerValue] > [[tableDataInstance statusValueForKey:@"Data_length"] integerValue]))
	{
		maxNumRows = [self fetchNumberOfRows];
		maxNumRowsIsEstimate = NO;
		[tableDataInstance setStatusValue:[NSString stringWithFormat:@"%ld", (long)maxNumRows] forKey:@"Rows"];
		[tableDataInstance setStatusValue:@"y" forKey:@"RowsCountAccurate"];
		[[tableInfoInstance onMainThread] tableChanged:nil];
		[[[tableDocumentInstance valueForKey:@"extendedTableInfoInstance"] onMainThread] loadTable:selectedTable];

	// Use the estimate count
	} else {
		maxNumRows = [[tableDataInstance statusValueForKey:@"Rows"] integerValue];
		maxNumRowsIsEstimate = YES;
		checkStatusCount = YES;
	}

	// Check whether the estimated count requires updating, ie if the retrieved count exceeds it
	if (checkStatusCount) {
		NSInteger foundMaxRows;
		if ([prefs boolForKey:SPLimitResults]) {
			foundMaxRows = ((contentPage - 1) * [prefs integerForKey:SPLimitResultsValue]) + tableRowsCount;
			if (foundMaxRows > maxNumRows) {
				if (tableRowsCount == [prefs integerForKey:SPLimitResultsValue]) {
					maxNumRows = foundMaxRows + 1;
					maxNumRowsIsEstimate = YES;
				} else {
					maxNumRows = foundMaxRows;
					maxNumRowsIsEstimate = NO;
				}
			} else if (!isInterruptedLoad && !isFiltered && tableRowsCount < [prefs integerForKey:SPLimitResultsValue]) {
				maxNumRows = foundMaxRows;
				maxNumRowsIsEstimate = NO;
			}
		} else if (tableRowsCount > maxNumRows) {
			maxNumRows = tableRowsCount;
			maxNumRowsIsEstimate = YES;
		}
		[tableDataInstance setStatusValue:[NSString stringWithFormat:@"%ld", (long)maxNumRows] forKey:@"Rows"];
		[tableDataInstance setStatusValue:maxNumRowsIsEstimate?@"n":@"y" forKey:@"RowsCountAccurate"];
		[[tableInfoInstance onMainThread] tableChanged:nil];
	}
}

/**
 * Fetches the number of rows in the selected table using a "SELECT COUNT(1)" query and return it
 */
- (NSInteger)fetchNumberOfRows
{
	return [[[[mySQLConnection queryString:[NSString stringWithFormat:@"SELECT COUNT(1) FROM %@", [selectedTable backtickQuotedString]]] fetchRowAsArray] objectAtIndex:0] integerValue];
}

/**
 * Autosize all columns based on their content.
 * Should be called on the main thread.
 */
- (void)autosizeColumns
{
	if (isWorking) pthread_mutex_lock(&tableValuesLock);
	NSDictionary *columnWidths = [tableContentView autodetectColumnWidths];
	if (isWorking) pthread_mutex_unlock(&tableValuesLock);
	[tableContentView setDelegate:nil];
	for (NSDictionary *columnDefinition in dataColumns) {

		// Skip columns with saved widths
		if ([[[[prefs objectForKey:SPTableColumnWidths] objectForKey:[NSString stringWithFormat:@"%@@%@", [tableDocumentInstance database], [tableDocumentInstance host]]] objectForKey:[tablesListInstance tableName]] objectForKey:[columnDefinition objectForKey:@"name"]]) continue;

		// Otherwise set the column width
		NSTableColumn *aTableColumn = [tableContentView tableColumnWithIdentifier:[columnDefinition objectForKey:@"datacolumnindex"]];
		NSUInteger targetWidth = [[columnWidths objectForKey:[columnDefinition objectForKey:@"datacolumnindex"]] unsignedIntegerValue];
		[aTableColumn setWidth:targetWidth];
	}
	[tableContentView setDelegate:self];
}

#pragma mark -
#pragma mark TableView delegate methods

/**
 * Show the table cell content as tooltip
 * - for text displays line breaks and tabs as well
 * - if blob data can be interpret as image data display the image as  transparent thumbnail
 *    (up to now using base64 encoded HTML data)
 */
- (NSString *)tableView:(NSTableView *)aTableView toolTipForCell:(SPTextAndLinkCell *)aCell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{

	if(aTableView == filterTableView) {
		return nil;
	}
	else if(aTableView == tableContentView) {

		if([[aCell stringValue] length] < 2 || [tableDocumentInstance isWorking]) return nil;

		NSImage *image;

		NSPoint pos = [NSEvent mouseLocation];
		pos.y -= 20;

		// Try to get the original data. If not possible return nil.
		// @try clause is used due to the multifarious cases of
		// possible exceptions (eg for reloading tables etc.)
		id theValue;
		@try{
			theValue = [tableValues cellDataAtRow:row column:[[aTableColumn identifier] integerValue]];
		}
		@catch(id ae) {
			return nil;
		}

		// Get the original data for trying to display the blob data as an image
		if ([theValue isKindOfClass:[NSData class]]) {
			image = [[[NSImage alloc] initWithData:theValue] autorelease];
			if(image) {
				[SPTooltip showWithObject:image atLocation:pos ofType:@"image"];
				return nil;
			}
		}

		// Show the cell string value as tooltip (including line breaks and tabs)
		// by using the cell's font
		[SPTooltip showWithObject:[aCell stringValue]
				atLocation:pos
					ofType:@"text"
			displayOptions:[NSDictionary dictionaryWithObjectsAndKeys:
						[[aCell font] familyName], @"fontname",
						[NSString stringWithFormat:@"%f",[[aCell font] pointSize]], @"fontsize",
						nil]];

		return nil;
	}
}

- (NSInteger)numberOfRowsInTableView:(SPCopyTable *)aTableView
{
	if(aTableView == filterTableView) {
		return [[[filterTableData objectForKey:[NSNumber numberWithInteger:0]] objectForKey:@"filter"] count];
	}
	else if(aTableView == tableContentView) {
		return tableRowsCount;
	}
}

- (id)tableView:(SPCopyTable *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{

	if(aTableView == filterTableView) {
		return NSArrayObjectAtIndex([[filterTableData objectForKey:[aTableColumn identifier]] objectForKey:@"filter"], rowIndex);
	}
	else if(aTableView == tableContentView) {

		NSUInteger columnIndex = [[aTableColumn identifier] integerValue];
		id theValue = nil;

		// While the table is being loaded, additional validation is required - data
		// locks must be used to avoid crashes, and indexes higher than the available
		// rows or columns may be requested.  Return "..." to indicate loading in these
		// cases.
		if (isWorking) {
			pthread_mutex_lock(&tableValuesLock);
			if (rowIndex < tableRowsCount && columnIndex < [tableValues columnCount]) {
				theValue = [[SPDataStorageObjectAtRowAndColumn(tableValues, rowIndex, columnIndex) copy] autorelease];
			}
			pthread_mutex_unlock(&tableValuesLock);

			if (!theValue) return @"...";
		} else {
			theValue = SPDataStorageObjectAtRowAndColumn(tableValues, rowIndex, columnIndex);
		}

		if ([theValue isNSNull])
			return [prefs objectForKey:SPNullValue];

		if ([theValue isKindOfClass:[NSData class]])
			return [theValue shortStringRepresentationUsingEncoding:[mySQLConnection stringEncoding]];

		if ([theValue isSPNotLoaded])
			return NSLocalizedString(@"(not loaded)", @"value shown for hidden blob and text fields");

		return theValue;
	}
}

/**
 * This function changes the text color of text/blob fields which are null or not yet loaded to gray
 */
- (void)tableView:(SPCopyTable *)aTableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{

	if(aTableView == filterTableView) {
		return;
	}
	else if(aTableView == tableContentView) {

		if (![cell respondsToSelector:@selector(setTextColor:)]) return;

		NSUInteger columnIndex = [[aTableColumn identifier] integerValue];
		id theValue = nil;

		// While the table is being loaded, additional validation is required - data
		// locks must be used to avoid crashes, and indexes higher than the available
		// rows or columns may be requested.  Use gray to indicate loading in these cases.
		if (isWorking) {
			pthread_mutex_lock(&tableValuesLock);
			if (rowIndex < tableRowsCount && columnIndex < [tableValues columnCount]) {
				theValue = SPDataStorageObjectAtRowAndColumn(tableValues, rowIndex, columnIndex);
			}
			pthread_mutex_unlock(&tableValuesLock);

			if (!theValue) {
				[cell setTextColor:[NSColor lightGrayColor]];
				return;
			}
		} else {
			theValue = SPDataStorageObjectAtRowAndColumn(tableValues, rowIndex, columnIndex);
		}

		// If user wants to edit 'cell' set text color to black and return to avoid
		// writing in gray if value was NULL
		if ([aTableView editedColumn] != -1
			&& [aTableView editedRow] == rowIndex
			&& [[NSArrayObjectAtIndex([aTableView tableColumns], [aTableView editedColumn]) identifier] integerValue] == columnIndex) {
			[cell setTextColor:[NSColor blackColor]];
			return;
		}

		// For null cells and not loaded cells, display the contents in gray.
		if ([theValue isNSNull] || [theValue isSPNotLoaded]) {
			[cell setTextColor:[NSColor lightGrayColor]];

		// Otherwise, set the color to black - required as NSTableView reuses NSCells.
		} else {
			[cell setTextColor:[NSColor blackColor]];
		}
	}
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if(aTableView == filterTableView) {
		[[[filterTableData objectForKey:[aTableColumn identifier]] objectForKey:@"filter"] replaceObjectAtIndex:rowIndex withObject:(NSString*)anObject];
		[self updateFilterTableClause:nil];
		return;
	}
	else if(aTableView == tableContentView) {
		// If table data come from a view
		if([tablesListInstance tableType] == SPTableTypeView) {

			// Field editing
			// if (fieldIDQueryString == nil) return;
			NSDictionary *columnDefinition;

			// Retrieve the column defintion
			for(id c in cqColumnDefinition) {
				if([[c objectForKey:@"datacolumnindex"] isEqualToNumber:[aTableColumn identifier]]) {
					columnDefinition = [NSDictionary dictionaryWithDictionary:c];
					break;
				}
			}

			// Resolve the original table name for current column if AS was used
			NSString *tableForColumn = [columnDefinition objectForKey:@"org_table"];

			if(!tableForColumn || ![tableForColumn length]) {
				NSPoint pos = [NSEvent mouseLocation];
				pos.y -= 20;
				[SPTooltip showWithObject:NSLocalizedString(@"Field is not editable. Field has no or multiple table or database origin(s).",@"field is not editable due to no table/database")
						atLocation:pos
						ofType:@"text"];
				NSBeep();
				return;
			}

			// Resolve the original column name if AS was used
			NSString *columnName = [columnDefinition objectForKey:@"org_name"];

			[tableDocumentInstance startTaskWithDescription:NSLocalizedString(@"Updating field data...", @"updating field task description")];
			[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:tableDocumentInstance];

			[self storeCurrentDetailsForRestoration];

			// Check if the IDstring identifies the current field bijectively and get the WHERE clause
			NSArray *editStatus = [self fieldEditStatusForRow:rowIndex andColumn:[aTableColumn identifier]];
			NSString *fieldIDQueryStr = [editStatus objectAtIndex:1];
			NSInteger numberOfPossibleUpdateRows = [[editStatus objectAtIndex:0] integerValue];

			if(numberOfPossibleUpdateRows == 1) {

				NSString *newObject = nil;
				if ( [anObject isKindOfClass:[NSCalendarDate class]] ) {
					newObject = [NSString stringWithFormat:@"'%@'", [mySQLConnection prepareString:[anObject description]]];
				} else if ( [anObject isKindOfClass:[NSNumber class]] ) {
					newObject = [anObject stringValue];
				} else if ( [anObject isKindOfClass:[NSData class]] ) {
					newObject = [NSString stringWithFormat:@"X'%@'", [mySQLConnection prepareBinaryData:anObject]];
				} else {
					if ( [[anObject description] isEqualToString:@"CURRENT_TIMESTAMP"] ) {
						newObject = @"CURRENT_TIMESTAMP";
					} else if([anObject isEqualToString:[prefs stringForKey:SPNullValue]]) {
						newObject = @"NULL";
					} else if ([[columnDefinition objectForKey:@"typegrouping"] isEqualToString:@"bit"]) {
						newObject = [NSString stringWithFormat:@"b'%@'", ((![[anObject description] length] || [[anObject description] isEqualToString:@"0"]) ? @"0" : [anObject description])];
					} else if ([[columnDefinition objectForKey:@"typegrouping"] isEqualToString:@"date"]
								&& [[anObject description] isEqualToString:@"NOW()"]) {
						newObject = @"NOW()";
					} else {
						newObject = [NSString stringWithFormat:@"'%@'", [mySQLConnection prepareString:[anObject description]]];
					}
				}

				[mySQLConnection queryString:
					[NSString stringWithFormat:@"UPDATE %@.%@ SET %@.%@.%@ = %@ %@ LIMIT 1",
						[[columnDefinition objectForKey:@"db"] backtickQuotedString], [tableForColumn backtickQuotedString],
						[[columnDefinition objectForKey:@"db"] backtickQuotedString], [tableForColumn backtickQuotedString], [columnName backtickQuotedString], newObject, fieldIDQueryStr]];


				// Check for errors while UPDATE
				if ([mySQLConnection queryErrored]) {
					SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), NSLocalizedString(@"Cancel", @"cancel button"), nil, [tableDocumentInstance parentWindow], self, nil, nil,
									  [NSString stringWithFormat:NSLocalizedString(@"Couldn't write field.\nMySQL said: %@", @"message of panel when error while updating field to db"), [mySQLConnection getLastErrorMessage]]);

					[tableDocumentInstance endTask];
					[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];
					return;
				}


				// This shouldn't happen – for safety reasons
				if ( ![mySQLConnection affectedRows] ) {
					if ( [prefs boolForKey:SPShowNoAffectedRowsError] ) {
						SPBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
										  NSLocalizedString(@"The row was not written to the MySQL database. You probably haven't changed anything.\nReload the table to be sure that the row exists and use a primary key for your table.\n(This error can be turned off in the preferences.)", @"message of panel when no rows have been affected after writing to the db"));
					} else {
						NSBeep();
					}
					[tableDocumentInstance endTask];
					[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];
					return;
				}

			} else {
				SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
								  [NSString stringWithFormat:NSLocalizedString(@"Updating field content failed. Couldn't identify field origin unambiguously (%ld match%@). It's very likely that while editing this field the table `%@` was changed by an other user.", @"message of panel when error while updating field to db after enabling it"),
											(long)numberOfPossibleUpdateRows, (numberOfPossibleUpdateRows>1)?@"es":@"", tableForColumn]);

				[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];
				[tableDocumentInstance endTask];
				return;

			}


			// Reload table after each editing due to complex declarations
			if(isFirstChangeInView) {
				// Set up the table details for the new table, and trigger an interface update
				// if the view was modified for the very first time
				NSDictionary *tableDetails = [NSDictionary dictionaryWithObjectsAndKeys:
												tableForColumn, @"name",
												[tableDataInstance columns], @"columns",
												[tableDataInstance columnNames], @"columnNames",
												[tableDataInstance getConstraints], @"constraints",
												nil];
				[self performSelectorOnMainThread:@selector(setTableDetails:) withObject:tableDetails waitUntilDone:YES];
				isFirstChangeInView = NO;
			}
			[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];
			[tableDocumentInstance endTask];

			[self loadTableValues];

			return;

		}

		// Catch editing events in the row and if the row isn't currently being edited,
		// start an edit.  This allows edits including enum changes to save correctly.
		if ( !isEditingRow ) {
			[oldRow setArray:[tableValues rowContentsAtIndex:rowIndex]];
			isEditingRow = YES;
			currentlyEditingRow = rowIndex;
		}

		NSDictionary *column = NSArrayObjectAtIndex(dataColumns, [[aTableColumn identifier] integerValue]);

		if (anObject) {

			// Restore NULLs if necessary
			if ([anObject isEqualToString:[prefs objectForKey:SPNullValue]] && [[column objectForKey:@"null"] boolValue])
				anObject = [NSNull null];

			[tableValues replaceObjectInRow:rowIndex column:[[aTableColumn identifier] integerValue] withObject:anObject];
		} else {
			[tableValues replaceObjectInRow:rowIndex column:[[aTableColumn identifier] integerValue] withObject:@""];
		}
	}
}

#pragma mark -
#pragma mark TableView delegate methods

/**
 * Sorts the tableView by the clicked column.
 * If clicked twice, order is altered to descending.
 * Performs the task in a new thread if necessary.
 */
- (void)tableView:(NSTableView*)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{

	if ( [selectedTable isEqualToString:@""] || !selectedTable || tableView != tableContentView )
		return;

	// Prevent sorting while the table is still loading
	if ([tableDocumentInstance isWorking]) return;

	// Start the task
	[tableDocumentInstance startTaskWithDescription:NSLocalizedString(@"Sorting table...", @"Sorting table task description")];
	if ([NSThread isMainThread]) {
		[NSThread detachNewThreadSelector:@selector(sortTableTaskWithColumn:) toTarget:self withObject:tableColumn];
	} else {
		[self sortTableTaskWithColumn:tableColumn];
	}
}

- (void)sortTableTaskWithColumn:(NSTableColumn *)tableColumn
{
	NSAutoreleasePool *sortPool = [[NSAutoreleasePool alloc] init];

	// Check whether a save of the current row is required.
	if (![[self onMainThread] saveRowOnDeselect]) {
		[sortPool drain];
		return;
	}

	// Sets column order as tri-state descending, ascending, no sort, descending, ascending etc. order if the same
	// header is clicked several times
	if ([[tableColumn identifier] isEqualTo:sortCol]) {
		if(isDesc) {
			[sortCol release];
			sortCol = nil;
		} else {
			if (sortCol) [sortCol release];
			sortCol = [[NSNumber alloc] initWithInteger:[[tableColumn identifier] integerValue]];
			isDesc = !isDesc;
		}
	} else {
		isDesc = NO;
		[[tableContentView onMainThread] setIndicatorImage:nil inTableColumn:[tableContentView tableColumnWithIdentifier:sortCol]];
		if (sortCol) [sortCol release];
		sortCol = [[NSNumber alloc] initWithInteger:[[tableColumn identifier] integerValue]];
	}

	if(sortCol) {
		// Set the highlight and indicatorImage
		[[tableContentView onMainThread] setHighlightedTableColumn:tableColumn];
		if (isDesc) {
			[[tableContentView onMainThread] setIndicatorImage:[NSImage imageNamed:@"NSDescendingSortIndicator"] inTableColumn:tableColumn];
		} else {
			[[tableContentView onMainThread] setIndicatorImage:[NSImage imageNamed:@"NSAscendingSortIndicator"] inTableColumn:tableColumn];
		}
	} else {
		// If no sort order deselect column header and
		// remove indicator image
		[[tableContentView onMainThread] setHighlightedTableColumn:nil];
		[[tableContentView onMainThread] setIndicatorImage:nil inTableColumn:tableColumn];
	}

	// Update data using the new sort order
	previousTableRowsCount = tableRowsCount;
	[self loadTableValues];

	if ([mySQLConnection queryErrored]) {
		SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
						  [NSString stringWithFormat:NSLocalizedString(@"Couldn't sort table. MySQL said: %@", @"message of panel when sorting of table failed"), [mySQLConnection getLastErrorMessage]]);
		[tableDocumentInstance endTask];
		[sortPool drain];
		return;
	}

	[tableDocumentInstance endTask];
	[sortPool drain];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{

	// Check our notification object is our table content view
	if ([aNotification object] != tableContentView) return;

	isFirstChangeInView = YES;


	[addButton setEnabled:([tablesListInstance tableType] == SPTableTypeTable)];

	// If we are editing a row, attempt to save that row - if saving failed, reselect the edit row.
	if (isEditingRow && [tableContentView selectedRow] != currentlyEditingRow && ![self saveRowOnDeselect]) return;

	if (![tableDocumentInstance isWorking]) {
		// Update the row selection count
		// and update the status of the delete/duplicate buttons
		if([tablesListInstance tableType] == SPTableTypeTable) {
			if ([tableContentView numberOfSelectedRows] > 0) {
				[copyButton setEnabled:([tableContentView numberOfSelectedRows] == 1)];
				[removeButton setEnabled:YES];
			}
			else {
				[copyButton setEnabled:NO];
				[removeButton setEnabled:NO];
			}
		} else {
			[copyButton setEnabled:NO];
			[removeButton setEnabled:NO];
		}
	}

	[self updateCountText];
}

/**
 saves the new column size in the preferences
 */
- (void)tableViewColumnDidResize:(NSNotification *)aNotification
{

	// Check our notification object is our table content view
	if ([aNotification object] != tableContentView) return;

	// sometimes the column has no identifier. I can't figure out what is causing it, so we just skip over this item
	if (![[[aNotification userInfo] objectForKey:@"NSTableColumn"] identifier])
		return;

	NSMutableDictionary *tableColumnWidths;
	NSString *database = [NSString stringWithFormat:@"%@@%@", [tableDocumentInstance database], [tableDocumentInstance host]];
	NSString *table = [tablesListInstance tableName];

	// get tableColumnWidths object
	if ( [prefs objectForKey:SPTableColumnWidths] != nil ) {
		tableColumnWidths = [NSMutableDictionary dictionaryWithDictionary:[prefs objectForKey:SPTableColumnWidths]];
	} else {
		tableColumnWidths = [NSMutableDictionary dictionary];
	}
	// get database object
	if  ( [tableColumnWidths objectForKey:database] == nil ) {
		[tableColumnWidths setObject:[NSMutableDictionary dictionary] forKey:database];
	} else {
		[tableColumnWidths setObject:[NSMutableDictionary dictionaryWithDictionary:[tableColumnWidths objectForKey:database]] forKey:database];

	}
	// get table object
	if  ( [[tableColumnWidths objectForKey:database] objectForKey:table] == nil ) {
		[[tableColumnWidths objectForKey:database] setObject:[NSMutableDictionary dictionary] forKey:table];
	} else {
		[[tableColumnWidths objectForKey:database] setObject:[NSMutableDictionary dictionaryWithDictionary:[[tableColumnWidths objectForKey:database] objectForKey:table]] forKey:table];

	}
	// save column size
	[[[tableColumnWidths objectForKey:database] objectForKey:table] setObject:[NSNumber numberWithDouble:[(NSTableColumn *)[[aNotification userInfo] objectForKey:@"NSTableColumn"] width]] forKey:[[[[aNotification userInfo] objectForKey:@"NSTableColumn"] headerCell] stringValue]];
	[prefs setObject:tableColumnWidths forKey:SPTableColumnWidths];
}

/**
 * Confirm whether to allow editing of a row. Returns YES by default, unless the multipleLineEditingButton is in
 * the ON state, or for blob or text fields - in those cases opens a sheet for editing instead and returns NO.
 */
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ([tableDocumentInstance isWorking]) return NO;

	if ( aTableView == tableContentView ) {

		// Ensure that row is editable since it could contain "(not loaded)" columns together with
		// issue that the table has no primary key
		NSString *wherePart = [NSString stringWithString:[self argumentForRow:[tableContentView selectedRow]]];
		if ([wherePart length] == 0) return NO;

		// If the selected cell hasn't been loaded, load it.
		if ([[tableValues cellDataAtRow:rowIndex column:[[aTableColumn identifier] integerValue]] isSPNotLoaded]) {

			// Only get the data for the selected column, not all of them
			NSString *query = [NSString stringWithFormat:@"SELECT %@ FROM %@ WHERE %@", [[[aTableColumn headerCell] stringValue] backtickQuotedString], [selectedTable backtickQuotedString], wherePart];

			MCPResult *tempResult = [mySQLConnection queryString:query];
			if (![tempResult numOfRows]) {
				SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, [tableDocumentInstance parentWindow], self, nil, nil,
								  NSLocalizedString(@"Couldn't load the row. Reload the table to be sure that the row exists and use a primary key for your table.", @"message of panel when loading of row failed"));
				return NO;
			}

			NSArray *tempRow = [tempResult fetchRowAsArray];
			[tableValues replaceObjectInRow:rowIndex column:[[tableContentView tableColumns] indexOfObject:aTableColumn] withObject:[tempRow objectAtIndex:0]];
			[tableContentView reloadData];
		}

		BOOL isBlob = [tableDataInstance columnIsBlobOrText:[[aTableColumn headerCell] stringValue]];
		BOOL isFieldEditable = YES;


		// Open the sheet if the multipleLineEditingButton is enabled or the column was a blob or a text.
		if ([multipleLineEditingButton state] == NSOnState || isBlob) {

			// A table is per definitionem editable
			isFieldEditable = YES;

			// Check for Views if field is editable
			if([tablesListInstance tableType] == SPTableTypeView) {
				NSArray *editStatus = [self fieldEditStatusForRow:rowIndex andColumn:[aTableColumn identifier]];
				isFieldEditable = ([[editStatus objectAtIndex:0] integerValue] == 1) ? YES : NO;
			}

			NSString *fieldType = nil;
			NSUInteger *fieldLength = 0;
			NSString *fieldEncoding = nil;
			BOOL allowNULL = YES;

			// Retrieve the column defintion
			for(id c in cqColumnDefinition) {
				if([[c objectForKey:@"datacolumnindex"] isEqualToNumber:[aTableColumn identifier]]) {
					fieldType = [c objectForKey:@"type"];
					if([c objectForKey:@"char_length"])
						fieldLength = [[c objectForKey:@"char_length"] integerValue];
					if([c objectForKey:@"null"])
						allowNULL = (![[c objectForKey:@"null"] integerValue]);
					if([c objectForKey:@"charset_name"] && ![[c objectForKey:@"charset_name"] isEqualToString:@"binary"])
						fieldEncoding = [c objectForKey:@"charset_name"];
					break;
				}
			}

			SPFieldEditorController *fieldEditor = [[SPFieldEditorController alloc] init];

			[fieldEditor setTextMaxLength:fieldLength];
			[fieldEditor setFieldType:(fieldType==nil) ? @"" : fieldType];
			[fieldEditor setFieldEncoding:(fieldEncoding==nil) ? @"" : fieldEncoding];
			[fieldEditor setAllowNULL:allowNULL];

			id cellValue = [tableValues cellDataAtRow:rowIndex column:[[aTableColumn identifier] integerValue]];
			if ([cellValue isNSNull]) cellValue = [NSString stringWithString:[prefs objectForKey:SPNullValue]];

			id editData = [[fieldEditor editWithObject:cellValue
										 fieldName:[[aTableColumn headerCell] stringValue]
									 usingEncoding:[mySQLConnection stringEncoding]
									  isObjectBlob:isBlob
										isEditable:isFieldEditable
										withWindow:[tableDocumentInstance parentWindow]] retain];

			if (editData) {
				if (!isEditingRow && [tablesListInstance tableType] != SPTableTypeView) {
					[oldRow setArray:[tableValues rowContentsAtIndex:rowIndex]];
					isEditingRow = YES;
					currentlyEditingRow = rowIndex;
				}

				if ([editData isKindOfClass:[NSString class]]
					&& [editData isEqualToString:[prefs objectForKey:SPNullValue]]
					&& [[NSArrayObjectAtIndex(dataColumns, [[aTableColumn identifier] integerValue]) objectForKey:@"null"] boolValue])
				{
					[editData release];
					editData = [[NSNull null] retain];
				}
				if(isFieldEditable) {
					if([tablesListInstance tableType] == SPTableTypeView) {
						// since in a view we're editing a field rather than a row
						isEditingRow = NO;
						// update the field and refresh the table
						[self tableView:aTableView setObjectValue:[[editData copy] autorelease] forTableColumn:aTableColumn row:rowIndex];
					} else {
						[tableValues replaceObjectInRow:rowIndex column:[[aTableColumn identifier] integerValue] withObject:[[editData copy] autorelease]];
					}
				}
			}

			[fieldEditor release];

			if (editData) [editData release];

			[[tableDocumentInstance parentWindow] makeFirstResponder:tableContentView];

			return NO;
		}

		return YES;
	}

	return YES;
}

/**
 * Enable drag from tableview
 */
- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard*)pboard
{
	if (aTableView == tableContentView) {
		NSString *tmp;

		// By holding ⌘, ⇧, or/and ⌥ copies selected rows as SQL INSERTS
		// otherwise \t delimited lines
		if([[NSApp currentEvent] modifierFlags] & (NSCommandKeyMask|NSShiftKeyMask|NSAlternateKeyMask))
			tmp = [tableContentView selectedRowsAsSqlInserts];
		else
			tmp = [tableContentView draggedRowsAsTabString];

		if ( nil != tmp && [tmp length] )
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

/**
 * Disable row selection while the document is working.
 */
- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{

	if(aTableView == filterTableView) 
		return YES;
	else if(aTableView == tableContentView)
		return tableRowsSelectable;
	else
		return YES;

}

/**
 * Resize a column when it's double-clicked.  (10.6+)
 */
- (CGFloat)tableView:(NSTableView *)tableView sizeToFitWidthOfColumn:(NSInteger)columnIndex
{

	NSTableColumn *theColumn = [[tableView tableColumns] objectAtIndex:columnIndex];
	NSDictionary *columnDefinition = [dataColumns objectAtIndex:[[theColumn identifier] integerValue]];

	// Get the column width
	NSUInteger targetWidth = [tableContentView autodetectWidthForColumnDefinition:columnDefinition maxRows:500];

	// Clear any saved widths for the column
	NSString *dbKey = [NSString stringWithFormat:@"%@@%@", [tableDocumentInstance database], [tableDocumentInstance host]];
	NSString *tableKey = [tablesListInstance tableName];
	NSMutableDictionary *savedWidths = [NSMutableDictionary dictionaryWithDictionary:[prefs objectForKey:SPTableColumnWidths]];
	NSMutableDictionary *dbDict = [NSMutableDictionary dictionaryWithDictionary:[savedWidths objectForKey:dbKey]];
	NSMutableDictionary *tableDict = [NSMutableDictionary dictionaryWithDictionary:[dbDict objectForKey:tableKey]];
	if ([tableDict objectForKey:[columnDefinition objectForKey:@"name"]]) {
		[tableDict removeObjectForKey:[columnDefinition objectForKey:@"name"]];
		if ([tableDict count]) {
			[dbDict setObject:[NSDictionary dictionaryWithDictionary:tableDict] forKey:tableKey];
		} else {
			[dbDict removeObjectForKey:tableKey];
		}
		if ([dbDict count]) {
			[savedWidths setObject:[NSDictionary dictionaryWithDictionary:dbDict] forKey:dbKey];
		} else {
			[savedWidths removeObjectForKey:dbKey];
		}
		[prefs setObject:[NSDictionary dictionaryWithDictionary:savedWidths] forKey:SPTableColumnWidths];
	}

	// Return the width, while the delegate is empty to prevent column resize notifications
	[tableContentView setDelegate:nil];
	[tableContentView performSelector:@selector(setDelegate:) withObject:self afterDelay:0.1];
	return targetWidth;
}

#pragma mark -
#pragma mark SplitView delegate methods

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	return NO;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset
{
	return (proposedMax - 180);
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
	return (proposedMin + 200);
}

#pragma mark -
#pragma mark Task interaction

/**
 * Disable all content interactive elements during an ongoing task.
 */
- (void) startDocumentTaskForTab:(NSNotification *)aNotification
{
	isWorking = YES;

	// Only proceed if this view is selected.
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableContent])
		return;

	[addButton setEnabled:NO];
	[removeButton setEnabled:NO];
	[copyButton setEnabled:NO];
	[reloadButton setEnabled:NO];
	[filterButton setEnabled:NO];
	tableRowsSelectable = NO;
	[paginationPreviousButton setEnabled:NO];
	[paginationNextButton setEnabled:NO];
	[paginationButton setEnabled:NO];
}

/**
 * Enable all content interactive elements after an ongoing task.
 */
- (void) endDocumentTaskForTab:(NSNotification *)aNotification
{
	isWorking = NO;

	// Only proceed if this view is selected.
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableContent])
		return;

	if ( ![[[tableDataInstance statusValues] objectForKey:@"Rows"] isNSNull] && selectedTable && [selectedTable length] && [tableDataInstance tableEncoding]) {
		[addButton setEnabled:([tablesListInstance tableType] == SPTableTypeTable)];
		[self updatePaginationState];
		[reloadButton setEnabled:YES];
	}
	if ([tableContentView numberOfSelectedRows] > 0) {
		if([tablesListInstance tableType] == SPTableTypeTable) {
			[removeButton setEnabled:YES];
			[copyButton setEnabled:YES];
		}
	}
	[filterButton setEnabled:[fieldField isEnabled]];
	tableRowsSelectable = YES;
}

#pragma mark -
#pragma mark Other methods

- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] == filterTableView) {

		NSString *str = [[[[notification userInfo] objectForKey:@"NSFieldEditor"] textStorage] string];
		if(str && [str length]) {
			if(lastEditedFilterTableValue) [lastEditedFilterTableValue release];
			lastEditedFilterTableValue = [[NSString stringWithString:str] retain];
		}
		[self updateFilterTableClause:str];

	}
}
/**
 * If user selected a table cell which is a blob field and tried to edit it
 * cancel the fieldEditor, display the field editor sheet instead for editing
 * and re-enable the fieldEditor after editing.
 */
- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)fieldEditor
{

	if(control != tableContentView) return YES;

	NSUInteger row, column;
	BOOL shouldBeginEditing = YES;

	row = [tableContentView editedRow];
	column = [tableContentView editedColumn];

	// If cell editing mode and editing request comes
	// from the keyboard show an error tooltip
	// or bypass if numberOfPossibleUpdateRows == 1
	if([tableContentView isCellEditingMode]) {
		NSArray *editStatus = [self fieldEditStatusForRow:row andColumn:[NSArrayObjectAtIndex([tableContentView tableColumns], column) identifier]];
		NSInteger numberOfPossibleUpdateRows = [[editStatus objectAtIndex:0] integerValue];
		NSPoint pos = [[tableDocumentInstance parentWindow] convertBaseToScreen:[tableContentView convertPoint:[tableContentView frameOfCellAtColumn:column row:row].origin toView:nil]];
		pos.y -= 20;
		switch(numberOfPossibleUpdateRows) {
			case -1:
			[SPTooltip showWithObject:kCellEditorErrorNoMultiTabDb
					atLocation:pos
					ofType:@"text"];
			shouldBeginEditing = NO;
			break;
			case 0:
			[SPTooltip showWithObject:[NSString stringWithFormat:kCellEditorErrorNoMatch, selectedTable]
					atLocation:pos
					ofType:@"text"];
			shouldBeginEditing = NO;
			break;

			case 1:
			shouldBeginEditing = YES;
			break;

			default:
			[SPTooltip showWithObject:[NSString stringWithFormat:kCellEditorErrorTooManyMatches, (long)numberOfPossibleUpdateRows, (numberOfPossibleUpdateRows>1)?NSLocalizedString(@"es", @"Plural suffix for row count, eg 4 match*es*"):@""]
					atLocation:pos
					ofType:@"text"];
			shouldBeginEditing = NO;
		}

	}

	NSString *fieldType;

	// Check if current edited field is a blob
	if ((fieldType = [[tableDataInstance columnWithName:[[NSArrayObjectAtIndex([tableContentView tableColumns], column) headerCell] stringValue]] objectForKey:@"typegrouping"])
		&& ([fieldType isEqualToString:@"textdata"] || [fieldType isEqualToString:@"blobdata"]))
	{
		// Cancel editing
		[control abortEditing];

		// Call the field editor sheet
		[self tableView:tableContentView shouldEditTableColumn:NSArrayObjectAtIndex([tableContentView tableColumns], column) row:row];

		// Reset the field editor
		[tableContentView editColumn:column row:row withEvent:nil select:YES];

		return NO;

	}

	return shouldBeginEditing;

}

/**
 * Trap the enter, escape, tab and arrow keys, overriding default behaviour and continuing/ending editing,
 * only within the current row.
 */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{

	// Check firstly if SPCopyTable can handle command
	if([control control:control textView:textView doCommandBySelector:(SEL)command])
		return YES;

	// Trap the escape key
	if (  [[control window] methodForSelector:command] == [[control window] methodForSelector:@selector(cancelOperation:)] )
	{

		NSUInteger row = [control editedRow];

		// Abort editing
		[control abortEditing];
		if(control == tableContentView)
			[self cancelRowEditing];
		return TRUE;
	}

	return FALSE;

}

/**
 * This method is called as part of Key Value Observing which is used to watch for prefernce changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	// Display table veiew vertical gridlines preference changed
	if ([keyPath isEqualToString:SPDisplayTableViewVerticalGridlines]) {
        [tableContentView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	}
	// Table font preference changed
	else if ([keyPath isEqualToString:SPGlobalResultTableFont]) {
		NSFont *tableFont = [NSUnarchiver unarchiveObjectWithData:[change objectForKey:NSKeyValueChangeNewKey]];
		[tableContentView setRowHeight:2.0f+NSSizeToCGSize([[NSString stringWithString:@"{ǞṶḹÜ∑zgyf"] sizeWithAttributes:[NSDictionary dictionaryWithObject:tableFont forKey:NSFontAttributeName]]).height];
		[tableContentView setFont:tableFont];
		[tableContentView reloadData];
	}
}

/**
 * Menu validation
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	// Remove row
	if ([menuItem action] == @selector(removeRow:)) {
		[menuItem setTitle:([tableContentView numberOfSelectedRows] > 1) ? @"Delete Rows" : @"Delete Row"];

		return ([tableContentView numberOfSelectedRows] > 0 && [tablesListInstance tableType] == SPTableTypeTable);
	}

	// Duplicate row
	if ([menuItem action] == @selector(copyRow:)) {
		return ([tableContentView numberOfSelectedRows] == 1 && [tablesListInstance tableType] == SPTableTypeTable);
	}

	return YES;
}

/**
 * Update WHERE clause in Filter Table Window
 */
- (void)updateFilterTableClause:(id)currentValue
{
	NSMutableString *clause = [NSMutableString string];
	NSInteger numberOfRows = [self numberOfRowsInTableView:filterTableView];
	NSInteger numberOfCols = [[filterTableView tableColumns] count];
	NSInteger numberOfValues = 0;
	NSRange opRange;

	BOOL lookInAllFields = NO;

	NSString *re1 = @"^\\s*(<|>|!?=)\\s*(.*?)\\s*$";
	NSString *re2 = @"(?i)^\\s*(.*)\\s+(.*?)\\s*$";
	NSCharacterSet *whiteSpaceCharSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

	if(currentValue == filterTableGearLookAllFields) {
		numberOfRows = 1;
		lookInAllFields = YES;
	}

	[filterTableWhereClause setString:@""];

	for(NSInteger i=0; i<numberOfRows; i++) {
		numberOfValues = 0;
		for(NSInteger index=0; index<numberOfCols; index++) {
			NSString *filterCell;
			NSDictionary *filterCellData = [NSDictionary dictionaryWithDictionary:[filterTableData objectForKey:[NSNumber numberWithInteger:index]]];
			if(currentValue == nil) {
				filterCell = NSArrayObjectAtIndex([filterCellData objectForKey:@"filter"], i);
			} else if(lookInAllFields) {
				if(lastEditedFilterTableValue && [lastEditedFilterTableValue length]) {

					filterCell = lastEditedFilterTableValue;

				} else {

					[filterTableWhereClause setString:@""];
					[filterTableWhereClause insertText:@""];
					[filterTableWhereClause scrollRangeToVisible:NSMakeRange(0, 0)];

					// If live search is set perform filtering
					if([filterTableLiveSearchCheckbox state] == NSOnState)
						[self filterTable:filterTableFilterButton];

				}
			} else if([currentValue isKindOfClass:[NSString class]]){
				if(index == [filterTableView editedColumn] && i == [filterTableView editedRow])
					filterCell = (NSString*)currentValue;
				else
					filterCell = NSArrayObjectAtIndex([filterCellData objectForKey:@"filter"], i);
			}
			if([filterCell length]) {

				if(numberOfValues)
					[clause appendString:(lookInAllFields) ? @" OR " : @" AND "];

				NSString *fieldName = [[filterCellData objectForKey:@"name"] backtickQuotedString];

				opRange = [filterCell rangeOfString:@"`@`"];
				if([filterCell isMatchedByRegex:@"^\\s*['\"]"]) {
					if([filterTableDefaultOperator isMatchedByRegex:@"['\"]"]) {
						NSArray *matches = [filterCell arrayOfCaptureComponentsMatchedByRegex:@"^\\s*(['\"])(.*)\\1\\s*$"];
						if([matches count] && [matches = NSArrayObjectAtIndex(matches,0) count] == 3) {
							[clause appendFormat:[NSString stringWithFormat:@"%%@ %@", filterTableDefaultOperator], fieldName, NSArrayObjectAtIndex(matches, 2)];
						} else {
							matches = [filterCell arrayOfCaptureComponentsMatchedByRegex:@"^\\s*(['\"])(.*)\\s*$"];
							if([matches count] && [matches = NSArrayObjectAtIndex(matches,0) count] == 3)
								[clause appendFormat:[NSString stringWithFormat:@"%%@ %@", filterTableDefaultOperator], fieldName, NSArrayObjectAtIndex(matches, 2)];
						}
					} else {
						[clause appendFormat:[NSString stringWithFormat:@"%%@ %@", filterTableDefaultOperator], fieldName, filterCell];
					}
				}
				else if(opRange.length) {
					filterCell = [filterCell stringByReplacingOccurrencesOfString:@"`@`" withString:fieldName];
					[clause appendString:[filterCell stringByReplacingOccurrencesOfString:@"`@`" withString:fieldName]];
				}
				else if([filterCell isMatchedByRegex:@"(?i)^\\s*null\\s*$"]) {
					[clause appendFormat:@"%@ IS NULL", fieldName];
				}
				else if([filterCell isMatchedByRegex:re1]) {
					NSArray *matches = [filterCell arrayOfCaptureComponentsMatchedByRegex:re1];
					if([matches count] && [matches = NSArrayObjectAtIndex(matches,0) count] == 3)
						[clause appendFormat:@"%@ %@ %@", fieldName, NSArrayObjectAtIndex(matches, 1), NSArrayObjectAtIndex(matches, 2)];
				}
				else if([filterCell isMatchedByRegex:re2]) {
					NSArray *matches = [filterCell arrayOfCaptureComponentsMatchedByRegex:re2];
					if([matches count] && [matches = NSArrayObjectAtIndex(matches,0) count] == 3)
						[clause appendFormat:@"%@ %@ %@", fieldName, [NSArrayObjectAtIndex(matches, 1) uppercaseString], NSArrayObjectAtIndex(matches, 2)];
				}
				else {
					[clause appendFormat:[NSString stringWithFormat:@"%%@ %@", filterTableDefaultOperator], fieldName, filterCell];
				}

				numberOfValues++;
			}
		}
		if(numberOfValues)
			[clause appendString:@"\nOR\n"];
	}

	// Remove last " OR " if any
	if([clause length] > 3)
		[filterTableWhereClause setString:[clause substringToIndex:([clause length]-4)]];
	else
		[filterTableWhereClause setString:@""];

	// Update syntax highlighting and uppercasing
	[filterTableWhereClause insertText:@""];
	[filterTableWhereClause scrollRangeToVisible:NSMakeRange(0, 0)];

	// If live search is set perform filtering
	if([filterTableLiveSearchCheckbox state] == NSOnState)
		[self filterTable:filterTableFilterButton];
}

/**
 * Makes the content filter field have focus by making it the first responder.
 */
- (void)makeContentFilterHaveFocus
{

	NSDictionary *filter = [[contentFilters objectForKey:compareType] objectAtIndex:[[compareField selectedItem] tag]];

	if([filter objectForKey:@"NumberOfArguments"]) {
		NSUInteger numOfArgs = [[filter objectForKey:@"NumberOfArguments"] integerValue];
		switch(numOfArgs) {
			case 2:
			[[tableDocumentInstance parentWindow] makeFirstResponder:firstBetweenField];
			break;
			case 1:
			[[tableDocumentInstance parentWindow] makeFirstResponder:argumentField];
			break;
			default:
			[[tableDocumentInstance parentWindow] makeFirstResponder:compareField];
		}
	}
}

#pragma mark -

// Last but not least
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	// Cancel previous performSelector: requests on ourselves and the table view
	// to prevent crashes for deferred actions
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:tableContentView];

	[self clearTableLoadTimer];
	[tableValues release];
	pthread_mutex_destroy(&tableValuesLock);
	[dataColumns release];
	[oldRow release];
	[filterTableData release];
	if(lastEditedFilterTableValue) [lastEditedFilterTableValue release];
	if (selectedTable) [selectedTable release];
	if (contentFilters) [contentFilters release];
	if (numberOfDefaultFilters) [numberOfDefaultFilters release];
	if (keys) [keys release];
	if (sortCol) [sortCol release];
	[usedQuery release];
	if (sortColumnToRestore) [sortColumnToRestore release];
	if (selectionIndexToRestore) [selectionIndexToRestore release];
	if (filterFieldToRestore) filterFieldToRestore = nil;
	if (filterComparisonToRestore) filterComparisonToRestore = nil;
	if (filterValueToRestore) filterValueToRestore = nil;
	if (firstBetweenValueToRestore) firstBetweenValueToRestore = nil;
	if (secondBetweenValueToRestore) secondBetweenValueToRestore = nil;
	if (cqColumnDefinition) [cqColumnDefinition release];

	[super dealloc];
}

@end
