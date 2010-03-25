//
//  $Id$
//
//  SPTableData.m
//  sequel-pro
//
//  Created by Rowan Beentje on 24/01/2009.
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

#import "SPTableData.h"
#import "SPSQLParser.h"
#import "TableDocument.h"
#import "TablesList.h"
#import "SPStringAdditions.h"
#import "SPArrayAdditions.h"
#import "SPConstants.h"
#import "SPAlertSheets.h"
#import "RegexKitLite.h"

@implementation SPTableData

- (id) init
{
	if ((self = [super init])) {
		columns = [[NSMutableArray alloc] init];
		columnNames = [[NSMutableArray alloc] init];
		constraints = [[NSMutableArray alloc] init];
		status = [[NSMutableDictionary alloc] init];
		triggers = [[NSMutableArray alloc] init];
		
		tableEncoding = nil;
		tableCreateSyntax = nil;
		mySQLConnection = nil;
	}

	return self;
}

/*
 * Set the connection for use.
 * Called by the connect sheet methods.
 */
- (void) setConnection:(MCPConnection *)theConnection
{
	mySQLConnection = theConnection;
	[mySQLConnection retain];
}

 
/*
 * Retrieve the encoding for the current table, using or refreshing the cache as appropriate.
 */
- (NSString *) tableEncoding
{
	if (tableEncoding == nil) {
		if ([tableListInstance tableType] == SPTableTypeView) {
			[self updateInformationForCurrentView];
		} else {
			[self updateInformationForCurrentTable];
		}
	}
	return (tableEncoding == nil) ? nil : [NSString stringWithString:tableEncoding];
}

/*
 * Retrieve the create syntax for the current table, using or refreshing the cache as appropriate.
 */
- (NSString *) tableCreateSyntax
{
	if (tableCreateSyntax == nil) {
		if ([tableListInstance tableType] == SPTableTypeView) {
			[self updateInformationForCurrentView];
		} 
		else {
			[self updateInformationForCurrentTable];
		}
	}
	
	return [NSString stringWithString:tableCreateSyntax];
}


/*
 * Retrieve all columns for the current table as an array, using or refreshing the cache as appropriate.
 */
- (NSArray *) columns
{
	if ([columns count] == 0) {
		if ([tableListInstance tableType] == SPTableTypeView) {
			[self updateInformationForCurrentView];
		} else {
			[self updateInformationForCurrentTable];
		}
	}
	return columns;
}

- (NSArray *) getConstraints
{
	return constraints;
}

- (NSArray *) triggers
{
	return (NSArray *)triggers;
}

/*
 * Retrieve a column with a specified name, using or refreshing the cache as appropriate.
 */
- (NSDictionary *) columnWithName:(NSString *)colName
{	
	if ([columns count] == 0) {
		if ([tableListInstance tableType] == SPTableTypeView) {
			[self updateInformationForCurrentView];
		} else {
			[self updateInformationForCurrentTable];
		}
	}
	NSInteger columnIndex = [columnNames indexOfObject:colName];
	if (columnIndex == NSNotFound) return nil;
	return [columns objectAtIndex:columnIndex];
}


/*
 * Retrieve column names for the current table as an array, using or refreshing the cache as appropriate.
 */
- (NSArray *) columnNames
{	
	if ([columnNames count] == 0) {
		if ([tableListInstance tableType] == SPTableTypeView) {
			[self updateInformationForCurrentView];
		} else {
			[self updateInformationForCurrentTable];
		}
	}
	return columnNames;
}


/*
 * Retrieve a specified column for the current table as a dictionary, using or refreshing the cache as appropriate.
 */
- (NSDictionary *) columnAtIndex:(NSInteger)index
{	
	if ([columns count] == 0) {
		if ([tableListInstance tableType] == SPTableTypeView) {
			[self updateInformationForCurrentView];
		} else {
			[self updateInformationForCurrentTable];
		}
	}
	return [columns objectAtIndex:index];
}

/* 
 * Checks if this column is type text or blob.
 * Used to determine if we have to show a popup when we edit a value from this column.
 */

- (BOOL) columnIsBlobOrText:(NSString *)colName
{	
	if ([columns count] == 0) {
		if ([tableListInstance tableType] == SPTableTypeView) {
			[self updateInformationForCurrentView];
		} else {
			[self updateInformationForCurrentTable];
		}
	}
	
	return (BOOL) ([[[self columnWithName:colName] objectForKey:@"typegrouping"] isEqualToString:@"textdata" ] || [[[self columnWithName:colName] objectForKey:@"typegrouping"] isEqualToString:@"blobdata"]);
}


/*
 * Retrieve the table status value for a supplied key, using or refreshing the cache as appropriate.
 */
- (NSString *) statusValueForKey:(NSString *)aKey
{
	if ([status count] == 0) {
		[self updateStatusInformationForCurrentTable];
	}
	return [status objectForKey:aKey];
}

/*
 * Set the table status value for the supplied key. This method is useful for when status values are obtained
 * via other means and are subsequently more accurate than the value currently set.
 */
- (void)setStatusValue:(NSString *)value forKey:(NSString *)key
{		
	[status setValue:value forKey:key];
}


/*
 * Retrieve all known status values as a dictionary, using or refreshing the cache as appropriate.
 */
- (NSDictionary *) statusValues
{
	if ([status count] == 0) {
		[self updateStatusInformationForCurrentTable];
	}
	return status;
}


/*
 * Flushes all caches - should be used on major changes, for example table changes.
 */
- (void) resetAllData
{
	[columns removeAllObjects];
	[columnNames removeAllObjects];
	[status removeAllObjects];
	
	if (tableEncoding != nil) {
		[tableEncoding release];
		tableEncoding = nil;
	}
	
	if (tableCreateSyntax != nil) {
		[tableCreateSyntax release];
		tableCreateSyntax = nil;
	}
}


/*
 * Flushes any status-related caches.
 */
- (void) resetStatusData
{
	[status removeAllObjects];
}


/*
 * Flushes any field/column-related caches.
 */
- (void) resetColumnData
{
	[columns removeAllObjects];
	[columnNames removeAllObjects];
}


