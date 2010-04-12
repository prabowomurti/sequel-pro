//
//  SPFileHandle.m
//  sequel-pro
//
//  Created by Rowan Beentje on 05/04/2010.
//  Copyright 2010 Arboreal. All rights reserved.
//

#import "SPFileHandle.h"
#import "zlib.1.2.4.h"

// Define the size of the background read/write buffer.  This affects speed and memory usage.
#define SPFH_BUFFER_SIZE 1048576

@interface SPFileHandle (PrivateAPI)
- (void) _writeBufferToData;
@end


@implementation SPFileHandle

#pragma mark -
#pragma mark Setup and teardown

/**
 * Initialises and returns a SPFileHandle with a specified file (FILE or gzFile).
 * "mode" indicates the file interaction mode - currently only read-only
 * or write-only are supported.
 * On reading, theFile should always be a gzFile; on writing, theFile is a FILE
 * when compression is disabled, or a gzFile when enbled.
 */
- (id) initWithFile:(void *)theFile fromPath:(const char *)path mode:(int)mode
{
	if (self = [super init]) {
		fileIsClosed = NO;

		wrappedFile = theFile;
		wrappedFilePath = malloc(strlen(path) + 1);
		strcpy(wrappedFilePath, path);

		// Check and set the mode
		fileMode = mode;
		if (fileMode != O_RDONLY && fileMode != O_WRONLY) {
			[NSException raise:NSInvalidArgumentException format:@"SPFileHandle only supports read-only and write-only file modes"];
		}

		// Instantiate the buffer
		pthread_mutex_init(&bufferLock, NULL);
		buffer = [[NSMutableData alloc] init];
		bufferDataLength = 0;
		bufferPosition = 0;
		endOfFile = NO;

		// If in read mode, set up the buffer
		if (fileMode == O_RDONLY) {
			gzbuffer(wrappedFile, 131072);
			useGzip = !gzdirect(wrappedFile);
			processingThread = nil;

		// In write mode, set up a thread to handle writing in the background
		} else if (fileMode == O_WRONLY) {
			useGzip = NO;
			processingThread = [[NSThread alloc] initWithTarget:self selector:@selector(_writeBufferToData) object:nil];
			[processingThread start];
		}
	}

	return self;
}

- (void) dealloc
{
	[self closeFile];
	if (processingThread) [processingThread release];
	free(wrappedFilePath);
	[buffer release];
	pthread_mutex_destroy(&bufferLock);
	[super dealloc];
}

#pragma mark -
#pragma mark Class methods

/**
 * Retrieve and return a SPFileHandle for reading a file at the supplied
 * path.  Returns nil if the file could not be found or opened.
 */
+ (id) fileHandleForReadingAtPath:(NSString *)path
{
	return [self fileHandleForPath:path mode:O_RDONLY];
}

/**
 * Retrieve and return a SPFileHandle for writing a file at the supplied
 * path.  Returns nil if the file could not be found or opened.
 */
+ (id) fileHandleForWritingAtPath:(NSString *)path
{
	return [self fileHandleForPath:path mode:O_WRONLY];
}

/**
 * Retrieve and return a SPFileHandle for a file at the specified path,
 * using the supplied file status flag.  Returns nil if the file could
 * not be found or opened.
 */
+ (id) fileHandleForPath:(NSString *)path mode:(int)mode
{

	// Retrieves the path in a filesystem-appropriate format and encoding
	const char *pathRepresentation = [path fileSystemRepresentation];
	if (!pathRepresentation) return nil;

	// Open the file to get a file descriptor, returning on failure
	FILE *theFile;
	const char *theMode;
	if (mode == O_WRONLY) {
		theMode = "wb";
		theFile = fopen(pathRepresentation, theMode);
	} else {
		theMode = "rb";
		theFile = gzopen(pathRepresentation, theMode);
	}
	if (theFile == NULL) return nil;

	// Return an autoreleased file handle
	return [[[self alloc] initWithFile:theFile fromPath:pathRepresentation mode:mode] autorelease];
}


#pragma mark -
#pragma mark Data reading

// Reads data up to a specified number of bytes from the file
- (NSMutableData *) readDataOfLength:(NSUInteger)length
{
	void *theData = malloc(length);
	long theDataLength = gzread(wrappedFile, theData, length);
	return [NSMutableData dataWithBytesNoCopy:theData length:theDataLength freeWhenDone:YES];
}

