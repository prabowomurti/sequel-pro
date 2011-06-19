//
//  $Id$
//
//  MCPConnection.m
//  MCPKit
//
//  Created by Serge Cohen (serge.cohen@m4x.org) on 08/12/2001.
//  Copyright (c) 2001 Serge Cohen. All rights reserved.
//
//  Forked by the Sequel Pro team (sequelpro.com), April 2009
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
//  More info at <http://mysql-cocoa.sourceforge.net/>
//  More info at <http://code.google.com/p/sequel-pro/>

#import "MCPConnection.h"
#import "MCPResult.h"
#import "MCPNumber.h"
#import "MCPNull.h"
#import "MCPStreamingResult.h"
#import "MCPConnectionProxy.h"
#import "MCPConnectionDelegate.h"
#import "MCPStringAdditions.h"
#import "RegexKitLite.h" // TODO: Remove along with queryDbStructureWithUserInfo 
#import "NSNotificationAdditions.h"

#include <unistd.h>
#include <mach/mach_time.h>
#include <SystemConfiguration/SystemConfiguration.h>

const NSUInteger kMCPConnectionDefaultOption = CLIENT_COMPRESS | CLIENT_REMEMBER_OPTIONS | CLIENT_MULTI_RESULTS;
const char *kMCPConnectionDefaultSocket = MYSQL_UNIX_ADDR;
const char *kMCPSSLCipherList = "DHE-RSA-AES256-SHA:AES256-SHA:DHE-RSA-AES128-SHA:AES128-SHA:AES256-RMD:AES128-RMD:DES-CBC3-RMD:DHE-RSA-AES256-RMD:DHE-RSA-AES128-RMD:DHE-RSA-DES-CBC3-RMD:RC4-SHA:RC4-MD5:DES-CBC3-SHA:DES-CBC-SHA:EDH-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC-SHA";
const NSUInteger kMCPConnection_Not_Inited = 1000;
const NSUInteger kLengthOfTruncationForLog = 100;

static BOOL sTruncateLongFieldInLogs = YES;

/**
 * Privte API
 */
@interface MCPConnection (PrivateAPI)

- (void)_getServerVersionString;
- (BOOL)_isCurrentHostReachable;
- (void)_setupKeepalivePingTimer;

@end

/**
 * Note that these aren't actually delegate methods, but are defined because queryDbStructureWithUserInfo needs
 * them. We define them here to supress compiler warnings.
 *
 * TODO: Remove along with queryDbStructureWithUserInfo
 */
@interface MCPConnection (MCPConnectionDelegate)

- (NSString *)database;
- (NSString *)connectionID;

- (NSArray *)allDatabaseNames;
- (NSArray *)allSystemDatabaseNames;
- (NSArray *)allTableNames;
- (NSArray *)allViewNames;
- (NSArray *)allSchemaKeys;

@end

@implementation MCPConnection

// Synthesize ivars
@synthesize useKeepAlive;
@synthesize delegateQueryLogging;
@synthesize connectionTimeout;
@synthesize keepAliveInterval;
@synthesize lastQueryExecutionTime;

#pragma mark -
#pragma mark Initialisation

/**
 * Initialise a MySQLConnection without making a connection, most likely useless, except with !{setConnectionOption:withArgument:}.
 *
 * Because this method is not making a connection to any MySQL server, it can not know already what the DB server encoding will be,
 * hence the encoding is set to some default (at present this is NSISOLatin1StringEncoding). Obviously this is reset to a proper
 * value as soon as a DB connection is performed.
 */
- (id)init
{
	if ((self = [super init])) {
		mConnection = mysql_init(NULL);
		mConnected = NO;
		
		if (mConnection == NULL) {
			[self autorelease];
			
			return nil;
		}
		
		encoding = [[NSString alloc] initWithString:@"utf8"];
		previousEncoding = nil;
		stringEncoding = NSUTF8StringEncoding;
		encodingUsesLatin1Transport = NO;
		previousEncodingUsesLatin1Transport = NO;
		mConnectionFlags = kMCPConnectionDefaultOption;
        
        // Anything that performs a mysql_net_read is not thread-safe: mysql queries, pings
        // Always lock the connection first. Don't use this lock directly, use the lockConnection method!
		connectionLock = [[NSConditionLock alloc] initWithCondition:MCPConnectionIdle];
		[connectionLock setName:@"MCPConnection connectionLock"];
        
		connectionHost = nil;
		connectionLogin = nil;
		connectionSocket = nil;
		connectionPassword = nil;
		useSSL = NO;
		sslKeyFilePath = nil;
		sslCertificatePath = nil;
		sslCACertificatePath = nil;
		lastKeepAliveTime = 0;
		pingThread = NULL;
		connectionProxy = nil;
		connectionStartTime = 0;
		lastQueryExecutedAtTime = CGFLOAT_MAX;
		lastDelegateDecisionForLostConnection = NSNotFound;
		queryCancelled = NO;
		queryCancelUsedReconnect = NO;
		serverVersionString = nil;
		mTimeZone = nil;
		isDisconnecting = NO;
		isReconnecting = NO;
		userTriggeredDisconnect = NO;
		automaticReconnectAttempts = 0;
		lastPingSuccess = NO;
		lastPingBlocked = NO;
		pingThreadActive = NO;
		pingFailureCount = 0;
		
		// Initialize ivar defaults
		connectionTimeout = 10;
		useKeepAlive      = YES; 
		keepAliveInterval = 60;  
		
		structure = [[NSMutableDictionary alloc] initWithCapacity:1];
		allKeysofDbStructure = [[NSMutableArray alloc] initWithCapacity:20];
		isQueryingDbStructure = 0;
		lockQuerying = NO;

		connectionThreadId     = 0;
		maxAllowedPacketSize   = 1048576;
		lastQueryExecutionTime = 0;
		lastQueryErrorId       = 0;
		lastQueryErrorMessage  = nil;
		lastQueryAffectedRows  = 0;
		lastPingSuccess	       = NO;
		delegate               = nil;
		delegateSupportsConnectionLostDecisions = NO;
		delegateResponseToWillQueryString = NO;
		
		// Enable delegate query logging by default
		delegateQueryLogging = YES;

		// Default to allowing queries to be reattempted if they fail due to connection issues
		retryAllowed = YES;
		
		// Obtain SEL references
		willQueryStringSEL = @selector(willQueryString:connection:);
		cStringSEL = @selector(cStringFromString:);
		
		// Obtain pointers
		cStringPtr = [self methodForSelector:cStringSEL];

		// Start the keepalive timer
		if ([NSThread isMainThread])
			[self _setupKeepalivePingTimer];
		else
			[self performSelectorOnMainThread:@selector(_setupKeepalivePingTimer) withObject:nil waitUntilDone:YES];
	}
	
	return self;
}

/**
 * Inialize connection using the supplied host details.
 */
- (id)initToHost:(NSString *)host withLogin:(NSString *)login usingPort:(NSUInteger)port
{
	if ((self = [self init])) {
		if (!host) host = @"";
		if (!login) login = @"";
		
		connectionHost = [[NSString alloc] initWithString:host];
		connectionLogin = [[NSString alloc] initWithString:login];
		connectionPort = port;
		connectionSocket = nil;
	}
	
	return self;
}

/**
 * Inialize connection using the supplied socket details.
 */
- (id)initToSocket:(NSString *)aSocket withLogin:(NSString *)login
{
	if ((self = [self init])) {
		if (!aSocket || ![aSocket length]) {
			aSocket = [self findSocketPath];
			if (!aSocket) aSocket = @"";
		}
		
		if (!login) login = @"";
		
		connectionHost = nil;
		connectionLogin = [[NSString alloc] initWithString:login];
		connectionSocket = [[NSString alloc] initWithString:aSocket];
		connectionPort = 0;
	}
	
	return self;
}

#pragma mark -
#pragma mark Delegate

/**
 * Get the connection's current delegate.
 */
- (id)delegate
{
	return delegate;
}

/**
 * Set the connection's delegate to the supplied object.
 */
- (void)setDelegate:(id)connectionDelegate
{
	delegate = connectionDelegate;
	
	// Check that the delegate implements willQueryString:connection: and cache the result as its used very frequently.
	delegateResponseToWillQueryString = [delegate respondsToSelector:@selector(willQueryString:connection:)];

	// Check whether the delegate supports returning a connection lost action decision
	delegateSupportsConnectionLostDecisions = [delegate respondsToSelector:@selector(connectionLost:)];
}

/**
 * Ask the delegate for the connection lost decision.  This can be called from
 * any thread, and will call itself on the main thread if necessary, updating a global
 * variable which is then returned on the child thread.
 */
- (MCPConnectionCheck)delegateDecisionForLostConnection
{

	// Return the "Disconnect" decision if the delegate doesn't support connectionLost: checks
	if (!delegateSupportsConnectionLostDecisions) return MCPConnectionCheckDisconnect;

	lastDelegateDecisionForLostConnection = NSNotFound;

	// If on the main thread, ask the delegate directly.
	// This is wrapped in a NSLock to ensure variables are completely committed for
	// thread-safe access, even though the lock is constrained to this code block.
	if ([NSThread isMainThread]) {
		NSLock *delegateDecisionLock = [[NSLock alloc] init];
		[delegateDecisionLock lock];
		lastDelegateDecisionForLostConnection = [delegate connectionLost:self];
		[delegateDecisionLock unlock];
		[delegateDecisionLock release];

	// Otherwise call ourself on the main thread, waiting until the reply is received.
	} else {

		// First check whether the application is in a modal state; if so, wait
		while ([NSApp modalWindow]) usleep(100000);

		[self performSelectorOnMainThread:@selector(delegateDecisionForLostConnection) withObject:nil waitUntilDone:YES];
	}

	return lastDelegateDecisionForLostConnection;
}

#pragma mark -
#pragma mark Connection details

/**
 * Sets or updates the connection port - for use with tunnels.
 */
- (BOOL)setPort:(NSUInteger)thePort
{
	connectionPort = thePort;
	
	return YES;
}

/**
 * Sets the password to be stored locally.
 * Providing a keychain name is much more secure.
 */
- (BOOL)setPassword:(NSString *)thePassword
{
	if (connectionPassword) [connectionPassword release], connectionPassword = nil;
	
	if (!thePassword) thePassword = @"";
	
	connectionPassword = [[NSString alloc] initWithString:thePassword];
	
	return YES;
}

/**
 * Set the connection to establish secure connections using SSL; must be
 * called before connect:.
 * This will always attempt to activate SSL if set, but depending on server
 * setup connection may sometimes proceed without SSL enabled even if requested;
 * it is suggested that after connection, -[MCPConnection isConnectedViaSSL]
 * is checked to determine whether SSL is actually active.
 */
- (void) setSSL:(BOOL)shouldUseSSL usingKeyFilePath:(NSString *)keyFilePath certificatePath:(NSString *)certificatePath certificateAuthorityCertificatePath:(NSString *)caCertificatePath
{
	useSSL = shouldUseSSL;

	// Reset the old SSL details
	if (sslKeyFilePath) [sslKeyFilePath release], sslKeyFilePath = nil;
	if (sslCertificatePath) [sslCertificatePath release], sslCertificatePath = nil;
	if (sslCACertificatePath) [sslCACertificatePath release], sslCACertificatePath = nil;

	// Set new details if provided
	if (keyFilePath) sslKeyFilePath = [[NSString alloc] initWithString:[keyFilePath stringByExpandingTildeInPath]];
	if (certificatePath) sslCertificatePath = [[NSString alloc] initWithString:[certificatePath stringByExpandingTildeInPath]];
	if (caCertificatePath) sslCACertificatePath = [[NSString alloc] initWithString:[caCertificatePath stringByExpandingTildeInPath]];
}

#pragma mark -
#pragma mark Connection proxy

/*
 * Set a connection proxy object to connect through.  This object will be retained locally,
 * and will be automatically connected/connection checked/reconnected/disconnected
 * together with the main connection.
 */
- (BOOL)setConnectionProxy:(id <MCPConnectionProxy>)proxy
{
	connectionProxy = proxy;
	[connectionProxy retain];
	
	currentProxyState = [connectionProxy state];
	[connectionProxy setConnectionStateChangeSelector:@selector(connectionProxyStateChange:) delegate:self];
	
	return YES;
}

/**
 * Handle any state changes in the associated connection proxy.
 */
- (void)connectionProxyStateChange:(id <MCPConnectionProxy>)proxy
{
	NSInteger newState = [proxy state];
	
	// Restart the tunnel if it dies - use a new thread to allow the main thread to process
	// events as required.
	if (mConnected && newState == PROXY_STATE_IDLE && currentProxyState == PROXY_STATE_CONNECTED) {
		currentProxyState = newState;
		[connectionProxy setConnectionStateChangeSelector:nil delegate:nil];

		// Trigger a reconnect
		if (!isDisconnecting) [NSThread detachNewThreadSelector:@selector(reconnect) toTarget:self withObject:nil];

		return;
	}
	
	currentProxyState = newState;
}

#pragma mark -
#pragma mark Connection

/**
 * Add a new connection method, intended for use with the init methods above.
 * Uses the stored details to instantiate a connection to the specified server,
 * including custom timeouts - used for pings, not for long-running commands.
 */
- (BOOL)connect
{
	const char *theLogin = [self cStringFromString:connectionLogin];
	const char *theHost;
	const char *thePass = NULL;
	const char *theSocket;
	void	   *theRet;
	
	// Disconnect if a connection is already active
	if (mConnected) {
		[self disconnect];
		mConnection = mysql_init(NULL);
		if (mConnection == NULL) return NO;
	}

	[self lockConnection];

	if (mConnection != NULL) {

		// Ensure the custom timeout option is set
		mysql_options(mConnection, MYSQL_OPT_CONNECT_TIMEOUT, (const void *)&connectionTimeout);

		// ensure that automatic reconnection is explicitly disabled - now handled manually.
		my_bool falseBool = FALSE;
		mysql_options(mConnection, MYSQL_OPT_RECONNECT, &falseBool);

		// Set the connection encoding to utf8
		mysql_options(mConnection, MYSQL_SET_CHARSET_NAME, [encoding UTF8String]);
	}

	// Set the host as appropriate
	if (!connectionHost || ![connectionHost length]) {
		theHost = NULL;
	} else {
		theHost = [self cStringFromString:connectionHost];
	}
	
	// Use the default socket if none is set, or set appropriately
	if (connectionSocket == nil || ![connectionSocket length]) {
		theSocket = kMCPConnectionDefaultSocket;
	} else {
		theSocket = [self cStringFromString:connectionSocket];
	}

	// Apply SSL if appropriate
	if (useSSL) {
		mysql_ssl_set(mConnection,
						sslKeyFilePath ? [sslKeyFilePath UTF8String] : NULL,
						sslCertificatePath ? [sslCertificatePath UTF8String] : NULL,
						sslCACertificatePath ? [sslCACertificatePath UTF8String] : NULL,
						NULL,
						kMCPSSLCipherList);
	}

	// Select the password from the provided method
	if (!connectionPassword) {
		if (delegate && [delegate respondsToSelector:@selector(keychainPasswordForConnection:)]) {
			thePass = [self cStringFromString:[delegate keychainPasswordForConnection:self]];
		}
	} else {		
		thePass = [self cStringFromString:connectionPassword];
	}

	// Connect
	theRet = mysql_real_connect(mConnection, theHost, theLogin, thePass, NULL, (unsigned int)connectionPort, theSocket, mConnectionFlags);
	thePass = NULL;

	if (theRet != mConnection) {
		[self unlockConnection];
		[self setLastErrorMessage:nil];

		lastQueryErrorId = mysql_errno(mConnection);
		
		return mConnected = NO;
	}

	mConnected = YES;
	userTriggeredDisconnect = NO;
	connectionStartTime = mach_absolute_time();
	lastKeepAliveTime = 0;
	automaticReconnectAttempts = 0;
	pingFailureCount = 0;
	const char *mysqlStringEncoding = mysql_character_set_name(mConnection);
	[encoding release];
	encoding = [[NSString alloc] initWithUTF8String:mysqlStringEncoding];
	stringEncoding = [MCPConnection encodingForMySQLEncoding:mysqlStringEncoding];
	encodingUsesLatin1Transport = NO;
	[self setLastErrorMessage:nil];
	connectionThreadId = mConnection->thread_id;
	[self unlockConnection];
	[self timeZone]; // Getting the timezone used by the server.
	
	// Only attempt to set the max allowed packet if we have a connection
	// The fetches may fail, in which case the class default (which should match
	// the MySQL default) will be used.
	if (mConnection != NULL) {
		isMaxAllowedPacketEditable = [self isMaxAllowedPacketEditable];
		[self fetchMaxAllowedPacket];
	}
	else {
		mConnected = NO;
		isMaxAllowedPacketEditable = NO;
	}
	
	return mConnected;
}

