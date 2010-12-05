//
//  $Id$
//
//  SPExportUtilities.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on April 24, 2010
//  Copyright (c) 2010 Stuart Connolly. All rights reserved.
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

#import "SPExportUtilities.h"

@implementation SPExportUtilities

/**
 * Tests whether the supplied delegate conforms to the supplied protocol. Throws an exception if it doesn't.
 *
 * @param delegate The delegate that is be tested.
 * @param protocol The protocol that we are testing conformance for.
 */
void SPExportDelegateConformsToProtocol(NSObject *delegate, Protocol *protocol)
{
	// Check that the the supplied delegate conforms to the supplied protocol, if not throw an exception
	if (![delegate conformsToProtocol:protocol]) {
		[NSException raise:@"Protocol Conformance" 
					format:@"The supplied delegate does not conform to the protocol '%@'." 
				 arguments:NSStringFromProtocol(protocol)];
	}
}

@end