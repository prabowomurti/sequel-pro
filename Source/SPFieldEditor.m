//
//  SPFieldEditor.m
//  sequel-pro
//
//  Created by Bibiko on 25.06.09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "SPFieldEditor.h"
#import "SPStringAdditions.h"
#import "SPArrayAdditions.h"
#import "SPTextViewAdditions.h"
#import "SPDataAdditions.h"
#import "QLPreviewPanel.h"


@implementation SPFieldEditor

// - (id) init
// {
// 	[self clean];
// 	self = [super init];
// 	return self;
// }

- (void)initWithObject:(id)data usingEncoding:(NSStringEncoding)anEncoding isObjectBlob:(BOOL)isFieldBlob
{

	[self clean];

	// hide all views in editSheet
	[hexTextView setHidden:YES];
	[hexTextScrollView setHidden:YES];
	[editImage setHidden:YES];
	[editTextView setHidden:YES];
	[editTextScrollView setHidden:YES];

	editSheetWillBeInitialized = YES;

	encoding = anEncoding;

	isBlob = isFieldBlob;

	// sheetEditData = data;
	sheetEditData = [data copy];
	NSLog(@"bbb:%@", sheetEditData);

	// hide all views in editSheet
	[hexTextView setHidden:YES];
	[hexTextScrollView setHidden:YES];
	[editImage setHidden:YES];
	[editTextView setHidden:YES];
	[editTextScrollView setHidden:YES];

	// Hide QuickLook button and text/iamge/hex control for text data
	[editSheetQuickLookButton setHidden:(!isBlob)];
	[editSheetSegmentControl setHidden:(!isBlob)];

	[editSheetProgressBar startAnimation:self];
	NSImage *image = nil;
	if ( [sheetEditData isKindOfClass:[NSData class]] ) {
		image = [[[NSImage alloc] initWithData:sheetEditData] autorelease];

		// Set hex view to "" - load on demand only
		[hexTextView setString:@""];
		
		stringValue = [[NSString alloc] initWithData:sheetEditData encoding:encoding];
		if (stringValue == nil)
			stringValue = [[NSString alloc] initWithData:sheetEditData encoding:NSASCIIStringEncoding];

		[hexTextView setHidden:NO];
		[hexTextScrollView setHidden:NO];
		[editImage setHidden:YES];
		[editTextView setHidden:YES];
		[editTextScrollView setHidden:YES];
		[editSheetSegmentControl setSelectedSegment:2];
	} else {
		stringValue = [sheetEditData retain];

		[hexTextView setString:@""];

		[hexTextView setHidden:YES];
		[hexTextScrollView setHidden:YES];
		[editImage setHidden:YES];
		[editTextView setHidden:NO];
		[editTextScrollView setHidden:NO];
		[editSheetSegmentControl setSelectedSegment:0];
	}

	if (image) {
		[editImage setImage:image];

		[hexTextView setHidden:YES];
		[hexTextScrollView setHidden:YES];
		[editImage setHidden:NO];
		[editTextView setHidden:YES];
		[editTextScrollView setHidden:YES];
		[editSheetSegmentControl setSelectedSegment:1];
	} else {
		[editImage setImage:nil];
	}
	if (stringValue) {
		[editTextView setString:stringValue];
		NSLog(@"tv:%@", [editTextView class]);

		if(image == nil) {
			[hexTextView setHidden:YES];
			[hexTextScrollView setHidden:YES];
			[editImage setHidden:YES];
			[editTextView setHidden:NO];
			[editTextScrollView setHidden:NO];
			[editSheetSegmentControl setSelectedSegment:0];
		 }

		// Locate the caret in editTextView
		// (to select all takes a bit time for large data)
		[editTextView setSelectedRange:NSMakeRange(0,0)];

		// Set focus
		if(image == nil)
			[self makeFirstResponder:editTextView];
		else
			[self makeFirstResponder:editImage];

		[stringValue release];
	}
	
	
	
	editSheetWillBeInitialized = NO;

	[editSheetProgressBar stopAnimation:self];


}

- (void)clean
{
	[hexTextView setString:@""];
	[editTextView setString:@"AA"];
	[editImage setImage:nil];
	if ( sheetEditData ) {
		[sheetEditData release];
	}
	
}