/*
 * Retrieves the information for the current table and stores it in cache.
 * Returns a boolean indicating success.
 */
- (BOOL) updateInformationForCurrentTable
{
	NSDictionary *tableData = nil;
	NSDictionary *columnData;
	NSEnumerator *enumerator;
	
	if( [tableListInstance tableType] == SPTableTypeTable || [tableListInstance tableType] == SPTableTypeView ) {		
		tableData = [self informationForTable:[tableListInstance tableName]];
	}
	
	if (tableData == nil ) {
		[columns removeAllObjects];
		[columnNames removeAllObjects];
		[constraints removeAllObjects];
		return FALSE;
	}

	[columns addObjectsFromArray:[tableData objectForKey:@"columns"]];

	enumerator = [columns objectEnumerator];
	while (columnData = [enumerator nextObject]) {
		[columnNames addObject:[NSString stringWithString:[columnData objectForKey:@"name"]]];
	}
	
	if (tableEncoding != nil) {
		[tableEncoding release];
	}
	tableEncoding = [[NSString alloc] initWithString:[tableData objectForKey:@"encoding"]];

	return TRUE;
}


/*
 * Retrieve the CREATE TABLE string for a table and analyse it to extract the field
 * details, primary key, unique keys, and table encoding.
 * In future this could also be used to retrieve the majority of index information
 * assuming information like cardinality isn't needed.
 * This function is rather long due to the painful parsing required, but is fast.
 * Returns a boolean indicating success.
 */
