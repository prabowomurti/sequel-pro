//
//  $Id$
//
//  MCPGeometryData.h
//  sequel-pro
//
//  Created by Hans-Jörg Bibiko on October 07, 2010
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

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

enum wkbType
{
	wkb_point = 1,
	wkb_linestring = 2,
	wkb_polygon = 3,
	wkb_multipoint = 4,
	wkb_multilinestring = 5,
	wkb_multipolygon = 6,
	wkb_geometrycollection = 7
};

typedef struct st_point_2d_
{
	double x;
	double y;
} st_point_2d;

@interface MCPGeometryData : NSObject <NSCoding, NSCopying>
{
	Byte *geoBuffer;
	NSUInteger bufferLength;
}

- (id)initWithBytes:(Byte*)geoData length:(NSUInteger)length;
+ (id)dataWithBytes:(Byte*)geoData length:(NSUInteger)length;
- (NSString*)description;
- (NSUInteger)length;
- (NSData*)data;
- (NSString*)wktString;

@end
