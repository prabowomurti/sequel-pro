//
//  $Id$
//
//  MCPConnection.h
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

#import <Foundation/Foundation.h>
#import <pthread.h>

#import "MCPConstants.h"
#import "mysql.h"

typedef struct {
	MYSQL	*mySQLConnection;
	BOOL	*pingActivePointer;
	BOOL	*lastPingSuccessPointer;
} MCPConnectionPingDetails;

@protocol MCPConnectionProxy;

@class MCPResult, MCPStreamingResult;

@interface NSObject (MCPConnectionDelegate)

/**
 *
 */
- (void)willQueryString:(NSString *)query connection:(id)connection;

/**
 *
 */
- (void)queryGaveError:(NSString *)error connection:(id)connection;

/**
 *
 */
- (void)showErrorWithTitle:(NSString *)error message:(NSString *)connection;

/**
 *
 */
- (NSString *)keychainPasswordForConnection:(id)connection;

/**
 *
 */
- (NSString *)onReconnectShouldSelectDatabase:(id)connection;

/**
 *
 */
- (void)noConnectionAvailable:(id)connection;

/**
 *
 */
- (MCPConnectionCheck)connectionLost:(id)connection;

/**
 *
 */
- (NSString *)connectionID;

/**
 *
 */
- (NSString *)database;

/**
 *
 */
- (BOOL)navigatorSchemaPathExistsForDatabase:(NSString*)dbname;

/**
 *
 */
- (NSArray*)allDatabaseNames;

/**
 *
 */
- (NSArray*)allSystemDatabaseNames;

/**
 *
 */
- (NSArray*)allTableNames;

/**
 *
 */
- (NSArray*)allViewNames;

/**
 *
 */
- (NSArray*)allSchemaKeys;

@end

@interface MCPConnection : NSObject 
{
	MYSQL			 *mConnection;     /* The inited MySQL connection. */
	BOOL			 mConnected;       /* Reflect the fact that the connection is already in place or not. */
	NSStringEncoding mEncoding;        /* The encoding used by MySQL server, to ISO-1 default. */
	NSTimeZone		 *mTimeZone;       /* The time zone of the session. */
	NSUInteger       mConnectionFlags; /* The flags to be used for the connection to the database. */
	
	id delegate; /* Connection delegate */
    
	/* Anything that performs a mysql_net_read is not thread-safe: mysql queries, pings */
    /* Always lock the connection first. Don't use this lock directly, use the lockConnection method! */
	NSConditionLock *connectionLock; 

	BOOL useKeepAlive;
	BOOL isDisconnecting;
	BOOL userTriggeredDisconnect;
	NSInteger connectionTimeout;
	CGFloat keepAliveInterval;
	
	NSObject <MCPConnectionProxy> *connectionProxy;
	NSString *connectionLogin;
	NSString *connectionPassword;
	NSString *connectionHost;
	NSInteger connectionPort;
	NSString *connectionSocket;
	NSInteger maxAllowedPacketSize;
	unsigned long connectionThreadId;

	BOOL useSSL;
	NSString *sslKeyFilePath;
	NSString *sslCertificatePath;
	NSString *sslCACertificatePath;

	NSString *encoding, *previousEncoding;
	NSStringEncoding stringEncoding;
	BOOL encodingUsesLatin1Transport, previousEncodingUsesLatin1Transport;

	NSInteger currentProxyState;
	
	double lastQueryExecutionTime;
	double lastQueryExecutedAtTime;
	NSString *lastQueryErrorMessage;
	NSUInteger lastQueryErrorId;
	my_ulonglong lastQueryAffectedRows;
	MCPConnectionCheck lastDelegateDecisionForLostConnection;
	
	BOOL isMaxAllowedPacketEditable;
	
	NSString *serverVersionString;
	NSMutableDictionary *structure;
	NSMutableArray *allKeysofDbStructure;
	