- (NSDictionary *) informationForTable:(NSString *)tableName
{	
	SPSQLParser *createTableParser, *fieldsParser, *fieldParser;
	NSMutableArray *tableColumns, *fieldStrings;
	NSMutableDictionary *tableColumn, *tableData;
	NSString *encodingString = nil;
	NSUInteger i, stringStart;
	unichar quoteCharacter;

	[columns removeAllObjects];
	[columnNames removeAllObjects];
	[constraints removeAllObjects];
	
	// Catch unselected tables and return nil
	if ([tableName isEqualToString:@""] || !tableName) return nil;

	// Retrieve the CREATE TABLE syntax for the table
	MCPResult *theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW CREATE TABLE %@", [tableName backtickQuotedString]]];
	[theResult setReturnDataAsStrings:YES];
	
	// Check for any errors, but only display them if a connection still exists
	if ([mySQLConnection queryErrored]) {
		if ([mySQLConnection isConnected]) {
			SPBeginAlertSheet(NSLocalizedString(@"Error retrieving table information", @"error retrieving table information message"), NSLocalizedString(@"OK", @"OK button"), 
					nil, nil, [NSApp mainWindow], self, nil, nil, nil,
					[NSString stringWithFormat:NSLocalizedString(@"An error occurred while retrieving the information for table '%@'. Please try again.\n\nMySQL said: %@", @"error retrieving table information informative message"),
					   tableName, [mySQLConnection getLastErrorMessage]]);
			// If the current table doesn't exist anymore reload table list
			if([mySQLConnection getLastErrorID] == 1146) {
				[[tableListInstance valueForKeyPath:@"tablesListView"] deselectAll:nil];
				[tableListInstance updateTables:self];
			}
		}
		
		return nil;
	}

	// Retrieve the table syntax string
	NSArray *syntaxResult = [theResult fetchRowAsArray];
	NSArray *resultFieldNames = [theResult fetchFieldNames];
	
	if (tableCreateSyntax != nil) [tableCreateSyntax release];
	
	tableCreateSyntax = [[NSString alloc] initWithString:[syntaxResult objectAtIndex:1]];
	createTableParser = [[SPSQLParser alloc] initWithString:[syntaxResult objectAtIndex:1]];

	// Extract the fields definition string from the CREATE TABLE syntax
	fieldsParser = [[SPSQLParser alloc] initWithString:[createTableParser trimAndReturnStringFromCharacter:'(' toCharacter:')' trimmingInclusively:YES returningInclusively:NO skippingBrackets:YES]];

	// Split the fields and keys string into an array of individual elements
	fieldStrings = [[NSMutableArray alloc] initWithArray:[fieldsParser splitStringByCharacter:',' skippingBrackets:YES]];

	// fieldStrings should now hold unparsed field and key strings, while tableProperty string holds unparsed
	// table information.  Proceed further by parsing the field strings.
	tableColumns = [[NSMutableArray alloc] init];
	tableColumn = [[NSMutableDictionary alloc] init];
	fieldParser = [[SPSQLParser alloc] init];
	
	NSCharacterSet *whitespaceAndNewlineSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSCharacterSet *quoteSet = [NSCharacterSet characterSetWithCharactersInString:@"`'\""];
	NSCharacterSet *bracketSet = [NSCharacterSet characterSetWithCharactersInString:@"()"];

	tableData = [NSMutableDictionary dictionary];

	for (i = 0; i < [fieldStrings count]; i++) {

		// Take this field/key string, trim whitespace from both ends and remove comments
		[fieldsParser setString:[NSArrayObjectAtIndex(fieldStrings, i) stringByTrimmingCharactersInSet:whitespaceAndNewlineSet]];
		[fieldsParser deleteComments];
		if (![fieldsParser length]) {
			continue;
		}
		[tableColumn removeAllObjects];

		// If the first character is a quote character, this is a field definition.
		if ([quoteSet characterIsMember:[fieldsParser characterAtIndex:0]]) {
			quoteCharacter = [fieldsParser characterAtIndex:0];

			// Capture the area between the two backticks as the name
			// Set the parser to ignoreCommentStrings since a field name can contain # or /*
			[fieldsParser setIgnoreCommentStrings:YES];
			NSString *fieldName = [fieldsParser trimAndReturnStringFromCharacter: quoteCharacter
																	 toCharacter: quoteCharacter
															 trimmingInclusively: YES
															returningInclusively: NO
														   ignoringQuotedStrings: NO];
			if(fieldName == nil || [fieldName length] == 0) {
				NSBeep();
				NSAlert *alert = [[NSAlert alloc] init];
				[alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
				[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"“%@” couldn't be parsed. You can edit the column setup but the column will not be shown in the Content view; please report this issue to the Sequel Pro team using the Help menu item.", @"“%@” couldn't be parsed. You can edit the column setup but the column will not be shown in the Content view; please report this issue to the Sequel Pro team using the Help menu item."), fieldsParser]];
				[alert setMessageText:NSLocalizedString(@"Error while parsing CREATE TABLE syntax",@"error while parsing CREATE TABLE syntax")];
				[alert setAlertStyle:NSCriticalAlertStyle];
				[alert runModal];
				[alert release];
				continue;
			}
			//if the next character is again a backtick, we stumbled across an escaped backtick. we have to continue parsing.
			while ([fieldsParser characterAtIndex:0] == quoteCharacter) {
				fieldName = [fieldName stringByAppendingFormat: @"`%@",
																[fieldsParser trimAndReturnStringFromCharacter: quoteCharacter
																								   toCharacter: quoteCharacter
																						   trimmingInclusively: YES
																						  returningInclusively: NO
																						 ignoringQuotedStrings: NO]
																];
			}
			[fieldsParser setIgnoreCommentStrings:NO];
			
			[tableColumn setObject:[NSNumber numberWithInteger:[tableColumns count]] forKey:@"datacolumnindex"];
			[tableColumn setObject:fieldName forKey:@"name"];

			// Split the remaining field definition string by spaces and process
			[tableColumn addEntriesFromDictionary:[self parseFieldDefinitionStringParts:[fieldsParser splitStringByCharacter:' ' skippingBrackets:YES]]];
			
			//if column is not null, but doesn't have a default value, set empty string
			if([[tableColumn objectForKey:@"null"] integerValue] == 0 && [[tableColumn objectForKey:@"autoincrement"] integerValue] == 0 && ![tableColumn objectForKey:@"default"]) {
				[tableColumn setObject:@"" forKey:@"default"];
			}
			
			// Store the column.
			NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:1];
			[d setDictionary:tableColumn];
			[tableColumns addObject:d];

		// TODO: Otherwise it's a key definition, check, or other 'metadata'.  Would be useful to parse/display these!
		} else {
			NSArray *parts = [fieldsParser splitStringByCharacter:' ' skippingBrackets:YES ignoringQuotedStrings:YES];

			// Constraints
			if( [[parts objectAtIndex:0] hasPrefix:@"CONSTRAINT"] ) {
				NSMutableDictionary *constraintDetails = [[NSMutableDictionary alloc] init];

				// Extract the relevant details from the constraint string
				[fieldsParser setString:[[parts objectAtIndex:1] stringByTrimmingCharactersInSet:bracketSet]];
				[constraintDetails setObject:[fieldsParser unquotedString] forKey:@"name"];

				NSMutableArray *keyColumns = [NSMutableArray array];
				NSArray *keyColumnStrings = [[[parts objectAtIndex:4] stringByTrimmingCharactersInSet:bracketSet] componentsSeparatedByString:@","];
				
				for (NSString *keyColumn in keyColumnStrings)
				{
					[fieldsParser setString:[[keyColumn stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByTrimmingCharactersInSet:bracketSet]];
					[keyColumns addObject:[fieldsParser unquotedString]];
				}
				
				[constraintDetails setObject:keyColumns forKey:@"columns"];

				[fieldsParser setString:[[parts objectAtIndex:6] stringByTrimmingCharactersInSet:bracketSet]];
				[constraintDetails setObject:[fieldsParser unquotedString] forKey:@"ref_table"];

				[fieldsParser setString:[[parts objectAtIndex:7] stringByTrimmingCharactersInSet:bracketSet]];
				[constraintDetails setObject:[fieldsParser unquotedString] forKey:@"ref_columns"];

				NSInteger nextOffs = 12;
				if( [parts count] > 8 ) {
					// NOTE: this won't get SET NULL | NO ACTION | RESTRICT
					if( [[parts objectAtIndex:9] hasPrefix:@"UPDATE"] ) {
						if( [NSArrayObjectAtIndex(parts, 10) hasPrefix:@"SET"] ) {
							[constraintDetails setObject:@"SET NULL"
												  forKey:@"update"];
							nextOffs = 13;
						} else if( [NSArrayObjectAtIndex(parts, 10) hasPrefix:@"NO"] ) {
							[constraintDetails setObject:@"NO ACTION"
												  forKey:@"update"];
							nextOffs = 13;
						} else {
							[constraintDetails setObject:NSArrayObjectAtIndex(parts, 10)
												  forKey:@"update"];
						}
					} 
					else if( [NSArrayObjectAtIndex(parts, 9) hasPrefix:@"DELETE"] ) {
						if( [NSArrayObjectAtIndex(parts, 10) hasPrefix:@"SET"] ) {
							[constraintDetails setObject:@"SET NULL"
												  forKey:@"delete"];
							nextOffs = 13;
						} else if( [NSArrayObjectAtIndex(parts, 10) hasPrefix:@"NO"] ) {
							[constraintDetails setObject:@"NO ACTION"
												  forKey:@"delete"];
							nextOffs = 13;
						} else {
							[constraintDetails setObject:NSArrayObjectAtIndex(parts, 10)
												  forKey:@"delete"];
						}
					}
				}
				if( [parts count] > nextOffs - 1 ) {
					if( [NSArrayObjectAtIndex(parts, nextOffs) hasPrefix:@"UPDATE"] ) {
						if( [NSArrayObjectAtIndex(parts, nextOffs+1) hasPrefix:@"SET"] ) {
							[constraintDetails setObject:@"SET NULL"
												  forKey:@"update"];
						} else if( [NSArrayObjectAtIndex(parts, nextOffs+1) hasPrefix:@"NO"] ) {
							[constraintDetails setObject:@"NO ACTION"
												  forKey:@"update"];
						} else {
							[constraintDetails setObject:NSArrayObjectAtIndex(parts, nextOffs+1)
												  forKey:@"update"];
						}
					} 
					else if( [NSArrayObjectAtIndex(parts, nextOffs) hasPrefix:@"DELETE"] ) {
						if( [NSArrayObjectAtIndex(parts, nextOffs+1) hasPrefix:@"SET"] ) {
							[constraintDetails setObject:@"SET NULL"
												  forKey:@"delete"];
						} else if( [NSArrayObjectAtIndex(parts, nextOffs+1) hasPrefix:@"NO"] ) {
							[constraintDetails setObject:@"NO ACTION"
												  forKey:@"delete"];
						} else {
							[constraintDetails setObject:NSArrayObjectAtIndex(parts, nextOffs+1)
												  forKey:@"delete"];
						}
					}
				}
				[constraints addObject:constraintDetails];
				[constraintDetails release];
			}
			// primary key
			// add "isprimarykey" to the corresponding tableColumn
			// add dict root "primarykeyfield" = <field> for faster accessing
			else if( [NSArrayObjectAtIndex(parts, 0) hasPrefix:@"PRIMARY"] && [parts count] == 3) {
				NSString *parsedString = [(NSString*)NSArrayObjectAtIndex(parts, 2) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				if([parsedString length]>4) {
					NSString *priFieldName = [[parsedString substringWithRange:NSMakeRange(2,[parsedString length]-4)] stringByReplacingOccurrencesOfString:@"``" withString:@"`"];
					[tableData setObject:priFieldName forKey:@"primarykeyfield"];
					for(id theTableColumn in tableColumns)
						if([[theTableColumn objectForKey:@"name"] isEqualToString:priFieldName]) {
							[theTableColumn setObject:[NSNumber numberWithInteger:1] forKey:@"isprimarykey"];
							break;
						}
				}
			}
			// unique keys
			// add to each corresponding tableColumn the tag "unique" if given
			else if( [NSArrayObjectAtIndex(parts, 0) hasPrefix:@"UNIQUE"]  && [parts count] == 4) {
				NSString *parsedString = [(NSString*)NSArrayObjectAtIndex(parts, 3) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				if([parsedString length]>4) {
					NSArray *uniqueFieldNames = [parsedString componentsSeparatedByString:@"`,`"];
					for(NSString* uniq in uniqueFieldNames) {
						NSString *uniqField = [[uniq stringByReplacingOccurrencesOfRegex:@"^\\(`|`\\)" withString:@""] stringByReplacingOccurrencesOfString:@"``" withString:@"`"];
						for(id theTableColumn in tableColumns)
							if([[theTableColumn objectForKey:@"name"] isEqualToString:uniqField]) {
								[theTableColumn setObject:[NSNumber numberWithInteger:1] forKey:@"unique"];
								break;
							}
					}
					
				}
			}
			// who knows
			else {
				// NSLog( @"not parsed: %@", [parts objectAtIndex:0] );
			}
		}
	}
	[fieldStrings release];
	[fieldsParser release];
	[tableColumn release];

	// Extract the encoding from the table properties string - other details come from TABLE STATUS.
	NSRange charsetDefinitionRange = [createTableParser rangeOfString:@"CHARSET=" options:NSCaseInsensitiveSearch];
	if (charsetDefinitionRange.location == NSNotFound) {
		charsetDefinitionRange = [createTableParser rangeOfString:@"CHARACTER SET=" options:NSCaseInsensitiveSearch];
	}
	if (charsetDefinitionRange.location != NSNotFound) {
		stringStart = charsetDefinitionRange.location + charsetDefinitionRange.length;
		for (i = stringStart; i < [createTableParser length]; i++) {
			if ([createTableParser characterAtIndex:i] == ' ') break;
		}

		// Catch the "default" character encoding:
		if ([[[createTableParser substringWithRange:NSMakeRange(stringStart, i-stringStart)] lowercaseString] isEqualToString:@"default"]) {
			encodingString = [[NSString alloc] initWithString:[tableDocumentInstance databaseEncoding]];
		} else {
			encodingString = [[NSString alloc] initWithString:[createTableParser substringWithRange:NSMakeRange(stringStart, i-stringStart)]];
		}

	// If no DEFAULT CHARSET is present, it's likely MySQL < 4; fall back to latin1.
	} else {
		encodingString = [[NSString alloc] initWithString:@"latin1"];
	}

	[createTableParser release];
	[fieldParser release];
	
	// Triggers
	theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"/*!50003 SHOW TRIGGERS WHERE `Table` = %@ */", 
											  [tableName tickQuotedString]]];
	[theResult setReturnDataAsStrings:YES];
	
	// Check for any errors, but only display them if a connection still exists
	if ([mySQLConnection queryErrored]) {
		if ([mySQLConnection isConnected]) {
			SPBeginAlertSheet(NSLocalizedString(@"Error retrieving table information", @"error retrieving table information message"), NSLocalizedString(@"OK", @"OK button"), 
							  nil, nil, [NSApp mainWindow], self, nil, nil, nil,
							  [NSString stringWithFormat:NSLocalizedString(@"An error occurred while retrieving the information for table '%@'. Please try again.\n\nMySQL said: %@", @"error retrieving table information informative message"),
							   tableName, [mySQLConnection getLastErrorMessage]]);
		}
		[tableColumns release];
		if (encodingString) [encodingString release];

		return nil;
	}
	
	[triggers removeAllObjects];
	if( [theResult numOfRows] ) {
		for(i=0; i<[theResult numOfRows]; i++){
			[triggers addObject:[theResult fetchRowAsDictionary]];
		}
	}
	

	// this will be 'Table' or 'View'
	[tableData setObject:[resultFieldNames objectAtIndex:0] forKey:@"type"];
	[tableData setObject:[NSString stringWithString:encodingString] forKey:@"encoding"];
	[tableData setObject:[NSArray arrayWithArray:tableColumns] forKey:@"columns"];
	[tableData setObject:[NSArray arrayWithArray:constraints] forKey:@"constraints"];
	[tableData setObject:[NSArray arrayWithArray:triggers] forKey:@"triggers"];

	[encodingString release];
	[tableColumns release];

	return tableData;
}


