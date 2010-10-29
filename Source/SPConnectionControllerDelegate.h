//
//  $Id$
//
//  SPConnectionControllerDelegate.h
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on April 15, 2010
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

/**
 * @protocol SPConnectionControllerDelegate SPConnectionControllerDelegate.h
 *
 * @author Stuart Connolly http://stuconnolly.com/ 
 *
 * Connection controller delegate protocol.
 */
@protocol SPConnectionControllerDelegate

/**
 * Called when the connection controller starts initiating the connection process.
 *
 * @param controller The calling connection controller
 */
- (void)connectionControllerInitiatingConnection:(id)controller;

/**
 * Called when the connection controller's connection attempt failed.
 *
 * @param controller The calling connection controller
 */
- (void)connectionControllerConnectAttemptFailed:(id)controller;

@end