/**
 * Disconnect the current connection.
 */
- (void)disconnect
{
	if (isDisconnecting) return;
	isDisconnecting = YES;

	if (mConnected) {
		[self cancelCurrentQuery];
		mConnected = NO;

		// Allow any pings or query cleanups to complete - within a time limit.
		uint64_t startTime_t, currentTime_t;
		Nanoseconds elapsedNanoseconds;
		startTime_t = mach_absolute_time();
		do {
			usleep(100000);

			currentTime_t = mach_absolute_time() - startTime_t	;
			elapsedNanoseconds = AbsoluteToNanoseconds(*(AbsoluteTime *)&(currentTime_t));
			if (((double)UnsignedWideToUInt64(elapsedNanoseconds)) * 1e-9 > 10) break;
		} while (![self tryLockConnection]);
		[self unlockConnection];

		// Only close the connection if it appears to still be active, and not reading or
		// writing.  This may result in a leak, but minimises crashes.
		if (!mConnection->net.reading_or_writing && mConnection->net.vio && mConnection->net.buff) mysql_close(mConnection);
		mConnection = NULL;
	}
	
	isDisconnecting = NO;

	if (connectionProxy) {
		[connectionProxy performSelectorOnMainThread:@selector(disconnect) withObject:nil waitUntilDone:YES];
	}
	
	if (serverVersionString) [serverVersionString release], serverVersionString = nil;
	if (structure) [structure release], structure = nil;
	if (allKeysofDbStructure) [allKeysofDbStructure release], allKeysofDbStructure = nil;
	if (pingThread != NULL) pthread_cancel(pingThread), pingThread = NULL;
}

/**
 * Reconnect to the currently "active" - but possibly disconnected - connection, using the
 * stored details.
 * Error checks extensively - if this method fails, it will ask how to proceed and loop depending
 * on the status, not returning control until either a connection has been established or
 * the connection and document have been closed.
 * Runs its own autorelease pool as sometimes called in a thread following proxy changes
 * (where the return code doesn't matter).
 */
