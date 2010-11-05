//
//  $Id$
//
//  SPSXMLExporter.h
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on October 6, 2009
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
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

#import "SPExporter.h"
#import "SPXMLExporterProtocol.h"

/**
 * @class SPXMLExporter SPXMLExporter.m
 *
 * @author Stuart Connolly http://stuconnolly.com/
 *
 * XML exporter class.
 */
@interface SPXMLExporter : SPExporter 
{
	NSObject <SPXMLExporterProtocol> *delegate;
	
	NSArray *xmlDataArray;

	NSString *xmlTableName;
	NSString *xmlNULLString;
	
	BOOL xmlOutputIncludeStructure;
	BOOL xmlOutputIncludeContent;
	
	SPXMLExportFormat xmlFormat;
}

/**
 * @property delegate Exporter delegate
 */
@property (readwrite, assign) NSObject <SPXMLExporterProtocol> *delegate;

/**
 * @property xmlDataArray Data array
 */
@property (readwrite, retain) NSArray *xmlDataArray;

/**
 * @property xmlTableName Table name
 */
@property (readwrite, retain) NSString *xmlTableName;

/**
 * @property xmlNULLString XML NULL string
 */
@property (readwrite, retain) NSString *xmlNULLString;

/**
 * @property xmlOutputIncludeStructure Include table structure
 */
@property (readwrite, assign) BOOL xmlOutputIncludeStructure;

/**
 * @property xmlOutputIncludeContent Include table content
 */
@property (readwrite, assign) BOOL xmlOutputIncludeContent;

/**
 * @property xmlFormat
 */
@property (readwrite, assign) SPXMLExportFormat xmlFormat;

- (id)initWithDelegate:(NSObject *)exportDelegate;

@end