	pthread_t pingThread;
	NSInteger pingFailureCount;
	BOOL pingThreadActive;
	BOOL lastPingSuccess;
	BOOL lastPingBlocked;
	NSTimer *keepAliveTimer;
	double lastKeepAliveTime;
	uint64_t connectionStartTime;
	
	BOOL retryAllowed;
	BOOL queryCancelled;
	BOOL queryCancelUsedReconnect;
	BOOL delegateQueryLogging;
	BOOL delegateResponseToWillQueryString;
	BOOL delegateSupportsConnectionLostDecisions;
	NSInteger isQueryingDbStructure;
	BOOL cancelQueryingDbStructure;
	BOOL lockQuerying;
	NSInteger automaticReconnectAttempts;
	
	// Pointers
	IMP cStringPtr;
	IMP willQueryStringPtr;
	IMP timeConnectedPtr;
	
	// Selectors
	SEL cStringSEL;
	SEL willQueryStringSEL;
	SEL timeConnectedSEL;
}

// Readonly properties
@property (readonly) double lastQueryExecutionTime;

// Read/write properties
@property (readwrite, assign) BOOL useKeepAlive;
@property (readwrite, assign) BOOL delegateQueryLogging;
@property (readwrite, assign) NSInteger connectionTimeout;
@property (readwrite, assign) CGFloat keepAliveInterval;

// Initialisation
- (id)initToHost:(NSString *)host withLogin:(NSString *)login usingPort:(NSInteger)port;
- (id)initToSocket:(NSString *)socket withLogin:(NSString *)login;

// Delegate
- (id)delegate;
- (void)setDelegate:(id)connectionDelegate;
- (MCPConnectionCheck)delegateDecisionForLostConnection;

// Connection details
- (BOOL)setPort:(NSInteger)thePort;
- (BOOL)setPassword:(NSString *)thePassword;
- (void) setSSL:(BOOL)shouldUseSSL usingKeyFilePath:(NSString *)keyFilePath certificatePath:(NSString *)certificatePath certificateAuthorityCertificatePath:(NSString *)caCertificatePath;

// Proxy
- (BOOL)setConnectionProxy:(id <MCPConnectionProxy>)proxy;
- (void)connectionProxyStateChange:(id <MCPConnectionProxy>)proxy;

// Connection
- (BOOL)connect;
- (void)disconnect;
- (BOOL)reconnect;
- (BOOL)isConnected;
- (BOOL)isConnectedViaSSL;
- (BOOL)userTriggeredDisconnect;
- (BOOL)checkConnection;
- (void)restoreConnectionDetails;
- (void)setAllowQueryRetries:(BOOL)allow;
- (double)timeConnected;

// Pinging and keepalive
- (BOOL)pingConnectionUsingLoopDelay:(NSUInteger)loopDelay;
void backgroundPingTask(void *ptr);
void forceThreadExit(int signalNumber);
void pingThreadCleanup();
- (void)keepAlive:(NSTimer *)theTimer;
- (void)threadedKeepAlive;

// Server versions
- (NSString *)serverVersionString;
- (NSInteger)serverMajorVersion;
- (NSInteger)serverMinorVersion;
- (NSInteger)serverReleaseVersion;

// MySQL defaults
+ (NSDictionary *)getMySQLLocales;
+ (NSStringEncoding)encodingForMySQLEncoding:(const char *)mysqlEncoding;
+ (NSStringEncoding)defaultMySQLEncoding;
+ (BOOL)isErrorNumberConnectionError:(NSInteger)theErrorNumber;

// Class maintenance
+ (void)setTruncateLongFieldInLogs:(BOOL)iTruncFlag;
+ (BOOL)truncateLongField;
- (BOOL)setConnectionOption:(NSInteger)option toValue:(BOOL)value;
- (BOOL)connectWithLogin:(NSString *)login password:(NSString *)pass host:(NSString *)host port:(NSInteger)port socket:(NSString *)socket;

- (BOOL)selectDB:(NSString *)dbName;

