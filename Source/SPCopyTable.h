//
//  $Id$
//
//  SPCopyTable.h
//  sequel-pro
//
//  Created by Stuart Glenn on Wed Apr 21 2004.
//  Changed by Lorenz Textor on Sat Nov 13 2004
//  Copyright (c) 2004 Stuart Glenn. All rights reserved.
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

#import "SPTableView.h"

@class SPDataStorage;
@class SPTableContent;

#define SP_MAX_CELL_WIDTH_MULTICOLUMN 200
#define SP_MAX_CELL_WIDTH 400

extern NSInteger SPEditMenuCopy;
extern NSInteger SPEditMenuCopyWithColumns;
extern NSInteger SPEditCopyAsSQL;

/*!
	@class copyTable
	@abstract   subclassed NSTableView to implement copy & drag-n-drop
	@discussion Allows copying by creating a string with each table row as
		a separate line and each cell then separate via tabs. The drag out
		is in similar format. The values for each cell are obtained via the
		objects description method
*/
@interface SPCopyTable : SPTableView
{
	SPTableContent* tableInstance;                 // the table content view instance
	id mySQLConnection;               // current MySQL connection
	NSArray* columnDefinitions;       // array of NSDictionary containing info about columns
	NSString* selectedTable;          // the name of the current selected table
	SPDataStorage* tableStorage;      // the underlying storage array holding the table data

	NSUserDefaults *prefs;

	NSRange fieldEditorSelectedRange;
	NSString *copyBlobFileDirectory;
}

@property(readwrite,assign) NSString *copyBlobFileDirectory;

@property(readwrite,assign) NSRange fieldEditorSelectedRange;

/*!
	@method	 copy:
	@abstract   does the work of copying
	@discussion gets selected (if any) row(s) as a string setting it 
	   then into th default pasteboard as a string type and tabular text type.
	@param	  sender who asked for this copy?
*/
- (void)copy:(id)sender;

/*!
	@method	 draggedRowsAsTabString:
	@abstract   getter of the dragged rows of the table for drag
	@discussion For the dragged rows returns a single string with each row
	   separated by a newline and then for each column value separated by a 
	   tab. Values are from the objects description method, so make sure it
	   returns something meaningful. 
	@result	 The above described string, or nil if nothing selected
*/
- (NSString *)draggedRowsAsTabString;

/*!
	@method	 draggingSourceOperationMaskForLocal:
	@discussion Allows for dragging out of the table to other applications
	@param	  isLocal who cares
	@result	 Always calls for a copy type drag operation
*/
- (NSUInteger)draggingSourceOperationMaskForLocal:(BOOL)isLocal;

#ifndef SP_REFACTOR /* method decls */
/*!
	@method	 rowsAsTabStringWithHeaders:onlySelectedRows:
	@abstract   getter of the selected rows or all of the table for copy
	@discussion For the selected rows or all returns a single string with each row
	   separated by a newline and then for each column value separated by a 
	   tab. Values are from the objects description method, so make sure it
	   returns something meaningful. 
	@result	 The above described string, or nil if nothing selected
*/
- (NSString *)rowsAsTabStringWithHeaders:(BOOL)withHeaders onlySelectedRows:(BOOL)onlySelected blobHandling:(NSInteger)withBlobHandling;

/*!
	@method	 rowsAsCsvStringWithHeaders:onlySelectedRows:
	@abstract   getter of the selected rows or all of the table csv formatted
	@discussion For the selected rows or all returns a single string with each row
	   separated by a newline and then for each column value separated by a 
	   , wherby each cell will be wrapped into quotes. Values are from the objects description method, so make sure it
	   returns something meaningful. 
	@result	 The above described string, or nil if nothing selected
*/
- (NSString *)rowsAsCsvStringWithHeaders:(BOOL)withHeaders onlySelectedRows:(BOOL)onlySelected blobHandling:(NSInteger)withBlobHandling;
#endif

/*
 * Generate a string in form of INSERT INTO <table> VALUES () of 
 * currently selected rows or all. Support blob data as well.
 */
- (NSString *)rowsAsSqlInsertsOnlySelectedRows:(BOOL)onlySelected;

/*
 * Set all necessary data from the table content view.
 */
- (void)setTableInstance:(id)anInstance withTableData:(SPDataStorage *)theTableStorage withColumns:(NSArray *)columnDefs withTableName:(NSString *)aTableName withConnection:(id)aMySqlConnection;

/*
 * Update the table storage location if necessary.
 */
- (void)setTableData:(SPDataStorage *)theTableStorage;

/*!
	@method  autodetectColumnWidths
	@abstract  Autodetect and return column widths based on contents
	@discussion  Support autocalculating column widths for the represented data.
		This uses the underlying table storage, calculates string widths,
		and eventually returns an array of table column widths.
		Suitable for calling on background threads, but ensure that the
		data storage range in use (currently rows 1-200) won't be altered
		while this accesses it.
	@result A dictionary - mapped by column identifier - of the column widths to use
*/
- (NSDictionary *)autodetectColumnWidths;

/*!
	@method  autodetectWidthForColumnDefinition:maxRows:
	@abstract  Autodetect and return column width based on contents
	@discussion  Support autocalculating column width for the represented data.
		This uses the underlying table storage, and the supplied column definition,
		iterating through the data and returning a reasonable column width to
		display that data.
		Suitable for calling on background threads, but ensure that the data
		storage range in use won't be altered while being accessed.
	@param  A column definition for a represented column; the column to use is derived
	@param  The maximum number of rows to process when looking at string lengths
	@result A reasonable column width to use when displaying data
*/
/**
 * Autodetect the column width for a specified column - derived from the supplied
 * column definition, using the stored data and the specified font.
 */
- (NSUInteger)autodetectWidthForColumnDefinition:(NSDictionary *)columnDefinition maxRows:(NSUInteger)rowsToCheck;

/*!
	@method	 validateMenuItem:
	@abstract   Dynamically enable Copy menu item for the table view
	@discussion Will only enable the Copy item when something is selected in
	  this table view
	@param	  anItem the menu item being validated
	@result	 YES if there is at least one row selected & the menu item is
	  copy, NO otherwise
*/
- (BOOL)validateMenuItem:(NSMenuItem*)anItem;

- (BOOL)isCellEditingMode;
- (BOOL)isCellComplex;

/*!
	@method	 shouldUseFieldEditorForRow:column:
	@abstract   Determine whether to trigger sheet editing or in-cell editing for a cell
	@discussion Checks the column data type, and the cell contents if necessary, to check
		the most appropriate editing type.
	@param	 rowIndex The row in the table the cell is present in
	@param	 colIndex The *original* column in the table the cell is present in (ie pre-reordering)
	@result	 YES if sheet editing should be used, NO otherwise.
*/
- (BOOL)shouldUseFieldEditorForRow:(NSUInteger)rowIndex column:(NSUInteger)colIndex;

- (IBAction)executeBundleItemForDataTable:(id)sender;

- (void)selectTableRows:(NSArray*)rowIndices;

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command;

@end