/*
 * Retrieves the information for the current view and stores it in cache.
 * Returns a boolean indicating success.
 */
- (BOOL) updateInformationForCurrentView
{
	NSDictionary *viewData = [self informationForView:[tableListInstance tableName]];
	NSDictionary *columnData;
	NSEnumerator *enumerator;

	if (viewData == nil) {
		[columns removeAllObjects];
		[columnNames removeAllObjects];
		[constraints removeAllObjects];
		return FALSE;
	}

	[columns addObjectsFromArray:[viewData objectForKey:@"columns"]];

	enumerator = [columns objectEnumerator];
	while (columnData = [enumerator nextObject]) {
		[columnNames addObject:[NSString stringWithString:[columnData objectForKey:@"name"]]];
	}
	
	if (tableEncoding != nil) {
		[tableEncoding release];
	}
	tableEncoding = [[NSString alloc] initWithString:[viewData objectForKey:@"encoding"]];

	return TRUE;
}


/*
 * Retrieve information which can be used to display views.  Unlike tables, all the information
 * for views cannot be extracted from the CREATE ALGORITHM syntax without selecting all the info
 * from the referenced tables.  For the time being we therefore use the column information for
 * SHOW COLUMNS (subsequently parsed), and derive the encoding from the database as no other source
 * is available.
 * Returns a boolean indicating success.
 */
