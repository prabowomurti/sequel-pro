//
//  $Id$
//
//  SPTextViewAdditions.h
//  sequel-pro
//
//  Created by Hans-Jörg Bibiko on April 05, 2009
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

@interface NSTextView (SPTextViewAdditions)

- (NSRange)getRangeForCurrentWord;

- (IBAction)selectCurrentWord:(id)sender;
- (IBAction)selectCurrentLine:(id)sender;
- (IBAction)selectEnclosingBrackets:(id)sender;
- (IBAction)doSelectionUpperCase:(id)sender;
- (IBAction)doSelectionLowerCase:(id)sender;
- (IBAction)doSelectionTitleCase:(id)sender;
- (IBAction)doDecomposedStringWithCanonicalMapping:(id)sender;
- (IBAction)doDecomposedStringWithCompatibilityMapping:(id)sender;
- (IBAction)doPrecomposedStringWithCanonicalMapping:(id)sender;
- (IBAction)doPrecomposedStringWithCompatibilityMapping:(id)sender;
- (IBAction)doTranspose:(id)sender;
- (IBAction)doRemoveDiacritics:(id)sender;
- (IBAction)insertNULLvalue:(id)sender;
- (IBAction)moveSelectionLineUp:(id)sender;
- (IBAction)moveSelectionLineDown:(id)sender;

- (IBAction)executeBundleItemForInputField:(id)sender;

- (void)makeTextSizeLarger;
- (void)makeTextSizeSmaller;
- (void)makeTextStandardSize;

@end