- (id)editData
{
	NSLog(@"aa:%@", sheetEditData);
	return [sheetEditData copy];
}


- (IBAction)closeEditSheet:(id)sender
{
	[NSApp stopModalWithCode:[sender tag]];
}

- (IBAction)openEditSheet:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	
	if ( [panel runModal] == NSOKButton ) {
		NSString *fileName = [panel filename];
		NSString *contents = nil;

		editSheetWillBeInitialized = YES;

		[editSheetProgressBar startAnimation:self];

		// free old data
		if ( sheetEditData != nil ) {
			[sheetEditData release];
		}
		
		// load new data/images
		sheetEditData = [[NSData alloc] initWithContentsOfFile:fileName];

		NSImage *image = [[NSImage alloc] initWithData:sheetEditData];
		contents = [[NSString alloc] initWithData:sheetEditData encoding:encoding];
		if (contents == nil)
			contents = [[NSString alloc] initWithData:sheetEditData encoding:NSASCIIStringEncoding];

		// set the image preview, string contents and hex representation
		[editImage setImage:image];

		
		if(contents)
			[editTextView setString:contents];
		else
			[editTextView setString:@""];
		
		// Load hex data only if user has already displayed them
		if(![[hexTextView string] isEqualToString:@""])
			[hexTextView setString:[sheetEditData dataToFormattedHexString]];

		// If the image cell now contains a valid image, select the image view
		if (image) {
			[editSheetSegmentControl setSelectedSegment:1];
			[hexTextView setHidden:YES];
			[hexTextScrollView setHidden:YES];
			[editImage setHidden:NO];
			[editTextView setHidden:YES];
			[editTextScrollView setHidden:YES];

		// Otherwise deselect the image view
		} else {
			[editSheetSegmentControl setSelectedSegment:0];
			[hexTextView setHidden:YES];
			[hexTextScrollView setHidden:YES];
			[editImage setHidden:YES];
			[editTextView setHidden:NO];
			[editTextScrollView setHidden:NO];
		}
		
		[image release];
		if(contents)
			[contents release];
		[editSheetProgressBar stopAnimation:self];
		editSheetWillBeInitialized = NO;
	}
}

/*
 * Segement controller for text/image/hex buttons in editSheet
 */
- (IBAction)segmentControllerChanged:(id)sender
{
	switch([sender selectedSegment]){
		case 0: // text
		[editTextView setHidden:NO];
		[editTextScrollView setHidden:NO];
		[editImage setHidden:YES];
		[hexTextView setHidden:YES];
		[hexTextScrollView setHidden:YES];
		// [self makeFirstResponder:editTextView];
		break;
		case 1: // image
		[editTextView setHidden:YES];
		[editTextScrollView setHidden:YES];
		[editImage setHidden:NO];
		[hexTextView setHidden:YES];
		[hexTextScrollView setHidden:YES];
		// [self makeFirstResponder:editImage];
		break;
		case 2: // hex - load on demand
		if([sheetEditData length] && [[hexTextView string] isEqualToString:@""]) {
			[editSheetProgressBar startAnimation:self];
			[hexTextView setString:[sheetEditData dataToFormattedHexString]];
			[editSheetProgressBar stopAnimation:self];
		}
		[editTextView setHidden:YES];
		[editTextScrollView setHidden:YES];
		[editImage setHidden:YES];
		[hexTextView setHidden:NO];
		[hexTextScrollView setHidden:NO];
		// [self makeFirstResponder:hexTextView];
		break;
	}
}

/*
 * Saves a file containing the content of the editSheet
 */
- (IBAction)saveEditSheet:(id)sender
{
	NSSavePanel *panel = [NSSavePanel savePanel];
	
	if ( [panel runModal] == NSOKButton ) {

		[editSheetProgressBar startAnimation:self];

		NSString *fileName = [panel filename];
		
		// Write binary field types directly to the file
		//// || [editSheetBinaryButton state] == NSOnState
		if ( [sheetEditData isKindOfClass:[NSData class]] ) {
			[sheetEditData writeToFile:fileName atomically:YES];
		
		// Write other field types' representations to the file via the current encoding
		} else {
			[[sheetEditData description] writeToFile:fileName
									 atomically:YES
									   encoding:encoding
										  error:NULL];
		}

		[editSheetProgressBar stopAnimation:self];

	}
}