- (BOOL)reconnect
{
	NSAutoreleasePool *reconnectionPool = [[NSAutoreleasePool alloc] init];
	NSString *currentEncoding = [NSString stringWithString:encoding];
	BOOL currentEncodingUsesLatin1Transport = encodingUsesLatin1Transport;
	NSString *currentDatabase = nil;

	// Check whether a reconnection attempt is already being made - if so, wait and return the status of that reconnection attempt.
	if (isReconnecting) {
		NSDate *eventLoopStartDate;
		while (isReconnecting) {
			eventLoopStartDate = [NSDate date];
			[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
			if ([[NSDate date] timeIntervalSinceDate:eventLoopStartDate] < 0.1) {
				usleep((useconds_t)(100000 - (1000000 * [[NSDate date] timeIntervalSinceDate:eventLoopStartDate])));
			}
		}
		[reconnectionPool drain];
		return mConnected;
	}

	isReconnecting = YES;
	
	// Store the currently selected database so it can be re-set if reconnection was successful
	if (delegate && [delegate respondsToSelector:@selector(onReconnectShouldSelectDatabase:)] && [delegate onReconnectShouldSelectDatabase:self]) {
		currentDatabase = [NSString stringWithString:[delegate onReconnectShouldSelectDatabase:self]];
	}
	
	// Close the connection if it exists.
	if (mConnected) {
		mConnected = NO;

		// Allow any pings or query cleanups to complete - within a time limit.
		uint64_t startTime_t, currentTime_t;
		Nanoseconds elapsedNanoseconds;
		startTime_t = mach_absolute_time();
		do {
			usleep(100000);

			currentTime_t = mach_absolute_time() - startTime_t	;
			elapsedNanoseconds = AbsoluteToNanoseconds(*(AbsoluteTime *)&(currentTime_t));
			if (((double)UnsignedWideToUInt64(elapsedNanoseconds)) * 1e-9 > 10) break;
		} while (![self tryLockConnection]);
		[self unlockConnection];

		// Only close the connection if it's not reading or writing - this may result
		// in leaks, but minimises crashes.
		if (!mConnection->net.reading_or_writing) mysql_close(mConnection);
		mConnection = NULL;
	}
	
	isDisconnecting = NO;
	[self lockConnection];

	// If no network is present, loop for a short period waiting for one to become available
	uint64_t elapsedTime_t, networkWaitStartTime_t = mach_absolute_time();
	Nanoseconds elapsedTime;
	while (![self _isCurrentHostReachable]) {
		elapsedTime_t = mach_absolute_time() - networkWaitStartTime_t;
		elapsedTime = AbsoluteToNanoseconds(*(AbsoluteTime *)&(elapsedTime_t));
		if (((double)UnsignedWideToUInt64(elapsedTime)) * 1e-9 > 5) break;
		usleep(250000);
	}

	// If there is a proxy, ensure it's disconnected and attempt to reconnect it in blocking fashion
	if (connectionProxy) {
		[connectionProxy setConnectionStateChangeSelector:nil delegate:nil];
		if ([connectionProxy state] != PROXY_STATE_IDLE) [connectionProxy disconnect];

		// Loop until the proxy has disconnected or the connection timeout has passed
		NSDate *proxyDisconnectStartDate = [NSDate date], *eventLoopStartDate;
		while ([connectionProxy state] != PROXY_STATE_IDLE
				&& [[NSDate date] timeIntervalSinceDate:proxyDisconnectStartDate] < connectionTimeout)
		{
			eventLoopStartDate = [NSDate date];
			[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
			if ([[NSDate date] timeIntervalSinceDate:eventLoopStartDate] < 0.25) {
				usleep((useconds_t)(250000 - (1000000 * [[NSDate date] timeIntervalSinceDate:eventLoopStartDate])));
			}
		}

		// Reconnect the proxy, looping up to the connection timeout
		[connectionProxy connect];

		NSDate *proxyStartDate = [NSDate date], *interfaceInteractionTimer;
		while (1) {

			// If the proxy has connected, break out of the loop
			if ([connectionProxy state] == PROXY_STATE_CONNECTED) {
				connectionPort = [connectionProxy localPort];
				break;
			}

			// If the proxy connection attempt time has exceeded the timeout, abort.
			if ([[NSDate date] timeIntervalSinceDate:proxyStartDate] > (connectionTimeout + 1)) {
				[connectionProxy disconnect];
				break;
			}
			
			// Process events for a short time, allowing dialogs to be shown but waiting for
			// the proxy. Capture how long this interface action took, standardising the
			// overall time and extending the connection timeout by any interface time.
			interfaceInteractionTimer = [NSDate date];
			[[NSRunLoop mainRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
			//[[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
			if ([[NSDate date] timeIntervalSinceDate:interfaceInteractionTimer] < 0.25) {
				usleep((useconds_t)(250000 - (1000000 * [[NSDate date] timeIntervalSinceDate:interfaceInteractionTimer])));
			}
			if ([connectionProxy state] == PROXY_STATE_WAITING_FOR_AUTH) {
				proxyStartDate = [proxyStartDate addTimeInterval:[[NSDate date] timeIntervalSinceDate:interfaceInteractionTimer]];
			}
		}
		
		currentProxyState = [connectionProxy state];
		[connectionProxy setConnectionStateChangeSelector:@selector(connectionProxyStateChange:) delegate:self];
	}

	[self unlockConnection];
	if (!connectionProxy || [connectionProxy state] == PROXY_STATE_CONNECTED) {
		
		// Attempt to reinitialise the connection - if this fails, it will still be set to NULL.
		if (mConnection == NULL) {
			mConnection = mysql_init(NULL);
		}
		
		if (mConnection != NULL) {

			// Attempt to reestablish the connection
			[self connect];
		}
	}
	
	// If the connection was successfully established, reselect the old database and encoding if appropriate.
	if (mConnected) {
		if (currentDatabase) {
			[self selectDB:currentDatabase];
		}
		
		if (currentEncoding) {
			[self setEncoding:currentEncoding];
			[self setEncodingUsesLatin1Transport:currentEncodingUsesLatin1Transport];
		}
	}
	else {
		[self setLastErrorMessage:nil];
		
		// Default to retry
		MCPConnectionCheck failureDecision = MCPConnectionCheckReconnect;
		
		// Ask delegate what to do
		if (delegateSupportsConnectionLostDecisions) {
			failureDecision = [self delegateDecisionForLostConnection];
		}
		
		switch (failureDecision) {				
			case MCPConnectionCheckDisconnect:
				[self setLastErrorMessage:NSLocalizedString(@"User triggered disconnection", @"User triggered disconnection")];
				userTriggeredDisconnect = YES;
				[reconnectionPool release];
				isReconnecting = NO;
				return NO;				
			default:
				[reconnectionPool release];
				isReconnecting = NO;
				return [self reconnect];
		}
	}

	[reconnectionPool release];
	isReconnecting = NO;
	return mConnected;
}

/**
 * Returns YES if the MCPConnection is connected to a DB, NO otherwise.
 */
- (BOOL)isConnected
{
	return mConnected;
}

/**
 * Returns YES if the MCPConnection is connected to a server via SSL, NO otherwise.
 */
- (BOOL)isConnectedViaSSL
{
	if (![self isConnected]) return NO;
	return (mysql_get_ssl_cipher(mConnection))?YES:NO;
}

/**
 * Returns YES if the user chose to disconnect at the last "connection failure"
 * prompt, NO otherwise.
 */
- (BOOL)userTriggeredDisconnect
{
	return userTriggeredDisconnect;
}

/**
 * Checks if the connection to the server is still on.
 * If not, tries to reconnect (changing no parameters from the MYSQL pointer).
 * This method just uses mysql_ping().
 */
- (BOOL)checkConnection
{
	if (!mConnected) return NO;

	BOOL connectionVerified = FALSE;
	
	// Check whether the connection is still operational via a wrapped version of MySQL ping.
	connectionVerified = [self pingConnectionUsingLoopDelay:400];

	// If the connection doesn't appear to be responding, and we can still attempt an automatic
	// reconnect (only once each connection - eg an automatic reconnect failure prevents loops,
	// but an automatic reconnect success resets the flag for another attempt in future)
	if (!connectionVerified && automaticReconnectAttempts < 1) {
		automaticReconnectAttempts++;
		
		// Note that a return of "NO" here has already asked the user, so if reconnect fails,
		// return failure.
		if ([self reconnect]) {
			return YES;
		}
		return NO;
	}

	// If automatic reconnect cannot be used, show a dialog asking how to proceed
	if (!connectionVerified) {
		
		// Ask delegate what to do, defaulting to "disconnect".
		MCPConnectionCheck failureDecision = MCPConnectionCheckDisconnect;
		if (delegateSupportsConnectionLostDecisions) {
			failureDecision = [self delegateDecisionForLostConnection];
		}
		
		switch (failureDecision) {

			// 'Reconnect' has been selected. Request a reconnect, and retry.
			case MCPConnectionCheckReconnect:
				[self reconnect];
				
				return [self checkConnection];
				
			// 'Disconnect' has been selected. The parent window should already have
			// triggered UI-specific actions, and may have disconnected already; if
			// not, disconnect, and clean up.
			case MCPConnectionCheckDisconnect:
				if (mConnected) [self disconnect];
				[self setLastErrorMessage:NSLocalizedString(@"User triggered disconnection", @"User triggered disconnection")];
				userTriggeredDisconnect = YES;
				return NO;
				
			// 'Retry' has been selected - return a recursive call.
			case MCPConnectionCheckRetry:
				return [self checkConnection];
		}
		
		// If a connection exists, check whether the thread id differs; if so, the connection has
		// probably been reestablished and we need to reset the connection encoding
	} else if (connectionThreadId != mConnection->thread_id) [self restoreConnectionDetails];
	
	return connectionVerified;
}

/**
 * Restore the connection encoding details as necessary based on the delegate-provided
 * details.
 */
- (void)restoreConnectionDetails
{
	connectionThreadId = mConnection->thread_id;
	connectionStartTime = mach_absolute_time();
	[self fetchMaxAllowedPacket];

	[self setEncoding:encoding];
	[self setEncodingUsesLatin1Transport:encodingUsesLatin1Transport];
}

/**
 * Allow controlling over whether queries are allowed to retry after a connection failure.
 * This defaults to YES on init, and is intended to allow temporary disabling in situations
 * where the query result is checked and displayed to the user without any repurcussions on
 * failure.
 */
- (void)setAllowQueryRetries:(BOOL)allow
{
	retryAllowed = allow;
}

/**
 * Retrieve the time elapsed since the connection was established, in seconds.
 * This time is retrieved in a monotonically increasing fashion and is high
 * precision; it is used internally for query timing, and is reset on reconnections.
 */
- (double)timeConnected
{
	if (connectionStartTime == 0) return -1;

	uint64_t currentTime_t = mach_absolute_time() - connectionStartTime;
	Nanoseconds elapsedTime = AbsoluteToNanoseconds(*(AbsoluteTime *)&(currentTime_t));

	return (((double)UnsignedWideToUInt64(elapsedTime)) * 1e-9);
}

#pragma mark -
#pragma mark Pinging and keepalive

/**
 * This function provides a method of pinging the remote server while also enforcing
 * the specified connection time.  This is required because low-level net reads can
 * block indefinitely if the remote server disappears or on network issues - setting
 * the MYSQL_OPT_READ_TIMEOUT (and the WRITE equivalent) would "fix" ping, but cause
 * long queries to be terminated.
 * The supplied loop delay number controls how tight the thread checking loop is, in
 * microseconds, to allow differentiating foreground and background pings.
 * Unlike mysql_ping, this function returns FALSE on failure and TRUE on success.
 */
- (BOOL)pingConnectionUsingLoopDelay:(NSUInteger)loopDelay
{
	if (!mConnected) return NO;

	uint64_t pingStartTime_t, currentTime_t;
	Nanoseconds elapsedNanoseconds;
	BOOL threadCancelled = NO;

	// Set up a query lock
	[self lockConnection];

	lastPingSuccess = NO;
	lastPingBlocked = NO;
	pingThreadActive = YES;

	// Use a ping timeout defaulting to thirty seconds, but using the connection timeout if set
	NSInteger pingTimeout = 30;
	if (connectionTimeout > 0) pingTimeout = connectionTimeout;

	// Set up a struct containing details the ping task will need
	MCPConnectionPingDetails pingDetails;
	pingDetails.mySQLConnection = mConnection;
	pingDetails.lastPingSuccessPointer = &lastPingSuccess;
	pingDetails.pingActivePointer = &pingThreadActive;

	// Create a pthread for the ping
	pthread_attr_t attr;
	pthread_attr_init(&attr);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
	pthread_create(&pingThread, &attr, (void *)&backgroundPingTask, &pingDetails);

	// Record the ping start time
	pingStartTime_t = mach_absolute_time();

	// Loop until the ping completes
	do {
		usleep((useconds_t)loopDelay);

		// If the ping timeout has been exceeded, force a timeout; double-check that the
		// thread is still active.
		currentTime_t = mach_absolute_time() - pingStartTime_t	;
		elapsedNanoseconds = AbsoluteToNanoseconds(*(AbsoluteTime *)&(currentTime_t));
		if (((double)UnsignedWideToUInt64(elapsedNanoseconds)) * 1e-9 > pingTimeout && pingThreadActive && !threadCancelled) {
			pthread_cancel(pingThread);
			threadCancelled = YES;

		// If the timeout has been exceeded by an additional two seconds, and the thread is
		// still active, kill the thread.  This can occur in certain network conditions causing
		// a blocking read.
		} else if (((double)UnsignedWideToUInt64(elapsedNanoseconds)) * 1e-9 > (pingTimeout + 2) && pingThreadActive) {
			pthread_kill(pingThread, SIGUSR1);	
			pingThreadActive = NO;
			lastPingBlocked = YES;
		}
	} while (pingThreadActive);

	// Clean up
	pingThread = NULL;
	pthread_attr_destroy(&attr);

    // Unlock the connection
	[self unlockConnection];

	return lastPingSuccess;
}

/**
 * Actually perform a keepalive ping - intended for use within a pthread.
 */
void backgroundPingTask(void *ptr)
{
	MCPConnectionPingDetails *pingDetails = (MCPConnectionPingDetails *)ptr;

	// Set up a cleanup routine
	pthread_cleanup_push(pingThreadCleanup, pingDetails);

	// Set up a signal handler for SIGUSR1, to handle forced timeouts.
	signal(SIGUSR1, forceThreadExit);

	// Perform a ping
	*(pingDetails->lastPingSuccessPointer) = (BOOL)(!mysql_ping(pingDetails->mySQLConnection));

	// Call the cleanup routine
	pthread_cleanup_pop(1);
}

/**
 * Support forcing a thread to exit as a result of a signal.
 */
void forceThreadExit(int signalNumber)
{
	pthread_exit(NULL);
}

void pingThreadCleanup(void *pingDetails)
{
	MCPConnectionPingDetails *pingDetailsStruct = pingDetails;
	*(pingDetailsStruct->pingActivePointer) = NO;
}

/**
 * Keeps a connection alive by running a ping.
 * This method is called every ten seconds and spawns a thread which determines
 * whether or not it should perform a ping.
 */
- (void)keepAlive:(NSTimer *)theTimer
{

	// Do nothing if not connected or if keepalive is disabled
	if (!mConnected || !useKeepAlive) return;

	// Check to see whether a ping is required.  First, compare the last query
	// and keepalive times against the keepalive interval.
	// Compare against interval-1 to allow default keepalive intervals to repeat
	// at the correct intervals (eg no timer interval delay).
	double timeConnected = [self timeConnected];
	if (timeConnected - lastQueryExecutedAtTime < keepAliveInterval - 1
		|| timeConnected - lastKeepAliveTime < keepAliveInterval - 1)
	{
		return;
	}

	// Attempt to lock the connection. If the connection is currently busy,
    // we don't need a ping.
	if (![self tryLockConnection]) return;
	[self unlockConnection];

	// Store the ping time
	lastKeepAliveTime = timeConnected;

	[NSThread detachNewThreadSelector:@selector(threadedKeepAlive) toTarget:self withObject:nil];
}

/**
 * A threaded keepalive to avoid blocking the interface.  Performs safety
 * checks, and then creates a child pthread to actually ping the connection,
 * forcing the thread to close after the timeout if it hasn't closed already.
 */
- (void)threadedKeepAlive
{

	// If the maximum number of ping failures has been reached, trigger a reconnect
	if (lastPingBlocked || pingFailureCount >= 3) {
		NSAutoreleasePool *connectionPool = [[NSAutoreleasePool alloc] init];
		[self reconnect];
		[connectionPool drain];
		return;
	}

	// Otherwise, perform a background ping.
	BOOL pingResult = [self pingConnectionUsingLoopDelay:10000];
	if (pingResult) {
		pingFailureCount = 0;
	} else {
		pingFailureCount++;
	}
}

#pragma mark -
#pragma mark Server versions

/**
 * Return the server version string, or nil on failure.
 */
- (NSString *)serverVersionString
{
	if (mConnected) {
		if (serverVersionString == nil) {
			[self _getServerVersionString];
		}

		if (serverVersionString) {
			return [NSString stringWithString:serverVersionString];
		}
	}

	return nil;
}

/**
 * rReturn the server major version or -1 on fail
 */
- (NSInteger)serverMajorVersion
{
	
	if (mConnected) {
		if (serverVersionString == nil) {
			[self _getServerVersionString];
		}

		if (serverVersionString != nil) {
			return [[[serverVersionString componentsSeparatedByString:@"."] objectAtIndex:0] integerValue];
		} 
	} 
	
	return -1;
}

/**
 * Return the server minor version or -1 on fail
 */
- (NSInteger)serverMinorVersion
{
	
	if (mConnected) {
		if (serverVersionString == nil) {
			[self _getServerVersionString];
		}
		
		if(serverVersionString != nil) {
			return [[[serverVersionString componentsSeparatedByString:@"."] objectAtIndex:1] integerValue];
		}
	}
	
	return -1;
}

/**
 * Return the server release version or -1 on fail
 */
- (NSInteger)serverReleaseVersion
{
	if (mConnected) {
		if (serverVersionString == nil) {
			[self _getServerVersionString];
		}
		
		if (serverVersionString != nil) {
			NSString *s = [[serverVersionString componentsSeparatedByString:@"."] objectAtIndex:2];
			return [[[s componentsSeparatedByString:@"-"] objectAtIndex:0] integerValue];
		}
	}
	
	return -1;
}

#pragma mark -
#pragma mark MySQL defaults

/**
 * This class is used to keep a connection with a MySQL server, it correspond to the MYSQL structure of the C API, or the database handle of the PERL DBI/DBD interface.
 *
 * You have to start any work on a MySQL server by getting a working MCPConnection object.
 *
 * Most likely you will use this kind of code:
 * 
 *
 *   MCPConnection	*theConnec = [MCPConnection alloc];
 *   MCPResult	*theRes;
 *   
 *   theConnec = [theConnec initToHost:@"albert.com" withLogin:@"toto" password:@"albert" usingPort:0];
 *   [theConnec selectDB:@"db1"];
 *   theRes = [theConnec queryString:@"select * from table1"];
 *   ...
 *
 * Failing to properly release your MCPConnection(s) object might cause a MySQL crash!!! (recovered if the server was started using mysqld_safe).
 *
 * Gets a proper Locale dictionary to use formater to parse strings from MySQL.
 * For example strings representing dates should give a proper Locales for use with methods such as NSDate::dateWithNaturalLanguageString: locales:
 */
+ (NSDictionary *)getMySQLLocales
{
	NSMutableDictionary	*theLocalDict = [NSMutableDictionary dictionaryWithCapacity:12];
	
	[theLocalDict setObject:@"." forKey:@"NSDecimalSeparator"];
	
	return [NSDictionary dictionaryWithDictionary:theLocalDict];
}

/**
 * Gets a proper NSStringEncoding according to the given MySQL charset.
 */
+ (NSStringEncoding) encodingForMySQLEncoding:(const char *)mysqlEncoding
{
	// Unicode encodings:
	if (!strncmp(mysqlEncoding, "utf8", 4)) {
		return NSUTF8StringEncoding;
	}
	if (!strncmp(mysqlEncoding, "ucs2", 4)) {
		return NSUnicodeStringEncoding;
	}	
	
	// Roman alphabet encodings:
	if (!strncmp(mysqlEncoding, "ascii", 5)) {
		return NSASCIIStringEncoding;
	}
	if (!strncmp(mysqlEncoding, "latin1", 6)) {
		return NSISOLatin1StringEncoding;
	}
	if (!strncmp(mysqlEncoding, "macroman", 8)) {
		return NSMacOSRomanStringEncoding;
	}
	
	// Roman alphabet with central/east european additions:
	if (!strncmp(mysqlEncoding, "latin2", 6)) {
		return NSISOLatin2StringEncoding;
	}
	if (!strncmp(mysqlEncoding, "cp1250", 6)) {
		return NSWindowsCP1250StringEncoding;
	}
	if (!strncmp(mysqlEncoding, "win1250", 7)) {
		return NSWindowsCP1250StringEncoding;
	}
	if (!strncmp(mysqlEncoding, "cp1257", 6)) {
		return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsBalticRim);
	}
	
	// Additions for Turkish:
	if (!strncmp(mysqlEncoding, "latin5", 6)) {
		return NSWindowsCP1254StringEncoding;
	}
	
	// Greek:
	if (!strncmp(mysqlEncoding, "greek", 5)) {
		return NSWindowsCP1253StringEncoding;
	}
	
	// Cyrillic:	
	if (!strncmp(mysqlEncoding, "win1251ukr", 6)) {
		return NSWindowsCP1251StringEncoding;
	}
	if (!strncmp(mysqlEncoding, "cp1251", 6)) {
		return NSWindowsCP1251StringEncoding;
	}
	if (!strncmp(mysqlEncoding, "koi8_ru", 6)) {
		return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingKOI8_R);
	}
	if (!strncmp(mysqlEncoding, "koi8_ukr", 6)) {
		return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingKOI8_R);
	}
	 
	// Arabic:
	if (!strncmp(mysqlEncoding, "cp1256", 6)) {
		return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsArabic);
	}
	
	// Hebrew:
	if (!strncmp(mysqlEncoding, "hebrew", 6)) {
		CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinHebrew);
	}
	
	// Asian:
	if (!strncmp(mysqlEncoding, "ujis", 4)) {
		return NSJapaneseEUCStringEncoding;
	}
	if (!strncmp(mysqlEncoding, "sjis", 4)) {
		return  NSShiftJISStringEncoding;
	}
	if (!strncmp(mysqlEncoding, "big5", 4)) {
		return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5);
	}
	if (!strncmp(mysqlEncoding, "euc_kr", 6)) {
		return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_KR);
	}
	if (!strncmp(mysqlEncoding, "euckr", 5)) {
		return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_KR);
	}
	
	// Default to iso latin 1, even if it is not exact (throw an exception?)    
	NSLog(@"WARNING: unknown name for MySQL encoding '%s'!\n\t\tFalling back to iso-latin1.", mysqlEncoding);
	
	return NSISOLatin1StringEncoding;
}

/**
 * Gets a MySQL charset for the given NSStringEncoding.
 * If the NSStringEncoding was not matched, nil is returned.
 */
+ (NSString *) mySQLEncodingForStringEncoding:(NSStringEncoding)stringEncoding
{
	switch (stringEncoding) {

		// Unicode encodings:
		case NSUTF8StringEncoding:
			return @"utf8";
		case NSUnicodeStringEncoding:
			return @"ucs2";
		
		// Roman alphabet encodings:
		case NSASCIIStringEncoding:
			return @"ascii";
		case NSISOLatin1StringEncoding:
		case NSWindowsCP1252StringEncoding:
			return @"latin1";
		case NSMacOSRomanStringEncoding:
			return @"macroman";
		
		// Roman alphabet with central/east european additions:
		case NSISOLatin2StringEncoding:
			return @"latin2";
		case NSWindowsCP1250StringEncoding:
			return @"cp1250";
		
		// Turkish
		case NSWindowsCP1254StringEncoding:
			return @"latin5";
		
		// Greek:
		case NSWindowsCP1253StringEncoding:
			return @"greek";
		
		// Cyrillic:	
		case NSWindowsCP1251StringEncoding:
			return @"cp1251";
		 		
		// Asian:
		case NSJapaneseEUCStringEncoding:
			return @"ujis";
		case NSShiftJISStringEncoding:
			return @"sjis";

		default:
			return nil;
	}
}

/**
 * Returns the default charset of the library mysqlclient used.
 */
+ (NSStringEncoding)defaultMySQLEncoding
{
	return [MCPConnection encodingForMySQLEncoding:"utf8_general_ci"];
}

#pragma mark -
#pragma mark Class maintenance

/**
  *
  */
+ (void)setTruncateLongFieldInLogs:(BOOL)iTruncFlag
{
	sTruncateLongFieldInLogs = iTruncFlag;
}

/**
 *
 */
+ (BOOL)truncateLongField
{
	return sTruncateLongFieldInLogs;
}

/**
 * This method is to be used for getting special option for a connection, in which case the MCPConnection 
 * has to be inited with the init method, then option are selected, finally connection is done using one 
 * of the connect methods:
 *
 * MCPConnection	*theConnect = [[MCPConnection alloc] init];
 *
 * [theConnect setConnectionOption: option toValue: value];
 * [theConnect connectToHost:albert.com withLogin:@"toto" password:@"albert" port:0];
 *
 */
- (BOOL)setConnectionOption:(NSInteger)option toValue:(BOOL)value
{
	// So far do nothing except for testing if it's proper time for setting option 
	// What about if some option where setted and a connection is made again with connectTo...
	if ((mConnected)  || (! mConnection)) {
		return FALSE;
	}
	
	if (value) { //Set this option to true
		mConnectionFlags |= option;
	}
	else { //Set this option to false
		mConnectionFlags &= (! option);
	}
	
	return YES;
}