- (NSDictionary *) informationForView:(NSString *)viewName
{
	SPSQLParser *fieldParser;
	NSMutableArray *tableColumns;
	NSDictionary *resultRow;
	NSMutableDictionary *tableColumn, *viewData;
	NSUInteger i;

	// Catch unselected views and return nil
	if ([viewName isEqualToString:@""] || !viewName) return nil;

	// Retrieve the CREATE TABLE syntax for the table
	MCPResult *theResult = [mySQLConnection queryString: [NSString stringWithFormat: @"SHOW CREATE TABLE %@",
																					   [viewName backtickQuotedString]
																					]];
	[theResult setReturnDataAsStrings:YES];

	// Check for any errors, but only display them if a connection still exists
	if ([mySQLConnection queryErrored]) {
		if ([mySQLConnection isConnected]) {
			SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), 
					nil, nil, [NSApp mainWindow], self, nil, nil, nil,
					[NSString stringWithFormat:NSLocalizedString(@"An error occurred while retrieving information.\nMySQL said: %@", @"message of panel when retrieving information failed"),
					   [mySQLConnection getLastErrorMessage]]);
		}
		return nil;
	}

	// Retrieve the table syntax string
	if (tableCreateSyntax) [tableCreateSyntax release], tableCreateSyntax = nil;
	tableCreateSyntax = [[NSString alloc] initWithString:[[theResult fetchRowAsArray] objectAtIndex:1]];

	// Retrieve the SHOW COLUMNS syntax for the table
	theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@", [viewName backtickQuotedString]]];
	[theResult setReturnDataAsStrings:YES];

	// Check for any errors, but only display them if a connection still exists
	if ([mySQLConnection queryErrored]) {
		if ([mySQLConnection isConnected]) {
			SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), 
					nil, nil, [NSApp mainWindow], self, nil, nil, nil,
					[NSString stringWithFormat:NSLocalizedString(@"An error occurred while retrieving information.\nMySQL said: %@", @"message of panel when retrieving information failed"),
					   [mySQLConnection getLastErrorMessage]]);
		}
		return nil;
	}

	// Loop through the fields and capture details
	if ([theResult numOfRows]) [theResult dataSeek:0];
	tableColumns = [[NSMutableArray alloc] init];
	tableColumn = [[NSMutableDictionary alloc] init];
	fieldParser = [[SPSQLParser alloc] init];
	for ( i = 0; i < [theResult numOfRows] ; i++ ) {
		[tableColumn removeAllObjects];
		resultRow = [theResult fetchRowAsDictionary];

		// Add the column index and name
		[tableColumn setObject:[NSNumber numberWithInteger:[tableColumns count]] forKey:@"datacolumnindex"];
		[tableColumn setObject:[NSString stringWithString:[resultRow objectForKey:@"Field"]] forKey:@"name"];

		// Populate type, length, and other available details from the Type columns
		[fieldParser setString:[resultRow objectForKey:@"Type"]];
		[tableColumn addEntriesFromDictionary:[self parseFieldDefinitionStringParts:[fieldParser splitStringByCharacter:' ' skippingBrackets:YES]]];

		// If there's a null column, use the details from it
		if ([resultRow objectForKey:@"Null"]) {
			if ([[[resultRow objectForKey:@"Null"] uppercaseString] isEqualToString:@"NO"]) {
				[tableColumn setValue:[NSNumber numberWithBool:NO] forKey:@"null"];
			} else {
				[tableColumn setValue:[NSNumber numberWithBool:YES] forKey:@"null"];
			}
		}

		// Select the column default if available
		if ([resultRow objectForKey:@"Default"])
			[tableColumn setObject:[resultRow objectForKey:@"Default"] forKey:@"default"];

		// Add the column to the list
		[tableColumns addObject:[NSDictionary dictionaryWithDictionary:tableColumn]];
	}
	[fieldParser release];
	[tableColumn release];

	// The character set has to be guessed at via the database encoding.
	// Add the details to the data object.
	viewData = [NSMutableDictionary dictionary];
	[viewData setObject:[NSString stringWithString:[tableDocumentInstance databaseEncoding]] forKey:@"encoding"];
	[viewData setObject:[NSArray arrayWithArray:tableColumns] forKey:@"columns"];

	[tableColumns release];

	return viewData;
}



/*
 * Retrieve the status of a table as a dictionary and add it to the local cache for reuse.
 */