#pragma mark -
#pragma mark QuickLook

- (IBAction)quickLookFormatButton:(id)sender
{
	switch([sender tag]) {
		case 0: [self invokeQuickLookOfType:@"pict" treatAsText:NO];  break;
		case 1: [self invokeQuickLookOfType:@"m4a"  treatAsText:NO];  break;
		case 2: [self invokeQuickLookOfType:@"mp3"  treatAsText:NO];  break;
		case 3: [self invokeQuickLookOfType:@"wav"  treatAsText:NO];  break;
		case 4: [self invokeQuickLookOfType:@"mov"  treatAsText:NO];  break;
		case 5: [self invokeQuickLookOfType:@"pdf"  treatAsText:NO];  break;
		case 6: [self invokeQuickLookOfType:@"html" treatAsText:YES]; break;
		case 7: [self invokeQuickLookOfType:@"doc"  treatAsText:NO];  break;
		case 8: [self invokeQuickLookOfType:@"rtf"  treatAsText:YES]; break;
	}
}

/*
 * Opens QuickLook for current data if QuickLook is available
 */
- (void)invokeQuickLookOfType:(NSString *)type treatAsText:(BOOL)isText
{

	// Load private framework
	if([[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/QuickLookUI.framework"] load]) {

		[editSheetProgressBar startAnimation:self];

		// Create a temporary file name to store the data as file
		// since QuickLook only works on files.
		NSString *tmpFileName = [NSString stringWithFormat:@"/tmp/SequelProQuickLook.%@", type];

		// if data are binary
		if ( [sheetEditData isKindOfClass:[NSData class]] || !isText) {
			[sheetEditData writeToFile:tmpFileName atomically:YES];
		
		// write other field types' representations to the file via the current encoding
		} else {
			[[sheetEditData description] writeToFile:tmpFileName
									 atomically:YES
									   encoding:encoding
										  error:NULL];
		}

		id ql = [NSClassFromString(@"QLPreviewPanel") sharedPreviewPanel];

		// Init QuickLook
		[[ql delegate] setDelegate:self];
		[ql setURLs:[NSArray arrayWithObject:
			[NSURL fileURLWithPath:tmpFileName]] currentIndex:0 preservingDisplayState:YES];
		// TODO: No interaction with iChat and iPhoto due to .scriptSuite warning:
		// for superclass of class 'MainController' in suite 'Sequel Pro': 'NSCoreSuite.NSAbstractObject' is not a valid class name. 
		[ql setShowsAddToiPhotoButton:NO];
		[ql setShowsiChatTheaterButton:NO];
		// Since we are inside of editSheet we have to avoid full-screen zooming
		// otherwise QuickLook hangs
		[ql setShowsFullscreenButton:NO];
		[ql setEnableDragNDrop:NO];
		// Order out QuickLook with animation effect according to self:previewPanel:frameForURL:
		[ql makeKeyAndOrderFrontWithEffect:2];   // 1 = fade in

		// quickLookCloseMarker == 1 break the modal session
		quickLookCloseMarker = 0;

		[editSheetProgressBar stopAnimation:self];

		// Run QuickLook in its own modal seesion for event handling
		NSModalSession session = [NSApp beginModalSessionForWindow:ql];
		for (;;) {
			// Conditions for closing QuickLook
			if ([NSApp runModalSession:session] != NSRunContinuesResponse 
				|| quickLookCloseMarker == 1 
				|| ![ql isVisible]) 
				break;
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode  
										beforeDate:[NSDate distantFuture]];

		}
		[NSApp endModalSession:session];

		// Remove temp file after closing the sheet to allow double-click event at the QuickLook preview.
		// The afterDelay: time is a kind of dummy, because after double-clicking the model session loop
		// will break (ql not visible) and returns the event handling back to the editSheet which by itself
		// blocks the execution of removeQuickLooksTempFile: until the editSheet is closed.
		[self performSelector:@selector(removeQuickLooksTempFile:) withObject:tmpFileName afterDelay:2];
		
		// [[NSFileManager defaultManager] removeItemAtPath:tmpFileName error:NULL];

	}

}

- (void)removeQuickLooksTempFile:(NSString*)aPath
{
	[[NSFileManager defaultManager] removeItemAtPath:aPath error:NULL];
}

// This is the delegate method
// It should return the frame for the item represented by the URL
// If an empty frame is returned then the panel will fade in/out instead
- (NSRect)previewPanel:(NSPanel*)panel frameForURL:(NSURL*)URL
{

	// Close modal session defined in invokeQuickLookOfType:
	// if user closes the QuickLook view
	quickLookCloseMarker = 1;

	// Return the App's middle point
	NSRect mwf = [[NSApp mainWindow] frame];
	return NSMakeRect(
		mwf.origin.x+mwf.size.width/2,
		mwf.origin.y+mwf.size.height/2,
		5, 5);

}

-(void)processPasteImageData
{
	editSheetWillBeInitialized = YES;

	NSImage *image = nil;
	
	image = [[[NSImage alloc] initWithPasteboard:[NSPasteboard generalPasteboard]] autorelease];
	if (image) {

		if (nil != sheetEditData) [sheetEditData release];

		[editImage setImage:image];

		sheetEditData = [[NSData alloc] initWithData:[image TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1]];

		NSString *contents = [[NSString alloc] initWithData:sheetEditData encoding:encoding];
		if (contents == nil)
			contents = [[NSString alloc] initWithData:sheetEditData encoding:NSASCIIStringEncoding];

		// Set the string contents and hex representation
		if(contents)
			[editTextView setString:contents];
		if(![[hexTextView string] isEqualToString:@""])
			[hexTextView setString:[sheetEditData dataToFormattedHexString]];

		[contents release];
		
	}

	editSheetWillBeInitialized = NO;
}
/*
 * Invoked when the imageView in the connection sheet has the contents deleted
 * or a file dragged and dropped onto it.
 */
- (void)processUpdatedImageData:(NSData *)data
{

	editSheetWillBeInitialized = YES;

	if (nil != sheetEditData) [sheetEditData release];

	// If the image was not processed, set a blank string as the contents of the edit and hex views.
	if ( data == nil ) {
		sheetEditData = [[NSData alloc] init];
		[editTextView setString:@""];
		[hexTextView setString:@""];
		editSheetWillBeInitialized = NO;
		return;
	}

	// Process the provided image
	sheetEditData = [[NSData alloc] initWithData:data];
	NSString *contents = [[NSString alloc] initWithData:data encoding:encoding];
	if (contents == nil)
		contents = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];

	// Set the string contents and hex representation
	if(contents)
		[editTextView setString:contents];
	if(![[hexTextView string] isEqualToString:@""])
		[hexTextView setString:[sheetEditData dataToFormattedHexString]];
	
	[contents release];
	editSheetWillBeInitialized = NO;
}