/**
 * The method used by !{initToHost:withLogin:password:usingPort:} and !{initToSocket:withLogin:password:}. Same information and use of the parameters:
 *
 * - login is the user name
 * - pass is the password corresponding to the user name
 * - host is the hostname or IP adress
 * - port is the TCP port to use to connect. If port = 0, uses the default port from mysql.h
 * - socket is the path to the socket (for the localhost)
 *
 * The socket is used if the host is set to !{@"localhost"}, to an empty or a !{nil} string
 * For the moment the implementation might not be safe if you have a nil pointer to one of the NSString* variables (underestand: I don't know what the result will be).
 */
- (BOOL)connectWithLogin:(NSString *)login password:(NSString *)pass host:(NSString *)host port:(NSUInteger)port socket:(NSString *)aSocket
{
	const char *theLogin  = [self cStringFromString:login];
	const char *theHost	  = [self cStringFromString:host];
	const char *thePass	  = [self cStringFromString:pass];
	const char *theSocket = [self cStringFromString:aSocket];
	void	   *theRet;
	
	// Disconnect if it was already connected
	if (mConnected) {
		[self disconnect];
		mConnection = mysql_init(NULL);
		if (mConnection == NULL) return NO;
	}
	
	if (mConnection != NULL) {

		// Ensure the custom timeout option is set
		mysql_options(mConnection, MYSQL_OPT_CONNECT_TIMEOUT, (const void *)&connectionTimeout);

		// ensure that automatic reconnection is explicitly disabled - now handled manually.
		my_bool falseBool = FALSE;
		mysql_options(mConnection, MYSQL_OPT_RECONNECT, &falseBool);

		// Set the connection encoding to utf8
		mysql_options(mConnection, MYSQL_SET_CHARSET_NAME, [encoding UTF8String]);
	}

	if ([host isEqualToString:@""]) {
		theHost = NULL;
	}
	
	if (theSocket == NULL) {
		theSocket = kMCPConnectionDefaultSocket;
	}

	// Apply SSL if appropriate
	if (useSSL) {
		mysql_ssl_set(mConnection,
						sslKeyFilePath ? [sslKeyFilePath UTF8String] : NULL,
						sslCertificatePath ? [sslCertificatePath UTF8String] : NULL,
						sslCACertificatePath ? [sslCACertificatePath UTF8String] : NULL,
						NULL,
						kMCPSSLCipherList);
	}
	
	theRet = mysql_real_connect(mConnection, theHost, theLogin, thePass, NULL, (unsigned int)port, theSocket, mConnectionFlags);
	if (theRet != mConnection) {
		return mConnected = NO;
	}
	
	mConnected = YES;
	const char *mysqlStringEncoding = mysql_character_set_name(mConnection);
	[encoding release];
	encoding = [[NSString alloc] initWithUTF8String:mysqlStringEncoding];
	stringEncoding = [MCPConnection encodingForMySQLEncoding:mysqlStringEncoding];
	encodingUsesLatin1Transport = NO;
	
	// Getting the timezone used by the server.
	[self timeZone]; 
	
	return mConnected;
}

/**
 * Selects a database to work with.
 *
 * The MCPConnection object needs to be properly inited and connected to a server.
 * If a connection is not yet set or the selection of the database didn't work, returns NO. Returns YES in normal cases where the database is properly selected.
 *
 * So far, if dbName is a nil pointer it will return NO (as if it cannot connect), most likely this will throw an exception in the future.
 */
- (BOOL)selectDB:(NSString *) dbName
{
	if (!mConnected) return NO;
	
	if (![self checkConnection]) return NO;
	
	// Here we should throw an exception, impossible to select a databse if the string is indeed a nil pointer
	if (dbName == nil) return NO;
	
	if (mConnected) {

		// Ensure the change is made in UTF8 to avoid encoding problems
		BOOL changeEncoding = ![[self encoding] isEqualToString:@"utf8"];
		if (changeEncoding) {
			[self storeEncodingForRestoration];
			[self setEncoding:@"utf8"];
		}

		const char	 *theDBName = [self cStringFromString:dbName];
		[self lockConnection];
		if (0 == mysql_select_db(mConnection, theDBName)) {
			[self unlockConnection];
			return YES;
		}
		[self unlockConnection];

		if (changeEncoding) [self restoreStoredEncoding];
	}
	
	[self setLastErrorMessage:nil];
	
	lastQueryErrorId = mysql_errno(mConnection);
	
	if (connectionProxy) {
		[connectionProxy disconnect];
	}
	
	return NO;
}

#pragma mark -
#pragma mark Error information

/**
 * Returns whether the last query errored or not.
 */
- (BOOL)queryErrored
{
	return (lastQueryErrorMessage)?YES:NO;
}

/**
 * Returns a string with the last MySQL error message on the connection.
 */
- (NSString *)getLastErrorMessage
{
	return lastQueryErrorMessage;
}

/**
 * Sets the string for the last MySQL error message on the connection,
 * managing memory as appropriate.  Supply a nil string to store the
 * last error on the connection.
 */
- (void)setLastErrorMessage:(NSString *)theErrorMessage
{
	if (!theErrorMessage) theErrorMessage = [self stringWithCString:mysql_error(mConnection)];
	
	if (lastQueryErrorMessage) [lastQueryErrorMessage release], lastQueryErrorMessage = nil;
	if (theErrorMessage && [theErrorMessage length]) lastQueryErrorMessage = [[NSString alloc] initWithString:theErrorMessage];
}

/**
 * Returns the ErrorID of the last MySQL error on the connection.
 */
- (NSUInteger)getLastErrorID
{
	return lastQueryErrorId;
}

/**
 * Determines whether a supplied error number can be classed as a connection error.
 */
+ (BOOL)isErrorNumberConnectionError:(NSInteger)theErrorNumber
{
	switch (theErrorNumber) {
		case 2001: // CR_SOCKET_CREATE_ERROR
		case 2002: // CR_CONNECTION_ERROR
		case 2003: // CR_CONN_HOST_ERROR
		case 2004: // CR_IPSOCK_ERROR
		case 2005: // CR_UNKNOWN_HOST
		case 2006: // CR_SERVER_GONE_ERROR
		case 2007: // CR_VERSION_ERROR
		case 2009: // CR_WRONG_HOST_INFO
		case 2012: // CR_SERVER_HANDSHAKE_ERR
		case 2013: // CR_SERVER_LOST
		case 2027: // CR_MALFORMED_PACKET
		case 2032: // CR_DATA_TRUNCATED
		case 2047: // CR_CONN_UNKNOW_PROTOCOL
		case 2048: // CR_INVALID_CONN_HANDLE
		case 2050: // CR_FETCH_CANCELED
		case 2055: // CR_SERVER_LOST_EXTENDED
			return YES;
	}
	
	return NO;
}

/**
 * Update error messages - for example after a streaming result has finished processing.
 */
- (void)updateErrorStatuses
{
	[self setLastErrorMessage:nil];
	lastQueryErrorId = mysql_errno(mConnection);
}

#pragma mark -
#pragma mark Queries

/**
 * Takes a NSData object and transform it in a proper string for sending to the server in between quotes.
 */
- (NSString *)prepareBinaryData:(NSData *)theData
{
	const char			*theCDataBuffer = [theData bytes];
	unsigned long		theLength = [theData length];
	char					*theCEscBuffer = (char *)calloc(sizeof(char),(theLength*2) + 1);
	NSString				*theReturn;

	// mysql_hex_string requires an active connection.
	// If no connection is present, and no automatic reconnections can be made, return nil.
	if (!mConnected && ![self checkConnection]) {
		
		// Inform the delegate that there is no connection available
		if (delegate && [delegate respondsToSelector:@selector(noConnectionAvailable:)]) {
			[delegate noConnectionAvailable:self];
		}
		
		return nil;
	}
	
	// If thirty seconds have elapsed since the last query, check the connection.
	// This minimises the impact of continuous additional connection checks, but handles
	// most network issues and keeps high read/write timeouts for long queries.
	if ([self timeConnected] - lastQueryExecutedAtTime > 30) {
		if (![self checkConnection]) return nil;
		lastQueryExecutedAtTime = [self timeConnected];
	}

	// Using the mysql_hex_string function : (NO other solution found to be able to support blobs while using UTF-8 charset).
	mysql_hex_string(theCEscBuffer, theCDataBuffer, theLength);
	theReturn = [NSString stringWithFormat:@"%s", theCEscBuffer];
	free (theCEscBuffer);
	return theReturn;
}

/**
 * Takes a string and escape any special character (like single quote : ') so that the string can be used directly in a query.
 */
- (NSString *)prepareString:(NSString *)theString
{
	NSData				*theCData = [theString dataUsingEncoding:stringEncoding allowLossyConversion:YES];
	unsigned long		theLength = [theCData length];
	char					*theCEscBuffer;
	NSString				*theReturn;
	unsigned long		theEscapedLength;
	
	if (theString == nil) {
		// In the mean time, no one should call this method on a nil string, the test should be done before by the user of this method.
		return @"";
	}

	// mysql_real_escape_string requires an active connection.
	// If no connection is present, and no automatic reconnections can be made, return nil.
	if (!mConnected && ![self checkConnection]) {
		
		// Inform the delegate that there is no connection available
		if (delegate && [delegate respondsToSelector:@selector(noConnectionAvailable:)]) {
			[delegate noConnectionAvailable:self];
		}
		
		return nil;
	}
	
	// If thirty seconds have elapsed since the last query, check the connection.
	// This minimises the impact of continuous additional connection checks, but handles
	// most network issues and keeps high read/write timeouts for long queries.
	if ([self timeConnected] - lastQueryExecutedAtTime > 30) {
		if (![self checkConnection]) return nil;
		lastQueryExecutedAtTime = [self timeConnected];
	}

	theCEscBuffer = (char *)calloc(sizeof(char),(theLength * 2) + 1);
	theEscapedLength = mysql_real_escape_string(mConnection, theCEscBuffer, [theCData bytes], theLength);
	theReturn = [[NSString alloc] initWithData:[NSData dataWithBytes:theCEscBuffer length:theEscapedLength] encoding:stringEncoding];
	free(theCEscBuffer);
	
	return [theReturn autorelease];    
}

/** 
 * Use the class of the theObject to know how it should be prepared for usage with the database.
 * If theObject is a string, this method will put single quotes to both its side and escape any necessary
 * character using prepareString: method. If theObject is NSData, the prepareBinaryData: method will be
 * used instead.
 *
 * For NSNumber object, the number is just quoted, for calendar dates, the calendar date is formatted in
 * the preferred format for the database.
 */