- (BOOL)updateStatusInformationForCurrentTable
{

	// Catch unselected tables and return false
	if ([[tableListInstance tableName] isEqualToString:@""] || ![tableListInstance tableName])
		return FALSE;

	// When views are selected, populate the table with a default dictionary - all values, including comment, return no
	// meaningful information for views so we may as well skip the query.
	if ([tableListInstance tableType] == SPTableTypeView) {
		[status setDictionary:[NSDictionary dictionaryWithObjectsAndKeys:@"View", @"Engine", @"No status information is available for views.", @"Comment", [tableListInstance tableName], @"Name", nil]];
		return TRUE;
	}

	// Run the status query and retrieve as a dictionary.
	NSMutableString *escapedTableName = [NSMutableString stringWithString:[tableListInstance tableName]];
	[escapedTableName replaceOccurrencesOfString:@"'" withString:@"\\\'" options:0 range:NSMakeRange(0, [escapedTableName length])];

	MCPResult *tableStatusResult = nil;

	if ([tableListInstance tableType] == SPTableTypeProc) {
		NSMutableString *escapedDatabaseName = [NSMutableString stringWithString:[tableDocumentInstance database]];
		[escapedDatabaseName replaceOccurrencesOfString:@"'" withString:@"\\\'" options:0 range:NSMakeRange(0, [escapedDatabaseName length])];
		tableStatusResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SELECT * FROM information_schema.ROUTINES AS r WHERE r.SPECIFIC_NAME = '%@' AND r.ROUTINE_SCHEMA = '%@' AND r.ROUTINE_TYPE = 'PROCEDURE'", escapedTableName, escapedDatabaseName]];
	}
	else if ([tableListInstance tableType] == SPTableTypeFunc) {
		NSMutableString *escapedDatabaseName = [NSMutableString stringWithString:[tableDocumentInstance database]];
		[escapedDatabaseName replaceOccurrencesOfString:@"'" withString:@"\\\'" options:0 range:NSMakeRange(0, [escapedDatabaseName length])];
		tableStatusResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SELECT * FROM information_schema.ROUTINES AS r WHERE r.SPECIFIC_NAME = '%@' AND r.ROUTINE_SCHEMA = '%@' AND r.ROUTINE_TYPE = 'FUNCTION'", escapedTableName, escapedDatabaseName]];
	}
	else if ([tableListInstance tableType] == SPTableTypeTable) {
		tableStatusResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW TABLE STATUS LIKE '%@'", escapedTableName ]];
		[tableStatusResult setReturnDataAsStrings:YES];
	}

	// Check for any errors, only displaying them if the connection hasn't been terminated
	if ([mySQLConnection queryErrored]) {
		if ([mySQLConnection isConnected]) {
			SPBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), 
					nil, nil, [NSApp mainWindow], self, nil, nil, nil,
					[NSString stringWithFormat:NSLocalizedString(@"An error occured while retrieving status data.\nMySQL said: %@", @"message of panel when retrieving view information failed"),
					   [mySQLConnection getLastErrorMessage]]);
		}
		return FALSE;
	}

	// Retrieve the status as a dictionary and set as the cache
	[status setDictionary:[tableStatusResult fetchRowAsDictionary]];

	if ([tableListInstance tableType] == SPTableTypeTable) {

		// Reassign any "Type" key - for MySQL < 4.1 - to "Engine" for consistency.
		if ([status objectForKey:@"Type"]) {
			[status setObject:[status objectForKey:@"Type"] forKey:@"Engine"];
		}

		// Add a note for whether the row count is accurate or not - only for MyISAM
		if ([[status objectForKey:@"Engine"] isEqualToString:@"MyISAM"]) {
			[status setObject:@"y" forKey:@"RowsCountAccurate"];
		} else {
			[status setObject:@"n" forKey:@"RowsCountAccurate"];
		}

		// [status objectForKey:@"Rows"] is NULL then try to get the number of rows via SELECT COUNT(1) FROM `foo`
		// this happens e.g. for db "information_schema"
		if([[status objectForKey:@"Rows"] isKindOfClass:[NSNull class]]) {
			tableStatusResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SELECT COUNT(1) FROM %@", [escapedTableName backtickQuotedString] ]];
			if (![mySQLConnection queryErrored])
				[status setObject:[[tableStatusResult fetchRowAsArray] objectAtIndex:0] forKey:@"Rows"];
				[status setObject:@"y" forKey:@"RowsCountAccurate"];
		}
	}

	return TRUE;
}


/*
 * Parse an array of field definition parts - not including name but including type and optionally unsigned/zerofill/null
 * and so forth - into a dictionary of parsed details.  Intended for use both with CREATE TABLE syntax - with fuller
 * details - and with the "type" column from SHOW COLUMNS.
 * Returns a dictionary of details with lowercase keys.
 */
