//
//  $Id$
//
//  SPArrayAdditions.h
//  sequel-pro
//
//  Created by Jakob Egger on March 24, 2009
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

static inline id NSArrayObjectAtIndex(NSArray *self, NSUInteger i) 
{
	return (id)CFArrayGetValueAtIndex((CFArrayRef)self, i);
}

static inline void NSMutableArrayAddObject(NSArray *self, id anObject) 
{
	CFArrayAppendValue((CFMutableArrayRef)self, anObject);
}

static inline void NSMutableArrayReplaceObject(NSArray *self, CFIndex idx, id anObject) 
{
	CFArraySetValueAtIndex((CFMutableArrayRef)self, idx, anObject);
}

@interface NSArray (SPArrayAdditions)

- (NSString *)componentsJoinedAndBacktickQuoted;
- (NSString *)componentsJoinedByCommas;
- (NSString *)componentsJoinedByPeriodAndBacktickQuoted;
- (NSString *)componentsJoinedByPeriodAndBacktickQuotedAndIgnoreFirst;
- (NSArray *)subarrayWithIndexes:(NSIndexSet *)indexes;

@end