// Error information
- (BOOL)queryErrored;
- (NSString *)getLastErrorMessage;
- (void)setLastErrorMessage:(NSString *)theErrorMessage;
- (NSUInteger)getLastErrorID;
+ (BOOL)isErrorNumberConnectionError:(NSInteger)theErrorNumber;
- (void)updateErrorStatuses;

// Queries
- (NSString *)prepareBinaryData:(NSData *)theData;
- (NSString *)prepareString:(NSString *)theString;
- (NSString *)quoteObject:(id)theObject;
- (MCPResult *)queryString:(NSString *)query;
- (MCPStreamingResult *)streamingQueryString:(NSString *)query;
- (MCPStreamingResult *)streamingQueryString:(NSString *)query useLowMemoryBlockingStreaming:(BOOL)fullStream;
- (id)queryString:(NSString *)query usingEncoding:(NSStringEncoding)encoding streamingResult:(NSInteger)streamResult;
- (my_ulonglong)affectedRows;
- (my_ulonglong)insertId;
- (void)cancelCurrentQuery;
- (BOOL)queryCancelled;
- (BOOL)queryCancellationUsedReconnect;
- (void)flushMultiResults;

// Locking
- (void)lockConnection;
- (BOOL)tryLockConnection;
- (void)unlockConnection;

// Database structure
- (MCPResult *)listDBs;
- (MCPResult *)listDBsLike:(NSString *)dbsName;
- (MCPResult *)listTables;
- (MCPResult *)listTablesLike:(NSString *)tablesName;
- (NSArray *)listTablesFromDB:(NSString *)dbName;
- (NSArray *)listTablesFromDB:(NSString *)dbName like:(NSString *)tablesName;
- (MCPResult *)listFieldsFromTable:(NSString *)tableName;
- (MCPResult *)listFieldsFromTable:(NSString *)tableName like:(NSString *)fieldsName;

// Structure querying
- (void)queryDbStructureWithUserInfo:(NSDictionary*)userInfo;
- (NSDictionary *)getDbStructure;
- (NSArray *)getAllKeysOfDbStructure;
- (BOOL)isQueryingDatabaseStructure;
- (void)incrementQueryingDbStructure;
- (void)decrementQueryingDbStructure;
- (void)lockQuerying;
- (void)unlockQuerying;
- (void)updateGlobalVariablesWith:(NSDictionary*)object;

// Server information
- (NSString *)clientInfo;
- (NSString *)hostInfo;
- (NSString *)serverInfo;
- (NSNumber *)protoInfo;
- (MCPResult *)listProcesses;
- (BOOL)killProcess:(unsigned long)pid;
- (NSString *)findSocketPath;

// Encoding
- (BOOL)setEncoding:(NSString *)theEncoding;
- (NSString *)encoding;
- (NSStringEncoding)stringEncoding;
- (BOOL)setEncodingUsesLatin1Transport:(BOOL)useLatin1;
- (BOOL)encodingUsesLatin1Transport;
- (void)storeEncodingForRestoration;
- (void)restoreStoredEncoding;

// Time zone
- (void)setTimeZone:(NSTimeZone *)iTimeZone;
- (NSTimeZone *)timeZone;

// Packet size
- (BOOL)fetchMaxAllowedPacket;
- (NSInteger)getMaxAllowedPacket;
- (BOOL)isMaxAllowedPacketEditable;
- (NSInteger)setMaxAllowedPacketTo:(NSInteger)newSize resetSize:(BOOL)reset;

// Data conversion
- (const char *)cStringFromString:(NSString *)theString;
- (const char *)cStringFromString:(NSString *)theString usingEncoding:(NSStringEncoding)encoding;
- (NSString *)stringWithCString:(const char *)theCString;
- (NSString *)stringWithCString:(const char *)theCString usingEncoding:(NSStringEncoding)encoding;
- (NSString *)stringWithText:(NSData *)theTextData;
- (NSString *)stringWithUTF8CString:(const char *)theCString;

@end