- (NSDictionary *) parseFieldDefinitionStringParts:(NSArray *)definitionParts
{
	if (![definitionParts count]) return [NSDictionary dictionary];

	SPSQLParser *detailParser;
	SPSQLParser *fieldParser = [[SPSQLParser alloc] init];
	NSMutableDictionary *fieldDetails = [[NSMutableDictionary alloc] init];
	NSMutableArray *detailParts;
	NSString *detailString;
	NSInteger i, definitionPartsIndex = 0, partsArrayLength;

	// Skip blank items within the definition parts
	while (definitionPartsIndex < [definitionParts count]
			&& ![[[definitionParts objectAtIndex:definitionPartsIndex] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length])
		definitionPartsIndex++;

	// The first item is always the data type.
	[fieldParser setString:[definitionParts objectAtIndex:definitionPartsIndex]];
	definitionPartsIndex++;

	// If no field length definition is present, store only the type
	if ([fieldParser firstOccurrenceOfCharacter:'(' ignoringQuotedStrings:YES] == NSNotFound) {
		[fieldDetails setObject:[fieldParser uppercaseString] forKey:@"type"];

	// Otherwise separate out the length definition for processing
	} else {
		detailParser = [[SPSQLParser alloc] initWithString:[[fieldParser stringToCharacter:'(' inclusively:NO] uppercaseString]];
		[fieldDetails setObject:[NSString stringWithString:detailParser] forKey:@"type"];

		// For ENUMs and SETs, capture the field value options into an array for storage
		if ([detailParser isEqualToString:@"ENUM"] || [detailParser isEqualToString:@"SET"]) {
			[detailParser setString:[fieldParser stringFromCharacter:'(' toCharacter:')' inclusively:NO]];
			detailParts = [[NSMutableArray alloc] initWithArray:[detailParser splitStringByCharacter:',']];
			for (i = 0; i < [detailParts count]; i++) {
				[detailParser setString:[detailParts objectAtIndex:i]];
				[detailParts replaceObjectAtIndex:i withObject:[detailParser unquotedString]];
			}
			[fieldDetails setObject:[NSArray arrayWithArray:detailParts] forKey:@"values"];
			[detailParts release];

		// For types with required or optional decimals, store as appropriate
		} else if ([detailParser isEqualToString:@"REAL"] || [detailParser isEqualToString:@"DOUBLE"] || [detailParser isEqualToString:@"FLOAT"] || [detailParser isEqualToString:@"DECIMAL"] || [detailParser isEqualToString:@"NUMERIC"]) {
			[detailParser setString:[fieldParser stringFromCharacter:'(' toCharacter:')' inclusively:NO]];
			detailParts = [[NSMutableArray alloc] initWithArray:[detailParser splitStringByCharacter:',']];
			[detailParser setString:[detailParts objectAtIndex:0]];
			[fieldDetails setObject:[detailParser unquotedString] forKey:@"length"];
			if ([detailParts count] > 1) {
				[detailParser setString:[detailParts objectAtIndex:1]];
				[fieldDetails setObject:[detailParser unquotedString] forKey:@"decimals"];
			}
			[detailParts release];

		// Otherwise capture the length only.
		} else {
			[detailParser setString:[fieldParser stringFromCharacter:'(' toCharacter:')' inclusively:NO]];
			[fieldDetails setObject:[detailParser unquotedString] forKey:@"length"];
		}
		[detailParser release];
	}
	[fieldParser release];

	// Also capture a general column type "group" to allow behavioural switches
	detailString = [[NSString alloc] initWithString:[fieldDetails objectForKey:@"type"]];
	if ([detailString isEqualToString:@"BIT"]) {
		[fieldDetails setObject:@"bit" forKey:@"typegrouping"];
	} else if ([detailString isEqualToString:@"TINYINT"] || [detailString isEqualToString:@"SMALLINT"] || [detailString isEqualToString:@"MEDIUMINT"]
				|| [detailString isEqualToString:@"INT"] || [detailString isEqualToString:@"INTEGER"] || [detailString isEqualToString:@"BIGINT"]) {
		[fieldDetails setObject:@"integer" forKey:@"typegrouping"];
	} else if ([detailString isEqualToString:@"REAL"] || [detailString isEqualToString:@"DOUBLE"] || [detailString isEqualToString:@"FLOAT"]
				|| [detailString isEqualToString:@"DECIMAL"] || [detailString isEqualToString:@"NUMERIC"]) {
		[fieldDetails setObject:@"float" forKey:@"typegrouping"];
	} else if ([detailString isEqualToString:@"DATE"] || [detailString isEqualToString:@"TIME"] || [detailString isEqualToString:@"TIMESTAMP"]
				|| [detailString isEqualToString:@"DATETIME"] || [detailString isEqualToString:@"YEAR"]) {
		[fieldDetails setObject:@"date" forKey:@"typegrouping"];
	} else if ([detailString isEqualToString:@"CHAR"] || [detailString isEqualToString:@"VARCHAR"]) {
		[fieldDetails setObject:@"string" forKey:@"typegrouping"];
	} else if ([detailString isEqualToString:@"BINARY"] || [detailString isEqualToString:@"VARBINARY"]) {
		[fieldDetails setObject:@"binary" forKey:@"typegrouping"];
	} else if ([detailString isEqualToString:@"ENUM"] || [detailString isEqualToString:@"SET"]) {
		[fieldDetails setObject:@"enum" forKey:@"typegrouping"];
	} else if ([detailString isEqualToString:@"TINYTEXT"] || [detailString isEqualToString:@"TEXT"]
				|| [detailString isEqualToString:@"MEDIUMTEXT"] || [detailString isEqualToString:@"LONGTEXT"]) {
		[fieldDetails setObject:@"textdata" forKey:@"typegrouping"];

	// Default to "blobdata".  This means that future and currently unsupported types - including spatial extensions -
	// will be preserved unmangled.
	} else {
		[fieldDetails setObject:@"blobdata" forKey:@"typegrouping"];
	}
	[detailString release];

	// Set up some column defaults for all columns
	[fieldDetails setValue:[NSNumber numberWithBool:YES] forKey:@"null"];
	[fieldDetails setValue:[NSNumber numberWithBool:NO] forKey:@"unsigned"];
	[fieldDetails setValue:[NSNumber numberWithBool:NO] forKey:@"binary"];
	[fieldDetails setValue:[NSNumber numberWithBool:NO] forKey:@"zerofill"];
	[fieldDetails setValue:[NSNumber numberWithBool:NO] forKey:@"autoincrement"];
	[fieldDetails setValue:[NSNumber numberWithBool:NO] forKey:@"onupdatetimestamp"];
	[fieldDetails setValue:@"" forKey:@"comment"];
	[fieldDetails setValue:[NSMutableString string] forKey:@"unparsed"];

	// Walk through the remaining column definition parts storing recognised details
	partsArrayLength = [definitionParts count];
	for ( ; definitionPartsIndex < partsArrayLength; definitionPartsIndex++) {
		detailString = [[NSString alloc] initWithString:[[definitionParts objectAtIndex:definitionPartsIndex] uppercaseString]];

		// Whether numeric fields are unsigned
		if ([detailString isEqualToString:@"UNSIGNED"]) {
			[fieldDetails setValue:[NSNumber numberWithBool:YES] forKey:@"unsigned"];

		// Whether numeric fields are zerofill
		} else if ([detailString isEqualToString:@"ZEROFILL"]) {
			[fieldDetails setValue:[NSNumber numberWithBool:YES] forKey:@"zerofill"];

		// Whether text types are binary
		} else if ([detailString isEqualToString:@"BINARY"]) {
			[fieldDetails setValue:[NSNumber numberWithBool:YES] forKey:@"binary"];

		// Whether text types have a different encoding to the table
		} else if ([detailString isEqualToString:@"CHARSET"] && (definitionPartsIndex + 1 < partsArrayLength)) {
			if (![[[definitionParts objectAtIndex:definitionPartsIndex+1] uppercaseString] isEqualToString:@"DEFAULT"]) {
				[fieldDetails setValue:[definitionParts objectAtIndex:definitionPartsIndex+1] forKey:@"encoding"];
			}
			definitionPartsIndex++;
		} else if ([detailString isEqualToString:@"CHARACTER"] && (definitionPartsIndex + 2 < partsArrayLength)
					&& [[[definitionParts objectAtIndex:definitionPartsIndex+1] uppercaseString] isEqualToString:@"SET"]) {
			if (![[[definitionParts objectAtIndex:definitionPartsIndex+2] uppercaseString] isEqualToString:@"DEFAULT"]) {;
				[fieldDetails setValue:[definitionParts objectAtIndex:definitionPartsIndex+2] forKey:@"encoding"];
			}
			definitionPartsIndex += 2;

		// Whether text types have a different collation to the table
		} else if ([detailString isEqualToString:@"COLLATE"] && (definitionPartsIndex + 1 < partsArrayLength)) {
			if (![[[definitionParts objectAtIndex:definitionPartsIndex+1] uppercaseString] isEqualToString:@"DEFAULT"]) {
				[fieldDetails setValue:[definitionParts objectAtIndex:definitionPartsIndex+1] forKey:@"collation"];
			}
			definitionPartsIndex++;

		// Whether fields are NOT NULL
		} else if ([detailString isEqualToString:@"NOT"] && (definitionPartsIndex + 1 < partsArrayLength)
					&& [[[definitionParts objectAtIndex:definitionPartsIndex+1] uppercaseString] isEqualToString:@"NULL"]) {
			[fieldDetails setValue:[NSNumber numberWithBool:NO] forKey:@"null"];
			definitionPartsIndex++;

		// Whether fields are NULL
		} else if ([detailString isEqualToString:@"NULL"]) {
			[fieldDetails setValue:[NSNumber numberWithBool:YES] forKey:@"null"];

		// Whether fields should auto-increment
		} else if ([detailString isEqualToString:@"AUTO_INCREMENT"]) {
			[fieldDetails setValue:[NSNumber numberWithBool:YES] forKey:@"autoincrement"];

		// Field defaults
		} else if ([detailString isEqualToString:@"DEFAULT"] && (definitionPartsIndex + 1 < partsArrayLength)) {
			detailParser = [[SPSQLParser alloc] initWithString:[definitionParts objectAtIndex:definitionPartsIndex+1]];
			if([[detailParser unquotedString] isEqualToString:@"NULL"])
				[fieldDetails setObject:[NSNull null] forKey:@"default"];
			else
				[fieldDetails setValue:[detailParser unquotedString] forKey:@"default"];
			[detailParser release];
			definitionPartsIndex++;

		// Special timestamp case - Whether fields are set to update the current timestamp
		} else if ([detailString isEqualToString:@"ON"] && (definitionPartsIndex + 2 < partsArrayLength)
					&& [[[definitionParts objectAtIndex:definitionPartsIndex+1] uppercaseString] isEqualToString:@"UPDATE"]
					&& [[[definitionParts objectAtIndex:definitionPartsIndex+2] uppercaseString] isEqualToString:@"CURRENT_TIMESTAMP"]) {
			[fieldDetails setValue:[NSNumber numberWithBool:YES] forKey:@"onupdatetimestamp"];
			definitionPartsIndex += 2;
		
		// Column comments
		} else if ([detailString isEqualToString:@"COMMENT"] && (definitionPartsIndex + 1 < partsArrayLength)) {
			detailParser = [[SPSQLParser alloc] initWithString:[definitionParts objectAtIndex:definitionPartsIndex+1]];
			[fieldDetails setValue:[detailParser unquotedString] forKey:@"comment"];
			[detailParser release];
			definitionPartsIndex++;
			
		// Preserve unhandled details to avoid losing information when rearranging columns etc
		// TODO: Currently unhandled: [UNIQUE | PRIMARY] KEY | COLUMN_FORMAT bar | STORAGE q | REFERENCES...
		} else {
			[[fieldDetails objectForKey:@"unparsed"] appendString:@" "];
			[[fieldDetails objectForKey:@"unparsed"] appendString:[definitionParts objectAtIndex:definitionPartsIndex]];
		}

		[detailString release];
	}

	return [fieldDetails autorelease];
}

/*
 * Return the column names which are set to PRIMIARY KEY; returns nil if no PRIMARY KEY is set.
 */
- (NSArray *)primaryKeyColumnNames
{

	NSString *selectedTable = [tableListInstance tableName];
	if(![selectedTable length]) return nil;

	MCPResult *r;
	NSArray *resultRow;
	NSInteger i;
	NSMutableArray *keyColumns = [NSMutableArray array];

	r = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@ WHERE `key` = 'PRI'", [selectedTable backtickQuotedString]]];
	[r setReturnDataAsStrings:YES];

	if([r numOfRows] < 1) return nil;

	if ([mySQLConnection queryErrored]) {
		if ([mySQLConnection isConnected])
			NSRunAlertPanel(@"Error", [NSString stringWithFormat:@"An error occured while retrieving the PRIAMRY KEY data:\n\n%@", [mySQLConnection getLastErrorMessage]], @"OK", nil, nil);
		return nil;
	}

	
	for( i = 0; i < [r numOfRows]; i++ ) {
		resultRow = [r fetchRowAsArray];
		[keyColumns addObject:[NSArrayObjectAtIndex(resultRow, 0) description]];
	}

	if([keyColumns count])
		return keyColumns;

	return nil;
}

#pragma mark -

- (void) dealloc
{
	[columns release];
	[columnNames release];
	[constraints release];
	[triggers release];
	[status release];
	
	if (tableEncoding) [tableEncoding release];
	if (tableCreateSyntax) [tableCreateSyntax release];
	if (mySQLConnection) [mySQLConnection release];

	[super dealloc];
}

@end
