//
//  $Id$
//
//  SPDatabaseRename.m
//  sequel-pro
//
//  Created by David Rekowski on Apr 13, 2010
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

#import "SPDBActionCommons.h"
#import "SPDatabaseRename.h"
#import "SPTableCopy.h"

@implementation SPDatabaseRename

@synthesize dbInfo;

- (SPDatabaseInfo *)getDBInfoObject 
{
	if (dbInfo != nil) {
		return dbInfo;
	} 
	else {
		dbInfo = [[SPDatabaseInfo alloc] init];
		
		[dbInfo setConnection:[self connection]];
		[dbInfo setMessageWindow:messageWindow];
	}
	
	return dbInfo;
}

- (BOOL)renameDatabaseFrom:(NSString *)sourceDatabaseName to:(NSString *)targetDatabaseName 
{
	SPDatabaseInfo *databaseInfo = [self getDBInfoObject];

	// Check, whether the source database exists and the target database doesn't.
	NSArray *tables = nil; 
	
	BOOL sourceExists = [databaseInfo databaseExists:sourceDatabaseName];
	BOOL targetExists = [databaseInfo databaseExists:targetDatabaseName];
	
	if (sourceExists && !targetExists) {
		
		// Retrieve the list of tables/views/funcs/triggers from the source database
		tables = [connection listTablesFromDB:sourceDatabaseName];
	}
	else {
		return NO;
	}
		
	BOOL success = [self createDatabase:targetDatabaseName];
	
	SPTableCopy *dbActionTableCopy = [[SPTableCopy alloc] init];
	
	[dbActionTableCopy setConnection:connection];
	
	for (NSString *currentTable in tables) 
	{
		success = [dbActionTableCopy moveTable:currentTable from:sourceDatabaseName to:targetDatabaseName];
	}
	
	[dbActionTableCopy release];
		
	tables = [connection listTablesFromDB:sourceDatabaseName];
		
	if ([tables count] == 0) {
		[self dropDatabase:sourceDatabaseName];
	} 
		
	return success;
}

- (BOOL)createDatabase:(NSString *)newDatabaseName 
{
	NSString *createStatement = [NSString stringWithFormat:@"CREATE DATABASE %@", [newDatabaseName backtickQuotedString]];
	
	[connection queryString:createStatement];	
	
	if ([connection queryErrored]) return NO;
	
	return YES;
}

- (BOOL)dropDatabase:(NSString *)databaseName 
{
	NSString *dropStatement = [NSString stringWithFormat:@"DROP DATABASE %@", [databaseName backtickQuotedString]];
	
	[connection queryString:dropStatement];	
	
	if ([connection queryErrored]) return NO;
	
	return YES;
}

- (void)dealloc 
{
	[dbInfo release], dbInfo = nil;
}

@end