- (IBAction)dropImage:(id)sender
{

	// If the image was deleted, set a blank string as the contents of the edit and hex views.
	// The actual dropped image processing is handled by processUpdatedImageData:.
	if ( [editImage image] == nil ) {
		if (nil != sheetEditData) [sheetEditData release];
		sheetEditData = [[NSData alloc] init];
		[editTextView setString:@""];
		[hexTextView setString:@""];
		return;
	}
}

- (void)textViewDidChangeSelection:(NSNotification *)notification
/*
 invoked when the user changes the string in the editSheet
 */
{

	// Do nothing if user really didn't changed text (e.g. for font size changing return)
	if(editSheetWillBeInitialized || ([[[notification object] textStorage] changeInLength]==0))
		return;

	// clear the image and hex (since i doubt someone can "type" a gif)
	[editImage setImage:nil];
	[hexTextView setString:@""];
	
	// free old data
	if ( sheetEditData != nil ) {
		[sheetEditData release];
	}
	
	// set edit data to text
	sheetEditData = [[editTextView string] retain];

}

// TextView delegate methods

/**
 * Traps enter and return key and closes editSheet instead of inserting a linebreak when user hits return.
 */
- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
	if ( aTextView == editTextView ) {
		if ( [aTextView methodForSelector:aSelector] == [aTextView methodForSelector:@selector(insertNewline:)] &&
			[[[NSApp currentEvent] characters] isEqualToString:@"\003"] )
		{
			[NSApp stopModalWithCode:1];
			return YES;
		} 
		else
			return NO;
	}
	return NO;
}


@end
