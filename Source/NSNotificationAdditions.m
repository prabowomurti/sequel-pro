//
//  $Id$
//
//  NSNotificationAdditions.m
//  sequel-pro
//
//  Copied from the Colloquy project; original code available from Trac at
//  http://colloquy.info/project/browser/trunk/Additions/NSNotificationAdditions.m
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

#import "NSNotificationAdditions.h"
#import "pthread.h"

@interface NSNotificationCenter (NSNotificationCenterAdditions_PrivateAPI)
+ (void)_postNotification:(NSNotification *)notification;
+ (void)_postNotificationName:(NSDictionary *)info;
+ (void)_postNotificationForwarder:(NSDictionary *)info;
@end

@implementation NSNotificationCenter (NSNotificationCenterAdditions)

- (void)postNotificationOnMainThread:(NSNotification *)notification 
{
	if (pthread_main_np()) return [self postNotification:notification];
	
	[self postNotificationOnMainThread:notification waitUntilDone:NO];
}

- (void)postNotificationOnMainThread:(NSNotification *)notification waitUntilDone:(BOOL)shouldWaitUntilDone 
{
	if (pthread_main_np()) return [self postNotification:notification];
	
	[self performSelectorOnMainThread:@selector(_postNotification:) withObject:notification waitUntilDone:shouldWaitUntilDone];
}

- (void)postNotificationOnMainThreadWithName:(NSString *)name object:(id)object 
{
	if (pthread_main_np()) return [self postNotificationName:name object:object userInfo:nil];
	
	[self postNotificationOnMainThreadWithName:name object:object userInfo:nil waitUntilDone:NO];
}

- (void)postNotificationOnMainThreadWithName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo 
{	
	if(pthread_main_np()) return [self postNotificationName:name object:object userInfo:userInfo];
	
	[self postNotificationOnMainThreadWithName:name object:object userInfo:userInfo waitUntilDone:NO];
}

- (void)postNotificationOnMainThreadWithName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo waitUntilDone:(BOOL)shouldWaitUntilDone 
{
	if (pthread_main_np()) return [self postNotificationName:name object:object userInfo:userInfo];

	NSMutableDictionary *info = [[NSMutableDictionary allocWithZone:nil] initWithCapacity:3];
	
	if (name) [info setObject:name forKey:@"name"];
	if (object) [info setObject:object forKey:@"object"];
	if (userInfo) [info setObject:userInfo forKey:@"userInfo"];

	[[self class] performSelectorOnMainThread:@selector(_postNotificationName:) withObject:info waitUntilDone:shouldWaitUntilDone];

	[info release];
}

@end

@implementation NSNotificationCenter (NSNotificationCenterAdditions_PrivateAPI)

+ (void)_postNotification:(NSNotification *)notification 
{
	[[self defaultCenter] postNotification:notification];
}

+ (void)_postNotificationName:(NSDictionary *)info 
{
	NSString *name = [info objectForKey:@"name"];
	
	id object = [info objectForKey:@"object"];
	
	NSDictionary *userInfo = [info objectForKey:@"userInfo"];

	[[self defaultCenter] postNotificationName:name object:object userInfo:userInfo];
}

+ (void)_postNotificationForwarder:(NSDictionary *)info 
{
	NSString *name = [info objectForKey:@"name"];
	
	id object = [info objectForKey:@"object"];
	
	NSDictionary *userInfo = [info objectForKey:@"userInfo"];

	[[self defaultCenter] postNotificationName:name object:object userInfo:userInfo];
}

@end