// Returns the data to the end of the file
- (NSMutableData *) readDataToEndOfFile
{
	return [self readDataOfLength:NSUIntegerMax];
}

// Returns the on-disk (raw) length of data read so far - can be used in progress bars
- (NSUInteger) realDataReadLength
{
	if (fileMode == O_WRONLY) return 0;
	return gzoffset(wrappedFile);
}

#pragma mark -
#pragma mark Data writing

/**
 * Set whether data should be written as gzipped data, defaulting
 * to NO on a fresh object. If this is called after data has been
 * written, an exception is thrown.
 */
- (void) setShouldWriteWithGzipCompression:(BOOL)shouldUseGzip
{
	if (shouldUseGzip == useGzip) return;

	if (dataWritten) [NSException raise:NSInternalInconsistencyException format:@"Cannot change compression settings when data has already been written"];

	if (shouldUseGzip) {
		fclose(wrappedFile);
		wrappedFile = gzopen(wrappedFilePath, "wb");
		gzbuffer(wrappedFile, 131072);
	} else {
		gzclose(wrappedFile);
		wrappedFile = fopen(wrappedFilePath, "wb");
	}
	useGzip = shouldUseGzip;
}


// Write the provided data to the file
- (void) writeData:(NSData *)data
{

	// Throw an exception if the file is closed
	if (fileIsClosed) [NSException raise:NSInternalInconsistencyException format:@"Cannot write to a file handle after it has been closed"];

	// Add the data to the buffer
	pthread_mutex_lock(&bufferLock);
	[buffer appendData:data];
	bufferDataLength += [data length];

	// If the buffer is large, wait for some to be written out
	while (bufferDataLength > SPFH_BUFFER_SIZE) {
		pthread_mutex_unlock(&bufferLock);
		usleep(100);
		pthread_mutex_lock(&bufferLock);
	}
	pthread_mutex_unlock(&bufferLock);
}

// Ensures any buffers are written to disk
- (void) synchronizeFile
{
	pthread_mutex_lock(&bufferLock);
	while (bufferDataLength) {
		pthread_mutex_unlock(&bufferLock);
		usleep(100);
		pthread_mutex_lock(&bufferLock);
	}
	pthread_mutex_unlock(&bufferLock);
}

// Prevent further access to the file
- (void)closeFile
{
	if (!fileIsClosed) {
		[self synchronizeFile];
		if (useGzip || fileMode == O_RDONLY) {
			gzclose(wrappedFile);
		} else {
			fclose(wrappedFile);
		}
		if (processingThread) {
			if ([processingThread isExecuting]) {
				[processingThread cancel];
				while ([processingThread isExecuting]) usleep(100);
			}
		}
		fileIsClosed = YES;
	}
}


#pragma mark -
#pragma mark File information

/**
 * Returns whether gzip compression is enabled on the file.
 */
- (BOOL) isCompressed
{
	return useGzip;
}

@end

@implementation SPFileHandle (PrivateAPI)

/**
 * A method to be called on a background thread, allowing write data to build
 * up in a buffer and write to disk in chunks as the buffer fills.  This allows
 * background compression of the data when using Gzip compression.
 */
- (void) _writeBufferToData
{
	NSAutoreleasePool *writePool = [[NSAutoreleasePool alloc] init];

	// Process the buffer in a loop into the file, until cancelled
	while (![processingThread isCancelled]) {

		// Check whether any data in the buffer needs to be written out - using thread locks for safety
		pthread_mutex_lock(&bufferLock);
		if (!bufferDataLength) {
			pthread_mutex_unlock(&bufferLock);
			usleep(1000);
			continue;
		}

		// Write out the data
		long bufferLengthWrittenOut;
		if (useGzip) {
			bufferLengthWrittenOut = gzwrite(wrappedFile, [buffer bytes], bufferDataLength);
		} else {
			bufferLengthWrittenOut = fwrite([buffer bytes], 1, bufferDataLength, wrappedFile);
		}

		// Update the buffer
		CFDataDeleteBytes((CFMutableDataRef)buffer, CFRangeMake(0, bufferLengthWrittenOut));
		bufferDataLength = 0;
		pthread_mutex_unlock(&bufferLock);
	}

	[writePool drain];
}

@end