- (NSString *)quoteObject:(id)theObject
{
	if ((! theObject) || ([theObject isNSNull])) {
		return @"NULL";
	}
	
	if ([theObject isKindOfClass:[NSData class]]) {
		return [NSString stringWithFormat:@"X'%@'", [self prepareBinaryData:(NSData *) theObject]];
	}
	
	if ([theObject isKindOfClass:[NSString class]]) {
		return [NSString stringWithFormat:@"'%@'", [self prepareString:(NSString *) theObject]];
	}
	
	if ([theObject isKindOfClass:[NSNumber class]]) {
		return [NSString stringWithFormat:@"%@", theObject];
	}
	
	if ([theObject isKindOfClass:[NSCalendarDate class]]) {
		return [NSString stringWithFormat:@"'%@'", [(NSCalendarDate *)theObject descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"]];
	}

	return [NSString stringWithFormat:@"'%@'", [self prepareString:[theObject description]]];
}

/**
 * Takes a query string and return an MCPResult object holding the result of the query.
 * The returned MCPResult is not retained, the client is responsible for that (it's autoreleased before being returned). If no field are present in the result (like in an insert query), will return nil (#{difference from previous version implementation}). Though, if their is at least one field the result will be non nil (even if no row are selected).
 *
 * Note that if you want to use this method with binary data (in the query), you should use !{prepareBinaryData:} to include the binary data in the query string. Also if you want to include in your query a string containing any special character (\, ', " ...) then you should use !{prepareString}.
 */
- (MCPResult *)queryString:(NSString *)query
{
	return [self queryString:query usingEncoding:stringEncoding streamingResult:MCPStreamingNone];
}

/**
 * Takes a query string and returns an MCPStreamingResult representing the result of the query.
 * If no fields are present in the result, nil will be returned.
 * Uses safe/fast mode, which may use more memory as results are downloaded.
 */
- (MCPStreamingResult *)streamingQueryString:(NSString *)query
{
	return [self queryString:query usingEncoding:stringEncoding streamingResult:MCPStreamingFast];
}

/**
 * Takes a query string and returns an MCPStreamingResult representing the result of the query.
 * If no fields are present in the result, nil will be returned.
 * Can be used in either fast/safe mode, where data is downloaded as fast as possible to avoid
 * blocking the server, or in full streaming mode for lowest memory usage but potentially blocking
 * the table.
 */
- (MCPStreamingResult *)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)fullStream
{
	return [self queryString:query usingEncoding:stringEncoding streamingResult:(fullStream?MCPStreamingLowMem:MCPStreamingFast)];
}

/**
 * Error checks connection extensively - if this method fails due to a connection error, it will ask how to
 * proceed and loop depending on the status, not returning control until either the query has been executed
 * and the result can be returned or the connection and document have been closed.
 */
- (id)queryString:(NSString *) query usingEncoding:(NSStringEncoding)aStringEncoding streamingResult:(NSInteger) streamResultType
{
	MCPResult		*theResult = nil;
	double			queryStartTime, queryExecutionTime;
	const char		*theCQuery;
	unsigned long	theCQueryLength;
	NSInteger		queryResultCode;
	NSInteger		queryErrorId = 0;
	my_ulonglong	queryAffectedRows = 0;
	NSInteger		currentMaxAllowedPacket = -1;
	BOOL			isQueryRetry = NO;
	NSString		*queryErrorMessage = nil;

	// Reset the query cancelled boolean
	queryCancelled = NO;

	// If no connection is present, and no automatic reconnections can be made, return nil.
	if (!mConnected && ![self checkConnection]) {
		// Write a log entry
		if ([delegate respondsToSelector:@selector(queryGaveError:connection:)]) [delegate queryGaveError:@"No connection available!" connection:self];
		
		// Notify that the query has been performed
		[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryHasBeenPerformed" object:delegate];
		
		// Inform the delegate that there is no connection available
		if (delegate && [delegate respondsToSelector:@selector(noConnectionAvailable:)]) {
			[delegate noConnectionAvailable:self];
		}
		
		return nil;
	}
	
	// Inform the delegate about the query if logging is enabled and delegate responds to willQueryString:connection:
	if (delegateQueryLogging && delegateResponseToWillQueryString) {
		[delegate willQueryString:query connection:self];
	}
	
	// If thirty seconds have elapsed since the last query, check the connection.
	// This minimises the impact of continuous additional connection checks, but handles
	// most network issues and keeps high read/write timeouts for long queries.
	if ([self timeConnected] - lastQueryExecutedAtTime > 30
		&& ![self checkConnection])
	{
		return nil;
	}

	// Derive the query string in the correct encoding
	NSData *d = NSStringDataUsingLossyEncoding(query, aStringEncoding, 1);
	theCQuery = [d bytes];
	// Set the length of the current query
	theCQueryLength = [d length];
	
	// Check query length against max_allowed_packet; if it is larger, the
	// query would error, so if max_allowed_packet is editable for the user
	// increase it for the current session and reconnect.
	if (maxAllowedPacketSize < theCQueryLength) {
		
		if (isMaxAllowedPacketEditable) {
			
			currentMaxAllowedPacket = maxAllowedPacketSize;
			[self setMaxAllowedPacketTo:strlen(theCQuery)+1024 resetSize:NO];
			[self reconnect];
			
		} 
		else {
			NSString *errorMessage = [NSString stringWithFormat:NSLocalizedString(@"The query length of %lu bytes is larger than max_allowed_packet size (%lu).", 
																				  @"error message if max_allowed_packet < query size"),
									  (unsigned long)theCQueryLength, maxAllowedPacketSize];
			
			// Write a log entry and update the connection error messages for those uses that check it
			if ([delegate respondsToSelector:@selector(queryGaveError:connection:)]) [delegate queryGaveError:errorMessage connection:self];
			[self setLastErrorMessage:errorMessage];
			
			// Notify that the query has been performed
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryHasBeenPerformed" object:delegate];

			// Show an error alert while resetting
			if ([delegate respondsToSelector:@selector(showErrorWithTitle:message:)])
				[delegate showErrorWithTitle:NSLocalizedString(@"Error", @"error") message:errorMessage];
			else
				NSRunAlertPanel(NSLocalizedString(@"Error", @"error"), errorMessage, @"OK", nil, nil);

			return nil;
		}
	}
	
	// In a loop to allow one reattempt, perform the query.
	while (1) {
		
		// If this query has failed once already, check the connection
		if (isQueryRetry) {
			if (![self checkConnection]) {
				if (queryErrorMessage) [queryErrorMessage release], queryErrorMessage = nil;

				// Notify that the query has been performed
				[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryHasBeenPerformed" object:delegate];
				return nil;
			}
		}

		[self lockConnection];

		// Run (or re-run) the query, timing the execution time of the query - note
		// that this time will include network lag.
		queryStartTime = [self timeConnected];
		queryResultCode = mysql_real_query(mConnection, theCQuery, theCQueryLength);
		lastQueryExecutedAtTime = [self timeConnected];
		queryExecutionTime = lastQueryExecutedAtTime - queryStartTime;

		// On success, capture the results
		if (0 == queryResultCode) {
			
			queryAffectedRows = mysql_affected_rows(mConnection);

			if (mysql_field_count(mConnection) != 0) {

				// For normal result sets, fetch the results and unlock the connection
				if (streamResultType == MCPStreamingNone) {
					theResult = [[MCPResult alloc] initWithMySQLPtr:mConnection encoding:stringEncoding timeZone:mTimeZone];
					if (!queryCancelled || !queryCancelUsedReconnect) {
                        [self unlockConnection];
                    }
				
				// For streaming result sets, fetch the result pointer and leave the connection locked
				} else if (streamResultType == MCPStreamingFast) {
					theResult = [[MCPStreamingResult alloc] initWithMySQLPtr:mConnection encoding:stringEncoding timeZone:mTimeZone connection:self withFullStreaming:NO];
				} else if (streamResultType == MCPStreamingLowMem) {
					theResult = [[MCPStreamingResult alloc] initWithMySQLPtr:mConnection encoding:stringEncoding timeZone:mTimeZone connection:self withFullStreaming:YES];
				}
				
				// Ensure no problem occurred during the result fetch
				if (mysql_errno(mConnection) != 0) {
					queryErrorMessage = [self stringWithCString:mysql_error(mConnection)];
					if (queryErrorMessage) [queryErrorMessage retain];
					queryErrorId = mysql_errno(mConnection);
					break;
				}
			} else {
				[self unlockConnection];
			}
			
			queryErrorMessage = [[NSString alloc] initWithString:@""];
			queryErrorId = 0;
			if (streamResultType == MCPStreamingNone && queryAffectedRows == (my_ulonglong)~0) {
				queryAffectedRows = mysql_affected_rows(mConnection);
			}
			
		// On failure, set the error messages and IDs
		} else {
			if (!queryCancelled || !queryCancelUsedReconnect) {
				[self unlockConnection];
			}
			
			if (queryCancelled) {
				if (queryErrorMessage) [queryErrorMessage release], queryErrorMessage = nil;
				queryErrorMessage = [[NSString alloc] initWithString:NSLocalizedString(@"Query cancelled.", @"Query cancelled error")];
				queryErrorId = 1317;
			} else {			
				if (queryErrorMessage) [queryErrorMessage release], queryErrorMessage = nil;
				queryErrorMessage = [self stringWithCString:mysql_error(mConnection)];
				if (queryErrorMessage) [queryErrorMessage retain];
				queryErrorId = mysql_errno(mConnection);

				// If the error was a connection error, retry once
				if (!isQueryRetry && retryAllowed && [MCPConnection isErrorNumberConnectionError:queryErrorId]) {
					isQueryRetry = YES;
					continue;
				}
			}
		}
		
		break;
	}
	
	if (streamResultType == MCPStreamingNone) {
		
		// If the mysql thread id has changed as a result of a connection error,
		// ensure connection details are still correct
		if (connectionThreadId != mConnection->thread_id) [self restoreConnectionDetails];
		
		// If max_allowed_packet was changed, reset it to default
		if(currentMaxAllowedPacket > -1)
			[self setMaxAllowedPacketTo:currentMaxAllowedPacket resetSize:YES];
	}
	
	// Update error strings and IDs
	lastQueryErrorId = queryErrorId;
	
	if (queryErrorMessage) {
		[self setLastErrorMessage:queryErrorMessage];
		
		[queryErrorMessage release];
	}
		
	lastQueryAffectedRows = queryAffectedRows;
	lastQueryExecutionTime = queryExecutionTime;
	
	// If an error occurred, inform the delegate
	if (queryResultCode & delegateResponseToWillQueryString)
		[delegate queryGaveError:lastQueryErrorMessage connection:self];
	
	if (!theResult) return nil;
	return [theResult autorelease];
}

/**
 * Returns the number of affected rows by the last query.  Only actual queries
 * supplied via queryString:, streamingQueryString:, streamingQueryString:useLowMemoryBlockingStreaming:
 * or queryString:usingEncoding:streamingResult: will have their affected rows
 * returned, not any "meta" type queries.
 */
- (my_ulonglong)affectedRows
{
	if (mConnected) return lastQueryAffectedRows;
	
	return 0;
}

/**
 * If the last query was an insert in a table having a autoindex column, returns the ID 
 * (autoindexed field) of the last row inserted.
 */
- (my_ulonglong)insertId
{
	if (mConnected) {
		return mysql_insert_id(mConnection);
	}
	
	return 0;
}

/**
 * Cancel the currently running query.  This tries to kill the current query, and if that
 * isn't possible, resets the connection.
 */
- (void) cancelCurrentQuery
{

	// If not connected, return.
	if (![self isConnected]) return;

	// Check whether a query is actually being performed - if not, also return.
	if ([self tryLockConnection]) {
		[self unlockConnection];
		return;
	}

	// Set queryCancelled to prevent query retries
	queryCancelled = YES;

	// Set up a new connection, and running a KILL QUERY via it.
	MYSQL *killerConnection = mysql_init(NULL);
	if (killerConnection) {
		const char *theLogin = [self cStringFromString:connectionLogin];
		const char *theHost;
		const char *thePass = NULL;
		const char *theSocket;
		void *connectionSetupStatus;

		mysql_options(killerConnection, MYSQL_OPT_CONNECT_TIMEOUT, (const void *)&connectionTimeout);
		mysql_options(killerConnection, MYSQL_SET_CHARSET_NAME, "utf8");

		// Set up the host, socket and password as per the connect method
		if (!connectionHost || ![connectionHost length]) {
			theHost = NULL;
		} else {
			theHost = [connectionHost UTF8String];
		}
		if (connectionSocket == nil || ![connectionSocket length]) {
			theSocket = kMCPConnectionDefaultSocket;
		} else {
			theSocket = [connectionSocket UTF8String];
		}
		if (!connectionPassword) {
			if (delegate && [delegate respondsToSelector:@selector(keychainPasswordForConnection:)]) {
				thePass = [[delegate keychainPasswordForConnection:self] UTF8String];
			}
		} else {		
			thePass = [connectionPassword UTF8String];
		}
		if (useSSL) {
			mysql_ssl_set(mConnection,
							sslKeyFilePath ? [sslKeyFilePath UTF8String] : NULL,
							sslCertificatePath ? [sslCertificatePath UTF8String] : NULL,
							sslCACertificatePath ? [sslCACertificatePath UTF8String] : NULL,
							NULL,
							kMCPSSLCipherList);
		}
		
		// Connect
		connectionSetupStatus = mysql_real_connect(killerConnection, theHost, theLogin, thePass, NULL, (unsigned int)connectionPort, theSocket, mConnectionFlags);
		thePass = NULL;
		if (connectionSetupStatus) {
		
			// Set up a KILL query.  For MySQL 5+, kill just the query; otherwise, kill the thread.
			NSStringEncoding killerConnectionEncoding = [MCPConnection encodingForMySQLEncoding:mysql_character_set_name(killerConnection)];
			NSString *killQueryString;
			if ([self serverMajorVersion] >= 5) {
				killQueryString = [NSString stringWithFormat:@"KILL QUERY %lu", mConnection->thread_id];
			} else {
				killQueryString = [NSString stringWithFormat:@"KILL %lu", mConnection->thread_id];
			}
			NSData *encodedKillQueryData = NSStringDataUsingLossyEncoding(killQueryString, killerConnectionEncoding, 1);
			const char *killQueryCString = [encodedKillQueryData bytes];
			unsigned long killQueryCStringLength = [encodedKillQueryData length];
			int killerReturnError = mysql_real_query(killerConnection, killQueryCString, killQueryCStringLength);
			mysql_close(killerConnection);
			if (killerReturnError == 0) {
				queryCancelUsedReconnect = NO;
				return;
			}
			NSLog(@"Task cancellation: kill query failed (Returned status %d)", killerReturnError);
		} else {
			NSLog(@"Task cancellation connection failed (error %u)", mysql_errno(killerConnection));
		}
	} else {
		NSLog(@"Task cancelletion MySQL init failed.");
	}

	// As the attempt may have taken up to the connection timeout, check lock status
	// again, returning if nothing is required.
	if ([self tryLockConnection]) {
		[self unlockConnection];
		return;
	}

	// Reset the connection
	[self unlockConnection];
	if (!isDisconnecting) [self reconnect];

	// Set queryCancelled again to handle requery cleanups, and return.
	queryCancelled = YES;
	queryCancelUsedReconnect = YES;
}

/**
 * Return whether the last query was cancelled
 */
- (BOOL)queryCancelled
{
	return queryCancelled;
}

/**
 * If the last query was cancelled, returns whether that cancellation
 * required a connection reset.  If the last query was not cancelled
 * the behaviour is undefined.
 */
- (BOOL)queryCancellationUsedReconnect
{
	return queryCancelUsedReconnect;
}

/**
 * Retrieves all remaining results and discards them.
 * Necessary if we only retrieve one result, and want to discard all the others.
 */
- (void)flushMultiResults
{
    // repeat as long as there are results
    while(!mysql_next_result(mConnection))
    {
        MYSQL_RES *result = mysql_use_result(mConnection);
        // check if the result is really a result
        if (result) {
            // retrieve all rows
            while (mysql_fetch_row(result));
            mysql_free_result(result);
        }
    }
}

#pragma mark -
#pragma mark Connection locking

/**
 * Lock the connection. This must be done before performing any operation
 * that is not thread safe, eg. performing queries or pinging.
 */
- (void)lockConnection
{
    // We can only start a query as soon as the condition is MCPConnectionIdle
	[connectionLock lockWhenCondition:MCPConnectionIdle];
    
    // We now set the condition to MCPConnectionBusy
    [connectionLock unlockWithCondition:MCPConnectionBusy];
}

/**
 * Try locking the connection. If the connection is idle (unlocked), this method
 * locks the connection and returns YES. The connection must afterwards be unlocked
 * using unlockConnection. If the connection is currently busy (locked), this
 * method immediately returns NO and doesn't lock the connection.
 */
- (BOOL)tryLockConnection
{
    // check if the condition is MCPConnectionIdle
	if ([connectionLock tryLockWhenCondition:MCPConnectionIdle]) {
        // We're allowed to use the connection!
        [connectionLock unlockWithCondition:MCPConnectionBusy];
        return YES;
    } else {
        // Someone else is using the connection right now
        return NO;
    }
}


/**
 * Unlock the connection.
 */
- (void)unlockConnection
{
    // We don't care if the connection is busy or not
    [connectionLock lock];
    
    // We check if the connection actually was busy. If it wasn't busy,
    // it means we probably tried to unlock the connection twice. This is
    // potentially dangerous, therefore we log this to the console
    if ([connectionLock condition] != MCPConnectionBusy) {
        NSLog(@"Tried to unlock the connection, but it wasn't locked.");
    }
    
    // Since we connected with CLIENT_MULTI_RESULT, we must make sure there are nor more results!
    // This is still a bit of a dirty hack
    if (mConnected && mConnection && mConnection->net.vio && mConnection->net.buff && mysql_more_results(mConnection)) {
        NSLog(@"Discarding unretrieved results. This is currently normal when using CALL.");
        [self flushMultiResults];
    }
    
    // We tell everyone that the connection is available again!
    [connectionLock unlockWithCondition:MCPConnectionIdle];
}

#pragma mark -
#pragma mark Database structure

/**
 * Just a fast wrapper for the more complex !{listDBsWithPattern:} method.
 */
- (MCPResult *)listDBs
{
	return [self listDBsLike:nil];
}

/**
 * Returns a list of database which name correspond to the SQL regular expression in 'pattern'.
 * The comparison is done with wild card extension : % and _.
 * The result should correspond to the queryString:@"SHOW databases [LIKE wild]"; but implemented with mysql_list_dbs.
 * If an empty string or nil is passed as pattern, all databases will be shown.
 */
- (MCPResult *)listDBsLike:(NSString *)dbsName
{
	if (!mConnected) return NO;
	
	MCPResult *theResult = nil;
	MYSQL_RES *theResPtr;
	
	if (![self checkConnection]) return [[[MCPResult alloc] init] autorelease];

	// Ensure UTF8 - where supported - when getting database list.
	NSString *currentEncoding = [NSString stringWithString:encoding];
	BOOL currentEncodingUsesLatin1Transport = encodingUsesLatin1Transport;
	[self setEncoding:@"utf8"];

	[self lockConnection];
	if ((dbsName == nil) || ([dbsName isEqualToString:@""])) {
		if ((theResPtr = mysql_list_dbs(mConnection, NULL))) {
			theResult = [[MCPResult alloc] initWithResPtr: theResPtr encoding:stringEncoding timeZone:mTimeZone];
		}
		else {
			theResult = [[MCPResult alloc] init];
		}
	}
	else {
		const char *theCDBsName = (const char *)[self cStringFromString:dbsName];
		
		if ((theResPtr = mysql_list_dbs(mConnection, theCDBsName))) {
			theResult = [[MCPResult alloc] initWithResPtr:theResPtr encoding:stringEncoding timeZone:mTimeZone];
		}
		else {
			theResult = [[MCPResult alloc] init];
		}        
	}
	[self unlockConnection];

	// Restore the connection encoding if necessary
	[self setEncoding:currentEncoding];
	[self setEncodingUsesLatin1Transport:currentEncodingUsesLatin1Transport];
	
	if (theResult) {
		[theResult autorelease];
	}
	
	return theResult;    
}

/**
 * Make sure a DB is selected (with !{selectDB:} method) first.
 */
- (MCPResult *)listTables
{
	return [self listTablesLike:nil];
}

/**
 * From within a database, give back the list of table which name correspond to tablesName 
 * (with wild card %, _ extension). Correspond to queryString:@"SHOW tables [LIKE wild]"; uses mysql_list_tables function.
 *
 * If an empty string or nil is passed as tablesName, all tables will be shown.
 *
 * WARNING: #{produce an error if no databases are selected} (with !{selectDB:} for example).
 */
- (MCPResult *)listTablesLike:(NSString *)tablesName
{
	if (!mConnected) return NO;
	
	MCPResult *theResult = nil;
	MYSQL_RES *theResPtr;
	
	if (![self checkConnection]) return [[[MCPResult alloc] init] autorelease];

	[self lockConnection];
	if ((tablesName == nil) || ([tablesName isEqualToString:@""])) {
		if ((theResPtr = mysql_list_tables(mConnection, NULL))) {
			theResult = [[MCPResult alloc] initWithResPtr: theResPtr encoding:stringEncoding timeZone:mTimeZone];
		}
		else {
			theResult = [[MCPResult alloc] init];
		}
	}
	else {
		const char	*theCTablesName = (const char *)[self cStringFromString:tablesName];
		if ((theResPtr = mysql_list_tables(mConnection, theCTablesName))) {
			theResult = [[MCPResult alloc] initWithResPtr: theResPtr encoding:stringEncoding timeZone:mTimeZone];
		}
		else {
			theResult = [[MCPResult alloc] init];
		}
	}
	
	[self unlockConnection];

	if (theResult) {
		[theResult autorelease];
	}
	
	return theResult;
}

- (NSArray *)listTablesFromDB:(NSString *)dbName {
	return [self listTablesFromDB:dbName like:nil];
}

/**
 * List tables in DB specified by dbName and corresponding to pattern.
 * This method indeed issues a !{SHOW TABLES FROM dbName LIKE ...} query to the server.
 * This is done this way to make sure the selected DB is not changed by this method.
 */
- (NSArray *)listTablesFromDB:(NSString *)dbName like:(NSString *)tablesName {
	MCPResult *theResult;
	if ((tablesName == nil) || ([tablesName isEqualToString:@""])) {
		NSString	*theQuery = [NSString stringWithFormat:@"SHOW TABLES FROM %@", 
								 [dbName backtickQuotedString]];
		theResult = [self queryString:theQuery];
	} else {
		NSString	*theQuery = [NSString stringWithFormat:@"SHOW TABLES FROM %@ LIKE '%@'", 
								 [dbName backtickQuotedString], 
								 [tablesName backtickQuotedString]];
		theResult = [self queryString:theQuery];
	}
	[theResult setReturnDataAsStrings:YES];
	NSString *theTableName;
	NSMutableArray *theDBTables = [NSMutableArray array];
		
	// NSLog(@"num of fields: %@; num of rows: %@", [theResult numOfFields], [theResult numOfRows]);
	if ([theResult numOfRows] > 0) {
		my_ulonglong i;
		for ( i = 0 ; i < [theResult numOfRows] ; i++ ) {
			theTableName = [[theResult fetchRowAsArray] objectAtIndex:0];
			[theDBTables addObject:theTableName];
		}		
	}	

	return theDBTables;
}

/**
 * Just a fast wrapper for the more complex list !{listFieldsWithPattern:forTable:} method.
 */
- (MCPResult *)listFieldsFromTable:(NSString *)tableName
{
	return [self listFieldsFromTable:tableName like:nil];
}

/**
 * Show all the fields of the table tableName which name correspond to pattern (with wild card expansion : %,_).
 * Indeed, and as recommanded from mysql reference, this method is NOT using mysql_list_fields but the !{queryString:} method.
 * If an empty string or nil is passed as fieldsName, all fields (of tableName) will be returned.
 */
- (MCPResult *)listFieldsFromTable:(NSString *)tableName like:(NSString *)fieldsName
{
	MCPResult *theResult;
	
	if ((fieldsName == nil) || ([fieldsName isEqualToString:@""])) {
		NSString	*theQuery = [NSString stringWithFormat:@"SHOW COLUMNS FROM %@", 
								 [tableName backtickQuotedString]];
		theResult = [self queryString:theQuery];
	}
	else {
		NSString	*theQuery = [NSString stringWithFormat:@"SHOW COLUMNS FROM %@ LIKE '%@'", 
								 [tableName backtickQuotedString], 
								 [fieldsName backtickQuotedString]];
		theResult = [self queryString:theQuery];
	}
	[theResult setReturnDataAsStrings:YES];

	return theResult;
}

/**
 * Updates the dict containing the structure of all available databases (mainly for completion/navigator)
 * executed on a new connection.
 *
 * TODO: Split this entire method out of MCPKit if possible
 */
- (void)queryDbStructureWithUserInfo:(NSDictionary*)userInfo
{
	NSAutoreleasePool *queryPool = [[NSAutoreleasePool alloc] init];
	BOOL structureWasUpdated = NO;

	// if 'cancelQuerying' is set try to interrupt any current querying
	if(userInfo && [userInfo objectForKey:@"cancelQuerying"])
		cancelQueryingDbStructure = YES;

	// Requests are queued
	while(isQueryingDbStructure > 0) { usleep(1000000); }

	cancelQueryingDbStructure = NO;

	[[NSNotificationCenter defaultCenter] postNotificationName:@"SPDBStructureIsUpdating" object:delegate];

	NSString *SPUniqueSchemaDelimiter = @"￸";

	NSString *connectionID;
	if([delegate respondsToSelector:@selector(connectionID)])
		connectionID = [NSString stringWithString:[[self delegate] connectionID]];
	else
		connectionID = @"_";

	// Re-init with already cached data from navigator controller
	NSMutableDictionary *queriedStructure = [NSMutableDictionary dictionary];
	NSDictionary *dbstructure = [[self delegate] getDbStructure];
	if (dbstructure) [queriedStructure setDictionary:[NSMutableDictionary dictionaryWithDictionary:dbstructure]];

	NSMutableArray *queriedStructureKeys = [NSMutableArray array];
	NSArray *dbStructureKeys = [[self delegate] allSchemaKeys];
	if (dbStructureKeys) [queriedStructureKeys setArray:dbStructureKeys];

	// Retrieve all the databases known of by the delegate
	NSMutableArray *connectionDatabases = [NSMutableArray array];
	[connectionDatabases addObjectsFromArray:[[self delegate] allSystemDatabaseNames]];
	[connectionDatabases addObjectsFromArray:[[self delegate] allDatabaseNames]];

	// Add all known databases coming from connection if they aren't parsed yet
	for (id db in connectionDatabases) {
		NSString *dbid = [NSString stringWithFormat:@"%@%@%@", connectionID, SPUniqueSchemaDelimiter, db];
		if(![queriedStructure objectForKey:dbid]) {
			structureWasUpdated = YES;
			[queriedStructure setObject:db forKey:dbid];
			[queriedStructureKeys addObject:dbid];
		}
	}

	// Check the existing databases in the 'structure' and 'allKeysOfDbStructure' stores,
	// and remove any that are no longer found in the connectionDatabases list (indicating deletion).
	// Iterate through extracted keys to avoid <NSCFDictionary> mutation while being enumerated.
	NSArray *keys = [queriedStructure allKeys];
	for(id key in keys) {
		NSString *db = [[key componentsSeparatedByString:SPUniqueSchemaDelimiter] objectAtIndex:1];
		if(![connectionDatabases containsObject:db]) {
			structureWasUpdated = YES;
			[queriedStructure removeObjectForKey:key];
			NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT SELF BEGINSWITH %@", [NSString stringWithFormat:@"%@%@", key, SPUniqueSchemaDelimiter]];
			[queriedStructureKeys filterUsingPredicate:predicate];
			[queriedStructureKeys removeObject:key];
		}
	}

	NSString *currentDatabase = nil;
	if([delegate respondsToSelector:@selector(database)])
		currentDatabase = [[self delegate] database];

	// Determine whether the database details need to be queried.
	BOOL shouldQueryStructure = YES;
	NSString *db_id = nil;

	// If no database is selected, no need to check further
	if(!currentDatabase || (currentDatabase && ![currentDatabase length])) {
		shouldQueryStructure = NO;

	// Otherwise, build up the schema key for the database to be retrieved.
	} else {
		db_id = [NSString stringWithFormat:@"%@%@%@", connectionID, SPUniqueSchemaDelimiter, currentDatabase];

		// Check to see if a cache already exists for the database.
		if ([queriedStructure objectForKey:db_id] && [[queriedStructure objectForKey:db_id] isKindOfClass:[NSDictionary class]]) {

			// The cache is available. If the `mysql` or `information_schema` databases are being queried,
			// never requery as their structure will never change.
			// 5.5.3+ also has performance_schema meta database
			if ([currentDatabase isEqualToString:@"mysql"] || [currentDatabase isEqualToString:@"information_schema"] || [currentDatabase isEqualToString:@"performance_schema"]) {
				shouldQueryStructure = NO;

			// Otherwise, if the forceUpdate flag wasn't supplied or evaluates to false, also don't update.
			} else if (userInfo == nil || ![userInfo objectForKey:@"forceUpdate"] || ![[userInfo objectForKey:@"forceUpdate"] boolValue]) {
				shouldQueryStructure = NO;
			}
		}
	}

	// If it has been determined that no new structure needs to be retrieved, clean up and return.
	if (!shouldQueryStructure) {

		// Update the global variables and make sure that no request reads these global variables
		// while updating
		[self performSelectorOnMainThread:@selector(lockQuerying) withObject:nil waitUntilDone:YES];
		[self performSelectorOnMainThread:@selector(updateGlobalVariablesWith:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:queriedStructure, @"structure", queriedStructureKeys, @"keys", nil] waitUntilDone:YES];
		[self performSelectorOnMainThread:@selector(unlockQuerying) withObject:nil waitUntilDone:YES];
		if (structureWasUpdated)
			[[NSNotificationCenter defaultCenter] postNotificationName:@"SPDBStructureWasUpdated" object:delegate];
		[queryPool release];
		return;
	}

	// Retrieve the tables and views for this database from SPTablesList
	NSMutableArray *tablesAndViews = [NSMutableArray array];
	for (id aTable in [[[self delegate] valueForKeyPath:@"tablesListInstance"] allTableNames]) {
		NSDictionary *aTableDict = [NSDictionary dictionaryWithObjectsAndKeys:
										aTable, @"name",
										@"0", @"type",
										nil];
		[tablesAndViews addObject:aTableDict];
	}
	for (id aView in [[[self delegate] valueForKeyPath:@"tablesListInstance"] allViewNames]) {
		NSDictionary *aViewDict = [NSDictionary dictionaryWithObjectsAndKeys:
										aView, @"name",
										@"1", @"type",
										nil];
		[tablesAndViews addObject:aViewDict];
	}

	// Do not parse more than 2000 tables/views per db
	if([tablesAndViews count] > 2000) {
		NSLog(@"%lu items in database %@. Only 2000 items can be parsed. Stopped parsing.", (unsigned long)[tablesAndViews count], currentDatabase);
		[queryPool release];
		return;
	}

	// For future usage - currently unused
	// If the affected item name and type - for example, table type and table name - were supplied, extract it.
	NSString *affectedItem = nil;
	NSInteger affectedItemType = -1;
	if(userInfo && [userInfo objectForKey:@"affectedItem"]) {
		affectedItem = [userInfo objectForKey:@"affectedItem"];
		if([userInfo objectForKey:@"affectedItemType"])
			affectedItemType = [[userInfo objectForKey:@"affectedItemType"] intValue];
		else
			affectedItem = nil;
	}

	// Delete all stored data for the database to be updated, leaving the structure key
	[queriedStructure removeObjectForKey:db_id];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT SELF BEGINSWITH %@", [NSString stringWithFormat:@"%@%@", db_id, SPUniqueSchemaDelimiter]];
	[queriedStructureKeys filterUsingPredicate:predicate];

	// Set up the database as an empty mutable dictionary ready for tables, and store a reference
	[queriedStructure setObject:[NSMutableDictionary dictionary] forKey:db_id];
	NSMutableDictionary *databaseStructure = [queriedStructure objectForKey:db_id];

	NSString *currentDatabaseEscaped = [currentDatabase stringByReplacingOccurrencesOfString:@"`" withString:@"``"];

	MYSQL *structConnection = mysql_init(NULL);
	if (structConnection) {
		const char *theLogin = [connectionLogin UTF8String];
		const char *theHost;
		const char *thePass = NULL;
		const char *theSocket;
		void *connectionSetupStatus;

		mysql_options(structConnection, MYSQL_OPT_CONNECT_TIMEOUT, (const void *)&connectionTimeout);
		mysql_options(structConnection, MYSQL_SET_CHARSET_NAME, "utf8");

		// Set up the host, socket and password as per the connect method
		if (!connectionHost || ![connectionHost length]) {
			theHost = NULL;
		} else {
			theHost = [connectionHost UTF8String];
		}
		if (connectionSocket == nil || ![connectionSocket length]) {
			theSocket = kMCPConnectionDefaultSocket;
		} else {
			theSocket = [connectionSocket UTF8String];
		}
		if (useSSL) {
			mysql_ssl_set(mConnection,
							sslKeyFilePath ? [sslKeyFilePath UTF8String] : NULL,
							sslCertificatePath ? [sslCertificatePath UTF8String] : NULL,
							sslCACertificatePath ? [sslCACertificatePath UTF8String] : NULL,
							NULL,
							kMCPSSLCipherList);
		}
		if (!connectionPassword) {
			if (delegate && [delegate respondsToSelector:@selector(keychainPasswordForConnection:)]) {
				thePass = [[delegate keychainPasswordForConnection:self] UTF8String];
			}
		} else {
			thePass = [connectionPassword UTF8String];
		}

		// Connect
		connectionSetupStatus = mysql_real_connect(structConnection, theHost, theLogin, thePass, NULL, (unsigned int)connectionPort, theSocket, mConnectionFlags);
		thePass = NULL;
		if (connectionSetupStatus) {
			MYSQL_RES *theResult;
			MYSQL_ROW row;
			NSString *charset;
			NSUInteger uniqueCounter = 0; // used to make field data unique
			NSString *query;
			NSData *encodedQueryData;
			const char *queryCString;
			unsigned long queryCStringLength;

			// Get the doc encoding due to pref settings etc, defaulting to UTF8
			NSString *docEncoding = [self encoding];
			if (!docEncoding) docEncoding = @"utf8";
			NSStringEncoding theConnectionEncoding = [MCPConnection encodingForMySQLEncoding:[self cStringFromString:docEncoding]];

			// Try to set connection encoding for MySQL >= 4.1
			if ([self serverMajorVersion] > 4 || ([self serverMajorVersion] >= 4 && [self serverMinorVersion] >= 1)) {
				query = [NSString stringWithFormat:@"SET NAMES '%@'", docEncoding];
				encodedQueryData = NSStringDataUsingLossyEncoding(query, theConnectionEncoding, 1);
				queryCString = [encodedQueryData bytes];
				queryCStringLength = [encodedQueryData length];
				if (mysql_real_query(structConnection, queryCString, queryCStringLength) != 0) {
					NSLog(@"Error while querying the database structure. Could not set encoding to %@", docEncoding);
					[queryPool release];
					return;
				}
			}

			// Increase global query-db-counter 
			[self performSelectorOnMainThread:@selector(incrementQueryingDbStructure) withObject:nil waitUntilDone:YES];

			// Loop through the known tables and views, retrieving details for each
			for (NSDictionary *aTableDict in tablesAndViews) {

				// If cancelled, abort without saving
				if (cancelQueryingDbStructure) {
					[self performSelectorOnMainThread:@selector(decrementQueryingDbStructure) withObject:nil waitUntilDone:YES];
					[queryPool release];
					return;
				}

				if(![aTableDict objectForKey:@"name"]) continue;
				// Extract the name
				NSString *aTableName = [aTableDict objectForKey:@"name"];

				if(!aTableName) continue;
				if(![aTableName isKindOfClass:[NSString class]]) continue;
				if(![aTableName length]) continue;
				// Retrieve the column details
				query = [NSString stringWithFormat:@"SHOW FULL COLUMNS FROM `%@` FROM `%@`", 
					[aTableName stringByReplacingOccurrencesOfString:@"`" withString:@"``"],
					currentDatabaseEscaped];
				encodedQueryData = NSStringDataUsingLossyEncoding(query, theConnectionEncoding, 1);
				queryCString = [encodedQueryData bytes];
				queryCStringLength = [encodedQueryData length];
				if (mysql_real_query(structConnection, queryCString, queryCStringLength) != 0) {
					// NSLog(@"error %@", aTableName);
					continue;
				}
				theResult = mysql_use_result(structConnection);

				// Add a structure key for this table
				NSString *table_id = [NSString stringWithFormat:@"%@%@%@", db_id, SPUniqueSchemaDelimiter, aTableName];
				[queriedStructureKeys addObject:table_id];

				// Add a mutable dictionary to the structure and store a reference
				[databaseStructure setObject:[NSMutableDictionary dictionary] forKey:table_id];
				NSMutableDictionary *tableStructure = [databaseStructure objectForKey:table_id];

				// Loop through the fields, extracting details for each
				while ((row = mysql_fetch_row(theResult))) {
					NSString *field = [self stringWithCString:row[0] usingEncoding:theConnectionEncoding] ;
					NSString *type = [self stringWithCString:row[1] usingEncoding:theConnectionEncoding] ;
					NSString *type_display = [type stringByReplacingOccurrencesOfRegex:@"\\(.*?,.*?\\)" withString:@"(…)"];
					NSString *coll = [self stringWithCString:row[2] usingEncoding:theConnectionEncoding] ;
					NSString *isnull = [self stringWithCString:row[3] usingEncoding:theConnectionEncoding] ;
					NSString *key = [self stringWithCString:row[4] usingEncoding:theConnectionEncoding] ;
					NSString *def = [self stringWithCString:row[5] usingEncoding:theConnectionEncoding] ;
					NSString *extra = [self stringWithCString:row[6] usingEncoding:theConnectionEncoding] ;
					NSString *priv = [self stringWithCString:row[7] usingEncoding:theConnectionEncoding] ;
					NSString *comment;
					if (sizeof(row) > 8) {
						comment = [self stringWithCString:row[8] usingEncoding:theConnectionEncoding] ;
					} else {
						comment = @"";
					}
					NSArray *a = [coll componentsSeparatedByString:@"_"];
					charset = ([a count]) ? [a objectAtIndex:0] : @"";

					// Add a structure key for this field
					NSString *field_id = [NSString stringWithFormat:@"%@%@%@", table_id, SPUniqueSchemaDelimiter, field];
					[queriedStructureKeys addObject:field_id];

					[tableStructure setObject:[NSArray arrayWithObjects:type, def, isnull, charset, coll, key, extra, priv, comment, type_display, [NSNumber numberWithUnsignedLongLong:uniqueCounter], nil] forKey:field_id];
					[tableStructure setObject:[aTableDict objectForKey:@"type"] forKey:@"  struct_type  "];
					uniqueCounter++;
				}
				mysql_free_result(theResult);
				usleep(10);
			}

			// If the MySQL version is higher than 5, also retrieve function/procedure details via the information_schema table
			if([self serverMajorVersion] >= 5) {

				// The information_schema table is UTF-8 encoded - alter the connection
				query = @"SET NAMES 'utf8'";
				encodedQueryData = NSStringDataUsingLossyEncoding(query, theConnectionEncoding, 1);
				queryCString = [encodedQueryData bytes];
				queryCStringLength = [encodedQueryData length];
				if (mysql_real_query(structConnection, queryCString, queryCStringLength) == 0) {

					// Query for procedures and functions
					query = [NSString stringWithFormat:@"SELECT * FROM `information_schema`.`ROUTINES` WHERE `information_schema`.`ROUTINES`.`ROUTINE_SCHEMA` = '%@'", [currentDatabase stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
					encodedQueryData = NSStringDataUsingLossyEncoding(query, theConnectionEncoding, 1);
					queryCString = [encodedQueryData bytes];
					queryCStringLength = [encodedQueryData length];
					if (mysql_real_query(structConnection, queryCString, queryCStringLength) == 0) {
						theResult = mysql_use_result(structConnection);
						
						// Loop through the rows and extract the function details
						while ((row = mysql_fetch_row(theResult))) {

							// If cancelled, abort without saving the new structure
							if(cancelQueryingDbStructure) {
								[self performSelectorOnMainThread:@selector(decrementQueryingDbStructure) withObject:nil waitUntilDone:YES];
								[queryPool release];
								return;
							}

							NSString *fname = [self stringWithUTF8CString:row[0]];
							NSString *type = ([[self stringWithUTF8CString:row[4]] isEqualToString:@"FUNCTION"]) ? @"3" : @"2";
							NSString *dtd = [self stringWithUTF8CString:row[5]];
							NSString *det = [self stringWithUTF8CString:row[11]];
							NSString *dataaccess = [self stringWithUTF8CString:row[12]];
							NSString *security_type = [self stringWithUTF8CString:row[14]];
							NSString *definer = [self stringWithUTF8CString:row[19]];

							// Generate "table" and "field" names and add to structure key store
							NSString *table_id = [NSString stringWithFormat:@"%@%@%@", db_id, SPUniqueSchemaDelimiter, fname];
							NSString *field_id = [NSString stringWithFormat:@"%@%@%@", table_id, SPUniqueSchemaDelimiter, fname];
							[queriedStructureKeys addObject:table_id];
							[queriedStructureKeys addObject:field_id];

							// Ensure that a dictionary exists for this "table" name
							if(![[queriedStructure valueForKey:db_id] valueForKey:table_id])
								[[queriedStructure valueForKey:db_id] setObject:[NSMutableDictionary dictionary] forKey:table_id];

							// Add the "field" details
							[[[queriedStructure valueForKey:db_id] valueForKey:table_id] setObject:
								[NSArray arrayWithObjects:dtd, dataaccess, det, security_type, definer, [NSNumber numberWithUnsignedLongLong:uniqueCounter], nil] forKey:field_id];
							[[[queriedStructure valueForKey:db_id] valueForKey:table_id] setObject:type forKey:@"  struct_type  "];
							uniqueCounter++;
						}
						mysql_free_result(theResult);
					} else {
						NSLog(@"Error while querying the database structure for procedures and functions. Could not set encoding to utf8");
					}
				}
			}

			// Update the global variables and make sure that no request reads these global variables
			// while updating
			[self performSelectorOnMainThread:@selector(lockQuerying) withObject:nil waitUntilDone:YES];
			[self performSelectorOnMainThread:@selector(updateGlobalVariablesWith:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:queriedStructure, @"structure", queriedStructureKeys, @"keys", nil] waitUntilDone:YES];
			[self performSelectorOnMainThread:@selector(unlockQuerying) withObject:nil waitUntilDone:YES];


			mysql_close(structConnection);

			// Notify that the structure querying has been performed
			[[NSNotificationCenter defaultCenter] postNotificationName:@"SPDBStructureWasUpdated" object:delegate];

			[self performSelectorOnMainThread:@selector(decrementQueryingDbStructure) withObject:nil waitUntilDone:YES];
		}
	}
	
	[queryPool release];
}

/*
 * Update global variables on main thread to avoid accessing from different threads
 */
- (void)updateGlobalVariablesWith:(NSDictionary*)object
{
	NSString *connectionID = [[self delegate] connectionID];

	// Return if the delegate indicates disconnection
	if([connectionID length] < 2) return;

	if(![structure valueForKey:connectionID])
		[structure setObject:[NSMutableDictionary dictionary] forKey:connectionID];
	[structure setObject:[object objectForKey:@"structure"] forKey:connectionID];
	[allKeysofDbStructure setArray:[object objectForKey:@"keys"]];
	usleep(100);
}

- (void)incrementQueryingDbStructure
{
	isQueryingDbStructure++;
}

- (void)decrementQueryingDbStructure
{
	isQueryingDbStructure--;
	if(isQueryingDbStructure < 0) isQueryingDbStructure = 0;
}

- (BOOL)isQueryingDatabaseStructure
{
	return (isQueryingDbStructure > 0) ? YES : NO;
}

- (void)lockQuerying
{
	lockQuerying = YES;
}

- (void)unlockQuerying
{
	lockQuerying = NO;
	usleep(50000);
}
/**
 * Returns a dict containing the structure of all available databases
 */
- (NSDictionary *)getDbStructure
{
	if(lockQuerying) return nil;
	NSDictionary *d = [NSDictionary dictionaryWithDictionary:structure];
	return d;
}

/**
 * Returns all keys of the db structure
 */
- (NSArray *)getAllKeysOfDbStructure
{
	if(lockQuerying) return nil;
	NSArray *r = [NSArray arrayWithArray:allKeysofDbStructure];
	return r;
}

#pragma mark -
#pragma mark Server information

/**
 * Returns a string giving the client library version.
 */
- (NSString *)clientInfo
{
	return [self stringWithCString:mysql_get_client_info()];
}

/**
 * Returns a string giving information on the host of the DB server.
 */
- (NSString *)hostInfo
{
	return [self stringWithCString:mysql_get_host_info(mConnection)];
}

/**
 * Returns a string giving the server version.
 */
- (NSString *)serverInfo
{
	if (mConnected) {
		return [self stringWithCString: mysql_get_server_info(mConnection)];
	}
	
	return @"";
}

/**
 * Returns the number of the protocole used to transfer info from server to client
 */
- (NSNumber *)protoInfo
{
	return [MCPNumber numberWithUnsignedInteger:mysql_get_proto_info(mConnection)];
}

/**
 * Lists active process
 */
- (MCPResult *)listProcesses
{
	MCPResult *result = nil;
	MYSQL_RES *theResPtr;
	
	[self lockConnection];
	
	if (mConnected && (mConnection != NULL)) {
		if ((theResPtr = mysql_list_processes(mConnection))) {
			result = [[MCPResult alloc] initWithResPtr:theResPtr encoding:stringEncoding timeZone:mTimeZone];
		} 
		else {
			result = [[MCPResult alloc] init];
		}
	} 
	
	[self unlockConnection];
	
	if (result) [result autorelease];
	
	return result;
}

/**
 * Kills the process with the given pid.
 * The users needs the !{Process_priv} privilege.
 */
- (BOOL)killProcess:(unsigned long)pid
{	
	NSInteger theErrorCode = mysql_kill(mConnection, pid);

	return (theErrorCode) ? NO : YES;
}

/*
 * Check some common locations for the presence of a MySQL socket file, returning
 * it if successful.
 */
- (NSString *)findSocketPath
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	NSArray *possibleSocketLocations = [NSArray arrayWithObjects:
										@"/tmp/mysql.sock",							// Default
										@"/Applications/MAMP/tmp/mysql/mysql.sock",	// MAMP default location
										@"/Applications/xampp/xamppfiles/var/mysql/mysql.sock", // XAMPP default location
										@"/var/mysql/mysql.sock",					// Mac OS X Server default
										@"/opt/local/var/run/mysqld/mysqld.sock",	// Darwinports MySQL
										@"/opt/local/var/run/mysql4/mysqld.sock",	// Darwinports MySQL 4
										@"/opt/local/var/run/mysql5/mysqld.sock",	// Darwinports MySQL 5
										@"/var/run/mysqld/mysqld.sock",				// As used on Debian/Gentoo
										@"/var/tmp/mysql.sock",						// As used on FreeBSD
										@"/var/lib/mysql/mysql.sock",				// As used by Fedora
										@"/opt/local/lib/mysql/mysql.sock",			// Alternate fedora
										nil];
	
	for (NSUInteger i = 0; i < [possibleSocketLocations count]; i++) 
	{
		if ([fileManager fileExistsAtPath:[possibleSocketLocations objectAtIndex:i]])
			return [possibleSocketLocations objectAtIndex:i];
	}
	
	return nil;
}

#pragma mark -
#pragma mark Encoding

/**
 * Sets the encoding for the database connection.
 * This sends a "SET NAMES" command to the server, as appropriate, and
 * also updates the class to decode the returned strings correctly.
 * If an encoding name unsupported by MySQL is encountered, a FALSE
 * status will be returned, and errors will be updated.
 * If an encoding name not supported by this class is encountered, a
 * warning will be logged to console but the MySQL connection will still
 * be updated.
 * This resets any setting to use Latin1 transport for the connection.
 */
- (BOOL)setEncoding:(NSString *)theEncoding
{
	if ([theEncoding isEqualToString:encoding] && !encodingUsesLatin1Transport) return YES;

	// MySQL < 4.1 will fail
	if ([self serverMajorVersion] < 4
		|| ([self serverMinorVersion] == 4 && [self serverMinorVersion] < 1))
	{
		return NO;
	}

	// Attempt to set the encoding of the connection, restoring the connection on failure
	[self queryString:[NSString stringWithFormat:@"SET NAMES %@", [theEncoding tickQuotedString]]];
	if ([self queryErrored]) {
		[self queryString:[NSString stringWithFormat:@"SET NAMES %@", [encoding tickQuotedString]]];
		if (encodingUsesLatin1Transport) [self queryString:@"SET CHARACTER_SET_RESULTS=latin1"];
		return NO;
	}

	// The connection set was successful - update stored details
	[encoding release];
	encoding = [[NSString alloc] initWithString:theEncoding];
	stringEncoding = [MCPConnection encodingForMySQLEncoding:[encoding UTF8String]];
	encodingUsesLatin1Transport = NO;
	return YES;
}

/**
 * Returns the currently active encoding.
 */
- (NSString *)encoding
{
	return [NSString stringWithString:encoding];
}

/**
 * Gets the string encoding for the connection
 */
- (NSStringEncoding)stringEncoding
{
	return stringEncoding;
}

/**
 * Sets whether the connection encoding should be transmitted via Latin1.
 * This is a method purely for backwards compatibility: old codebases or
 * applications often believed they stored UTF8 data in UTF8 tables, but
 * for the purposes of storing and reading the data, the MySQL connecttion
 * was never changed from the default Latin1.  UTF8 data was therefore
 * altered during transit and stored as UTF8 encoding Latin1 pairs which
 * together make up extended UTF8 characters.  Reading these characters back
 * over Latin1 makes the data editable in a compatible fashion.
 */
- (BOOL)setEncodingUsesLatin1Transport:(BOOL)useLatin1
{
	if (encodingUsesLatin1Transport == useLatin1) return YES;

	// If disabling Latin1 transport, restore the connection encoding
	if (!useLatin1) return [self setEncoding:encoding];

	// Otherwise attempt to set Latin1 transport
	[self queryString:@"SET CHARACTER_SET_RESULTS=latin1"];
	if ([self queryErrored]) return NO;
	[self queryString:@"SET CHARACTER_SET_CLIENT=latin1"];
	if ([self queryErrored]) {
		[self setEncoding:encoding];
		return NO;
	}
	encodingUsesLatin1Transport = YES;
	return YES;
}

/**
 * Return whether the current connection is set to use Latin1 tranport.
 */
- (BOOL)encodingUsesLatin1Transport
{
	return encodingUsesLatin1Transport;
}

/**
 * Store a previous encoding setting.  This allows easy restoration
 * later - useful if certain tasks require the encoding to be
 * temporarily changed.
 */
- (void)storeEncodingForRestoration
{
	if (previousEncoding) [previousEncoding release];
	previousEncoding = [[NSString alloc] initWithString:encoding];
	previousEncodingUsesLatin1Transport = encodingUsesLatin1Transport;
}

/**
 * Restore a previously stored encoding setting, if one is stored.
 * Useful if certain tasks required the encoding to be temporarily changed.
 */
- (void)restoreStoredEncoding
{
	if (!previousEncoding || !mConnected) return;

	[self setEncoding:previousEncoding];
	[self setEncodingUsesLatin1Transport:previousEncodingUsesLatin1Transport];
}

#pragma mark -
#pragma mark Time Zone

/**
 * Setting the time zone to be used with the server. 
 */
- (void)setTimeZone:(NSTimeZone *)iTimeZone
{
	if (iTimeZone != mTimeZone) {
		[mTimeZone release];
		mTimeZone = [iTimeZone retain];
	}
	
	if ([self checkConnection]) {
		if (mTimeZone) {
			[self queryString:[NSString stringWithFormat:@"SET time_zone = '%@'", [mTimeZone name]]];
		}
		else {
			[self queryString:@"SET time_zone = 'SYSTEM'"];
		}
	}
}

/**
 * Getting the currently used time zone (in communication with the DB server).
 */
- (NSTimeZone *)timeZone
{
	if ([self checkConnection]) {
		MCPResult	*theSessionTZ = [self queryString:@"SHOW VARIABLES LIKE '%time_zone'"];
		NSArray		*theRow;
		id			theTZName;
		NSTimeZone	*theTZ;

		[theSessionTZ setReturnDataAsStrings:YES];
		[theSessionTZ dataSeek:1ULL];
		theRow = [theSessionTZ fetchRowAsArray];
		theTZName = [theRow objectAtIndex:1];
		
		if ([theTZName isEqualToString:@"SYSTEM"]) {
			[theSessionTZ dataSeek:0ULL];
			theRow = [theSessionTZ fetchRowAsArray];
			theTZName = [theRow objectAtIndex:1];
			
			if ( [theTZName isKindOfClass:[NSData class]] ) {
				// MySQL 4.1.14 returns the mysql variables as NSData
				theTZName = [self stringWithText:theTZName];
			}
		}
		
		if (theTZName) { // Old versions of the server does not support there own time zone ?
			theTZ = [NSTimeZone timeZoneWithName:theTZName];
		} else {
			// By default set the time zone to the local one..
			// Try to get the name using the previously available variable:
			theSessionTZ = [self queryString:@"SHOW VARIABLES LIKE 'timezone'"];
			[theSessionTZ setReturnDataAsStrings:YES];
			[theSessionTZ dataSeek:0ULL];
			theRow = [theSessionTZ fetchRowAsArray];
			theTZName = [theRow objectAtIndex:1];
			if (theTZName) {
				// Finally we found one ...
				theTZ = [NSTimeZone timeZoneWithName:theTZName];
			} else {
				theTZ = [NSTimeZone defaultTimeZone];
				//theTZ = [NSTimeZone systemTimeZone];
				NSLog(@"The time zone is not defined on the server, set it to the default one : %@", theTZ);
			}
		}
		
		if (theTZ != mTimeZone) {
			[mTimeZone release];
			mTimeZone = [theTZ retain];
		}
	}
	
	return mTimeZone;
}

#pragma mark -
#pragma mark Packet size

/**
 * Retrieve the max_allowed_packet size from the server; returns
 * false if the query fails.
 */
- (BOOL)fetchMaxAllowedPacket
{
	char *queryString;

	if ([self serverMajorVersion] == 3) queryString = "SHOW VARIABLES LIKE 'max_allowed_packet'";
	else queryString = "SELECT @@global.max_allowed_packet";
	
	[self lockConnection];
	if (0 == mysql_query(mConnection, queryString)) {
		if (mysql_field_count(mConnection) != 0) {
			MCPResult *r = [[MCPResult alloc] initWithMySQLPtr:mConnection encoding:stringEncoding timeZone:mTimeZone];
			[r setReturnDataAsStrings:YES];
			NSArray *a = [r fetchRowAsArray];
			[r autorelease];
			if([a count]) {
				[self unlockConnection];
				maxAllowedPacketSize = [[a objectAtIndex:([self serverMajorVersion] == 3)?1:0] integerValue];
				return true;
			}
		}
	}
	[self unlockConnection];
	
	return false;
}

/**
 * Retrieves max_allowed_packet size set as global variable.
 * It returns NSNotFound if it fails.
 */
- (NSUInteger)getMaxAllowedPacket
{
	MCPResult *r;
	r = [self queryString:@"SELECT @@global.max_allowed_packet" usingEncoding:stringEncoding streamingResult:NO];
	if (![[self getLastErrorMessage] isEqualToString:@""]) {
		if ([self isConnected]) {
			NSString *errorMessage = [NSString stringWithFormat:@"An error occured while retrieving max_allowed_packet size:\n\n%@", [self getLastErrorMessage]];
			if ([delegate respondsToSelector:@selector(showErrorWithTitle:message:)]) 
				[delegate showErrorWithTitle:NSLocalizedString(@"Error", @"error") message:errorMessage];
			else
				NSRunAlertPanel(@"Error", errorMessage, @"OK", nil, nil);
		}
		return NSNotFound;
	}
	NSArray *a = [r fetchRowAsArray];
	if([a count])
		return [[a objectAtIndex:0] integerValue];
	
	return NSNotFound;
}

/*
 * It sets max_allowed_packet size to newSize and it returns
 * max_allowed_packet after setting it to newSize for cross-checking 
 * if the maximal size was reached (e.g. set it to 4GB it'll return 1GB up to now).
 * If something failed it return -1;
 */
- (NSUInteger)setMaxAllowedPacketTo:(NSUInteger)newSize resetSize:(BOOL)reset
{
	if(![self isMaxAllowedPacketEditable] || newSize < 1024) return maxAllowedPacketSize;
	
	[self lockConnection];
	mysql_query(mConnection, [[NSString stringWithFormat:@"SET GLOBAL max_allowed_packet = %lu", newSize] UTF8String]);
	[self unlockConnection];

	// Inform the user via a log entry about that change according to reset value
	if(delegate && [delegate respondsToSelector:@selector(queryGaveError:connection:)]) {
		if(reset)
			[delegate queryGaveError:[NSString stringWithFormat:@"max_allowed_packet was reset to %lu for new session", newSize] connection:self];
		else
			[delegate queryGaveError:[NSString stringWithFormat:@"Query too large; max_allowed_packet temporarily set to %lu for the current session to allow query to succeed", newSize] connection:self];
	}

	return maxAllowedPacketSize;
}

/**
 * It returns whether max_allowed_packet is setable for the user.
 */
- (BOOL)isMaxAllowedPacketEditable
{
	BOOL isEditable;

	[self lockConnection];
	isEditable = !mysql_query(mConnection, "SET GLOBAL max_allowed_packet = @@global.max_allowed_packet");
	[self unlockConnection];

	return isEditable;
}

#pragma mark -
#pragma mark Data conversion

/**
 * For internal use only. Transforms a NSString to a C type string (ending with \0) using the character set from the MCPConnection.
 * Lossy conversions are enabled.
 */
- (const char *)cStringFromString:(NSString *)theString
{
	NSMutableData *theData;
	
	if (! theString) {
		return (const char *)NULL;
	}
	
	theData = [NSMutableData dataWithData:[theString dataUsingEncoding:stringEncoding allowLossyConversion:YES]];
	[theData increaseLengthBy:1];
	
	return (const char *)[theData bytes];
}

/**
 * Modified version of the original to support a supplied encoding.
 * For internal use only. Transforms a NSString to a C type string (ending with \0).
 * Lossy conversions are enabled.
 */
- (const char *)cStringFromString:(NSString *)theString usingEncoding:(NSStringEncoding)aStringEncoding
{
	NSMutableData *theData;
	
	if (! theString) {
		return (const char *)NULL;
	}
	
	theData = [NSMutableData dataWithData:[theString dataUsingEncoding:aStringEncoding allowLossyConversion:YES]];
	[theData increaseLengthBy:1];
	
	return (const char *)[theData bytes];
}

/**
 * Returns a NSString from a C style string encoded with the character set of theMCPConnection.
 */
- (NSString *)stringWithCString:(const char *)theCString
{
	NSData	 *theData;
	NSString *theString;
	
	if (theCString == NULL) return @"";
	
	theData = [NSData dataWithBytes:theCString length:(strlen(theCString))];
	theString = [[NSString alloc] initWithData:theData encoding:stringEncoding];
	
	if (theString) {
		[theString autorelease];
	}
	
	return theString;
}

/**
 * Returns a NSString from a C style string.
 */
- (NSString *)stringWithCString:(const char *)theCString usingEncoding:(NSStringEncoding)aStringEncoding
{
	NSData	 *theData;
	NSString *theString;
	
	if (theCString == NULL) return @"";
	
	theData = [NSData dataWithBytes:theCString length:(strlen(theCString))];
	theString = [[NSString alloc] initWithData:theData encoding:aStringEncoding];
	
	if (theString) {
		[theString autorelease];
	}
	
	return theString;
}

/**
 * Returns a NSString from a C style string encoded with the character set of theMCPConnection.
 */
- (NSString *)stringWithUTF8CString:(const char *)theCString
{
	NSData	 *theData;
	NSString *theString;
	
	if (theCString == NULL) return @"";
	
	theData = [NSData dataWithBytes:theCString length:(strlen(theCString))];
	theString = [[NSString alloc] initWithData:theData encoding:NSUTF8StringEncoding];
	
	if (theString) {
		[theString autorelease];
	}
	
	return theString;
}

/**
 * Use the string encoding to convert the returned NSData to a string (for a Text field).
 */
- (NSString *)stringWithText:(NSData *)theTextData
{
	NSString *theString;
	
	if (theTextData == nil) return nil;
	
	theString = [[NSString alloc] initWithData:theTextData encoding:stringEncoding];
	
	if (theString) {
		[theString autorelease];
	}
	
	return theString;
}

#pragma mark -

/**
 * Object deallocation.
 */
- (void) dealloc
{
	delegate = nil;

	// Ensure the query lock is unlocked, thereafter setting to nil in case of pending calls
	[self unlockConnection];
	[connectionLock release], connectionLock = nil;

	// Clean up connections if necessary
	if (mConnected) [self disconnect];
	if (connectionProxy) {
		[connectionProxy setConnectionStateChangeSelector:NULL delegate:nil];
		[connectionProxy disconnect];
	}

	[encoding release];
	if (previousEncoding) [previousEncoding release];
	[keepAliveTimer invalidate];
	[keepAliveTimer release];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	if (lastQueryErrorMessage) [lastQueryErrorMessage release];
	if (connectionHost) [connectionHost release];
	if (connectionLogin) [connectionLogin release];
	if (connectionSocket) [connectionSocket release];
	if (connectionPassword) [connectionPassword release];
	if (sslKeyFilePath) [sslKeyFilePath release];
	if (sslCertificatePath) [sslCertificatePath release];
	if (sslCACertificatePath) [sslCACertificatePath release];
	if (serverVersionString) [serverVersionString release], serverVersionString = nil;
	if (structure) [structure release], structure = nil;
	if (allKeysofDbStructure) [allKeysofDbStructure release], allKeysofDbStructure = nil;
	
	[super dealloc];
}

@end

@implementation MCPConnection (PrivateAPI)

/**
 * Get the server's version string
 */
- (void)_getServerVersionString
{
	if (mConnected) {
		MCPResult *theResult = [self queryString:@"SHOW VARIABLES LIKE 'version'"];
		[theResult setReturnDataAsStrings:YES];
		
		if ([theResult numOfRows]) {
			[theResult dataSeek:0];
			serverVersionString = [[NSString stringWithString:[[theResult fetchRowAsArray] objectAtIndex:1]] retain];
		}
	}
}

/**
 * Determine whether the current host is reachable; essentially
 * whether a connection is available (no packets should be sent)
 */
- (BOOL)_isCurrentHostReachable
{
	BOOL hostReachable;
	SCNetworkConnectionFlags reachabilityStatus;
	hostReachable = SCNetworkCheckReachabilityByName("dev.mysql.com", &reachabilityStatus);

	// If the function returned failure, also return failure.
	if (!hostReachable) return NO;

	// Ensure that the network is reachable
	if (!(reachabilityStatus & kSCNetworkFlagsReachable)) return NO;

	// Ensure that Airport is up/connected if present
	if (reachabilityStatus & kSCNetworkFlagsConnectionRequired) return NO;

	// Return success
	return YES;
}

/**
 * Set up the keepalive timer; this should be called on the main
 * thread, to ensure the timer isn't descheduled when child threads
 * terminate.
 */
- (void)_setupKeepalivePingTimer
{
	keepAliveTimer = [[NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(keepAlive:) userInfo:nil repeats:YES] retain];
}
@end
